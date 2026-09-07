#!/usr/bin/env python3
"""Stage public Wiki Markdown as Jekyll collection documents."""
import argparse
import re
import shutil
from pathlib import Path

WIKI_URL = "https://github.com/T-Crypt/aphotic-hypr/wiki/"

def slugify(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")

def rewrite_wiki_links(text):
    def replace(match):
        label, target = match.groups()
        if target.startswith(("http://", "https://", "#", "/", "mailto:")):
            return match.group(0)
        page, anchor = (target.split("#", 1) + [""])[:2] if "#" in target else (target, "")
        page = page.removesuffix(".md")
        suffix = f"#{anchor}" if anchor else ""
        return f"[{label}]({{{{ '/docs/{slugify(page)}/' | relative_url }}}}{suffix})"
    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", replace, text)

def prepare(wiki_dir, output_dir):
    wiki_dir, output_dir = Path(wiki_dir), Path(output_dir)
    if output_dir.exists(): shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)
    written = []
    for source in sorted(wiki_dir.glob("*.md")):
        title = source.stem.replace("-", " ")
        slug = slugify(source.stem)
        header = f"---\nlayout: docs\ntitle: {title}\nwiki_source: {WIKI_URL}{source.stem}\n---\n\n"
        target = output_dir / f"{slug}.md"
        target.write_text(header + rewrite_wiki_links(source.read_text()))
        written.append(target)
    return written

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--wiki", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    print(f"Prepared {len(prepare(args.wiki, args.output))} Wiki pages")
