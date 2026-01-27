"""Audit deck JSONs for missing card image files.

Checks all deck JSONs in:
- data/decks
- output/decks/starter

Uses the same filename conventions as DeckManager.gd:
- DON!! -> assets/cards/Don/Don.png
- Otherwise -> assets/cards/{set_code}/{card_code}.{png|jpg|jpeg} (also checks *_small variants)

Writes:
- output/reports/deck_image_audit.json
- output/reports/deck_image_audit_summary.txt

Run:
  python tools/validate_deck_images.py
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple


PROJECT_ROOT = Path(__file__).resolve().parents[1]
ASSETS_CARDS_DIR = PROJECT_ROOT / "assets" / "cards"
OUTPUT_CARDS_DIR = PROJECT_ROOT / "output" / "images" / "cards"
DEFAULT_DECK_DIRS = [
    PROJECT_ROOT / "data" / "decks",
    PROJECT_ROOT / "output" / "decks" / "starter",
]
REPORT_DIR = PROJECT_ROOT / "output" / "reports"

IMAGE_EXTS = (".png", ".jpg", ".jpeg")


@dataclass
class CardRef:
    deck_file: str
    section: str  # main/don
    name: str
    set_code: str
    card_code: str


def _read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _iter_deck_files(deck_dirs: Iterable[Path]) -> Iterable[Path]:
    for deck_dir in deck_dirs:
        if not deck_dir.exists():
            continue
        for p in sorted(deck_dir.glob("*.json")):
            if p.name == "deck_export.json":
                continue
            if p.name.endswith("_complete.json"):
                # We purposely stopped generating these; ignore if present.
                continue
            yield p


def _normalize_set_code(value: str) -> str:
    v = (value or "").strip()
    if not v:
        return ""
    return v.replace("-", "").upper()


def _normalize_card_code(value: str) -> str:
    v = (value or "").strip()
    if not v:
        return ""
    return v.upper()


def _candidates_for_card(set_code: str, card_code: str) -> List[Path]:
    base_dir = ASSETS_CARDS_DIR / set_code

    # Some sources encode variants as suffixes like "ST16-029_R1" or "ST16-057_P1",
    # while assets are typically stored under the base code ("ST16-029.png").
    codes = [card_code]
    if "_" in card_code:
        base = card_code.split("_", 1)[0]
        if base and base != card_code:
            codes.append(base)

    full: List[Path] = []
    small: List[Path] = []
    for code in codes:
        full.extend([base_dir / f"{code}{ext}" for ext in IMAGE_EXTS])
        small.extend([base_dir / f"{code}_small{ext}" for ext in IMAGE_EXTS])
    # Fallback: output/images/cards is a flat layout that may have art even when
    # assets/cards hasn't been fully synced.
    out_full: List[Path] = []
    out_small: List[Path] = []
    for code in codes:
        out_full.extend([OUTPUT_CARDS_DIR / f"{code}{ext}" for ext in IMAGE_EXTS])
        out_small.extend([OUTPUT_CARDS_DIR / f"{code}_small{ext}" for ext in IMAGE_EXTS])
    # Prefer full size but check both (and both locations).
    return full + small + out_full + out_small


def _find_existing(paths: Iterable[Path]) -> Optional[Path]:
    for p in paths:
        if p.exists():
            return p
    return None


def _slug(s: str) -> str:
    s = (s or "").strip().upper()
    s = re.sub(r"[^A-Z0-9]+", "-", s)
    s = re.sub(r"-+", "-", s).strip("-")
    return s


def _extract_cards(deck: Dict[str, Any], deck_file: str) -> List[CardRef]:
    cards: List[CardRef] = []

    def pull(section_name: str, arr: Any) -> None:
        if not isinstance(arr, list):
            return
        for entry in arr:
            if not isinstance(entry, dict):
                continue
            name = str(entry.get("name", "") or "")
            card_type = str(entry.get("type", "") or "")
            set_code = str(entry.get("set_code", "") or "")
            card_code = str(entry.get("card_code", "") or "")

            # Fallbacks
            if not card_code:
                number = str(entry.get("number", "") or "")
                if set_code and number:
                    card_code = f"{set_code}-{number}"

            if card_type.upper() in ("DON!!", "DON") or (card_code or "").upper().startswith("DON"):
                cards.append(CardRef(deck_file, section_name, name or "DON!!", "Don", "Don"))
                continue

            cards.append(
                CardRef(
                    deck_file=deck_file,
                    section=section_name,
                    name=name,
                    set_code=set_code,
                    card_code=card_code,
                )
            )

    pull("main", deck.get("main"))
    pull("don", deck.get("don"))

    return cards


def audit(deck_dirs: List[Path]) -> Dict[str, Any]:
    missing: List[Dict[str, Any]] = []
    totals = {
        "deck_files": 0,
        "cards_checked": 0,
        "missing_images": 0,
        "missing_set_dirs": 0,
        "missing_card_codes": 0,
    }

    for deck_path in _iter_deck_files(deck_dirs):
        totals["deck_files"] += 1
        try:
            deck_data = _read_json(deck_path)
        except Exception as e:
            missing.append(
                {
                    "deck": str(deck_path.relative_to(PROJECT_ROOT)).replace("\\", "/"),
                    "error": f"failed to parse json: {e}",
                }
            )
            continue

        if not isinstance(deck_data, dict):
            missing.append(
                {
                    "deck": str(deck_path.relative_to(PROJECT_ROOT)).replace("\\", "/"),
                    "error": "deck json is not an object",
                }
            )
            continue

        deck_rel = str(deck_path.relative_to(PROJECT_ROOT)).replace("\\", "/")
        for cref in _extract_cards(deck_data, deck_rel):
            totals["cards_checked"] += 1

            if cref.set_code == "Don":
                # Special case
                don_path = ASSETS_CARDS_DIR / "Don" / "Don.png"
                if not don_path.exists():
                    totals["missing_images"] += 1
                    missing.append(
                        {
                            "deck": deck_rel,
                            "section": cref.section,
                            "name": cref.name,
                            "set_code": "Don",
                            "card_code": "DON!!",
                            "reason": "missing Don.png",
                            "expected_any": [str(don_path.relative_to(PROJECT_ROOT)).replace("\\", "/")],
                        }
                    )
                continue

            set_code_norm = _normalize_set_code(cref.set_code)
            card_code_norm = _normalize_card_code(cref.card_code)

            if not set_code_norm or not card_code_norm:
                totals["missing_card_codes"] += 1
                missing.append(
                    {
                        "deck": deck_rel,
                        "section": cref.section,
                        "name": cref.name,
                        "set_code": cref.set_code,
                        "card_code": cref.card_code,
                        "reason": "missing set_code/card_code in deck json",
                    }
                )
                continue

            set_dir = ASSETS_CARDS_DIR / set_code_norm
            if not set_dir.exists():
                totals["missing_set_dirs"] += 1

            candidates = _candidates_for_card(set_code_norm, card_code_norm)
            found = _find_existing(candidates)
            if found:
                continue

            # Suggestions: try stripping hyphens from set_code, or re-slugging card code
            suggestions: List[Dict[str, Any]] = []

            alt_set = _normalize_set_code(cref.set_code)
            if alt_set and alt_set != set_code_norm:
                alt_candidates = _candidates_for_card(alt_set, card_code_norm)
                alt_found = _find_existing(alt_candidates)
                if alt_found:
                    suggestions.append({"suggested_set_code": alt_set, "found": str(alt_found)})

            # Sometimes card_code might have wrong separators; try a best-effort slug-like transform
            card_slug = _slug(cref.card_code)
            if card_slug and card_slug != card_code_norm:
                alt_candidates = _candidates_for_card(set_code_norm, card_slug)
                alt_found = _find_existing(alt_candidates)
                if alt_found:
                    suggestions.append({"suggested_card_code": card_slug, "found": str(alt_found)})

            totals["missing_images"] += 1
            missing.append(
                {
                    "deck": deck_rel,
                    "section": cref.section,
                    "name": cref.name,
                    "set_code": set_code_norm,
                    "card_code": card_code_norm,
                    "reason": "image not found",
                    "expected_any": [
                        str(p.relative_to(PROJECT_ROOT)).replace("\\", "/")
                        for p in candidates
                    ],
                    "suggestions": suggestions,
                }
            )

    return {"totals": totals, "missing": missing}


def main() -> int:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)

    result = audit(DEFAULT_DECK_DIRS)

    out_json = REPORT_DIR / "deck_image_audit.json"
    out_txt = REPORT_DIR / "deck_image_audit_summary.txt"

    out_json.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")

    totals = result.get("totals", {})
    missing = result.get("missing", [])

    # Build summary grouped by deck
    per_deck: Dict[str, int] = {}
    for item in missing:
        deck = item.get("deck", "<unknown>")
        per_deck[deck] = per_deck.get(deck, 0) + 1

    lines = []
    lines.append("Deck image audit summary")
    lines.append(f"Deck files: {totals.get('deck_files', 0)}")
    lines.append(f"Cards checked: {totals.get('cards_checked', 0)}")
    lines.append(f"Missing images: {totals.get('missing_images', 0)}")
    lines.append(f"Missing set dirs: {totals.get('missing_set_dirs', 0)}")
    lines.append(f"Missing code fields: {totals.get('missing_card_codes', 0)}")
    lines.append("")
    lines.append("Worst decks (most missing entries):")

    for deck, count in sorted(per_deck.items(), key=lambda x: (-x[1], x[0]))[:25]:
        lines.append(f"- {deck}: {count}")

    out_txt.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"Wrote {out_json}")
    print(f"Wrote {out_txt}")
    print(f"Missing images: {totals.get('missing_images', 0)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
