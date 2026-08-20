#!/usr/bin/env bash
# Unified launcher: apps (drun) + open windows (window) + shell commands (run)
# in one search, so there's no separate mode-switch step.

rofi -show combi -combi-modi "drun,window,run" -theme "$HOME/.config/rofi/style.rasi"
