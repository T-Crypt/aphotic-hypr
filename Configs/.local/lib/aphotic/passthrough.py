#!/usr/bin/env python3
"""Compare declared passthrough prerequisites with the running host. Never apply changes."""
import argparse
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tomllib

PCI = re.compile(r'[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]')
MODULE = re.compile(r'[a-zA-Z0-9_-]+')


def validate(desired):
    if not isinstance(desired, dict) or set(desired) - {'devices', 'modules', 'kernel_parameters', 'initramfs_images'}:
        raise ValueError('Invalid [passthrough] fields')
    devices = desired.get('devices')
    if not isinstance(devices, list) or not devices:
        raise ValueError('[passthrough] must declare at least one device')
    seen = set()
    for device in devices:
        if not isinstance(device, dict) or set(device) != {'pci', 'vendor', 'device', 'driver', 'group_members'}:
            raise ValueError('Each passthrough device needs pci, vendor, device, driver and group_members')
        address = device['pci']
        if not isinstance(address, str) or not PCI.fullmatch(address) or address in seen:
            raise ValueError('Invalid or duplicate passthrough PCI address')
        seen.add(address)
        if any(not isinstance(device[k], str) or not re.fullmatch('[0-9a-f]{4}', device[k]) for k in ('vendor', 'device')):
            raise ValueError('PCI vendor/device IDs must be four lowercase hex digits')
        if device['driver'] != 'vfio-pci':
            raise ValueError('Declared passthrough devices must use vfio-pci')
        group = device['group_members']
        if not isinstance(group, list) or not group or address not in group or len(set(group)) != len(group) or any(not isinstance(p, str) or not PCI.fullmatch(p) for p in group):
            raise ValueError('group_members must contain unique PCI addresses including the device')
    for key in ('modules', 'kernel_parameters', 'initramfs_images'):
        items = desired.get(key)
        if not isinstance(items, list) or not items or any(not isinstance(s, str) or not s for s in items):
            raise ValueError(key + ' must be a nonempty string array')
    if any(not MODULE.fullmatch(m) for m in desired['modules']):
        raise ValueError('Invalid module name')
    if any(any(c.isspace() for c in p) for p in desired['kernel_parameters']):
        raise ValueError('Kernel parameters must be individual tokens')
    if any(not Path(p).is_absolute() or '..' in Path(p).parts for p in desired['initramfs_images']):
        raise ValueError('Initramfs images must use absolute paths without parent traversal')
    return desired


def text(path):
    try:
        return path.read_text().strip()
    except (OSError, UnicodeError):
        return None


def initramfs_listing(path):
    try:
        result = subprocess.run(['lsinitcpio', '-l', str(path)], capture_output=True, text=True,
                                timeout=20, check=False)
        return result.stdout if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def discover(desired, root=Path('/'), listing=initramfs_listing):
    validate(desired)
    root = Path(root)
    devices = {}
    for device in desired['devices']:
        node = root / 'sys/bus/pci/devices' / device['pci']
        if not node.is_dir():
            continue
        driver_path = node / 'driver'
        driver = driver_path.resolve().name if driver_path.exists() else None
        group = node / 'iommu_group/devices'
        members = sorted(p.name for p in group.iterdir()) if group.is_dir() else None
        connectors = list((node / 'drm').glob('card*/card*-*'))
        connector_states = [text(c / 'enabled') for c in connectors]
        boot_vga = text(node / 'boot_vga')
        # Without DRM evidence, only an already bound VFIO device proves no host display.
        display = True if boot_vga == '1' or 'enabled' in connector_states else (
            False if driver == 'vfio-pci' or connector_states and all(s == 'disabled' for s in connector_states) else None)
        devices[device['pci']] = {'vendor': (text(node / 'vendor') or '').removeprefix('0x'),
                                  'device': (text(node / 'device') or '').removeprefix('0x'),
                                  'driver': driver, 'group_members': members, 'display': display}
    modules = sorted(p.name.replace('-', '_') for p in (root / 'sys/module').glob('*'))
    cmdline = text(root / 'proc/cmdline')
    initramfs = {}
    for image in desired['initramfs_images']:
        output = listing(root / image.lstrip('/'))
        initramfs[image] = (sorted(set(m.replace('-', '_') for m in re.findall(
            r'(?:^|/)([A-Za-z0-9_-]+)\.ko(?:\.(?:zst|xz|gz))?(?=\s|$)', output, re.M))) if output is not None else None)
    return {'devices': devices, 'modules': modules,
            'kernel_parameters': shlex.split(cmdline) if cmdline is not None else None, 'initramfs': initramfs}


def compare(desired, actual):
    validate(desired)
    checks = []
    def add(key, expected, observed, remedy, unknown=False, display=False):
        status = 'UNKNOWN' if unknown else ('ok' if expected == observed else 'DRIFTED')
        if display and observed is True:
            status = 'MANUAL ACTION REQUIRED'
        checks.append({'key': key, 'status': status, 'desired': expected, 'actual': observed, 'remedy': remedy})
    for device in desired['devices']:
        pci = device['pci']
        found = actual['devices'].get(pci)
        add(pci + ':present', True, found is not None, 'Check hardware and declared PCI addresses after firmware changes')
        if found is None:
            continue
        for key in ('vendor', 'device', 'driver', 'group_members'):
            expected = sorted(device[key]) if key == 'group_members' else device[key]
            value = found.get(key)
            if key == 'group_members' and isinstance(value, list): value = sorted(value)
            add(pci + ':' + key, expected, value,
                'Review the rendered diff and repair host configuration with explicit approval; do not apply ACS override')
        add(pci + ':display', False, found.get('display'),
            'Stop: move the host display to another GPU and confirm ownership before any rebind, launch or boot apply',
            unknown=found.get('display') is None, display=True)
    for module in desired['modules']:
        normalized = module.replace('-', '_')
        add('module:' + module, True, normalized in actual['modules'], 'Review loaded VFIO modules before launch')
        for image in desired['initramfs_images']:
            listed = actual['initramfs'].get(image)
            add('initramfs:' + image + ':' + module, True, normalized in listed if listed is not None else None,
                'Inspect the initramfs. Review a config diff before an approved rebuild', unknown=listed is None)
    for parameter in desired['kernel_parameters']:
        cmdline = actual.get('kernel_parameters')
        add('kernel:' + parameter, True, parameter in cmdline if cmdline is not None else None,
            'Review the boot configuration diff; applying kernel parameters requires approval and a reboot', unknown=cmdline is None)
    statuses = {c['status'] for c in checks}
    status = next((s for s in ('MANUAL ACTION REQUIRED', 'DRIFTED', 'UNKNOWN') if s in statuses), 'READY')
    return {'opted_in': True, 'status': status, 'checks': checks}


def report(config, probe=discover):
    path = Path(config)
    if not path.exists():
        return {'opted_in': False, 'status': 'OPTED OUT', 'checks': []}
    try:
        data = tomllib.loads(path.read_text())
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise ValueError('Cannot read desired state: ' + str(exc)) from exc
    if 'passthrough' not in data:
        return {'opted_in': False, 'status': 'OPTED OUT', 'checks': []}
    desired = validate(data['passthrough'])
    return compare(desired, probe(desired))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    try:
        result = report(args.config)
    except (ValueError, OSError, TypeError) as exc:
        result = {'opted_in': True, 'status': 'INVALID', 'checks': [], 'error': str(exc)}
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print('Passthrough readiness: ' + result['status'])
        if result.get('error'): print('  ' + result['error'])
        for check in result['checks']:
            print(f"  [{check['status']}] {check['key']}: desired {check['desired']!r}, actual {check['actual']!r}")
            if check['status'] != 'ok': print('    ' + check['remedy'])
    return 0 if result['status'] in ('READY', 'OPTED OUT') else 1


if __name__ == '__main__':
    sys.exit(main())
