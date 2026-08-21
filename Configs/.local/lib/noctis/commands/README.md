# Noctis CLI Commands

This directory contains the individual command implementations for the `noctis` CLI tool.

## Adding New Commands

To add a new command:
1. Create a file named `cmd_<name>.sh` following the existing pattern
2. The file should define a function named `noctis_cmd_<name>()`
3. Include proper documentation with @cmd, @cmd.desc, and @cmd.opt annotations
4. The dispatcher will automatically discover and load the command

## Command Structure

Each command file should:
- Start with a shebang (`#!/usr/bin/env bash`)
- Include a header comment with documentation
- Define the `noctis_cmd_<name>()` function
- Use the helper functions from `globalcontrol.sh` (noctis_log, noctis_ok, noctis_warn, noctis_err)
- Follow the existing pattern for help text and argument parsing

## Available Helper Functions

- `noctis_log(message)` - Log a message with cyan prefix
- `noctis_ok(message)` - Log a success message with green prefix  
- `noctis_warn(message)` - Log a warning message with yellow prefix
- `noctis_err(message)` - Log an error message with red prefix
- `noctis_confirm(prompt)` - Prompt user for confirmation
- `noctis_require(binary)` - Check if a binary exists on PATH

## Environment Variables

The following variables are available:
- `NOCTIS_VERSION` - The version of Noctis
- `NOCTIS_CONFIG_HOME` - XDG config directory for Noctis
- `NOCTIS_STATE_HOME` - XDG state directory for Noctis
- `NOCTIS_DATA_HOME` - XDG data directory for Noctis
- `NOCTIS_RUNTIME_DIR` - XDG runtime directory for Noctis
- `NOCTIS_CONFIG_FILE` - Path to the main config file
- `NOCTIS_BACKUP_DIR` - Directory for backups
- `NOCTIS_DOTS_DIR` - Path to the dots repository
- `QUICKSHELL_CONFIG_DIR` - Quickshell configuration directory