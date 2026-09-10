#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors
#
# Wallpaper thumbnail and poster-frame cache.
#
# Two modes, both taking source paths on argv and printing a JSON object
# mapping each source path to the generated file:
#
#   wallpaper_thumbs.py SRC...             500px-tall previews for the picker
#   wallpaper_thumbs.py --poster SRC...    full-resolution stills
#
# A poster only means something for a video: it is the frame wallust derives
# the palette from and the image `awww img` actually displays, since neither
# speaks video. Asking for the poster of a still image returns the image
# itself rather than a pointless re-encode.
#
# The cache key is a hash of the absolute path, mtime and size, not the
# basename. Two themes are free to ship a wallpaper with the same filename,
# and editing one in place produces a new key rather than a stale hit.

import hashlib
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

VIDEO_EXTENSIONS = {".mp4", ".webm", ".mov", ".mkv", ".m4v"}

THUMB_DIR = os.path.expanduser("~/.cache/aphotic/wallpaper-thumbs")
POSTER_DIR = os.path.expanduser("~/.cache/aphotic/wallpaper-posters")

THUMB_HEIGHT = 500
# ffmpeg refuses odd dimensions for some encoders; -2 rounds the derived
# width to an even number instead of failing the whole run.
THUMB_SCALE = f"scale=-2:{THUMB_HEIGHT}"

# How far into a video to look for a representative frame. The opening
# second of a clip is very often black or a fade-in.
SEEK_SECONDS = 5

MAX_WORKERS = 8


def is_video(path):
    return os.path.splitext(path)[1].lower() in VIDEO_EXTENSIONS


def cache_key(path):
    try:
        st = os.stat(path)
    except OSError:
        return None
    raw = f"{os.path.abspath(path)}\0{int(st.st_mtime)}\0{st.st_size}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:32]


def run(cmd):
    try:
        proc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return proc.returncode == 0


def ffmpeg_attempts(src, out, scale):
    """Command ladder, most to least desirable.

    A still needs one attempt. A video needs three: the seek overshoots the
    end of anything shorter than SEEK_SECONDS, and a stream with no seekable
    keyframe at all still yields frame zero.
    """
    vf = ["-vf", scale] if scale else []
    if not is_video(src):
        return [["ffmpeg", "-v", "error", "-i", src, *vf, "-q:v", "3", out, "-y"]]
    return [
        ["ffmpeg", "-v", "error", "-ss", str(SEEK_SECONDS), "-i", src, "-frames:v", "1", *vf, "-q:v", "2", out, "-y"],
        ["ffmpeg", "-v", "error", "-ss", "1", "-i", src, "-frames:v", "1", *vf, "-q:v", "2", out, "-y"],
        ["ffmpeg", "-v", "error", "-i", src, "-frames:v", "1", "-q:v", "2", out, "-y"],
    ]


def generate(src, poster_mode):
    if poster_mode and not is_video(src):
        return src if os.path.isfile(src) else None

    key = cache_key(src)
    if key is None:
        return None

    out_dir = POSTER_DIR if poster_mode else THUMB_DIR
    out = os.path.join(out_dir, f"{key}.jpg")
    if os.path.isfile(out) and os.path.getsize(out) > 0:
        return out

    scale = None if poster_mode else THUMB_SCALE
    for cmd in ffmpeg_attempts(src, out, scale):
        if run(cmd) and os.path.isfile(out) and os.path.getsize(out) > 0:
            return out

    # A partial file from the last failed attempt would otherwise be served
    # as a valid cache hit on the next run.
    if os.path.exists(out):
        try:
            os.remove(out)
        except OSError:
            pass
    return None


def main(argv):
    poster_mode = "--poster" in argv
    sources = [a for a in argv if not a.startswith("--")]
    if not sources:
        json.dump({}, sys.stdout)
        return 0

    os.makedirs(POSTER_DIR if poster_mode else THUMB_DIR, exist_ok=True)

    # Materialized inside the block on purpose: pool.map is lazy, and
    # reading it after the executor has shut down yields nothing.
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        results = list(pool.map(lambda s: generate(s, poster_mode), sources))

    json.dump({src: out for src, out in zip(sources, results) if out}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
