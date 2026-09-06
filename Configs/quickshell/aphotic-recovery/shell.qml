// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import Quickshell

// A separate quickshell config from the desktop shell, on purpose. This
// is what runs when `qs -c aphotic` will not stay up, so it can share
// nothing with it: no qs.* import, no theme, no plugin, no settings
// file. Everything it needs is in this directory, and everything it
// knows comes from `aphotic recovery status --json`.
//
// It is not a fallback shell and must never grow into one. Four buttons,
// one diagnosis, then it gets out of the way.
ShellRoot {
    Variants {
        model: Quickshell.screens

        RecoveryWindow {}
    }
}
