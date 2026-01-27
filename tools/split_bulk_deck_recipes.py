"""Split a bulk deck recipe file into per-deck recipe files.

This is for large pasted lists like data/recipes/STs.txt where each deck is
separated by a header line.

Input assumptions (flexible):
- Deck header lines start with '#' and contain 'ST' and a deck number.
  Examples:
    # ST-06 (Starter Deck 06) recipe
    # ST-10 Law (Starter Deck 10) recipe
- Card lines contain a count and a card code, optionally followed by a name.
  Examples:
    4 ST06-010 Helmeppo
    4xOP01-016_p3
    2xST11-004_p1

Output:
- Writes one file per detected deck into a destination folder (default: data/recipes).
- Output file contains only `NxCODE` lines (e.g. `4xST06-010`), suitable for:
    python tools/import_deck_recipe_text.py --input data/recipes/<file>

Safety:
- By default, does not overwrite existing files.

Also writes a split report:
- output/reports/bulk_recipe_split_report.json

Usage:
  python tools/split_bulk_deck_recipes.py --input data/recipes/STs.txt
  python tools/split_bulk_deck_recipes.py --input data/recipes/STs.txt --overwrite
"""

from __future__ import annotations

import argparse
import json
import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REPORT_DIR = ROOT / "output" / "reports"
REPORT_DIR.mkdir(parents=True, exist_ok=True)


HEADER_RE = re.compile(r"^\s*#\s*(.+?)\s*$")
# Accept: ST-06, ST06, ST 06, ST-13.3
ST_TOKEN_RE = re.compile(r"\bST\s*[-_]?\s*(\d{2})(?:\s*\.\s*(\d+))?\b", re.IGNORECASE)

# Matches:
#  - 4 ST06-010 Helmeppo
#  - 4xOP01-016_p3
#  - 2xST11-004_p1
LINE_RE_1 = re.compile(r"^\s*(\d+)\s*[xX]?\s*([A-Za-z0-9\-!_]+)\b")


def _save_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _norm_code(code: str) -> str:
    return (code or "").strip().upper()


def _deck_id_from_header(header: str) -> str | None:
    """Convert a header string into a deck id used for output filename.

    Rules:
    - Prefer explicit sub-variant notation: ST-13.3 -> ST-13.3
    - Do NOT bake colors/names into the id (those are display metadata).
    - If a base id repeats (e.g. ST-10 appears 3 times), numbering is handled
      by the caller.
    """

    m = ST_TOKEN_RE.search(header or "")
    if not m:
        return None

    n = int(m.group(1))
    base = f"ST-{n:02d}"
    sub = (m.group(2) or "").strip()
    if sub:
        return f"{base}.{int(sub)}"
    return base


@dataclass
class DeckBucket:
    deck_id: str
    base_id: str
    has_explicit_sub: bool
    header: str
    counts: dict[str, int]


def _renumber_implicit_variants(buckets: list[DeckBucket]) -> None:
    """Renumber duplicate base decks that don't have an explicit .sub in the header.

    Example: if ST-10 appears 3 times, and none of those headers specified ST-10.1,
    then rewrite ids to ST-10.1, ST-10.2, ST-10.3 (in appearance order).
    """

    # Group indices by base id for buckets that did not specify an explicit sub.
    groups: dict[str, list[int]] = {}
    for i, b in enumerate(buckets):
        if b.has_explicit_sub:
            continue
        groups.setdefault(b.base_id, []).append(i)

    for base_id, idxs in groups.items():
        if len(idxs) <= 1:
            continue
        for n, i in enumerate(idxs, start=1):
            buckets[i].deck_id = f"{base_id}.{n}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="Bulk recipe text file.")
    ap.add_argument(
        "--dest",
        default="data/recipes",
        help="Destination folder for per-deck recipe files (relative to repo root).",
    )
    ap.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing per-deck recipe files.",
    )
    args = ap.parse_args()

    in_path = Path(args.input)
    if not in_path.is_absolute():
        in_path = (ROOT / in_path).resolve()
    if not in_path.exists():
        raise SystemExit(f"Input not found: {in_path}")

    dest_dir = Path(args.dest)
    if not dest_dir.is_absolute():
        dest_dir = (ROOT / dest_dir).resolve()
    dest_dir.mkdir(parents=True, exist_ok=True)

    buckets: list[DeckBucket] = []
    current: DeckBucket | None = None
    seen_ids: set[str] = set()

    for raw in in_path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.rstrip("\n")

        hm = HEADER_RE.match(line)
        if hm:
            header = hm.group(1).strip()
            did = _deck_id_from_header(header)
            if did:
                base_id = did.split(".", 1)[0]
                has_explicit_sub = "." in did
                current = DeckBucket(deck_id=did, base_id=base_id, has_explicit_sub=has_explicit_sub, header=header, counts={})
                buckets.append(current)
            else:
                # A header line that isn't one of our recognized deck ids.
                # Stop accumulating into the previous deck bucket to avoid
                # accidentally merging unrelated sections.
                current = None
            continue

        if current is None:
            continue

        if not line.strip():
            continue

        m = LINE_RE_1.match(line)
        if not m:
            continue

        count = int(m.group(1))
        code = _norm_code(m.group(2))
        if not code or "-" not in code:
            continue
        # Ignore DON lines; importer forces DON=10.
        if code.startswith("DON"):
            continue
        current.counts[code] = int(current.counts.get(code, 0)) + count

    written: list[str] = []
    skipped: list[str] = []

    deck_summaries: list[dict[str, Any]] = []

    # Renumber duplicates like ST-10 -> ST-10.1/.2/.3.
    _renumber_implicit_variants(buckets)

    # Ensure deck ids are unique after renumbering.
    for b in buckets:
        did = b.deck_id
        if did in seen_ids:
            j = 2
            while f"{did}-{j}" in seen_ids:
                j += 1
            b.deck_id = f"{did}-{j}"
        seen_ids.add(b.deck_id)

    for b in buckets:
        out_path = dest_dir / f"{b.deck_id}.txt"
        rel_out = str(out_path.relative_to(ROOT)).replace("\\", "/")

        if out_path.exists() and not args.overwrite:
            skipped.append(rel_out)
            continue

        lines: list[str] = []
        lines.append(f"# {b.header}")

        # Sort by code to keep stable.
        for code in sorted(b.counts.keys()):
            lines.append(f"{b.counts[code]}x{code}")

        out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        written.append(rel_out)

        total = sum(b.counts.values())
        non_st = sum(v for k, v in b.counts.items() if not k.startswith("ST"))
        deck_summaries.append(
            {
                "deck_id": b.deck_id,
                "header": b.header,
                "cards_total": total,
                "unique_codes": len(b.counts),
                "non_st_copies": non_st,
                "path": rel_out,
            }
        )

    report = {
        "generated_at": int(time.time()),
        "input": str(in_path.relative_to(ROOT)).replace("\\", "/")
        if str(in_path).startswith(str(ROOT))
        else str(in_path).replace("\\", "/"),
        "dest": str(dest_dir.relative_to(ROOT)).replace("\\", "/"),
        "overwrite": bool(args.overwrite),
        "decks_detected": len(buckets),
        "written": written,
        "skipped": skipped,
        "summaries": deck_summaries,
    }

    report_path = REPORT_DIR / "bulk_recipe_split_report.json"
    _save_json(report_path, report)
    print(f"Wrote report: {report_path}")
    print(f"Decks detected: {len(buckets)} | written: {len(written)} | skipped: {len(skipped)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
