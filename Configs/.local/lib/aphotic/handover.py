#!/usr/bin/env python3
"""Durable, typed host leases. No commands are accepted from a lease plan."""
import argparse
import base64
from contextlib import contextmanager
import fcntl
import json
import math
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import time


class HandoverError(Exception):
    pass


def atomic(path, data, mode=0o600, metadata=None):
    path = Path(path)
    fd, temporary = tempfile.mkstemp(prefix='.handover-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(data)
            stream.flush()
            if metadata:
                os.fchown(stream.fileno(), -1, metadata['gid'])
                for key, value in metadata.get('xattrs', {}).items():
                    os.setxattr(stream.fileno(), key, base64.b64decode(value))
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def file_state(path):
    path = Path(path)
    if path.is_symlink() or path.resolve() != path:
        raise HandoverError('file stage refuses symlinks')
    if not path.exists():
        return {'exists': False}
    info = path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_size > 1024 * 1024:
        raise HandoverError('file stage requires a regular file under 1 MiB')
    if info.st_uid != os.getuid() or info.st_nlink != 1:
        raise HandoverError('file stage requires a private file owned by this user')
    return {'exists': True, 'data': base64.b64encode(path.read_bytes()).decode(),
            'mode': stat.S_IMODE(info.st_mode), 'gid': info.st_gid,
            'xattrs': {key: base64.b64encode(os.getxattr(path, key)).decode() for key in os.listxattr(path)}}


class Bridge:
    def call(self, method, payload):
        for attempt in range(30):
            try:
                result = subprocess.run(['qs', '-c', 'aphotic', 'ipc', 'call', 'handover', method,
                                         json.dumps(payload, separators=(',', ':'))],
                                        capture_output=True, text=True, timeout=15, check=True)
                response = json.loads(result.stdout)
            except (OSError, subprocess.SubprocessError, ValueError) as error:
                raise HandoverError(f'Flow bridge unavailable: {error}') from error
            if response.get('ok'):
                return response
            if response.get('retry') and method == 'preview':
                time.sleep(.1)
                continue
            raise HandoverError(response.get('error', 'Flow refused operation'))
        raise HandoverError('Host capacity is still unknown; retry rehearsal')


class Engine:
    def __init__(self, directory, bridge=None):
        self.directory = Path(directory)
        self.bridge = bridge or Bridge()

    @contextmanager
    def lock(self):
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        info = self.directory.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise HandoverError('lease directory must be private and owned by this user')
        fd = os.open(self.directory / '.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            yield
        except BlockingIOError as error:
            raise HandoverError('another handover operation is in progress') from error
        finally:
            os.close(fd)

    def validate(self, plan):
        if not isinstance(plan, dict) or not re.fullmatch(r'[a-zA-Z0-9_-]{1,64}', str(plan.get('id', ''))):
            raise HandoverError('invalid lease id')
        if plan['id'] in ('index', '__proto__', 'constructor', 'prototype'):
            raise HandoverError('reserved lease id')
        if not plan.get('owner') or plan.get('plane') not in ('ai', 'dev', 'gaming', 'security'):
            raise HandoverError('owner and workload plane required')
        resources = plan.get('resources')
        if not isinstance(resources, list) or not resources or len(resources) > 128:
            raise HandoverError('bounded resource list required')
        keys = set()
        for resource in resources:
            if not isinstance(resource, dict):
                raise HandoverError('resource must be an object')
            key, amount = resource.get('key'), resource.get('amount')
            if not isinstance(key, str) or not re.fullmatch(r'[a-zA-Z0-9:._-]{1,160}', key) or key in keys:
                raise HandoverError('invalid or duplicate resource key')
            keys.add(key)
            if type(amount) not in (int, float) or not math.isfinite(amount) or amount <= 0:
                raise HandoverError('resource amount must be positive and finite')
            if key not in ('memory', 'cpu') and resource.get('exclusive') is not True:
                raise HandoverError('device resources must be exclusive')
            if key == 'memory' and resource.get('unit') != 'MiB':
                raise HandoverError('memory reservations use MiB')
        stages = plan.get('stages', [])
        if not isinstance(stages, list) or len(stages) > 64:
            raise HandoverError('invalid stages')
        ids, targets = {'reserve'}, set()
        for stage in stages:
            if not isinstance(stage, dict) or not re.fullmatch(r'[a-zA-Z0-9_-]{1,64}', str(stage.get('id', ''))) or stage['id'] in ids:
                raise HandoverError('invalid or duplicate stage id')
            ids.add(stage['id'])
            if stage.get('kind') == 'file':
                path = Path(stage.get('path', ''))
                if not path.is_absolute() or str(path) in targets or not path.parent.is_dir():
                    raise HandoverError('file paths must be unique absolute paths with existing parents')
                if path.resolve().is_relative_to(self.directory.resolve()):
                    raise HandoverError('file stage cannot target lease journal storage')
                if str(path).startswith(('/dev/', '/sys/', '/proc/')):
                    raise HandoverError('device and kernel paths are forbidden')
                if not isinstance(stage.get('content'), str) or len(stage['content'].encode()) > 1024 * 1024:
                    raise HandoverError('bounded file content required')
                targets.add(str(path))
            elif stage.get('kind') == 'shelter':
                if not isinstance(stage.get('owner'), str) or not stage['owner']:
                    raise HandoverError('shelter owner required')
            else:
                raise HandoverError('unsupported stage kind')
        return plan

    def load(self, lease_id):
        if not re.fullmatch(r'[a-zA-Z0-9_-]{1,64}', lease_id):
            raise HandoverError('invalid lease id')
        path = self.directory / f'{lease_id}.json'
        if path.is_symlink():
            raise HandoverError('symlink journal refused')
        data = json.loads(path.read_text())
        if data.get('schema') != 1 or data.get('writtenBy') != 'aphotic-handover' or data.get('id') != lease_id:
            raise HandoverError('unrecognized journal; refusing recovery')
        stages = data.get('stages', [])
        if not stages or stages[0].get('kind') != 'reserve' or stages[0].get('id') != 'reserve':
            raise HandoverError('journal has no reservation stage')
        self.validate(dict(data, stages=stages[1:]))
        for stage in stages:
            if stage.get('status') not in ('prepared', 'applying', 'applied', 'restored', 'restore-failed'):
                raise HandoverError('unrecognized stage status')
        return data

    def status(self):
        return [self.load(path.stem) for path in sorted(self.directory.glob('*.json')) if path.name != 'index.json']

    def save(self, journal):
        journal['updatedAt'] = int(time.time() * 1000)
        atomic(self.directory / f"{journal['id']}.json", json.dumps(journal, indent=2).encode())
        # Index is a view only; recovery always reads the per-lease journal.
        leases, errors = [], []
        for path in sorted(self.directory.glob('*.json')):
            if path.name == 'index.json':
                continue
            try:
                leases.append(self.load(path.stem))
            except (HandoverError, ValueError, OSError, TypeError, KeyError) as error:
                errors.append({'file': path.name, 'error': str(error)})
        atomic(self.directory / 'index.json', json.dumps({'schema': 1, 'leases': leases, 'errors': errors}).encode())

    def check_resources(self, plan):
        active = [j for j in self.status() if j['status'] != 'restored']
        if any(j['id'] == plan['id'] for j in active):
            raise HandoverError('lease already exists; release or recover it first')
        for request in plan['resources']:
            key = request['key']
            held = [(j, r) for j in active for r in j['resources'] if r['key'] == key]
            if held and (request.get('exclusive') or any(r.get('exclusive') for _, r in held)):
                raise HandoverError(f"{key} held by {held[0][0]['id']}")
            total = request['amount'] + sum(r['amount'] for _, r in held)
            if key == 'memory':
                capacity = os.sysconf('SC_PHYS_PAGES') * os.sysconf('SC_PAGE_SIZE') / 1048576
                if total > capacity - max(2048, capacity * .1):
                    raise HandoverError('memory reservations exceed capacity with host reserve')
            elif key == 'cpu' and total > max(0, (os.cpu_count() or 1) - 1):
                raise HandoverError('CPU reservations leave no host capacity')
        targets = {s['path'] for s in plan.get('stages', []) if s['kind'] == 'file'}
        shelters = {s['owner'] for s in plan.get('stages', []) if s['kind'] == 'shelter'}
        for journal in active:
            if shelters & {s['owner'] for s in journal['stages'] if s['kind'] == 'shelter'}:
                raise HandoverError('shelter owner is held by another lease')
            if targets & {s['path'] for s in journal['stages'] if s['kind'] == 'file'}:
                raise HandoverError('file is owned by another lease')

    def prepare(self, plan):
        self.validate(plan)
        self.check_resources(plan)
        preview = self.bridge.call('preview', plan)
        if preview.get('agents') and not plan.get('acknowledgeAgents'):
            raise HandoverError('live agent sessions: ' + ', '.join(str(x) for x in preview['agents']))
        stages = [{'id': 'reserve', 'kind': 'reserve', 'plan': {k: v for k, v in plan.items() if k != 'stages'}, 'before': None}]
        for source in plan.get('stages', []):
            stage = dict(source)
            if stage['kind'] == 'file':
                stage['before'] = file_state(stage['path'])
                stage['after'] = {'exists': True, 'data': base64.b64encode(stage['content'].encode()).decode(),
                                  'mode': stage['before'].get('mode', 0o600),
                                  'gid': stage['before'].get('gid', os.getegid()),
                                  'xattrs': stage['before'].get('xattrs', {})}
            else:
                stage['before'] = self.bridge.call('shelterSnapshot', stage)['value']
                stage['after'] = 'sheltered'
            stages.append(stage)
        for stage in stages:
            stage['status'] = 'prepared'
        return stages

    def rehearse(self, plan):
        stages = self.prepare(plan)
        return {'id': plan['id'], 'mutation': False, 'resources': plan['resources'], 'stages': stages}

    def apply_stage(self, stage):
        if stage['kind'] == 'reserve':
            self.bridge.call('reserve', stage['plan'])
        elif stage['kind'] == 'file':
            if file_state(stage['path']) != stage['before']:
                raise HandoverError('file changed since snapshot')
            atomic(stage['path'], base64.b64decode(stage['after']['data']), stage['after']['mode'], stage['after'])
        else:
            self.bridge.call('shelterApply', stage)

    def undo_stage(self, stage):
        if stage['kind'] == 'reserve':
            # The durable index releases the claim even when the shell is down.
            try:
                self.bridge.call('release', {'id': stage['plan']['id']})
            except HandoverError:
                pass
        elif stage['kind'] == 'file':
            current = file_state(stage['path'])
            if current == stage['before']:
                return
            if current != stage['after']:
                raise HandoverError('value changed outside Aphotic; preserving it')
            if stage['before']['exists']:
                atomic(stage['path'], base64.b64decode(stage['before']['data']), stage['before']['mode'], stage['before'])
            else:
                Path(stage['path']).unlink()
                directory = os.open(Path(stage['path']).parent, os.O_RDONLY | os.O_DIRECTORY)
                try:
                    os.fsync(directory)
                finally:
                    os.close(directory)
        else:
            self.bridge.call('shelterRestore', stage)

    def acquire(self, plan):
        with self.lock():
            stages = self.prepare(plan)
            journal = dict(plan, schema=1, writtenBy='aphotic-handover', status='acquiring', stages=stages, createdAt=int(time.time() * 1000))
            self.save(journal)
            try:
                for stage in stages:
                    stage['requestedAt'] = int(time.time() * 1000)
                    stage['status'] = 'applying'
                    self.save(journal)
                    self.apply_stage(stage)
                    stage['status'] = 'applied'
                    stage['completedAt'] = int(time.time() * 1000)
                    self.save(journal)
            except Exception as error:
                stage['applyError'] = str(error)
                journal['failedStage'] = stage['id']
                journal['error'] = str(error)
                self._recover(journal)
                raise HandoverError(f"stage {stage['id']}: {error}") from error
            journal['status'] = 'active'
            self.save(journal)
            return journal

    def _recover(self, journal):
        journal['status'] = 'restoring'
        self.save(journal)
        failed = False
        for stage in reversed(journal['stages']):
            if stage['status'] in ('prepared', 'restored'):
                continue
            if stage['kind'] == 'reserve' and failed:
                continue
            try:
                self.undo_stage(stage)
                stage['status'] = 'restored'
                stage['restoredAt'] = int(time.time() * 1000)
                stage.pop('error', None)
            except Exception as error:
                stage['status'] = 'restore-failed'
                stage['error'] = str(error)
                failed = True
            self.save(journal)
        journal['status'] = 'recovery-required' if failed else 'restored'
        self.save(journal)
        return journal

    def recover(self, lease_id):
        with self.lock():
            return self._recover(self.load(lease_id))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state-dir', default=str(Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'aphotic/handover'))
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('status')
    for name in ('recover', 'release'):
        commands.add_parser(name).add_argument('id')
    commands.add_parser('rehearse').add_argument('plan')
    acquire = commands.add_parser('acquire')
    acquire.add_argument('plan')
    acquire.add_argument('--confirm', action='store_true')
    args = parser.parse_args()
    engine = Engine(args.state_dir)
    try:
        if args.command == 'status':
            result = engine.status()
        elif args.command in ('recover', 'release'):
            result = engine.recover(args.id)
        else:
            plan = json.loads(Path(args.plan).read_text())
            if args.command == 'acquire' and not args.confirm:
                raise HandoverError('review rehearse output, then pass --confirm to acquire')
            result = engine.acquire(plan) if args.command == 'acquire' else engine.rehearse(plan)
        print(json.dumps(result, indent=2))
        return 2 if isinstance(result, dict) and result.get('status') == 'recovery-required' else 0
    except (HandoverError, OSError, ValueError, TypeError, KeyError) as error:
        print(json.dumps({'error': str(error)}), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
