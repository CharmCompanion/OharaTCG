"""Import a deck recipe text file into this project's deck JSON schema.

This is designed for when you have *quantities* (e.g. from a deck recipe PDF
or a copied decklist), unlike some sources that only list unique card codes.

Accepted line formats (mixed is OK):
- 4xST06-010
- 4 x ST06-010
- ST06-010 x4
- ST06-010 4
- ST06-010            (count defaults to 1; repeated lines accumulate)

Also supports a JSON array export format (one code per entry), e.g.:
  ["Exported from ...", "ST06-010", "ST06-010", ...]

Behavior:
- Builds `main[]` entries with counts.
- Always writes DON!! as exactly 10 in `don[]` (ignores any DON lines).
- Attempts to identify the leader from card database metadata; falls back to
  `<deckPrefix>-001` if needed.
- Validates the result (leader=1, non-leader main total=50, don total=10).

Outputs:
- Always writes an import report:
    output/reports/deck_recipe_import_report.json

Writing deck JSON files:
- By default it does NOT overwrite any deck files.
- With --write, writes to `data/decks/<DECK_ID>.json` and/or
  `output/decks/starter/<DECK_ID>.json`.

Examples:
  python tools/import_deck_recipe_text.py --input recipes/ST-06.txt --deck-id ST-06
  python tools/import_deck_recipe_text.py --input recipes/ --write --dest data --also output
"""

from __future__ import annotations

import argparse
import json
import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple


ROOT = Path(__file__).resolve().parents[1]
SETS_ROOT = ROOT / "output" / "sets"
REPORT_DIR = ROOT / "output" / "reports"
REPORT_DIR.mkdir(parents=True, exist_ok=True)

OUT_DECKS = ROOT / "output" / "decks" / "starter"
DATA_DECKS = ROOT / "data" / "decks"


# Matches: 4xST06-010, 4 x ST06-010
RE_COUNT_X_CODE = re.compile(r"^\s*(\d+)\s*[xX]\s*([A-Za-z0-9\-!_]+)\s*$")
# Matches: ST06-010 x4, ST06-010 4
RE_CODE_X_COUNT = re.compile(r"^\s*([A-Za-z0-9\-!_]+)\s*(?:[xX]\s*)?(\d+)\s*$")


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _save_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _index_cards() -> dict[str, dict]:
    """Build a best-effort index: card_code -> representative card dict."""
    index: dict[str, dict] = {}
    if not SETS_ROOT.exists():
        return index

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
            code = str(c.get("card_code") or "").strip().upper()
            if not code:
                continue
            # Prefer a non-parallel base record if we see one.
            if code not in index or "_p" in str(index[code].get("id", "")).lower():
                index[code] = c

    return index


def _normalize_code(code: str) -> str:
    return (code or "").strip().upper()


def _base_code(code: str) -> str:
    return _normalize_code(code).split("_", 1)[0]


def _lookup_card(card_index: dict[str, dict], code: str) -> tuple[dict | None, str]:
    """Lookup a card by exact code first, then by base code.

    Returns (card_dict_or_none, matched_code).
    """
    normalized = _normalize_code(code)
    if normalized in card_index:
        return card_index[normalized], normalized
    base = _base_code(normalized)
    if base in card_index:
        return card_index[base], base
    return None, base


def _is_don_code(code: str) -> bool:
    c = _normalize_code(code)
    return c.startswith("DON")


def _don_entry() -> dict:
    return {
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


def _build_entry(card: dict, count: int, zone: str) -> dict:
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
        "set_code": str(card.get("set_code") or card.get("set") or ""),
        "number": str(card.get("number") or ""),
        "card_code": str(card.get("card_code") or ""),
        "count": int(count),
        "zone": zone,
    }


def _stub_entry(code: str, count: int, zone: str, force_type: str = "") -> dict:
    normalized = _normalize_code(code)
    base = _base_code(normalized)
    set_code = base.split("-")[0] if "-" in base else ""
    number = base.split("-")[1] if "-" in base else ""
    return {
        "id": normalized,
        "name": "",
        "type": force_type,
        "color": [],
        "cost": 0,
        "power": 0,
        "life": 0,
        "counter": 0,
        "rarity": "L" if force_type.lower() == "leader" else "",
        "attribute": "",
        "traits": [],
        "effect": "",
        "set_code": set_code,
        "number": number,
        "card_code": normalized,
        "count": int(count),
        "zone": zone,
    }


def _sum_counts(entries: Iterable[dict]) -> int:
    s = 0
    for e in entries:
        if isinstance(e, dict):
            s += int(e.get("count", 0) or 0)
    return s


def _parse_recipe_text(text: str) -> dict[str, int]:
    s = (text or "").strip()
    if not s:
        return {}

    # JSON array export format: ["...", "ST06-010", "ST06-010", ...]
    if s.startswith("["):
        try:
            parsed = json.loads(s)
        except Exception:
            parsed = None
        if isinstance(parsed, list):
            counts: dict[str, int] = {}
            for item in parsed:
                code = _normalize_code(str(item))
                if not code or "-" not in code:
                    continue
                counts[code] = int(counts.get(code, 0)) + 1
            return counts

    counts: dict[str, int] = {}
    for raw in s.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#"):
            continue
        # tolerate commas and tabs
        line = line.replace(",", " ").replace("\t", " ")

        m = RE_COUNT_X_CODE.match(line)
        if m:
            n = int(m.group(1))
            code = _normalize_code(m.group(2))
            if not code:
                continue
            counts[code] = int(counts.get(code, 0)) + n
            continue

        m = RE_CODE_X_COUNT.match(line)
        if m and "-" in m.group(1):
            code = _normalize_code(m.group(1))
            n = int(m.group(2))
            counts[code] = int(counts.get(code, 0)) + n
            continue

        # Bare code
        if "-" in line:
            code = _normalize_code(line)
            counts[code] = int(counts.get(code, 0)) + 1

    return counts


def _guess_deck_id_from_path(path: Path) -> str | None:
    """Best-effort deck id guess from a recipe filename.

    Supports variants like:
    - ST-10-Luffy.txt  -> ST-10-Luffy
    - ST10_Law.txt     -> ST-10-Law
    - ST-06.txt        -> ST-06
    """

    stem_raw = (path.stem or "").strip()
    if not stem_raw:
        return None

    # Capture: ST + number + optional .sub + optional suffix.
    # Examples:
    #  - ST-13.3.txt -> ST-13.3
    #  - ST-10-Luffy.txt -> ST-10-Luffy
    #  - ST10_Law.txt -> ST-10-Law
    m = re.match(r"(?i)^ST\s*[-_]?\s*(\d{2})(?:\s*\.\s*(\d+))?(?:\s*[-_]+\s*(.+))?$", stem_raw)
    if not m:
        # Fallback: find ST## anywhere in the stem.
        m2 = re.search(r"(?i)ST\s*[-_]?\s*(\d{2})(?:\s*\.\s*(\d+))?", stem_raw)
        if not m2:
            return None
        n2 = int(m2.group(1))
        deck_id2 = f"ST-{n2:02d}"
        sub2 = (m2.group(2) or "").strip()
        if sub2:
            deck_id2 = f"{deck_id2}.{int(sub2)}"
        return deck_id2

    n = int(m.group(1))
    deck_id = f"ST-{n:02d}"

    sub = (m.group(2) or "").strip()
    if sub:
        deck_id = f"{deck_id}.{int(sub)}"

    suffix = (m.group(3) or "").strip()
    if suffix:
        # Normalize separators, strip odd punctuation, keep case.
        suffix = suffix.replace("/", " ").replace("\\", " ")
        suffix = re.sub(r"\s+", " ", suffix)
        suffix = re.sub(r"[^A-Za-z0-9]+", "-", suffix).strip("-")
        if suffix:
            deck_id = f"{deck_id}-{suffix}"

    return deck_id


def _parse_recipe_header_display(header_line: str) -> dict[str, str]:
    """Parse a recipe header comment into display metadata.

    Expected examples:
      "# ST-01 R Luffy (Starter Deck 01) recipe"
      "# ST-13.3 R/Y Sabo(Starter Deck 13) recipe"
      "# ST-10 R/P Law (Starter Deck 10) recipe"
    """

    s = (header_line or "").strip()
    if s.startswith("#"):
        s = s[1:].strip()

    # Drop trailing parenthetical section for name parsing.
    before_paren = s.split("(", 1)[0].strip()
    if not before_paren:
        return {}

    # Deck token (best effort): first token beginning with ST.
    m = re.search(r"(?i)\bST\s*[-_]?\s*\d{2}(?:\s*\.\s*\d+)?\b", before_paren)
    if not m:
        return {}

    after = before_paren[m.end() :].strip()
    colors = ""
    title = ""

    if after:
        parts = after.split()
        if parts:
            maybe_colors = parts[0].strip().upper()
            # Accept: R, G, B, Y, P, BK and slash combos like R/P or G/B.
            if re.fullmatch(r"(?:R|G|B|Y|P|BK)(?:/(?:R|G|B|Y|P|BK))*", maybe_colors):
                colors = maybe_colors
                title = after[len(parts[0]) :].strip()
            else:
                title = after

    return {
        "source_header": s,
        "colors": colors,
        "title": title,
    }


def _identify_leader(counts: dict[str, int], card_index: dict[str, dict], deck_id: str | None) -> str | None:
    candidates: list[str] = []
    for code in counts.keys():
        if _is_don_code(code):
            continue
        card, _matched = _lookup_card(card_index, code)
        if not isinstance(card, dict):
            continue
        t = str(card.get("type") or "").strip().lower()
        r = str(card.get("rarity") or "").strip().upper()
        if t == "leader" or r == "L":
            candidates.append(_normalize_code(code))

    # Prefer explicit type Leader.
    for c in candidates:
        card, _matched = _lookup_card(card_index, c)
        if isinstance(card, dict) and str(card.get("type") or "").strip().lower() == "leader":
            return c

    if len(candidates) == 1:
        return candidates[0]

    # Fallback: STxx-001
    if deck_id and deck_id.startswith("ST-"):
        n = int(deck_id.split("-")[1])
        expected = f"ST{n:02d}-001"
        # Prefer exact match if recipe used a suffix, otherwise base.
        for k in counts.keys():
            if _base_code(k) == expected:
                return _normalize_code(k)

    return None


@dataclass
class ImportResult:
    deck_id: str
    input_path: str
    ok: bool
    message: str
    totals: dict[str, int]
    missing_codes: list[str]
    leader_code: str | None


def import_one(path: Path, deck_id: str, card_index: dict[str, dict]) -> Tuple[dict, ImportResult]:
    text = path.read_text(encoding="utf-8", errors="replace")
    header_line = ""
    for raw in (text or "").splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#"):
            header_line = line
        break

    display_meta = _parse_recipe_header_display(header_line)
    counts = _parse_recipe_text(text)

    # Remove DON from main; we'll force don=10.
    # Keep explicit suffix variants (e.g. _P1) if provided in the recipe.
    # We only use base-code fallback for metadata lookup.
    main_counts = { _normalize_code(k): int(v) for k, v in counts.items() if not _is_don_code(k) }

    leader = _identify_leader(main_counts, card_index, deck_id=deck_id)

    leader_total = 0
    non_leader_total = 0

    main_entries: list[dict] = []
    missing: list[str] = []

    # Build leader first (if known)
    if leader:
        cnt = int(main_counts.pop(_normalize_code(leader), 0) or 0)
        if cnt <= 0:
            cnt = 1
        leader_total = cnt
        card, _matched = _lookup_card(card_index, leader)
        if isinstance(card, dict):
            e = _build_entry(card, count=cnt, zone="main")
            # Preserve explicit recipe code (including suffix) for image/variant selection.
            e["id"] = _normalize_code(leader)
            e["card_code"] = _normalize_code(leader)
            # Ensure type reflects leader
            if str(e.get("type") or "").strip().lower() != "leader":
                e["type"] = "Leader"
                e["rarity"] = str(e.get("rarity") or "L")
            main_entries.append(e)
        else:
            missing.append(leader)
            main_entries.append(_stub_entry(leader, count=cnt, zone="main", force_type="Leader"))

    # Build remaining entries
    for code in sorted(main_counts.keys()):
        cnt = int(main_counts[code] or 0)
        if cnt <= 0:
            continue
        non_leader_total += cnt
        card, _matched = _lookup_card(card_index, code)
        if isinstance(card, dict):
            e = _build_entry(card, count=cnt, zone="main")
            e["id"] = _normalize_code(code)
            e["card_code"] = _normalize_code(code)
            main_entries.append(e)
        else:
            missing.append(code)
            main_entries.append(_stub_entry(code, count=cnt, zone="main"))

    # Force don
    don_entries = [_don_entry()]

    totals = {
        "leader_total": int(leader_total),
        "non_leader_total": int(non_leader_total),
        "main_total_including_leader": int(leader_total + non_leader_total),
        "don_total": 10,
    }

    ok = (leader_total == 1 and non_leader_total == 50 and totals["don_total"] == 10)
    msg = "OK" if ok else f"INVALID: leader={leader_total} nonLeader={non_leader_total} don=10"

    deck_json: dict[str, Any] = {
        "deck_id": deck_id,
        "display_name": " ".join([p for p in [deck_id, display_meta.get("colors", ""), display_meta.get("title", "")] if p]).strip(),
        "display_colors": display_meta.get("colors", ""),
        "display_title": display_meta.get("title", ""),
        "source_header": display_meta.get("source_header", ""),
        "source": "recipe_text",
        "imported_at": int(time.time()),
        "recipe_file": str(path).replace("\\", "/"),
        "main": main_entries,
        "don": don_entries,
        "_totals": totals,
    }

    return deck_json, ImportResult(
        deck_id=deck_id,
        input_path=str(path).replace("\\", "/"),
        ok=ok,
        message=msg,
        totals=totals,
        missing_codes=missing,
        leader_code=leader,
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="Path to a recipe file or a directory of recipe files.")
    ap.add_argument("--deck-id", default="", help="Deck id like ST-06. If omitted, guessed from filename.")
    ap.add_argument(
        "--write",
        action="store_true",
        help="Actually write deck JSON files (default is dry-run report only).",
    )
    ap.add_argument(
        "--preview",
        action="store_true",
        help="Write a preview JSON to output/reports/recipe_previews/<DECK_ID>.json (no overwrites of real decks).",
    )
    ap.add_argument(
        "--allow-invalid",
        action="store_true",
        help="Allow writing invalid decks (otherwise invalid decks are skipped).",
    )
    ap.add_argument(
        "--dest",
        choices=["output", "data"],
        default="data",
        help="Primary destination folder for generated deck JSON files.",
    )
    ap.add_argument(
        "--also",
        choices=["output", "data"],
        action="append",
        default=[],
        help="Optional additional destination(s). Can be repeated.",
    )
    args = ap.parse_args()

    card_index = _index_cards()

    in_path = Path(args.input)
    if not in_path.exists():
        raise SystemExit(f"Input not found: {in_path}")

    files: list[Path] = []
    if in_path.is_dir():
        files = sorted([p for p in in_path.glob("*.*") if p.suffix.lower() in {".txt", ".deck", ".csv", ".ydl", ".json"}])
    else:
        files = [in_path]

    dest_map = {"output": OUT_DECKS, "data": DATA_DECKS}
    dest_keys = [args.dest] + list(args.also)
    seen: set[str] = set()
    dest_keys = [k for k in dest_keys if not (k in seen or seen.add(k))]
    dest_dirs = [dest_map[k] for k in dest_keys]

    results: list[dict[str, Any]] = []
    written: list[str] = []
    preview_paths: list[str] = []

    preview_dir = REPORT_DIR / "recipe_previews"
    if args.preview:
        preview_dir.mkdir(parents=True, exist_ok=True)

    for p in files:
        deck_id = (args.deck_id or "").strip().upper()
        if not deck_id:
            deck_id = _guess_deck_id_from_path(p) or p.stem
        if not deck_id:
            deck_id = p.stem

        print(f"[import] {deck_id} <- {p.name}", flush=True)

        deck_json, res = import_one(p, deck_id=deck_id, card_index=card_index)

        if args.preview:
            preview_path = preview_dir / f"{deck_id}.json"
            _save_json(preview_path, deck_json)
            preview_paths.append(str(preview_path.relative_to(ROOT)).replace("\\", "/"))
        results.append(
            {
                "deck_id": res.deck_id,
                "input": res.input_path,
                "ok": res.ok,
                "message": res.message,
                "totals": res.totals,
                "leader_code": res.leader_code,
                "missing_codes": res.missing_codes,
            }
        )

        if args.write and (res.ok or args.allow_invalid):
            for d in dest_dirs:
                d.mkdir(parents=True, exist_ok=True)
                out_path = d / f"{deck_id}.json"
                _save_json(out_path, deck_json)
                written.append(str(out_path.relative_to(ROOT)).replace("\\", "/"))

    report = {
        "generated_at": int(time.time()),
        "input": str(in_path).replace("\\", "/"),
        "write": bool(args.write),
        "preview": bool(args.preview),
        "destinations": dest_keys,
        "results": results,
        "written": written,
        "previews": preview_paths,
    }

    report_path = REPORT_DIR / "deck_recipe_import_report.json"
    _save_json(report_path, report)

    print(f"\nWrote report: {report_path}")
    if args.write:
        print(f"Wrote decks: {len(written)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
