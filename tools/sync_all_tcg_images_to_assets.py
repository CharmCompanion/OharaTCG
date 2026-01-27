"""Download/sync ALL TCG card images into Godot assets.

This is the "no placeholders in search" fix.

It reads output/databases/complete_card_database.json, filters to language==tcg,
dedupes by (set_code, card_code), then calls ImageDownloader.sync_to_godot_assets
with download_missing=True.

Run:
  python tools/sync_all_tcg_images_to_assets.py

Optional:
  --verbose   print progress more often
  --limit N   only process first N cards (for testing)
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _load_db_cards(db_path: Path) -> list[dict[str, Any]]:
    db = json.loads(db_path.read_text(encoding="utf-8"))
    cards = db.get("cards", [])
    if not isinstance(cards, list):
        return []
    return [c for c in cards if isinstance(c, dict)]


def _normalize_set_code(value: str) -> str:
    return (value or "").strip().upper().replace("-", "").replace(" ", "")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verbose", action="store_true", help="Print progress")
    parser.add_argument("--limit", type=int, default=0, help="Only process first N cards (for testing)")
    args = parser.parse_args()

    db_path = PROJECT_ROOT / "output" / "databases" / "complete_card_database.json"
    if not db_path.exists():
        print(f"Missing card database: {db_path}")
        return 2

    cards = _load_db_cards(db_path)
    tcg = [c for c in cards if (c.get("language") or "tcg") == "tcg"]

    # Deduplicate to avoid wasting work on merged-source duplicates.
    seen: set[tuple[str, str]] = set()
    deduped: list[dict[str, Any]] = []
    for c in tcg:
        set_code = _normalize_set_code(str(c.get("set_code", "") or ""))
        card_code = str(c.get("card_code", "") or "").strip().upper()
        if not set_code or not card_code:
            continue
        key = (set_code, card_code)
        if key in seen:
            continue
        seen.add(key)
        c = dict(c)
        c["set_code"] = set_code
        c["card_code"] = card_code
        deduped.append(c)

    if args.limit and args.limit > 0:
        deduped = deduped[: args.limit]

    print(f"TCG unique cards to process: {len(deduped)}")

    # Ensure project root is importable
    sys.path.insert(0, str(PROJECT_ROOT))

    # Use streamlit shim to satisfy ImageDownloader import
    from addons.GrandLineScraper import streamlit_shim as st  # noqa: E402

    sys.modules["streamlit"] = st

    from addons.GrandLineScraper.image_downloader import ImageDownloader  # noqa: E402

    downloader = ImageDownloader(str(PROJECT_ROOT / "output"))
    stats = downloader.sync_to_godot_assets(
        {"cards": deduped},
        project_root=PROJECT_ROOT,
        overwrite=False,
        download_missing=True,
        only_language="tcg",
        verbose=args.verbose,
    )

    print(
        "All-card image sync complete:",
        f"total={stats.get('total')}",
        f"copied={stats.get('copied')}",
        f"downloaded={stats.get('downloaded')}",
        f"skipped={stats.get('skipped')}",
        f"failed={stats.get('failed')}",
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
