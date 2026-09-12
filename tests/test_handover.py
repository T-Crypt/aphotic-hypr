import importlib.util
import json
from pathlib import Path
import subprocess
import sys

import pytest

MODULE = Path(__file__).resolve().parents[1] / 'Configs/.local/lib/aphotic/handover.py'


def module():
    assert MODULE.exists(), 'durable handover executor is missing'
    spec = importlib.util.spec_from_file_location('handover', MODULE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Bridge:
    def __init__(self):
        self.leases = {}
    def call(self, method, payload):
        if method == 'reserve':
            self.leases[payload['id']] = payload
        elif method == 'release':
            self.leases.pop(payload['id'], None)
        return {'ok': True, 'claims': [], 'agents': []}


def plan(tmp_path, name='a'):
    targets = [tmp_path / f'{name}-{i}' for i in range(3)]
    for i, target in enumerate(targets):
        target.write_text(f'before-{i}')
        target.chmod(0o640)
    return {'id': name, 'owner': 'test', 'plane': 'dev', 'label': name,
            'resources': [{'key': 'memory', 'amount': 1024, 'unit': 'MiB', 'exclusive': False}],
            'stages': [{'id': f'file-{i}', 'kind': 'file', 'path': str(p), 'content': 'leased'} for i, p in enumerate(targets)]}


@pytest.mark.parametrize('failure', range(4))
def test_reverse_rollback_at_every_stage(tmp_path, failure):
    m = module()
    p = plan(tmp_path)
    bridge = Bridge()
    engine = m.Engine(tmp_path / 'state', bridge)
    original = engine.apply_stage
    seen = []
    def induced(stage):
        original(stage)
        seen.append(stage['id'])
        if len(seen) == failure + 1:
            raise RuntimeError('induced failure')
    engine.apply_stage = induced
    with pytest.raises(m.HandoverError, match='induced failure'):
        engine.acquire(p)
    for i in range(3):
        assert (tmp_path / f'a-{i}').read_text() == f'before-{i}'
        assert (tmp_path / f'a-{i}').stat().st_mode & 0o777 == 0o640
    assert not bridge.leases
    assert engine.status()[0]['status'] == 'restored'


def test_crash_after_effect_is_recoverable_without_shell(tmp_path):
    m = module()
    p = plan(tmp_path)
    engine = m.Engine(tmp_path / 'state', Bridge())
    original = engine.apply_stage
    def crash(stage):
        original(stage)
        if stage['id'] == 'file-1':
            raise KeyboardInterrupt()
    engine.apply_stage = crash
    with pytest.raises(KeyboardInterrupt):
        engine.acquire(p)
    restarted = m.Engine(tmp_path / 'state', Bridge())
    restarted.recover('a')
    assert all((tmp_path / f'a-{i}').read_text() == f'before-{i}' for i in range(3))


def test_preserves_intervening_edit_and_retains_reservation(tmp_path):
    m = module()
    p = plan(tmp_path)
    engine = m.Engine(tmp_path / 'state', Bridge())
    engine.acquire(p)
    (tmp_path / 'a-1').write_text('user edit')
    result = engine.recover('a')
    assert result['status'] == 'recovery-required'
    assert (tmp_path / 'a-1').read_text() == 'user edit'
    assert result['stages'][0]['status'] == 'applied'


def test_rehearsal_is_read_only(tmp_path):
    m = module()
    p = plan(tmp_path)
    state = tmp_path / 'absent'
    result = m.Engine(state, Bridge()).rehearse(p)
    assert not state.exists()
    assert len(result['stages']) == 4
    assert (tmp_path / 'a-0').read_text() == 'before-0'


def test_multiple_workloads_capacity_and_device_conflicts(tmp_path):
    m = module()
    engine = m.Engine(tmp_path / 'state', Bridge())
    a, b = plan(tmp_path, 'a'), plan(tmp_path, 'b')
    a['resources'].append({'key': 'pci:0000:01:00.0', 'amount': 1, 'exclusive': True})
    b['resources'].append({'key': 'pci:0000:02:00.0', 'amount': 1, 'exclusive': True})
    engine.acquire(a)
    engine.acquire(b)
    assert len([x for x in engine.status() if x['status'] == 'active']) == 2
    with pytest.raises(m.HandoverError, match='already'):
        engine.acquire(a)
    c = plan(tmp_path, 'c')
    c['resources'] = a['resources']
    with pytest.raises(m.HandoverError, match='pci:'):
        engine.acquire(c)
    engine.recover('a')
    assert engine.load('b')['status'] == 'active'


def test_malformed_and_unknown_stage_rejected_without_writes(tmp_path):
    m = module()
    p = plan(tmp_path)
    p['stages'][1]['kind'] = 'command'
    with pytest.raises(m.HandoverError):
        m.Engine(tmp_path / 'state', Bridge()).rehearse(p)
    assert not (tmp_path / 'state').exists()


def test_tty_status_does_not_need_quickshell(tmp_path):
    module()
    proc = subprocess.run([sys.executable, str(MODULE), '--state-dir', str(tmp_path / 'state'), 'status'], capture_output=True, text=True)
    assert proc.returncode == 0, proc.stderr
    assert json.loads(proc.stdout) == []
    assert not (tmp_path / 'state').exists()


def test_tty_recovery_after_restart_without_display(tmp_path):
    m = module()
    p = plan(tmp_path)
    state = tmp_path / 'state'
    engine = m.Engine(state, Bridge())
    engine.acquire(p)
    import os
    env = dict(os.environ, PATH='/nonexistent')
    proc = subprocess.run([sys.executable, str(MODULE), '--state-dir', str(state), 'recover', 'a'],
                          capture_output=True, text=True, env=env)
    assert proc.returncode == 0, proc.stderr
    assert json.loads(proc.stdout)['status'] == 'restored'
    assert all((tmp_path / f'a-{i}').read_text() == f'before-{i}' for i in range(3))


def test_lock_prevents_interleaved_acquisition(tmp_path):
    m = module()
    engine = m.Engine(tmp_path / 'state', Bridge())
    p = plan(tmp_path)
    with engine.lock():
        with pytest.raises(m.HandoverError, match='in progress'):
            m.Engine(tmp_path / 'state', Bridge()).acquire(p)


def test_cpu_and_memory_reservations_keep_host_capacity(tmp_path):
    m = module()
    engine = m.Engine(tmp_path / 'state', Bridge())
    p = plan(tmp_path)
    for resource in ({'key': 'memory', 'amount': 10**12, 'unit': 'MiB'}, {'key': 'cpu', 'amount': 10**8}):
        p['resources'] = [resource]
        with pytest.raises(m.HandoverError, match='capacity'):
            engine.rehearse(p)


def test_missing_shell_refuses_acquire_before_any_file_effect(tmp_path):
    m = module()
    p = plan(tmp_path)
    class Missing:
        def call(self, *args):
            raise m.HandoverError('Flow bridge unavailable')
    with pytest.raises(m.HandoverError, match='unavailable'):
        m.Engine(tmp_path / 'state', Missing()).acquire(p)
    assert all((tmp_path / f'a-{i}').read_text() == f'before-{i}' for i in range(3))


def test_cannot_lease_journal_or_lock_files(tmp_path):
    m = module()
    state = tmp_path / 'state'
    state.mkdir(mode=0o700)
    p = plan(tmp_path)
    for name in ('.lock', 'index.json', 'a.json'):
        p['stages'][0]['path'] = str(state / name)
        with pytest.raises(m.HandoverError, match='journal'):
            m.Engine(state, Bridge()).rehearse(p)


def test_shelter_owner_cannot_be_held_by_two_leases(tmp_path):
    m = module()
    class ShelterBridge(Bridge):
        def call(self, method, payload):
            if method == 'shelterSnapshot':
                return {'ok': True, 'value': 'full'}
            return super().call(method, payload)
    engine = m.Engine(tmp_path / 'state', ShelterBridge())
    a, b = plan(tmp_path, 'a'), plan(tmp_path, 'b')
    for p in (a, b):
        p['stages'] = [{'id': 'shelter', 'kind': 'shelter', 'owner': 'background'}]
    engine.acquire(a)
    with pytest.raises(m.HandoverError, match='shelter'):
        engine.rehearse(b)


def test_reserved_index_id_refused(tmp_path):
    m = module()
    p = plan(tmp_path)
    p['id'] = 'index'
    with pytest.raises(m.HandoverError, match='reserved'):
        m.Engine(tmp_path / 'state', Bridge()).rehearse(p)


def test_corrupt_neighbor_does_not_prevent_known_lease_recovery(tmp_path):
    m = module()
    p = plan(tmp_path)
    engine = m.Engine(tmp_path / 'state', Bridge())
    engine.acquire(p)
    (tmp_path / 'state/broken.json').write_text('{')
    assert engine.recover('a')['status'] == 'restored'
    assert json.loads((tmp_path / 'state/index.json').read_text())['errors']
    assert (tmp_path / 'a-0').read_text() == 'before-0'


@pytest.mark.parametrize('bad', [None, [], 'memory', 3])
def test_malformed_resource_is_a_controlled_refusal(tmp_path, bad):
    m = module()
    p = plan(tmp_path)
    p['resources'] = [bad]
    with pytest.raises(m.HandoverError):
        m.Engine(tmp_path / 'state', Bridge()).rehearse(p)


def test_file_restore_keeps_group_and_extended_attributes(tmp_path):
    import os
    m = module()
    p = plan(tmp_path)
    target = tmp_path / 'a-0'
    os.setxattr(target, 'user.handover-test', b'prior')
    before = m.file_state(target)
    engine = m.Engine(tmp_path / 'state', Bridge())
    engine.acquire(p)
    engine.recover('a')
    assert m.file_state(target) == before
