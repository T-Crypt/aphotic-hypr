import importlib.util
from pathlib import Path
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'Configs/.local/lib/aphotic/passthrough.py'
spec = importlib.util.spec_from_file_location('passthrough', SOURCE)
p = importlib.util.module_from_spec(spec)
if SOURCE.exists(): spec.loader.exec_module(p)

class PassthroughDrift(unittest.TestCase):
    def desired(self):
        return {'devices': [{'pci': '0000:01:00.0', 'vendor': '10de', 'device': '2684', 'driver': 'vfio-pci',
                             'group_members': ['0000:01:00.0', '0000:01:00.1']}],
                'modules': ['vfio_pci'], 'kernel_parameters': ['intel_iommu=on'],
                'initramfs_images': ['/boot/initramfs-linux.img']}

    def actual(self):
        return {'devices': {'0000:01:00.0': {'vendor': '10de', 'device': '2684', 'driver': 'vfio-pci',
                    'group_members': ['0000:01:00.0', '0000:01:00.1'], 'display': False}},
                'modules': ['vfio_pci'], 'kernel_parameters': ['quiet', 'intel_iommu=on'],
                'initramfs': {'/boot/initramfs-linux.img': ['vfio_pci']}}

    def test_missing_section_opts_out_without_probe(self):
        self.assertTrue(hasattr(p, 'report'), 'Passthrough drift report is missing')
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'aphotic.toml'
            path.write_text('[install]\nlayers = ["gaming"]\n')
            self.assertEqual(p.report(path, probe=lambda desired: self.fail('opt-out probed host')),
                             {'opted_in': False, 'status': 'OPTED OUT', 'checks': []})

    def test_clean_and_drift(self):
        desired, actual = self.desired(), self.actual()
        self.assertEqual(p.compare(desired, actual)['status'], 'READY')
        actual['devices']['0000:01:00.0']['driver'] = 'nvidia'
        actual['devices']['0000:01:00.0']['group_members'].append('0000:02:00.0')
        actual['initramfs']['/boot/initramfs-linux.img'] = []
        result = p.compare(desired, actual)
        self.assertEqual(result['status'], 'DRIFTED')
        self.assertEqual(sum(c['status'] == 'DRIFTED' for c in result['checks']), 3)
        self.assertTrue(any('initramfs' in c['key'] and 'vfio_pci' in c['key'] for c in result['checks']))

    def test_unknown_initramfs_is_not_ready(self):
        actual = self.actual()
        actual['initramfs']['/boot/initramfs-linux.img'] = None
        self.assertEqual(p.compare(self.desired(), actual)['status'], 'UNKNOWN')

    def test_display_gpu_blocks_even_if_declared(self):
        actual = self.actual()
        actual['devices']['0000:01:00.0']['display'] = True
        self.assertEqual(p.compare(self.desired(), actual)['status'], 'MANUAL ACTION REQUIRED')
        actual['devices']['0000:01:00.0']['display'] = None
        self.assertNotEqual(p.compare(self.desired(), actual)['status'], 'READY')

    def test_missing_device_and_parameters(self):
        actual = self.actual()
        actual['devices'] = {}
        actual['kernel_parameters'] = []
        actual['modules'] = []
        self.assertEqual(p.compare(self.desired(), actual)['status'], 'DRIFTED')

    def test_malformed_and_empty_config_refused(self):
        for desired in ({}, {'devices': 'bad'}, dict(self.desired(), modules='vfio'),
                        dict(self.desired(), devices=[{'pci': '/dev/sda'}]),
                        dict(self.desired(), surprise='ignored')):
            with self.subTest(desired=desired), self.assertRaises(ValueError): p.validate(desired)

    def test_sysfs_discovery_and_initramfs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            node = root / 'sys/bus/pci/devices/0000:01:00.0'
            node.mkdir(parents=True)
            (node / 'vendor').write_text('0x10de\n')
            (node / 'device').write_text('0x2684\n')
            (node / 'boot_vga').write_text('0\n')
            driver = root / 'sys/bus/pci/drivers/vfio-pci'
            driver.mkdir(parents=True)
            (node / 'driver').symlink_to(driver)
            group = root / 'sys/kernel/iommu_groups/55'
            (group / 'devices').mkdir(parents=True)
            (group / 'devices/0000:01:00.0').touch()
            (group / 'devices/0000:01:00.1').touch()
            (node / 'iommu_group').symlink_to(group)
            (root / 'sys/module/vfio_pci').mkdir(parents=True)
            (root / 'proc').mkdir()
            (root / 'proc/cmdline').write_text('quiet intel_iommu=on')
            actual = p.discover(self.desired(), root=root,
                listing=lambda path: 'usr/lib/modules/kernel/vfio-pci.ko.zst\n')
            self.assertEqual(p.compare(self.desired(), actual)['status'], 'READY')
            self.assertEqual(actual['devices']['0000:01:00.0']['group_members'],
                             ['0000:01:00.0', '0000:01:00.1'])

if __name__ == '__main__': unittest.main()
