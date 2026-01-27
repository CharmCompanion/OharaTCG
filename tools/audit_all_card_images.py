"""Audit card image coverage for the current cached card list.

This checks whether each TCG card in output/databases/complete_card_database.json
has a corresponding image in assets/cards/<set_code>/<card_code>.(png|jpg|jpeg).

Run:
  python tools/audit_all_card_images.py

Output:
  - Summary counts
  - Top sets with missing images
  - Writes tools/_missing_card_images.json with detailed missing entries
"""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Dict, List, Tuple

ROOT = Path(__file__).resolve().parents[1]
ASSETS_CARDS = ROOT / "assets" / "cards"
DB_PATH = ROOT / "output" / "databases" / "complete_card_database.json"
OUT_PATH = ROOT / "tools" / "_missing_card_images.json"


def build_existing_index() -> set[Tuple[str, str]]:
    existing: set[Tuple[str, str]] = set()
    if not ASSETS_CARDS.exists():
        return existing

    for set_dir in ASSETS_CARDS.iterdir():
        if not set_dir.is_dir():
            continue
        set_code = set_dir.name
        try:
            for p in set_dir.iterdir():
                if p.is_file() and p.suffix.lower() in {".png", ".jpg", ".jpeg"}:
                    existing.add((set_code, p.stem))
        except OSError:
            # Ignore transient/permission errors.
            continue

    return existing


def main() -> None:
    if not DB_PATH.exists():
        raise SystemExit(f"Missing DB: {DB_PATH}")

    data = json.loads(DB_PATH.read_text(encoding="utf-8"))
    cards = data.get("cards", [])
    if not isinstance(cards, list):
        raise SystemExit("DB cards is not a list")

    tcg_cards = [c for c in cards if isinstance(c, dict) and c.get("language") == "tcg"]

    existing = build_existing_index()
    missing: List[Dict[str, str]] = []

    for c in tcg_cards:
        set_code = str(c.get("set_code", "") or "").strip()
        card_code = str(c.get("card_code", "") or "").strip()
        card_id = str(c.get("id", "") or "").strip()
        if not set_code or not card_code:
            continue
        if (set_code, card_code) not in existing:
            missing.append({
                "set_code": set_code,
                "card_code": card_code,
                "id": card_id,
                "source": str(c.get("source", "") or ""),
                "image_url": str(c.get("image_url", "") or ""),
            })

    by_set = Counter(m["set_code"] for m in missing)

    print(f"TCG cards in DB: {len(tcg_cards)}")
    print(f"Existing (set_code, stem) image entries: {len(existing)}")
    print(f"Missing images: {len(missing)}")
    print("Top missing sets:")
    for set_code, count in by_set.most_common(25):
        print(f"  {set_code}: {count}")

    OUT_PATH.write_text(json.dumps(missing, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote details: {OUT_PATH}")


if __name__ == "__main__":
    main()
