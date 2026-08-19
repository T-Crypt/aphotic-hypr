import tomllib


def _load(path):
    with open(path, "rb") as f:
        return tomllib.load(f)


def _dedup(seq):
    seen = set()
    out = []
    for item in seq:
        if item not in seen:
            seen.add(item)
            out.append(item)
    return out


def merge_packages(base_path, layer_paths, custom_apps_path=None):
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
