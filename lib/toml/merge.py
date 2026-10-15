import sys
import tomllib


def _load(path):
    """Load and parse a TOML file from `path`.

    Returns the parsed mapping on success. Prints an error to stderr and
    exits the process with status 1 if the file cannot be read or the TOML
    is malformed. Keeping this fatal behavior matches the script's usage
    pattern where a malformed input should stop downstream processing.
    """
    try:
        with open(path, "rb") as f:
            return tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        print(f"malformed {path}: {exc}", file=sys.stderr)
        sys.exit(1)


def _dedup(seq):
    """Deduplicate `seq` while preserving order.

    Returns a new list containing the first occurrence of each item from
    `seq`. This preserves ordering which is important for package lists
    where prep/main order can be meaningful to installers.
    """
    seen = set()
    out = []
    for item in seq:
        if item not in seen:
            seen.add(item)
            out.append(item)
    return out


def _read_list(path):
    """Read a newline-separated list file, stripping blanks and whitespace.

    `custom_apps.lst` and `custom_flatpaks.lst` are the two users of this:
    one package or Flatpak id per line, editable by hand, no comments.
    """
    out = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            item = line.strip()
            if item:
                out.append(item)
    return out


def merge_packages(base_path, layer_paths, custom_apps_path=None, custom_flatpaks_path=None):
    """Merge package and Flatpak lists from a base TOML and zero or more layers.

    Parameters
    - base_path: path to the base TOML describing `packages.prep`,
      `packages.main` and `flatpak.apps` lists.
    - layer_paths: iterable of paths to layer TOML files; each may also
      contain the same three lists, appended in order.
    - custom_apps_path: optional path to a newline-separated text file of
      additional package names to append to the `main` list.
    - custom_flatpaks_path: optional path to a newline-separated text file
      of additional Flatpak application ids to append to the `flatpak` list.

    Returns a dict with keys "prep", "main" and "flatpak", each a
    deduplicated list preserving first-seen order. Deduplication ensures
    repeated entries across layers or custom lists don't appear twice.
    """
    base = _load(base_path)
    prep = list(base.get("packages", {}).get("prep", []))
    main = list(base.get("packages", {}).get("main", []))
    flatpak = list(base.get("flatpak", {}).get("apps", []))

    for layer_path in layer_paths:
        layer = _load(layer_path)
        prep.extend(layer.get("packages", {}).get("prep", []))
        main.extend(layer.get("packages", {}).get("main", []))
        flatpak.extend(layer.get("flatpak", {}).get("apps", []))

    if custom_apps_path:
        main.extend(_read_list(custom_apps_path))
    if custom_flatpaks_path:
        flatpak.extend(_read_list(custom_flatpaks_path))

    return {"prep": _dedup(prep), "main": _dedup(main), "flatpak": _dedup(flatpak)}


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True)
    parser.add_argument("--layers", default="")
    parser.add_argument("--custom-apps", default=None)
    parser.add_argument("--custom-flatpaks", default=None)
    parser.add_argument("--field", choices=["prep", "main", "flatpak"], required=True)
    args = parser.parse_args()

    layer_paths = [p for p in args.layers.split(",") if p]
    result = merge_packages(args.base, layer_paths, args.custom_apps, args.custom_flatpaks)
    for pkg in result[args.field]:
        print(pkg)
