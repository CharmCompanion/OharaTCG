"""Compare a fetched global catalog against this repo's local outputs.

Why:
- You want a definitive checklist of *what exists* (sets/decks/promos) from a public catalog
  and then a diff against what OharaTCG has locally.

Inputs:
- A catalog sources JSON produced by `tools/dump_catalog_sources.py`
  (network fetch; run locally on your machine).
- Local inventory JSON produced by `tools/build_local_catalog_report.py`.

Outputs:
- output/catalog/global_compare_report.md

Usage:
  python tools/build_local_catalog_report.py
  python tools/dump_catalog_sources.py
  python tools/global_catalog_compare.py --sources output/catalog/catalog_sources_YYYYMMDD_HHMMSS.json

If you can't fetch in this environment, you can still run compare once the sources JSON exists.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "output" / "catalog"
OUT_DIR.mkdir(parents=True, exist_ok=True)


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _local_set_ids(local_summary: dict) -> set[str]:
    out: set[str] = set()
    for s in local_summary.get("sets", []):
        if isinstance(s, dict):
            sid = str(s.get("set_id") or "").strip()
            if sid:
                out.add(sid)
    return out


def _local_deck_ids(local_summary: dict) -> set[str]:
    out: set[str] = set()
    for d in local_summary.get("decks", []):
        if isinstance(d, dict):
            did = str(d.get("deck_id") or "").strip()
            if did:
                out.add(did)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--sources",
        required=True,
        help="Path to catalog_sources_*.json produced by dump_catalog_sources.py",
    )
    ap.add_argument(
        "--local",
        default=str(OUT_DIR / "local_catalog_summary.json"),
        help="Path to local_catalog_summary.json (default: output/catalog/local_catalog_summary.json)",
    )
    args = ap.parse_args()

    sources_path = Path(args.sources)
    local_path = Path(args.local)

    sources = _load_json(sources_path)
    local = _load_json(local_path)

    local_sets = _local_set_ids(local)
    local_decks = _local_deck_ids(local)

    # Global sets/decks from OPTCG API.
    global_sets = set()
    for s in sources.get("optcgapi", {}).get("sets", []):
        if isinstance(s, dict):
            sid = str(s.get("set_id") or "").strip()
            if sid:
                global_sets.add(sid)

    global_decks = set()
    for d in sources.get("optcgapi", {}).get("decks", []):
        if isinstance(d, dict):
            did = str(d.get("structure_deck_id") or "").strip()
            if did:
                global_decks.add(did)

    promo_set_ids = set(sources.get("optcgapi", {}).get("promo_set_ids", []) or [])

    missing_sets = sorted(global_sets - local_sets)
    extra_sets = sorted(local_sets - global_sets)

    # Local deck ids are like ST-01; global structure deck ids often like ST-01.
    missing_decks = sorted(global_decks - local_decks)
    extra_decks = sorted(local_decks - global_decks)

    md: list[str] = []
    md.append("# Global Catalog Compare")
    md.append("")
    md.append(f"Sources: `{sources_path.as_posix()}`")
    md.append(f"Local: `{local_path.as_posix()}`")
    md.append("")

    md.append("## Summary")
    md.append("")
    md.append(f"- Global sets (OPTCG API /allSets): {len(global_sets)}")
    md.append(f"- Local sets (output/sets): {len(local_sets)}")
    md.append(f"- Missing sets locally: {len(missing_sets)}")
    md.append(f"- Extra sets locally (not in global list): {len(extra_sets)}")
    md.append("")

    md.append(f"- Global structure decks (/allDecks): {len(global_decks)}")
    md.append(f"- Local deck exports (output/decks): {len(local_decks)}")
    md.append(f"- Missing decks locally: {len(missing_decks)}")
    md.append(f"- Extra decks locally: {len(extra_decks)}")
    md.append("")

    md.append(f"- Promo set IDs seen in /allPromos: {len(promo_set_ids)}")
    md.append("")

    md.append("## Missing sets (global → not found locally)")
    md.append("")
    for sid in missing_sets:
        md.append(f"- {sid}")
    if not missing_sets:
        md.append("- (none)")
    md.append("")

    md.append("## Extra sets (local → not found in global)")
    md.append("")
    for sid in extra_sets:
        md.append(f"- {sid}")
    if not extra_sets:
        md.append("- (none)")
    md.append("")

    md.append("## Missing decks (global → not found locally)")
    md.append("")
    for did in missing_decks:
        md.append(f"- {did}")
    if not missing_decks:
        md.append("- (none)")
    md.append("")

    md.append("## Extra decks (local → not found in global)")
    md.append("")
    for did in extra_decks:
        md.append(f"- {did}")
    if not extra_decks:
        md.append("- (none)")
    md.append("")

    out_path = OUT_DIR / "global_compare_report.md"
    out_path.write_text("\n".join(md), encoding="utf-8")
    print(f"WROTE {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
