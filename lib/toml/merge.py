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


def merge_packages(base_path, layer_paths, custom_apps_path=None):
    """Merge package lists from a base TOML and zero or more layer TOMLs.

    Parameters
    - base_path: path to the base TOML describing `packages.prep` and
      `packages.main` lists.
    - layer_paths: iterable of paths to layer TOML files; each may also contain
      `packages.prep` and `packages.main` lists which are appended in order.
    - custom_apps_path: optional path to a newline-separated text file of
      additional package names to append to the `main` list.

    Returns a dict with keys "prep" and "main", each a deduplicated list
    preserving first-seen order. Deduplication ensures repeated packages
    across layers or custom lists don't appear multiple times.
    """
    base = _load(base_path)
    prep = list(base.get("packages", {}).get("prep", []))
    main = list(base.get("packages", {}).get("main", []))

    for layer_path in layer_paths:
        layer = _load(layer_path)
        prep.extend(layer.get("packages", {}).get("prep", []))
        main.extend(layer.get("packages", {}).get("main", []))

    if custom_apps_path:
        with open(custom_apps_path, "r", encoding="utf-8") as f:
            for line in f:
                app = line.strip()
                if app:
                    main.append(app)

    return {"prep": _dedup(prep), "main": _dedup(main)}


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True)
    parser.add_argument("--layers", default="")
    parser.add_argument("--custom-apps", default=None)
    parser.add_argument("--field", choices=["prep", "main"], required=True)
    args = parser.parse_args()

    layer_paths = [p for p in args.layers.split(",") if p]
    result = merge_packages(args.base, layer_paths, args.custom_apps)
    for pkg in result[args.field]:
        print(pkg)
