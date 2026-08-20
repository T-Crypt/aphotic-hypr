# noctis CLI scaffold

Drop this into the root of `Noctis-Hypr`:

```
Noctis-Hypr/
├── bin/noctis
├── lib/noctis/
│   ├── globalcontrol.sh
│   ├── restore.manifest
│   └── commands/cmd_*.sh
└── docs/cli.md
```

Then symlink onto PATH:

```sh
ln -s "$(pwd)/bin/noctis" ~/.local/bin/noctis
```

Try it:

```sh
noctis --help
noctis doctor
noctis backup create --label test
noctis backup list
```

See `docs/cli.md` for the full command reference and what's done vs stubbed.
