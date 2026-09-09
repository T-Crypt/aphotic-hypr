# Graph Report - Aphotic-Hypr  (2026-09-09)

## Corpus Check
- Large corpus: 347 files · ~4,893,324 words. Semantic extraction will be expensive (many Claude tokens). Consider running on a subfolder.

## Summary
- 1077 nodes · 1594 edges · 108 communities (75 shown, 21 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 130 edges (avg confidence: 0.63)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Plugin Management
- Backup System
- Greeter Config
- Install Conflicts
- Agent Statusline
- Playground Commands
- Wallpaper Theming
- AMD GPU Setup
- TOML Merge
- Global Utilities
- Agent Usage Tracking
- Palette Clamping
- VPN Commands
- Exploit Disclaimer
- Plugin State
- Config Deployment
- Agent Hook
- Install Entry
- Install Wizard
- Bar Commands
- Community 20
- Community 21
- Community 22
- Community 23
- Community 24
- Community 25
- Community 26
- Community 27
- Community 28
- Community 29
- Community 30
- Community 31
- Community 32
- Community 33
- Community 34
- Community 35
- Community 36
- Community 37
- Community 38
- Community 39
- Community 40
- Community 41
- Community 42
- Community 43
- Community 44
- Community 45
- Community 46
- Community 47
- Community 48
- Community 49
- Community 50
- Community 51
- Community 52
- Community 53
- Community 54
- Community 55
- Community 56
- Community 57
- Community 58
- Community 59
- Community 60
- Community 61
- Community 62
- Community 63
- Community 64
- Community 65
- Community 66
- Community 67
- Community 68
- Community 69
- Community 70
- Community 71
- Community 72
- Community 73
- Community 74
- Community 75
- Community 76
- Community 77
- Community 78
- Community 79
- Community 80
- Community 81
- Community 82
- Community 83
- Community 84
- Community 85
- Community 86
- Community 87
- Community 88
- Community 89
- Community 90
- Community 91
- Community 92
- Community 93
- Community 94
- Community 95

## God Nodes (most connected - your core abstractions)
1. `main()` - 47 edges
2. `aphotic_cmd_plugin()` - 21 edges
3. `merge_packages()` - 16 edges
4. `_aphotic_theme_apply()` - 14 edges
5. `build_record()` - 13 edges
6. `build_usage_record()` - 13 edges
7. `_aphotic_plugin_registry_sync()` - 12 edges
8. `aphotic_cmd_theme()` - 11 edges
9. `_aphotic_plugin_dir()` - 10 edges
10. `_aphotic_plugin_install()` - 10 edges

## Surprising Connections (you probably didn't know these)
- `test_percentages_are_clamped_and_bad_input_drops_the_window()` --calls--> `window()`  [INFERRED]
  tests/test_agent_statusline.py → Configs/.local/lib/aphotic/agent_statusline.py
- `test_unparseable_reset_falls_back_to_zero()` --calls--> `window()`  [INFERRED]
  tests/test_agent_statusline.py → Configs/.local/lib/aphotic/agent_statusline.py
- `test_missing_rate_limits_is_empty_not_zero()` --calls--> `build_record()`  [INFERRED]
  tests/test_agent_statusline.py → Configs/.local/lib/aphotic/agent_statusline.py
- `test_real_payload_shape_yields_both_windows_and_context()` --calls--> `build_record()`  [INFERRED]
  tests/test_agent_statusline.py → Configs/.local/lib/aphotic/agent_statusline.py
- `test_record_is_json_serialisable()` --calls--> `build_record()`  [INFERRED]
  tests/test_agent_statusline.py → Configs/.local/lib/aphotic/agent_statusline.py

## Import Cycles
- None detected.

## Communities (108 total, 21 thin omitted)

### Community 0 - "Plugin Management"
Cohesion: 0.08
Nodes (57): aphotic_cmd_plugin(), _aphotic_plugin_action_entry_json(), _aphotic_plugin_actions_json(), _aphotic_plugin_annotate_remote_json(), _aphotic_plugin_chat_provider_json(), _aphotic_plugin_cli_json(), _aphotic_plugin_describe(), _aphotic_plugin_dir() (+49 more)

### Community 1 - "Backup System"
Cohesion: 0.08
Nodes (40): _aphotic_backup_clean(), _aphotic_backup_create(), _aphotic_backup_list(), _aphotic_backup_revert(), aphotic_cmd_backup(), cmd_backup.sh script, aphotic_cmd_config(), cmd_config.sh script (+32 more)

### Community 2 - "Greeter Config"
Cohesion: 0.10
Nodes (41): aphotic_cmd_greeter(), _aphotic_greeter_palette_json(), _aphotic_greeter_sync(), _aphotic_greeter_write(), cmd_greeter.sh script, aphotic_cmd_scheme(), cmd_scheme.sh script, aphotic_cmd_sddm() (+33 more)

### Community 3 - "Install Conflicts"
Cohesion: 0.11
Nodes (18): _announce_conflicting_packages(), check_conflicting_packages(), conflicting_package_role(), prompt_conflicting_packages(), conflicts.sh script, guided_configure(), _guided_heading(), guided_intro() (+10 more)

### Community 4 - "Agent Statusline"
Cohesion: 0.14
Nodes (24): atomic_write(), build_record(), context_window(), format_line(), main(), merge(), Keep other providers' entries when writing this one. The file is per-provider,…, The line Claude Code prints in place of its default status line. Aphotic claims… (+16 more)

### Community 5 - "Playground Commands"
Cohesion: 0.12
Nodes (18): aphotic_cmd_play(), cmd_play.sh script, aphotic_cmd_play_guess(), guess.sh script, aphotic_cmd_play_hangman(), hangman.sh script, _aphotic_play_best_score(), _aphotic_play_record_low() (+10 more)

### Community 6 - "Wallpaper Theming"
Cohesion: 0.13
Nodes (23): apply_palette_clamp(), apply_theme_pins(), apply_wallpaper(), list_themes(), list_wallpapers(), main(), parse_engine_pin(), parse_palette_pin() (+15 more)

### Community 7 - "AMD GPU Setup"
Cohesion: 0.12
Nodes (17): detect_amd(), setup_amd(), amd.sh script, resolve_ollama_accel_package(), setup_gpu_compute(), gpu_compute.sh script, configure_nvidia_modules(), detect_nvidia() (+9 more)

### Community 8 - "TOML Merge"
Cohesion: 0.13
Nodes (21): _dedup(), _load(), merge_packages(), Deduplicate `seq` while preserving order. Returns a new list containing the…, Merge package lists from a base TOML and zero or more layer TOMLs. Parameters -…, Load and parse a TOML file from `path`. Returns the parsed mapping on success.…, test_base_only(), test_base_plus_multiple_layers_dedup() (+13 more)

### Community 9 - "Global Utilities"
Cohesion: 0.11
Nodes (10): aphotic_err(), aphotic_json_set(), aphotic_matugen_run(), aphotic_plugin_set_enabled(), aphotic_plugins_set_security_index_trusted(), aphotic_record_change(), aphotic_require(), aphotic_safe_mode_set() (+2 more)

### Community 10 - "Agent Usage Tracking"
Cohesion: 0.16
Nodes (20): build_usage_record(), main(), Path, Write `record` to `path` atomically as JSON. Creates parent directories if…, CLI entrypoint. Expects a single argument: the directory where the generated…, Aggregate local AI-CLI transcript token usage into a small JSON record. Reads…, Sum token usage in a single transcript file for `today`. Reads a transcript…, Build a compact usage record aggregating today's token counts. Parameters: -… (+12 more)

### Community 11 - "Palette Clamping"
Cohesion: 0.19
Nodes (20): clamp_color(), clamp_hue(), clamp_linear(), clamp_palette(), hex_to_hls(), hls_to_hex(), main(), Clamp a wallpaper-derived pywal palette to a theme's own anchor palette.… (+12 more)

### Community 12 - "VPN Commands"
Cohesion: 0.15
Nodes (16): aphotic_cmd_vpn(), _aphotic_vpn_auto_connect(), _aphotic_vpn_autostart(), _aphotic_vpn_config_path(), _aphotic_vpn_connect(), _aphotic_vpn_disconnect(), _aphotic_vpn_pid(), _aphotic_vpn_status() (+8 more)

### Community 13 - "Exploit Disclaimer"
Cohesion: 0.20
Nodes (13): any_layer_is_exploit_family(), expand_layer_bundles(), exploit_disclaimer_gate(), layer_in_csv(), layer_is_exploit_family(), notice_exploit_failure(), _predicate_exploit_family(), print_exploit_disclaimer() (+5 more)

### Community 14 - "Plugin State"
Cohesion: 0.17
Nodes (13): _aphotic_state_actual_plugins(), _aphotic_state_desired_plugins(), _aphotic_state_plugin_drift(), _aphotic_state_plugins_declared(), state.sh script, APHOTIC_DOTS_DIR, fail(), HOME (+5 more)

### Community 15 - "Config Deployment"
Cohesion: 0.22
Nodes (14): main(), build_shell_shaders(), config_sync(), deploy_user_configs(), install_vscode_extensions(), kill_omarchy_shell_if_running(), kill_orphan_qs_processes(), restart_shell_if_enabled() (+6 more)

### Community 16 - "Agent Hook"
Cohesion: 0.20
Nodes (14): atomic_write(), cached_session(), main(), model_from_transcript(), prune_runs(), Last model named in the harness transcript, or "" if there is none.…, The last session file written for this session, or {}., aphotic agent hook worker -- see agent_hook.sh for why this is one process and… (+6 more)

### Community 17 - "Install Entry"
Cohesion: 0.15
Nodes (11): print_banner(), print_help(), print_stage(), install.sh script, offer_start_hyprland(), hyprland_launch.sh script, resolve_python_bin(), python.sh script (+3 more)

### Community 18 - "Install Wizard"
Cohesion: 0.24
Nodes (12): load_saved_config(), prompt_layers(), prompt_profile(), prompt_theme(), read_saved_layers(), resolve_config(), wizard.sh script, _wizard_repo_dir() (+4 more)

### Community 19 - "Bar Commands"
Cohesion: 0.21
Nodes (11): _aphotic_bar_cycle(), _aphotic_bar_style(), aphotic_cmd_bar(), cmd_bar.sh script, aphotic_err(), aphotic_require(), fail(), PATH (+3 more)

### Community 20 - "Community 20"
Cohesion: 0.19
Nodes (9): aphotic_cmd_packages(), cmd_packages.sh script, aphotic_err(), aphotic_require(), fail(), HOME, PATH, reset_logs() (+1 more)

### Community 21 - "Community 21"
Cohesion: 0.23
Nodes (11): backup_root(), prune_backups(), backup.sh script, snapshot_config(), APHOTIC_BACKUP_ROOT, fail(), HOME, test_backup.sh script (+3 more)

### Community 22 - "Community 22"
Cohesion: 0.14
Nodes (8): Test the main payload processing logic (simulated via helper functions)., Record contains required fields with correct types., Optional fields are included in record when in payload., Optional fields are skipped when empty or None., spawnedAgentId is extracted from tool_response., tool_response fields are optional., Invalid payloads are skipped with status 0 (not processed)., TestPayloadProcessing

### Community 23 - "Community 23"
Cohesion: 0.21
Nodes (7): Every event says which harness produced it and, once known, which model…, Run main() against an isolated state dir and return its events., Claude Code sends no `harness`, so the default has to be written., A non-Claude adapter states its own harness and keeps it., The /clear case: SessionStart names no model, the transcript does., Re-stating it per tool call would bloat a size-capped log., TestHarnessAndModelIdentity

### Community 24 - "Community 24"
Cohesion: 0.31
Nodes (9): aphotic_cmd_diff(), _aphotic_diff_line(), cmd_diff.sh script, aphotic_cmd_sync(), _aphotic_sync_missing_packages(), _aphotic_sync_outdated_plugins(), _aphotic_sync_run(), _aphotic_sync_write_status() (+1 more)

### Community 25 - "Community 25"
Cohesion: 0.29
Nodes (9): _elapsed_str(), _install_activity_line(), install_package_list(), install_software(), _package_in_list(), print_package_plan(), report_failed_optional_packages(), packages.sh script (+1 more)

### Community 27 - "Community 27"
Cohesion: 0.18
Nodes (5): Test event name mapping and record building., EVENT_NAMES maps hook event names to internal names., STATUS maps event types to execution statuses., TestCachedSession, TestEventMapping

### Community 28 - "Community 28"
Cohesion: 0.24
Nodes (9): APHOTIC_DOTS_DIR, APHOTIC_PLUGINS_REPO, check_verdict(), fail(), HOME, test_plugin_host_gate.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME (+1 more)

### Community 29 - "Community 29"
Cohesion: 0.20
Nodes (10): APHOTIC_DOTS_DIR, CALL_LOG, fail(), HOME, PATH, test_recovery.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME (+2 more)

### Community 30 - "Community 30"
Cohesion: 0.24
Nodes (6): aphotic_cmd_agent(), cmd_agent.sh script, APHOTIC_STATE_HOME, fail(), HOME, test_agent_usage_cmd.sh script

### Community 31 - "Community 31"
Cohesion: 0.36
Nodes (8): detect_aur_helper(), ensure_aur_helper(), ensure_pacman_db(), install_yay(), aur.sh script, fail(), PATH, test_aur.sh script

### Community 32 - "Community 32"
Cohesion: 0.29
Nodes (6): ensure_multilib_repo(), multilib_repo_present(), multilib.sh script, fail(), multilib_repo_present(), test_multilib.sh script

### Community 33 - "Community 33"
Cohesion: 0.27
Nodes (9): check_aur(), check_official(), load_packages(), main(), Collect package names referenced in profiles TOML files. Scans…, Check every package referenced in profiles/*.toml against official Arch repos…, Return True if `pkg` exists in official Arch repos, False if not, or None on…, Return True if `pkg` exists in the AUR, False if not, or None on error. Uses… (+1 more)

### Community 34 - "Community 34"
Cohesion: 0.20
Nodes (6): sweep continues if a session file can't be deleted., Test stale session cleanup., sweep removes session files older than STALE_SECONDS., sweep keeps session files newer than STALE_SECONDS., sweep ignores files that don't end with .json., TestSweep

### Community 35 - "Community 35"
Cohesion: 0.20
Nodes (6): Test old run file cleanup., prune_runs removes oldest files when count exceeds MAX_RUNS., prune_runs keeps all files when under MAX_RUNS., prune_runs only counts .jsonl files., prune_runs continues if a file can't be deleted., TestPruneRuns

### Community 36 - "Community 36"
Cohesion: 0.20
Nodes (6): Test atomic file writing prevents partial/corrupted writes., atomic_write creates file with correct content., atomic_write overwrites existing files atomically., atomic_write cleans up temp files after write., atomic_write uses process ID in temp filename., TestAtomicWrite

### Community 37 - "Community 37"
Cohesion: 0.22
Nodes (9): APHOTIC_DOTS_DIR, APHOTIC_PLUGINS_REPO, fail(), HOME, LIB_DIR, test_plugin_harness_hook.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME (+1 more)

### Community 38 - "Community 38"
Cohesion: 0.24
Nodes (9): APHOTIC_DOTS_DIR, fail(), HOME, new_plugin(), PATH, test_plugin_install_deps.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME (+1 more)

### Community 39 - "Community 39"
Cohesion: 0.22
Nodes (8): APHOTIC_DOTS_DIR, APHOTIC_PLUGINS_REPO, fail(), HOME, test_plugin_registry_drift.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME

### Community 40 - "Community 40"
Cohesion: 0.24
Nodes (9): APHOTIC_DOTS_DIR, APHOTIC_PLUGINS_REPO, fail(), HOME, test_plugin_update.sh script, write_manifest(), XDG_CONFIG_HOME, XDG_DATA_HOME (+1 more)

### Community 41 - "Community 41"
Cohesion: 0.36
Nodes (8): _code(), Path, _qml_files(), A QML singleton nothing references is never constructed, so it never runs.…, File contents with // comments removed., _singletons(), test_every_singleton_is_referenced(), test_finds_singletons()

### Community 42 - "Community 42"
Cohesion: 0.22
Nodes (8): APHOTIC_DOTS_DIR, APHOTIC_THEMES_REPO, fail(), HOME, test_theme_download.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME

### Community 43 - "Community 43"
Cohesion: 0.22
Nodes (9): APHOTIC_DOTS_DIR, APHOTIC_SDDM_THEME_DIR, fail(), HOME, PATH, test_theme_ensure_default.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME (+1 more)

### Community 44 - "Community 44"
Cohesion: 0.22
Nodes (9): APHOTIC_DOTS_DIR, APHOTIC_SDDM_THEME_DIR, fail(), HOME, PATH, test_theme_refresh_gtk.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME (+1 more)

### Community 45 - "Community 45"
Cohesion: 0.36
Nodes (7): aphotic_cmd_displaymanager(), _aphotic_dm_print_validation_steps(), _aphotic_dm_status(), _aphotic_dm_switch(), _aphotic_dm_switch_to_greetd(), _aphotic_dm_switch_to_sddm(), cmd_displaymanager.sh script

### Community 46 - "Community 46"
Cohesion: 0.25
Nodes (8): aphotic_plugins_security_index_trusted(), APHOTIC_DOTS_DIR, fail(), HOME, test_plugin_v2.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME

### Community 47 - "Community 47"
Cohesion: 0.33
Nodes (7): blackarch_repo_present(), ensure_blackarch_repo(), print_blackarch_warning(), blackarch.sh script, blackarch_repo_present(), fail(), test_blackarch.sh script

### Community 48 - "Community 48"
Cohesion: 0.25
Nodes (8): APHOTIC_DOTS_DIR, fail(), HOME, PATH, test_diff_cli.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME

### Community 49 - "Community 49"
Cohesion: 0.25
Nodes (8): APHOTIC_DOTS_DIR, APHOTIC_PLUGINS_REPO, fail(), HOME, test_plugin_v3.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME

### Community 50 - "Community 50"
Cohesion: 0.28
Nodes (8): APHOTIC_DOTS_DIR, fail(), HOME, install_plugin(), test_reconcile_rollback.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME

### Community 51 - "Community 51"
Cohesion: 0.25
Nodes (8): APHOTIC_DOTS_DIR, fail(), HOME, PATH, test_status_cli.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME

### Community 52 - "Community 52"
Cohesion: 0.36
Nodes (7): parametrize, Every path that regenerates the palette must also deploy the GTK4 stylesheet.…, A grep-shaped test fails on its own explanatory prose otherwise. Both halves…, source_files(), strip_comments(), test_known_palette_path_deploys_gtk4_stylesheet(), test_no_unlisted_path_runs_a_colour_engine()

### Community 53 - "Community 53"
Cohesion: 0.25
Nodes (5): Test event log rotation., trim keeps only last KEEP_LINES when file exceeds MAX_BYTES., trim doesn't modify file when under MAX_BYTES., trim handles empty or missing events file gracefully., TestTrim

### Community 54 - "Community 54"
Cohesion: 0.25
Nodes (5): Test run archive file creation and size limits., Run file is created and appended for new sessions., Run file stops appending when it reaches MAX_RUN_BYTES., prune_runs is invoked when a new session starts., TestRunFileManagement

### Community 55 - "Community 55"
Cohesion: 0.29
Nodes (7): APHOTIC_DOTS_DIR, fail(), HOME, test_backup_targets.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME

### Community 56 - "Community 56"
Cohesion: 0.39
Nodes (6): fail(), PATH, test_config_sync_orphan_kill.sh script, write_pgrep(), write_ps_follower(), write_ps_leader()

### Community 57 - "Community 57"
Cohesion: 0.29
Nodes (7): APHOTIC_DOTS_DIR, fail(), HOME, test_plugin_action_capability.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME

### Community 58 - "Community 58"
Cohesion: 0.29
Nodes (7): APHOTIC_DOTS_DIR, fail(), HOME, test_plugin_chat_provider.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME

### Community 59 - "Community 59"
Cohesion: 0.29
Nodes (7): APHOTIC_DOTS_DIR, fail(), HOME, test_plugin_cli_dispatch.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME

### Community 60 - "Community 60"
Cohesion: 0.29
Nodes (7): APHOTIC_DOTS_DIR, fail(), HOME, test_plugin_fullscreen_overlay_surface.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME

### Community 61 - "Community 61"
Cohesion: 0.29
Nodes (7): APHOTIC_DOTS_DIR, fail(), HOME, test_plugin_overlay_surface.sh script, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME

### Community 62 - "Community 62"
Cohesion: 0.48
Nodes (6): aphotic_cmd_report(), _aphotic_report_list(), _aphotic_report_new(), _aphotic_report_render(), _aphotic_report_template(), cmd_report.sh script

### Community 63 - "Community 63"
Cohesion: 0.43
Nodes (6): render_assistant_prompt(), resolve_assistant(), resolve_assistant_model_via_llmfit(), setup_assistant(), assistant.sh script, write_assistant_config()

### Community 65 - "Community 65"
Cohesion: 0.60
Nodes (4): switcher_finish(), switcher_open(), switcher_stop_watch(), switcher_watch_release()

### Community 66 - "Community 66"
Cohesion: 0.53
Nodes (5): aphotic_cmd_doctor(), _aphotic_doctor_check(), _aphotic_doctor_layer_plugins(), _aphotic_doctor_version_drift(), cmd_doctor.sh script

### Community 67 - "Community 67"
Cohesion: 0.60
Nodes (6): aphotic_plugin_cli_help(), aphotic_plugin_cli_resolve(), aphotic_plugin_cli_top_level(), aphotic_plugin_is_enabled(), aphotic_toml_get(), aphotic_toml_get_array()

### Community 68 - "Community 68"
Cohesion: 0.47
Nodes (4): detect_dotfile_manager(), detect_environment(), detect_omarchy(), detect.sh script

### Community 70 - "Community 70"
Cohesion: 0.33
Nodes (4): Test session state file creation and updates., Session state file has correct JSON format., Session file is deleted when SessionEnd event occurs., TestSessionFileManagement

### Community 71 - "Community 71"
Cohesion: 0.33
Nodes (4): Integration tests for the full event processing pipeline., Complete session from start to end processes correctly., Malformed JSON payloads don't crash the system., TestIntegration

### Community 72 - "Community 72"
Cohesion: 0.70
Nodes (4): aphotic script, _aphotic_dispatch(), _aphotic_list_commands(), _aphotic_usage()

### Community 73 - "Community 73"
Cohesion: 0.60
Nodes (4): prepare(), Stage public Wiki Markdown as Jekyll collection documents., rewrite_wiki_links(), slugify()

### Community 74 - "Community 74"
Cohesion: 0.50
Nodes (4): APHOTIC_STATE_HOME, fail(), PATH, test_agent_hook.sh script

### Community 75 - "Community 75"
Cohesion: 0.50
Nodes (4): APHOTIC_BACKUP_ROOT, fail(), HOME, test_uninstall.sh script

### Community 77 - "Community 77"
Cohesion: 0.83
Nodes (3): fail(), mkrepo(), test_doctor_version_drift.sh script

### Community 78 - "Community 78"
Cohesion: 0.83
Nodes (3): code(), fail(), test_profile_substrate.sh script

## Knowledge Gaps
- **211 isolated node(s):** `$schema`, `plugin`, `agent_hook.sh script`, `agent_statusline.sh script`, `cmd_agent.sh script` (+206 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 407 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **21 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `main()` connect `Config Deployment` to `Community 32`, `Install Conflicts`, `Community 68`, `Community 69`, `AMD GPU Setup`, `Exploit Disclaimer`, `Community 47`, `Install Entry`, `Install Wizard`, `Community 21`, `Community 25`, `Community 63`, `Community 31`?**
  _High betweenness centrality (0.019) - this node is a cross-community bridge._
- **Why does `TestTrim` connect `Community 53` to `Community 27`?**
  _High betweenness centrality (0.003) - this node is a cross-community bridge._
- **Are the 12 inferred relationships involving `merge_packages()` (e.g. with `test_base_only()` and `test_base_plus_multiple_layers_dedup()`) actually correct?**
  _`merge_packages()` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `build_record()` (e.g. with `test_merge_discards_a_record_from_a_different_schema()` and `test_merge_keeps_another_providers_section()`) actually correct?**
  _`build_record()` has 8 INFERRED edges - model-reasoned connections that need verification._
- **What connects `$schema`, `plugin`, `agent_hook.sh script` to the rest of the system?**
  _211 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Plugin Management` be split into smaller, more focused modules?**
  _Cohesion score 0.07540983606557378 - nodes in this community are weakly interconnected._
- **Should `Backup System` be split into smaller, more focused modules?**
  _Cohesion score 0.07529411764705882 - nodes in this community are weakly interconnected._