# Aphotic as an inference desktop

**Planning draft, 2026-10-05.** This is an implementation map, not a claim that the features below have shipped. Target branch: `dev`. The first public proof must use the Strata and NInfer installations already on this machine through one extensible contract while preserving Aphotic as a daily desktop; the design must also describe two GPUs, mixed workloads, and a session-preserving offload path.

Phase 0 has begun. Sonar/Shelves and the quality batch are already merged into `dev`. The Settings outline work and standalone llama.cpp claim adapter are in separate PRs, [#291](https://github.com/T-Crypt/aphotic-hypr/pull/291) and [#292](https://github.com/T-Crypt/aphotic-hypr/pull/292). Neither PR is part of the Strata implementation branch. OpenCode wiring is already merged in the plugin repository. This plan assumes those PRs remain unmerged until the operator reviews them.

## The promise

Aphotic makes a local inference machine understandable and usable while it remains a desktop. A user can see which engine and model are resident, which CPU threads, system RAM, and *specific GPU* memory they occupy, what is measured versus reserved, what is failing, and what Aphotic can safely yield. They can connect an engine they already run, or opt into a guided installation. Gaming, security, and development use the same resource vocabulary even when AI is disabled. Existing llama-swap/llama.cpp claims are the starting proof; Strata is the next engine integration, and NInfer tests whether the contract stays general.

The product phrase is **inference desktop** or **inference host mode**, rather than pretending that Aphotic is a new Linux kernel or a model runtime. Strata, NInfer, llama.cpp, llama-swap, Ollama, and later engines still own inference. Aphotic owns discovery, resource accounting, decisions, lifecycle coordination, and the interface. “Official OS for Strata” requires Strata maintainer agreement; until then the accurate claim is “Aphotic supports Strata.”

The signature demo is simple: Strata loads a large model; Flow shows its RAM and each GPU's VRAM rise, with the desktop's own cost visible; inference mode yields eligible shell effects; a gaming or second-engine claim shows exactly which device is contended; unloading restores the desktop. No guessed tokens per second, fabricated process ownership, or claim that all installed VRAM is usable on one card.

## What exists today, and the gaps

| Existing seam | Evidence in the current Aphotic tree | Work needed |
|---|---|---|
| Resource policy | `services/profile/ResourceEngine.qml` holds declared capacities and claims, asks about contention, and never kills a process. `SystemCapacity.qml` declares CPU threads and system RAM on demand. | Clarify CPU reservation semantics, RAM accounting, device-qualified resources, stale source states, and ownership. Preserve existing `claims`, `claimsOf()`, and `claimById()` consumers. |
| Hardware source | `services/GpuVramSource.qml` discovers GPU memory and per-process use. Its current `gpu-vram` capacity sums cards. NVIDIA process attribution is stronger than AMD; Intel integrated memory has no dedicated VRAM budget. | Introduce stable GPU IDs and per-device capacity/measurement. Keep a compatibility aggregate for old readers, without arbitrating against a sum that conceals placement. |
| Engine adapters | `services/ai/BackendClaims.qml` feeds models into `LocalInference`, Resource Engine, Flow passports and action receipts. Ollama, llama-swap, and LM Studio already have adapters. | Make engine capabilities explicit; add Strata first and NInfer second. Prevent a proxy and its underlying engine from being counted twice. |
| Desktop response | `services/ai/InferenceMode.qml` can react to local models, shelter cooperating profiles, tune rendering, and restore a saved render state after a shell crash. | Support more than one active engine without treating one selected model as the whole machine. Keep its automatic mode optional and compatible with existing behavior. |
| Interface | `modules/flow/FlowModel.js` already draws resource and workload nodes; the dashboard AI tab and settings AI pane exist. | Flow currently has one GPU/VRAM node, eight visible workloads, and fixed plane owner lists. Add device detail, engine ownership and useful overflow/drilldown. Reuse the AI tab instead of creating a second competing dashboard. |
| CLI | `Configs/.local/lib/aphotic/commands/` has performance commands; no engine lifecycle command was found in this review. | Add status first. Add attach/start/stop/load/unload only where the adapter proves it owns the process and the engine supports the operation. |

The local `feature/llamacpp-standalone` worktree had uncommitted adapter changes. PR #292 carries those changes on a fresh `dev` base; do not stack Strata work on the older worktree. The local checkout's `docs/ROADMAP.md` contains older priority text; `docs/DECISIONS.md` D-26 through D-29 supersede parts of it. Recheck Git and PR state at each phase boundary.

### Engine facts that shape the design

- **Strata is the next engine after Aphotic's existing llama-swap/llama.cpp path.** The inspected local checkout has `GET /health`, authenticated `GET /v1/status`, and authenticated `GET /metrics`. `/metrics` contains engine, live activity, recent request metadata, machine readings and history; it is not a Prometheus endpoint. `/status` can expose the end of an answer, so Aphotic should avoid it. `POST /unload` is available in the inspected server. Its Linux setup already chooses a model, downloads assets, builds where needed, and supports multi-GPU layer splitting. Aphotic should wrap that setup and preserve its choices, not fork its build logic.
- **The local Strata model identity is `qwen3.8-flash-next-iq2_xs`** in a setup-generated config. Qwen's model card calls its language core 125B with a further 51B n-gram embedding and 4B MTP parameters. GGUF listings often use 177B. Product copy should name the exact model and quantization, then explain which parameter count it uses rather than assert that one label is universally correct. A live `/v1/status` check was blocked by this session's network sandbox, so current residency and speed are unverified.
- **NInfer is the independent contract proof.** The inspected local fork offers `GET /health`, `/v1/models`, and `/slots`, plus OpenAI and Anthropic request routes. It is already set up on this machine for live tests. Its engine has GPU, host state and KV budgets; a CPU or host cache “spill” is not automatically an out-of-memory failure. The reviewed serving guide does not establish a general engine metrics endpoint or graceful model unload. Initial attachment should report only available facts; lifecycle management needs a process Aphotic started or a documented control API.
- **Other engines demonstrate the boundary.** llama.cpp's server has optional Prometheus `/metrics`; vLLM and SGLang expose their own metrics. OpenAI-compatible generation alone does not tell Aphotic what memory is resident, which GPU it sits on, or how to stop it. Give such a server a useful “connected, resource attribution unknown” state until a richer adapter is available.
- **Small decision engines belong in the same registry.** JEV-style local projects use different runtimes and model sizes; the checked [JEV-Local project](https://github.com/tapsin/jev-local) can sit on top of Ollama, vLLM, llama.cpp or LM Studio. Treat “1 ms decisions” as a benchmark hypothesis for a specific model, hardware and warmed request, not a generic compatibility promise. Register these as decision workloads, with CPU or GPU placement reported by their actual runtime.

## Design decisions

1. **Keep Resource Engine as the policy core.** It accepts owner reports and evaluates declared capacity. Hardware probes and HTTP clients live outside it. Never let the UI scrape processes independently and call that a claim.
2. **Represent three different numbers.** A *reservation* is what an owner plans to need; *resident* is memory or capacity it reports it holds; *observed* is what the OS or driver measures. Show source, timestamp, confidence and unit. Do not add resident and observed numbers for the same allocation. Do not treat page cache as a model's private RAM.
3. **Use device identities, not GPU list positions, for policy.** Normalize PCI bus ID or GPU UUID to a durable `deviceId`; index 0 is only a display/launch mapping. `gpu-vram/<deviceId>` is the arbitration unit. One engine may hold claims on two devices. An aggregate GPU value may appear as a summary but cannot decide whether a new engine fits on GPU 1.
4. **Make RAM and CPU meaningful.** `memory` uses MiB and reports process proportional/private memory where possible; show host `MemAvailable` separately from resident claims. `cpu` capacity is logical threads; a claim is a declared thread/core budget or affinity allocation, while measured CPU utilization is a separate percent. A Strata CPU expert pool can claim a budget if Strata supplies one; a process using 600% CPU does not become a six-thread reservation by inference.
5. **Connect read-only before taking control.** “Attached” means Aphotic can read a configured loopback endpoint. “Managed” means Aphotic launched the engine in a tracked user service or scope and can request a documented graceful stop. Existing engines are never killed, restarted, rewritten, or moved by attach. An engine can opt into more controls later.
6. **Separate fact from response.** A threshold crossing first creates a pressure event with evidence. User-selected rules can dim shell effects or request a graceful unload. Resource Engine's existing `suspend`/`keep`/`ignore` choice remains the decision point for contention. No global cache clearing, Node module deletion, `drop_caches`, kernel tuning, or automatic process killing.
7. **AI remains optional.** Engine adapters, downloads and AI UI need the AI layer or an explicit engine opt-in. Base Flow can still show CPU/RAM/GPU claims for gaming, dev and security. Dormant mode does no engine HTTP polling.

### Proposed engine contract, version 1

An adapter reports a stable engine instance, not only a model name:

```json
{
  "instanceId": "local:strata:127.0.0.1:8080",
  "owner": "strata",
  "mode": "attached",
  "state": "loading|ready|busy|unloaded|degraded|offline|unknown",
  "observedAt": "ISO-8601 timestamp",
  "capabilities": ["chat", "status", "metrics", "graceful-unload"],
  "models": [{"id": "qwen3.8-flash-next-iq2_xs", "role": "chat", "residency": "loaded"}],
  "claims": [
    {"resource": "memory", "amountMiB": 35000, "kind": "observed", "source": "proc-smaps-rollup"},
    {"resource": "gpu-vram/GPU-UUID", "amountMiB": 19000, "kind": "observed", "source": "nvml"}
  ],
  "activity": {"inFlight": 1, "queued": 0, "outputTokensPerSec": null}
}
```

The numbers above illustrate shape only. Never hardcode them as Strata defaults. In code, define enum validation, units, age limits, and a versioned normalizer. A source timeout changes health to `unknown`/`offline`, marks passports stale, and avoids claiming a successful unload. Use instance-qualified claim IDs to avoid collisions when two engines serve a model with the same name. Keep the existing `BackendClaims` model-entry API through an additive translation layer until all consumers migrate.

`engine.inspect`, `engine.start`, `engine.requestUnload`, and `engine.stop` are separate capabilities. Read-only adapters implement only `inspect`. Every control action receives a receipt: requested, confirmed by the source, failed, or timed out. A successful HTTP response alone is not proof that VRAM was released. For proxy chains, associate the proxy model with its backend instance and give the physical allocation one owner; the proxy gets request/route metrics but no duplicate memory claim.

An engine adapter is opt-in, named by a manifest/capability, and scoped to a configured local endpoint or a managed process. Do not hardcode engine IDs into core services. Validate loopback and path handling, store API keys in the existing secrets mechanism, redact logs, and never send prompts or request bodies to Flow. Show endpoint trust clearly if a user chooses a remote host; remote engine memory is not local hardware capacity.

## User experience

Flow becomes a hardware map with an **AI workload group** when enabled. The top line reports host RAM and CPU capacity, per-card VRAM and headroom, and the number of active engines. Each engine card shows model/quantization, connection mode, loaded/busy state, inference mode state, memory placement, queue and throughput when supplied, plus a link to the engine's own UI. Click a card for claim source, freshness, process identity, logs or recent errors. Display “unknown” wherever a source cannot prove a number.

The existing llama-swap AI tab becomes an **Engines** view. It can show llama-swap as a router, Strata and NInfer as direct engines, and an explicit route relationship. The same backend registry feeds the tab, Flow, notifications and CLI. An engine loaded through llama-swap appears once for physical resources. A plain OpenAI endpoint can still power chat with an “unattributed resources” badge. Keep the base shell palette, motion rules and visible daily-driver features; inference mode temporarily reduces only the effects it actually owns and restores their saved state.

Notifications are events, not per-second spam: engine ready, disconnected, load failed, out-of-memory confirmed, pressure sustained, unload requested/confirmed, and restore failed. Rate-limit by engine and event type; retain an incident timeline with source and time. Distinguish GPU allocation failure, Linux OOM kill, host swap activity, CUDA managed-memory migration, an intentional CPU expert path, and an engine's own cache eviction. “VRAM spill” is a diagnosis only when the backend or counters support it.

For a 96 GB RAM and two 5090 host, the UI must show two separate 32 GB-class device budgets based on *measured* capacity. A Strata layer split can claim both; NInfer pinned to one card claims that card only. A game on the display card can coexist with inference on the other when each budget fits. If the model needs CPU experts, show system RAM residency and CPU activity, not a false VRAM allocation. A small CPU decision model can register an independent low-latency workload without triggering full inference mode unless its operator asks for that policy.

## Delivery phases

Each row is an independently reviewable PR into `dev`, with an owner-neutral core and adapter code placed in the matching layer. Tickets should be created on epiq when implementation begins; do not invent board refs in this document. Every phase has a demo and a stop gate.

| Phase | Build | Prove before advancing |
|---|---|---|
| **0. Baseline and contracts** | Inventory the current `dev`, open PRs, plugin consumers and machine baseline. Use the existing Strata and NInfer installations to capture idle desktop and existing inference-mode CPU/RAM/VRAM, load time, restore behavior and a small repeatable prompt benchmark. Define engine-report schema, freshness, source precedence, IDs, units and privacy rules. No engine installation. | Existing desktop and llama-swap/llama.cpp claims still behave the same; baseline has commands, hardware IDs, raw measurements and reproducible inputs. |
| **1. Strata attach, first visible win** | Add opt-in endpoint configuration and a Strata adapter. Read `/health`, `/v1/status` and bounded `/metrics` with authentication. Translate model readiness, live activity and metric availability into `LocalInference`, `BackendClaims`, passports and Flow. Show existing running Strata without restarting it. Prefer event/state change where available; rate-limit required sampling and stop it when disconnected/disabled. | The current IQ2_XS instance appears in Flow and the AI tab with accurate readiness and source labels; unplug/restart/token failure yields stale/offline, never a ghost “loaded” model. Desktop inference mode enters/restores once. |
| **2. CPU/RAM truth and per-device GPU** | Extend the resource source contract for per-GPU identities and live RAM/CPU measurements. Upgrade `GpuVramSource`, `SystemCapacity`, Flow and contention to device-qualified resources. Attribute one PID across multiple GPUs; distinguish host-wide readings from engine-specific readings. Keep legacy aggregate readers working while moving arbitration to device keys. | Two GPU fixture demonstrates Strata on both, two engines on separate cards, and contention only on the affected card. RAM avoids double counting shared maps and page cache. Existing plugin claims and single-GPU behavior pass regression checks. |
| **3. Engine registry and NInfer** | Extract the v1 adapter interface from Strata work. Attach the already installed NInfer fork through health/models/slots, represent unsupported metrics as unknown, map its local PID claims when available, and validate two active engines plus llama-swap proxy deduplication. Add a minimal documented adapter template for a future CUDA/C++ engine. | Live Strata and NInfer runs on this machine pass the same contract and appear in Flow without engine names added to its policy code. One GPU alternating runs and a two GPU fixture show correct ownership. NInfer never advertises unload until a supported path exists. A third-party mock adapter can supply a model and claims without editing `ResourceEngine` or Flow. |
| **4. Guided setup and controls** | Add `aphotic inference status`, `engine list`, `attach`, `doctor` first. Make Strata setup a separately consented workflow that checks driver, GPU capability, RAM, free disk, model license/size, port, API key and version pin, then calls Strata's own installer. Download size and destination appear before consent; resumption and rollback are documented. Add managed user-service start/stop and documented graceful unload, with action receipts and a keep-existing-install path. | Fresh disposable VM install, update, interrupted download, port collision, failed build and uninstall are recoverable. Attaching an existing Strata never changes its files or process. No model download starts implicitly. |
| **5. Pressure, tuning and hosting** | Add an incident monitor that correlates per-device free VRAM, process allocations, engine errors, host `MemAvailable`, swap and OOM events without claiming certainty from one signal. Offer profiles such as “desktop balanced” and “maximum inference” as saved, reversible user choices. Add optional API exposure with bind address, authentication and firewall guidance; keep loopback default. Publish a reproducible benchmark recipe and source-visible tuning recommendations rather than universal magic settings. | Simulated OOM, driver disappearance, malformed telemetry and contention yield one clear notification and a correct recovery path. Benchmarks report desktop cost, inference throughput, startup time, and whether changes helped or hurt on at least a 4090 and a second hardware profile. |
| **6A. Session-preserving offload** | Build a small user-service supervisor outside Quickshell so `aphotic inference offload enter/exit/status` survives QS shutdown. Record active windows/workspaces and Aphotic state; park only named, restartable shell surfaces and services while leaving Hyprland and client connections alive. Offer a dry run, resource-savings estimate, rescue command and automatic recovery of Aphotic-owned state after a failed handover. | Existing windows, focus and workspaces survive a round trip on a disposable host. Engine remains usable from SSH/TTY; exit restores every parked Aphotic service and the same GUI session. If measured savings are small, say so and keep this a niche option. |
| **6B. Full compositor offload research** | Prototype Hyprland/client and GPU state checkpointing on a disposable machine. Test CRIU/CUDA support against this exact compositor, driver and app mix, and quantify which processes cannot be restored. Do not advertise or ship a command that kills Hyprland until the old session, windows and client state can be restored reliably. | First release gate is exact existing-session restoration after normal exit, failed engine start and crash. If the gate fails, leave full shutdown experimental and keep 6A as the supported offload mode. |
| **7. Ecosystem and partnership** | Publish the adapter specification, compatibility matrix, Strata guide, benchmark template and small demo. Enrich the existing llama-swap/llama.cpp path and add vLLM, SGLang or decision-engine adapters according to maintainer demand and useful observability, not a name count. Propose upstream integration points to Strata and NInfer maintainers; seek endorsement only after tested support. | A clean Aphotic install plus guided Strata setup works for a community tester. External contributors can build an adapter against the public contract. Claims and performance figures in the launch post link to runs and versions. |

### Implementation boundaries and likely touch points

- Core policy and source: `services/profile/ResourceEngine.qml`, `services/SystemCapacity.qml`, `services/GpuVramSource.qml`; add a small versioned report/normalizer and GPU inventory source. Avoid putting HTTP, `nvidia-smi` or engine names inside `ResourceEngine`.
- AI integration: `services/ai/BackendClaims.qml`, `LocalInference.qml`, `InferenceMode.qml`, new Strata and NInfer adapters, and adapter registration under the AI gate. `shell.qml` must construct any acting singleton in `_residentSingletons`.
- UI: `modules/flow/FlowModel.js`, Flow scene/detail, `modules/dashboard/AiChatTab.qml`, `modules/settings/panes/AiPane.qml`. Preserve static `PanelWindow` geometry and lazy hidden surfaces.
- CLI and installer: `Configs/.local/lib/aphotic/commands/`, layer manifests, setup wrapper, and user service. Any binary the shell invokes belongs in both base package manifests. Installer/systemd changes require the disposable dev VM gate.
- Separate plugin repository: use profile/adapter manifests and shared host seams; do not put plugin IDs in Aphotic core or make gaming/security/dev depend on AI.

## Headless mode choices

**Required release path:** desktop attach first, managed engine second, session-preserving offload next. The existing GUI session must return. That rules out presenting Hyprland shutdown and a new graphical login as the first supported offload mode. Hyprland must remain alive for 6A; a true shell-free mode needs successful checkpoint and restore of the compositor and its clients on supported hardware before release. Stopping a Wayland compositor ordinarily breaks its clients' connection, so merely saving window metadata cannot satisfy this gate.

| Option | Benefit | Cost and release decision |
|---|---|---|
| GUI inference mode, existing path | Daily driver remains active; immediate Strata demo; reversible rendering changes. | Some compositor/QS RAM and VRAM remain. **Ship first.** |
| Managed lean desktop session | Keep the existing windows while parking optional Aphotic services and QS surfaces. | Hyprland and application VRAM remain. **First supported offload release if measured savings justify it.** |
| No compositor inference host | Maximum reclaimable desktop resources; remote clients and SSH remain. | Exact existing-session restore needs a proven checkpoint path. **Research only until that test passes.** |

The “clean stale RAM/node modules” idea should be translated into evidence-led cleanup: detect a named idle service or cache with a documented owner and a safe stop/restart hook; show expected savings; ask before applying. Linux uses free RAM for useful cache. Deleting project dependencies or flushing cache in response to model load risks data loss or slower inference.

## Release bar and public story

The first Reddit-worthy release is **Phases 1 through 3**, tested against the Strata and NInfer installations already on this machine: attach both, show real RAM and GPU ownership in Flow, visibly yield and restore the desktop, demonstrate a third-party mock adapter, and publish before/after measurements on the current 4090. The guided installer can follow as Phase 4. The two 5090 story becomes a release claim only after per-device accounting and a tested dual-GPU machine. “Official Strata OS” is a possible partnership outcome, not an Aphotic launch slogan today.

Use a 60-90 second demo with real counters and an exact hardware/spec line: desktop at rest; Strata loading IQ2_XS; Flow's per-resource claims; an inference request; unload and restoration. Publish raw benchmark steps, versions, context length, quantization, prompt sizes, sampling, measured throughput and desktop overhead. Invite community adapter contributions with a small test fixture. The strongest claim is that Aphotic makes inference resource placement visible and actionable without giving up a daily desktop.

## Decisions recorded and choices still open

1. **Decided:** the first public milestone includes both Strata and NInfer through the common engine contract. Both are already usable on this host; integration begins by attaching to them. Aphotic's existing llama-swap/llama.cpp claims remain a regression baseline.
2. **Decided:** a supported offload mode restores the existing GUI session. A mode that destroys it and starts a new login does not meet the requirement.
3. **Suggested:** ship an explicitly consented, pinned Strata installer after the live attach milestone. Users can keep an existing setup. Confirm the exact supported distro and driver matrix before announcing the installer.
4. **Suggested:** build a local adapter and evidence first, then propose small upstream integration points to engine maintainers. Formal endorsement is separate.

## Sources checked

Local source: Aphotic `origin/dev` at `41306ca` during this review, plus the isolated PR branches for Settings and standalone llama.cpp; the local Strata server, telemetry, setup docs and config metadata; and the local NInfer fork serving guide. Live Strata HTTP remained unavailable from the sandbox, so active process state and current metrics still need a live check. GitHub PR state was checked on 2026-10-05.

External primary sources: [Strata README](https://github.com/Niko1221/Strata/blob/main/README.md), [Strata details/API](https://github.com/Niko1221/Strata/blob/main/docs/DETAILS.md), [Strata multi-GPU](https://github.com/Niko1221/Strata/blob/main/docs/MULTI_GPU.md), [Qwen model card](https://huggingface.co/Qwen/Qwen3.8-Flash-Next), [NInfer serving](https://github.com/Neroued/ninfer/blob/master/docs/serving.md), [llama.cpp server](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md), [vLLM metrics](https://github.com/vllm-project/vllm/blob/main/docs/usage/metrics.md), [SGLang metrics](https://github.com/sgl-project/sglang/blob/main/docs/docs/references/production_metrics.mdx), [JEV-Local](https://github.com/tapsin/jev-local), [NVIDIA NVML](https://docs.nvidia.com/deploy/nvml-api/latest/index.html), [CRIU GPU checkpointing](https://www.criu.org/GPU_Checkpointing).
