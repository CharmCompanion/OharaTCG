"""Fix illegal card counts in starter deck JSON files.

This is a safety/repair tool for already-exported decks in:
- data/decks
- output/decks/starter

It clamps main-deck cards to max 4 copies (excluding leader), forces leader to 1,
and normalizes DON!! to 10 total.

Run:
  python tools/fix_starter_deck_counts.py
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Tuple


ROOT = Path(__file__).resolve().parents[1]


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _save_json(path: Path, data: Any) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _is_don_entry(entry: Dict[str, Any]) -> bool:
    t = str(entry.get("type", "") or "").strip().lower()
    code = str(entry.get("card_code", "") or "").strip().upper()
    name = str(entry.get("name", "") or "").strip().upper()
    return t in {"don", "don!!"} or code.startswith("DON") or name.startswith("DON")


def _clamp_main(main: List[Dict[str, Any]]) -> Tuple[bool, int]:
    changed = False
    clamped = 0

    for entry in main:
        if not isinstance(entry, dict):
            continue

        t = str(entry.get("type", "") or "").strip().lower()
        if t == "leader":
            if int(entry.get("count", 1)) != 1:
                entry["count"] = 1
                changed = True
            continue

        # Main deck should not contain DON, but clamp defensively.
        if _is_don_entry(entry):
            continue

        old = int(entry.get("count", 1))
        new = min(old, 4)
        if new != old:
            entry["count"] = new
            changed = True
            clamped += 1

    return changed, clamped


def _normalize_don(don: List[Dict[str, Any]]) -> bool:
    """Ensure DON total is exactly 10."""
    changed = False

    # Filter to dict entries.
    don_entries = [d for d in don if isinstance(d, dict)]
    if not don_entries:
        return False

    # Sum copies.
    total = sum(int(d.get("count", 1)) for d in don_entries)
    if total == 10:
        return False

    # If total is zero or missing, force first to 10.
    if total <= 0:
        don_entries[0]["count"] = 10
        for d in don_entries[1:]:
            d["count"] = 0
        changed = True
    elif total < 10:
        don_entries[0]["count"] = int(don_entries[0].get("count", 1)) + (10 - total)
        changed = True
    else:
        # Reduce from the end.
        extra = total - 10
        for d in reversed(don_entries):
            if extra <= 0:
                break
            c = int(d.get("count", 1))
            take = min(c, extra)
            d["count"] = c - take
            extra -= take
            changed = True

    # Remove any zero-count trailing entries.
    new_list = [d for d in don_entries if int(d.get("count", 0)) > 0]
    if len(new_list) != len(don):
        changed = True

    don[:] = new_list
    return changed


def fix_deck_file(path: Path) -> Tuple[bool, str]:
    data = _load_json(path)
    if not isinstance(data, dict):
        return False, "not a dict"

    main_key = "main" if "main" in data else ("main_deck" if "main_deck" in data else "")
    don_key = "don" if "don" in data else ("don_cards" if "don_cards" in data else "")

    if not main_key or not isinstance(data.get(main_key), list):
        return False, "missing main"

    changed_main, clamped = _clamp_main(data[main_key])

    changed_don = False
    if don_key and isinstance(data.get(don_key), list):
        changed_don = _normalize_don(data[don_key])

    changed = changed_main or changed_don
    if changed:
        _save_json(path, data)

    return changed, f"clamped={clamped}" + (" don_fixed" if changed_don else "")


def main() -> None:
    targets = [
        ROOT / "data" / "decks",
        ROOT / "output" / "decks" / "starter",
    ]

    changed_files = 0
    visited = 0

    for folder in targets:
        if not folder.exists():
            continue

        for path in sorted(folder.glob("ST-*.json")):
            visited += 1
            changed, note = fix_deck_file(path)
            if changed:
                changed_files += 1
                print(f"UPDATED {path.relative_to(ROOT)} ({note})")

    print(f"Done. Visited {visited} starter deck files; updated {changed_files}.")


if __name__ == "__main__":
    main()
