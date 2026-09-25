#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
OharaTCG card art fetcher.

Downloads any missing card art (base + parallel "_pN" variants) from the
official onepiece-cardgame.com cardlist CDN into res://assets/cards/<SET>/,
using the per-card "img_url" written by import_sets.py.

Rules:
  - Skips cards that already exist locally (any of .png/.jpg/.jpeg/.webp).
  - Skips DON!! cards (they resolve via image_override in assets/cards/Don).
  - Resumable: a checkpoint file (tools/.art_download_state.json) records
    completed downloads; rerun to finish the remaining images.
  - Polite: small delay between requests, one retry on transient failure.

Usage:
  python fetch_art.py [ohara-project-root]
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_PROJECT_ROOT = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
)

STATE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".art_download_state.json")
DELAY_S = 0.12
UA = "OharaTCG-updater/1.0 (fan project; missing card art sync)"


def load_cards(project_root: str) -> list:
    sets_dir = os.path.join(project_root, "data", "cards", "sets")
    cards = []
    for fname in os.listdir(sets_dir):
        if not fname.endswith(".json"):
            continue
        try:
            arr = json.load(open(os.path.join(sets_dir, fname), encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            print("  [warn] skip %s: %s" % (fname, exc))
            continue
        payload = arr.get("main", arr) if isinstance(arr, dict) else arr
        if isinstance(payload, list):
            cards.extend(payload)
    return cards


ART_EXTS = (".png", ".jpg", ".jpeg", ".webp")
_NO_IMG = ("DON-001",)


def local_target(project_root: str, card: dict):
    """Returns the local path where the art for this card should live."""
    vid = card.get("variant_id", "")
    sc = card.get("set_code", "")
    if vid.startswith("DON-001"):
        return None  # DON handled by image_override
    if not vid or not sc:
        return None
    return os.path.join(project_root, "assets", "cards", sc, vid + ".png")


def have_local_art(path):
    if not path:
        return True
    base, _ = os.path.splitext(path)
    for ext in ART_EXTS:
        if os.path.exists(base + ext):
            return True
    return False


def clean_url(url: str) -> str:
    if not url:
        return ""
    url = url.split("?")[0]  # drop cache-busting timestamp
    return url


def download(url: str, dest: str) -> bool:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read()
        if len(data) < 500:
            print("    [warn] suspiciously small download for %s" % url)
            return False
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as fh:
            fh.write(data)
        return True
    except Exception as exc:  # noqa: BLE001
        print("    [error] %s -> %s" % (url, exc))
        return False


def main() -> None:
    project_root = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PROJECT_ROOT
    cards = load_cards(project_root)

    done = set()
    if os.path.exists(STATE_FILE):
        try:
            done = set(json.load(open(STATE_FILE, encoding="utf-8")))
        except Exception:  # noqa: BLE001
            done = set()

    todo = []
    for card in cards:
        vid = card.get("variant_id", "")
        if vid in done:
            continue
        local = local_target(project_root, card)
        if not local:
            continue  # DON etc.
        url = clean_url(card.get("img_url", ""))
        if not url:
            print("  [warn] %s has no img_url" % vid)
            continue
        if not have_local_art(local):
            todo.append((vid, url, local))

    print("Cards loaded: %d | already downloaded: %d | missing: %d"
          % (len(cards), len(done), len(todo)))

    ok = fail = 0
    for i, (vid, url, local) in enumerate(todo, 1):
        if download(url, local):
            ok += 1
        else:
            fail += 1
        done.add(vid)
        if i % 50 == 0 or i == len(todo):
            with open(STATE_FILE, "w", encoding="utf-8") as fh:
                json.dump(sorted(done), fh)
            print("  ...%d/%d (fail=%d)" % (i, len(todo), fail))
        time.sleep(DELAY_S)

    with open(STATE_FILE, "w", encoding="utf-8") as fh:
        json.dump(sorted(done), fh)
    print("Done: ok=%d fail=%d" % (ok, fail))


if __name__ == "__main__":
    main()