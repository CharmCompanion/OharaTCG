"""Sync `data/decks/*.json` into `output/decks/starter/*.json`.

Why:
- `data/decks/` contains full starter decklists (1 Leader + 50 main + 10 DON).
- Some generated `output/decks/starter/` files are incomplete depending on exporter sources.

This script overwrites output starter decks with the authoritative ones.

Usage:
  python tools/sync_data_decks_to_output.py
"""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "data" / "decks"
DST = ROOT / "output" / "decks" / "starter"


def main() -> int:
    if not SRC.exists():
        raise SystemExit(f"Missing source folder: {SRC}")
    DST.mkdir(parents=True, exist_ok=True)

    src_files = sorted(SRC.glob("ST-*.json"))
    if not src_files:
        print("No ST-*.json files found in data/decks")
        return 0

    copied = 0
    for src in src_files:
        dst = DST / src.name
        dst.write_bytes(src.read_bytes())
        copied += 1

    print(f"Synced {copied} files -> {DST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
