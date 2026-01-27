"""Sync deck-referenced images into Godot assets.

This is a fast, offline-friendly helper:
- Reads deck JSONs from data/decks (Godot format)
- Copies matching images from output/images/cards into assets/cards/<set_code>/<card_code>.png

It uses the same ImageDownloader logic as the scraper, but does NOT scrape or download anything.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Dict, Any, List


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _load_deck_cards(deck_path: Path) -> List[Dict[str, Any]]:
    deck = json.loads(deck_path.read_text(encoding="utf-8"))
    cards: List[Dict[str, Any]] = []

    for section in ("main", "don", "life"):
        section_cards = deck.get(section, [])
        if isinstance(section_cards, list):
            for c in section_cards:
                if isinstance(c, dict):
                    # Ensure minimum fields for ImageDownloader
                    cards.append(
                        {
                            "card_code": c.get("card_code") or "",
                            "set_code": c.get("set_code") or "",
                            "number": c.get("number") or "",
                            "type": c.get("type") or "",
                            "id": c.get("id") or "",
                            "language": "tcg",
                        }
                    )

    return cards


def main() -> int:
    # Ensure project root is importable (needed when running from other CWDs)
    sys.path.insert(0, str(PROJECT_ROOT))

    # Ensure ImageDownloader can be imported even when streamlit isn't installed
    from addons.GrandLineScraper import streamlit_shim as st  # noqa: E402

    sys.modules["streamlit"] = st

    from addons.GrandLineScraper.image_downloader import ImageDownloader  # noqa: E402

    decks_dir = PROJECT_ROOT / "data" / "decks"
    if not decks_dir.exists():
        print(f"Decks directory not found: {decks_dir}")
        return 2

    deck_paths = sorted(decks_dir.glob("*.json"))
    all_cards: List[Dict[str, Any]] = []
    for deck_path in deck_paths:
        try:
            all_cards.extend(_load_deck_cards(deck_path))
        except Exception as e:
            print(f"Failed to read {deck_path.name}: {e}")

    processed_data = {"cards": all_cards}

    downloader = ImageDownloader(str(PROJECT_ROOT / "output"))
    stats = downloader.sync_to_godot_assets(
        processed_data,
        project_root=PROJECT_ROOT,
        overwrite=False,
        download_missing=False,
        only_language="tcg",
    )

    print(
        "Deck asset sync done:",
        f"total={stats.get('total')}",
        f"copied={stats.get('copied')}",
        f"skipped={stats.get('skipped')}",
        f"failed={stats.get('failed')}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
