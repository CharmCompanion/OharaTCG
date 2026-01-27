"""Download missing deck-referenced card images into Godot assets.

Workflow:
1) Reads output/reports/deck_image_audit.json to get missing card_code/set_code.
2) Looks up image_url from output/databases/complete_card_database.json.
3) Uses ImageDownloader.sync_to_godot_assets(download_missing=True) to download images
   directly into assets/cards/<set_code>/<card_code>.png.

This targets *only* what decks are missing, so it's far faster than downloading everything.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Dict, Any, List, Tuple


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _asset_exists(project_root: Path, set_code: str, card_code: str) -> bool:
    base = project_root / "assets" / "cards" / set_code
    for ext in (".png", ".jpg", ".jpeg"):
        if (base / f"{card_code}{ext}").exists():
            return True
        if (base / f"{card_code}_small{ext}").exists():
            return True
    return False


def _load_missing_from_audit(audit_path: Path) -> List[Tuple[str, str]]:
    audit = json.loads(audit_path.read_text(encoding="utf-8"))
    missing = []
    for entry in audit.get("missing", []):
        set_code = (entry.get("set_code") or "").strip()
        card_code = (entry.get("card_code") or "").strip()
        if set_code and card_code:
            missing.append((set_code, card_code))

    # Deduplicate
    seen = set()
    unique: List[Tuple[str, str]] = []
    for sc, cc in missing:
        key = (sc.lower(), cc.lower())
        if key not in seen:
            seen.add(key)
            unique.append((sc, cc))
    return unique


def _build_cardcode_index(db_path: Path) -> Dict[str, Dict[str, Any]]:
    db = json.loads(db_path.read_text(encoding="utf-8"))
    cards = db.get("cards", []) or []

    # Prefer TCG entries when multiple share a card_code.
    index: Dict[str, Dict[str, Any]] = {}
    for c in cards:
        if not isinstance(c, dict):
            continue
        cc = (c.get("card_code") or "").strip()
        if not cc:
            continue
        key = cc.lower()
        if key not in index:
            index[key] = c
        else:
            # Prefer TCG over OCG
            existing = index[key]
            if existing.get("language") != "tcg" and c.get("language") == "tcg":
                index[key] = c
    return index


def main() -> int:
    audit_path = PROJECT_ROOT / "output" / "reports" / "deck_image_audit.json"
    db_path = PROJECT_ROOT / "output" / "databases" / "complete_card_database.json"

    if not audit_path.exists():
        print(f"Missing audit file: {audit_path}")
        return 2
    if not db_path.exists():
        print(f"Missing card database: {db_path}")
        return 2

    missing_pairs = _load_missing_from_audit(audit_path)
    if not missing_pairs:
        print("No missing images found in audit.")
        return 0

    # Filter out anything that is already satisfied in assets to avoid noisy
    # skipped counts.
    missing_pairs = [(sc, cc) for (sc, cc) in missing_pairs if not _asset_exists(PROJECT_ROOT, sc, cc)]
    if not missing_pairs:
        print("All audit entries are already satisfied by existing assets.")
        return 0

    index = _build_cardcode_index(db_path)

    # Create a minimal processed_data payload for ImageDownloader
    cards_to_fetch: List[Dict[str, Any]] = []
    not_found = 0

    for set_code, card_code in missing_pairs:
        src = index.get(card_code.lower())
        if not src:
            not_found += 1
            continue
        # Copy only the fields ImageDownloader needs
        cards_to_fetch.append(
            {
                "id": src.get("id") or card_code,
                "card_code": card_code,
                "set_code": set_code,
                "number": src.get("number") or "",
                "type": src.get("type") or "",
                "language": "tcg",
                "image_url": src.get("image_url") or "",
                "image_urls": src.get("image_urls") or {},
            }
        )

    print(f"Missing entries in audit: {len(missing_pairs)}")
    print(f"Found in database: {len(cards_to_fetch)} (not found: {not_found})")

    # Ensure project root is importable (needed when running from other CWDs)
    sys.path.insert(0, str(PROJECT_ROOT))

    # Use streamlit shim to avoid noisy ScriptRunContext warnings
    from addons.GrandLineScraper import streamlit_shim as st  # noqa: E402

    sys.modules["streamlit"] = st

    from addons.GrandLineScraper.image_downloader import ImageDownloader  # noqa: E402

    downloader = ImageDownloader(str(PROJECT_ROOT / "output"))
    stats = downloader.sync_to_godot_assets(
        {"cards": cards_to_fetch},
        project_root=PROJECT_ROOT,
        overwrite=False,
        download_missing=True,
        only_language="tcg",
        verbose=True,
    )

    print(
        "Downloaded missing deck images:",
        f"downloaded={stats.get('downloaded')}",
        f"copied={stats.get('copied')}",
        f"skipped={stats.get('skipped')}",
        f"failed={stats.get('failed')}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
