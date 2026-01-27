"""Download/sync all images for a given set into Godot assets.

This fixes cases where the card database contains a full set (including variants
like `_p1`, `_r1`, etc.) but the project only has art for the base prints.

Example:
  python tools/sync_set_images_to_assets.py EB-02

It reads `output/databases/complete_card_database.json`, filters cards where
`set_id == <label>` OR `set_code == <label>` OR `set_code == <label without hyphen>`.
Then it calls `ImageDownloader.sync_to_godot_assets(download_missing=True)` which:
- skips already-present .png/.jpg/.jpeg assets
- downloads missing art to `assets/cards/<set_code>/<card_code>.png`
- handles reprint/alias fallbacks (when art exists under a different prefix)

Note: This downloads potentially many images; start with one set.
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


def _matches_set(card: dict[str, Any], label: str) -> bool:
    set_id = (card.get("set_id") or "").strip()
    set_code = (card.get("set_code") or "").strip()
    label_norm = label.strip()
    label_no_dash = label_norm.replace("-", "")
    return (
        set_id == label_norm
        or set_code == label_norm
        or (label_no_dash and set_code == label_no_dash)
        or (label_no_dash and set_id == label_no_dash)
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("set", help="Set label like EB-02, OP01, ST-01")
    parser.add_argument("--language", default="tcg", help="Filter by card language (default: tcg)")
    parser.add_argument("--verbose", action="store_true", help="Print progress")
    args = parser.parse_args()

    db_path = PROJECT_ROOT / "output" / "databases" / "complete_card_database.json"
    if not db_path.exists():
        print(f"Missing card database: {db_path}")
        return 2

    cards = _load_db_cards(db_path)
    subset = [c for c in cards if _matches_set(c, args.set)]

    if args.language:
        subset = [c for c in subset if (c.get("language") or args.language) == args.language]

    if not subset:
        print(f"No cards matched set '{args.set}'.")
        return 1

    # Ensure project root is importable
    sys.path.insert(0, str(PROJECT_ROOT))

    # Use streamlit shim to satisfy ImageDownloader import
    from addons.GrandLineScraper import streamlit_shim as st  # noqa: E402

    sys.modules["streamlit"] = st

    from addons.GrandLineScraper.image_downloader import ImageDownloader  # noqa: E402

    downloader = ImageDownloader(str(PROJECT_ROOT / "output"))
    stats = downloader.sync_to_godot_assets(
        {"cards": subset},
        project_root=PROJECT_ROOT,
        overwrite=False,
        download_missing=True,
        only_language=args.language,
        verbose=args.verbose,
    )

    print(
        "Set image sync complete:",
        f"set={args.set}",
        f"total={stats.get('total')}",
        f"copied={stats.get('copied')}",
        f"downloaded={stats.get('downloaded')}",
        f"skipped={stats.get('skipped')}",
        f"failed={stats.get('failed')}",
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
