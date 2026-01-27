"""Import .deck files into this project's deck JSON format.

OPTCGSim deck files live at:
  addons/Builds_Windows/Decks/*.deck

Format is lines like:
  4xST01-006

This can generate/update:
    data/decks/<ST-XX>.json
    output/decks/starter/<ST-XX>.json

Notes:
- Deck files list Leader + 50-card deck => 51 total lines-by-count.
- We keep your existing deck JSON schema (main[] + don[]).
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SIM_DECKS = ROOT / "addons" / "Builds_Windows" / "Decks"
SETS_ROOT = ROOT / "output" / "sets"
OUT_DECKS = ROOT / "output" / "decks" / "starter"
DATA_DECKS = ROOT / "data" / "decks"

LINE_RE = re.compile(r"^(\d+)x([A-Za-z0-9\-!]+)$")


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _index_cards() -> dict[str, dict]:
    """Build a best-effort index: card_code -> representative card dict."""
    index: dict[str, dict] = {}
    for json_path in SETS_ROOT.rglob("*.json"):
        try:
            data = _load_json(json_path)
        except Exception:
            continue
        cards = data.get("cards")
        if not isinstance(cards, list):
            continue
        for c in cards:
            if not isinstance(c, dict):
                continue
            code = str(c.get("card_code") or "").strip()
            if not code:
                continue
            # Prefer a non-parallel base record if we see one.
            if code not in index or "_p" in str(index[code].get("id", "")):
                index[code] = c
    return index


def _build_entry(card: dict, count: int) -> dict:
    # Match existing deck json shape (keys used by your Godot importer).
    return {
        "id": str(card.get("id") or card.get("card_code") or ""),
        "name": str(card.get("name_english") or card.get("name") or ""),
        "type": str(card.get("type") or ""),
        "color": card.get("colors") or card.get("color") or [],
        "cost": int(card.get("cost") or 0),
        "power": int(card.get("power") or 0),
        "life": int(card.get("life") or 0),
        "counter": int(card.get("counter") or 0),
        "rarity": str(card.get("rarity") or ""),
        "attribute": str(card.get("attribute") or ""),
        "traits": card.get("traits") or [],
        "effect": str(card.get("effect_english") or card.get("effect") or ""),
        "set_code": str(card.get("set_code") or ""),
        "number": str(card.get("number") or ""),
        "card_code": str(card.get("card_code") or ""),
        "count": int(count),
        "zone": "main",
    }


def _parse_deck(path: Path) -> list[tuple[str, int]]:
    out: list[tuple[str, int]] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line:
            continue
        m = LINE_RE.match(line)
        if not m:
            continue
        count = int(m.group(1))
        code = m.group(2).strip().upper()
        out.append((code, count))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--write",
        action="store_true",
        help="Actually write output files (default is dry-run summary).",
    )
    ap.add_argument(
        "--dest",
        choices=["output", "data"],
        default="output",
        help="Primary destination folder for generated ST-*.json files.",
    )
    ap.add_argument(
        "--also",
        choices=["output", "data"],
        action="append",
        default=[],
        help="Optional additional destination(s). Can be repeated.",
    )
    args = ap.parse_args()

    if not SIM_DECKS.exists():
        raise SystemExit(f"Missing OPTCGSim decks folder: {SIM_DECKS}")

    card_index = _index_cards()

    dest_map = {
        "output": OUT_DECKS,
        "data": DATA_DECKS,
    }
    dest_keys = [args.dest] + list(args.also)
    # De-dup while keeping order.
    seen: set[str] = set()
    dest_keys = [k for k in dest_keys if not (k in seen or seen.add(k))]
    dest_dirs = [dest_map[k] for k in dest_keys]
    for d in dest_dirs:
        d.mkdir(parents=True, exist_ok=True)

    deck_files = sorted(SIM_DECKS.glob("*.deck"))
    if not deck_files:
        print("No .deck files found.")
        return 0

    wrote = 0
    for deck_path in deck_files:
        entries = _parse_deck(deck_path)
        if not entries:
            print("SKIP (empty)", deck_path.name)
            continue

        # Derive ST-XX filename from first code or from name prefix.
        st_id = None
        for code, _ in entries:
            if code.startswith("ST") and "-" in code:
                st_id = code.split("-", 1)[0]  # ST01
                break
        if st_id is None:
            # Fallback: read from filename, expecting "ST01 - ..."
            st_id = deck_path.name.split(" ", 1)[0].strip().upper()

        # Normalize to ST-01 form.
        st_out_id = f"{st_id[:2]}-{st_id[2:]}" if len(st_id) == 4 else st_id
        out_paths = [d / f"{st_out_id}.json" for d in dest_dirs]

        main_list: list[dict] = []
        missing: list[str] = []
        total = 0

        for code, count in entries:
            total += count
            card = card_index.get(code)
            if card is None:
                missing.append(code)
                # Minimal placeholder entry (still usable in UI with placeholder art).
                main_list.append(
                    {
                        "id": code,
                        "name": code,
                        "type": "",
                        "color": [],
                        "cost": 0,
                        "power": 0,
                        "life": 0,
                        "counter": 0,
                        "rarity": "",
                        "attribute": "",
                        "traits": [],
                        "effect": "",
                        "set_code": code.split("-", 1)[0],
                        "number": "",
                        "card_code": code,
                        "count": int(count),
                        "zone": "main",
                    }
                )
                continue

            main_list.append(_build_entry(card, count))

        deck_json = {
            "main": main_list,
            "don": [
                {
                    "id": "DON!!",
                    "name": "DON!!",
                    "type": "DON!!",
                    "color": [],
                    "cost": 0,
                    "power": 0,
                    "life": 0,
                    "counter": 0,
                    "rarity": "",
                    "attribute": "",
                    "traits": [],
                    "effect": "",
                    "set_code": "DON",
                    "number": "001",
                    "card_code": "DON!!",
                    "count": 10,
                    "zone": "don",
                }
            ],
        }

        leader_count = sum(
            1
            for e in main_list
            if str(e.get("type", "")).strip().lower() == "leader"
        )
        non_leader_total = sum(
            int(e.get("count") or 0)
            for e in main_list
            if str(e.get("type", "")).strip().lower() != "leader"
        )

        targets = ", ".join(p.as_posix().split("/", 1)[-1] for p in out_paths)
        print(
            f"{deck_path.name} -> {targets}: total(incl leader)={total}, leader_count={leader_count}, non_leader_total={non_leader_total}, missing={len(missing)}"
        )
        if missing:
            print("  missing codes:", ", ".join(missing[:20]), "..." if len(missing) > 20 else "")

        if args.write:
            payload = json.dumps(deck_json, ensure_ascii=False, indent=2)
            for out_path in out_paths:
                out_path.write_text(payload, encoding="utf-8")
            wrote += len(out_paths)

    if args.write:
        print("WROTE", wrote, "deck json file(s) across", len(dest_dirs), "destination(s)")
    else:
        print(
            "Dry-run only. Re-run with --write to generate deck JSON files. "
            "Use --dest data --also output to update both locations."
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
