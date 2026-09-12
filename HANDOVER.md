# Host Handover

This branch adds concurrent host leases, terminal recovery and read-only
passthrough drift checks. It does not launch a VM or change boot configuration.

## Lease API

Run `aphotic handover rehearse plan.json` to read snapshots and check claims.
Review its output before `aphotic handover acquire plan.json --confirm`.
Use `aphotic handover status` to inspect journals and
`aphotic handover recover <id>` or `release <id>` to restore one workload.
Recovery of file stages works from a TTY without Quickshell. Shelter recovery
needs its registered provider; a missing provider leaves a recovery-required
journal and retains the reservation.

A plan uses this shape:

```json
{
  "id": "build-session-1",
  "owner": "dev",
  "plane": "dev",
  "label": "Build session",
  "resources": [
    {"key": "memory", "amount": 4096, "unit": "MiB", "exclusive": false},
    {"key": "cpu", "amount": 4, "unit": "threads", "exclusive": false}
  ],
  "stages": []
}
```

Each workload gets its own journal. CPU and RAM reservations share a bounded
capacity; device keys require exclusive ownership. Separate devices allow
concurrent leases. The CLI enforces a host reserve and Flow also checks its
existing claims. Reservations describe ownership, not measured usage or a
kernel allocation. They do not constrain processes outside Aphotic.

`handover.py` exposes `Engine.rehearse`, `acquire`, `status`, `load` and
`recover`. It inserts a reservation stage before the caller's ordered stages:

- `file`: `id`, `kind`, absolute `path`, replacement `content`. The executor
  saves content, mode, group and extended attributes before replacement. It
  refuses device paths, symlinks, hardlinks, another user's files, oversized
  files and its own journal directory. Recovery compares the current value
  with the value it wrote before restoring. File inode identity and timestamps
  are not restored by this version.
- `shelter`: `id`, `kind`, `owner`. The profile must pass `canShelter` and
  provide `handoverState()`, `handoverShelter(target)` and
  `handoverRestore(target)`. State is a string of at most 64 characters;
  the applied target is `sheltered`. Both setters must return true only after
  the state reader confirms the effect. Asynchronous providers need a future
  acknowledgement contract. Existing graceful-stop hooks do not meet this
  contract and the executor does not call them.

The executor snapshots all stages before the first effect, writes intent
before each stage, then records completion. It unwinds in reverse order after
failure. Failed undo retains the reservation. Journals live under
`$XDG_STATE_HOME/aphotic/handover` with private permissions. A nonblocking file
lock serializes acquisition and recovery. File writes and journals use atomic
replacement and fsync. Recovery preserves intervening user edits and reports
the conflict instead of claiming success.

`Handover.qml` watches the aggregate journal, exposes incomplete leases in Flow,
imports stage receipts and opens workload passports through the shipped API.
ResourceEngine rejects new claims that violate a lease. Restart does not resume
an incomplete transaction. One event-driven file watch is the new idle cost;
there is no discovery timer or libvirt poll. Known live AgentEvents sessions
require `acknowledgeAgents: true`; the bridge does not start the agent feed, so
this is not a fresh census when no existing reader holds that feed.

## Passthrough drift

`aphotic handover drift [--json]`, `aphotic doctor`, `aphotic status` and
`aphotic diff` report the optional `[passthrough]` section of `aphotic.toml`.
An absent section opts out and causes no hardware probe. An invalid section
reports INVALID. UNKNOWN evidence cannot produce READY.

```toml
[passthrough]
modules = ["vfio", "vfio_pci", "vfio_iommu_type1"]
kernel_parameters = ["intel_iommu=on"]
initramfs_images = ["/boot/initramfs-linux.img"]

[[passthrough.devices]]
pci = "0000:01:00.0"
vendor = "10de"
device = "2684"
driver = "vfio-pci"
group_members = ["0000:01:00.0", "0000:01:00.1"]
```

This is an example schema, not a configuration to apply. Record each device
and its actual group members after hardware discovery. Compare uses device
IDs, driver bindings, exact group membership, running kernel parameters,
loaded modules and the modules listed from each named initramfs image.
`lsinitcpio` failure yields UNKNOWN. Display ownership from boot-VGA and DRM
connectors can force MANUAL ACTION REQUIRED. Unknown display ownership blocks
READY. These checks do not prove that a guest boots or that its GPU resets.

`passthrough.py` exposes `validate`, `discover`, `compare` and `report`. Future
launch code must require READY immediately before transferring hardware. This
branch has no launch or rebind path, no automatic repair, no ACS override and
no boot apply. The existing reconcile command does not repair passthrough.

## Evidence and next work

Validated directly: CLI journal/file operations in temporary directories,
TTY recovery without a shell binary, independent lease release, lock refusal,
metadata restoration, malformed input handling and a windowless Quickshell
probe that compiles and instantiates the bridge.

Validated dry-run or mocked: failure after each stage, restart recovery,
provider shelter/restore hooks, resource conflicts and passthrough sysfs and
initramfs fixtures. Existing Flow, profile, plugin gates and status/diff checks
also run against this branch.

Requires physical VFIO validation: GPU ownership transfer, guest startup,
reset, Looking Glass, disk isolation during a real guest session and restoration
after guest exit. No host mutation occurred during development.

Next: integrate a real reversible background-work provider; add fresh agent
session acknowledgement; add a journal-backed workload-exit adapter and bounded
history retention; connect readiness to VM launch; implement the allowlisted
storage lease, automount exclusion and mountability-aware restoration; add GPU
and domain lifecycle stages with rollback tests. The companion VM experiment
remains local and inactive. It is not part of this PR.
