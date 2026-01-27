"""Dump set/deck/promo catalogs from public sources.

Writes a consolidated summary JSON under output/catalog/.

Sources:
- OPTCG API: https://optcgapi.com/api/allSets/, /allDecks/, /allPromos/
- Vegapull records (English pack list):
  https://raw.githubusercontent.com/Coko7/vegapull-records/main/data/english/sets.json

This does NOT scrape any third-party site content beyond these public endpoints.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import requests


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "output" / "catalog"
OUT_DIR.mkdir(parents=True, exist_ok=True)


@dataclass(frozen=True)
class Source:
    name: str
    url: str


SOURCES = {
    "optcg_allSets": Source("optcg_allSets", "https://optcgapi.com/api/allSets/"),
    "optcg_allDecks": Source("optcg_allDecks", "https://optcgapi.com/api/allDecks/"),
    "optcg_allPromos": Source("optcg_allPromos", "https://optcgapi.com/api/allPromos/"),
    "vegapull_tcg_sets": Source(
        "vegapull_tcg_sets",
        "https://raw.githubusercontent.com/Coko7/vegapull-records/main/data/english/sets.json",
    ),
}


def _get_json(session: requests.Session, url: str) -> Any:
    resp = session.get(url, timeout=60)
    resp.raise_for_status()
    return resp.json()


def _safe_str(v: Any) -> str:
    return "" if v is None else str(v).strip()


def main() -> int:
    session = requests.Session()
    session.headers.update({"User-Agent": "OharaTCG-Catalog/1.0"})

    fetched_at = time.time()

    optcg_sets = _get_json(session, SOURCES["optcg_allSets"].url)
    optcg_decks = _get_json(session, SOURCES["optcg_allDecks"].url)
    optcg_promos = _get_json(session, SOURCES["optcg_allPromos"].url)
    vegapull_sets = _get_json(session, SOURCES["vegapull_tcg_sets"].url)

    # Normalize into compact lists.
    optcg_sets_norm = []
    if isinstance(optcg_sets, list):
        for it in optcg_sets:
            if not isinstance(it, dict):
                continue
            optcg_sets_norm.append(
                {
                    "set_id": _safe_str(it.get("set_id")),
                    "set_name": _safe_str(it.get("set_name")),
                }
            )

    optcg_decks_norm = []
    if isinstance(optcg_decks, list):
        for it in optcg_decks:
            if not isinstance(it, dict):
                continue
            optcg_decks_norm.append(
                {
                    "structure_deck_id": _safe_str(it.get("structure_deck_id")),
                    "structure_deck_name": _safe_str(it.get("structure_deck_name")),
                }
            )

    # /allPromos/ returns a big card list; we only keep promo set IDs/names if present.
    promo_set_ids = set()
    if isinstance(optcg_promos, list):
        for it in optcg_promos:
            if not isinstance(it, dict):
                continue
            sid = _safe_str(it.get("set_id"))
            if sid:
                promo_set_ids.add(sid)

    vegapull_packs_norm = []
    if isinstance(vegapull_sets, list):
        for it in vegapull_sets:
            if not isinstance(it, dict):
                continue
            vegapull_packs_norm.append(
                {
                    "id": _safe_str(it.get("id")),
                    "title": _safe_str(it.get("title")),
                    "label": _safe_str(it.get("label")),
                    "type": _safe_str(it.get("type")),
                    "language": _safe_str(it.get("language")),
                }
            )

    summary = {
        "fetched_at_unix": fetched_at,
        "sources": {k: v.url for k, v in SOURCES.items()},
        "counts": {
            "optcg_allSets": len(optcg_sets) if isinstance(optcg_sets, list) else None,
            "optcg_allDecks": len(optcg_decks) if isinstance(optcg_decks, list) else None,
            "optcg_allPromos": len(optcg_promos) if isinstance(optcg_promos, list) else None,
            "vegapull_tcg_sets": len(vegapull_sets) if isinstance(vegapull_sets, list) else None,
        },
        "optcgapi": {
            "sets": sorted(optcg_sets_norm, key=lambda d: d.get("set_id", "")),
            "decks": sorted(optcg_decks_norm, key=lambda d: d.get("structure_deck_id", "")),
            "promo_set_ids": sorted(promo_set_ids),
        },
        "vegapull": {
            "packs": sorted(vegapull_packs_norm, key=lambda d: d.get("id", "")),
        },
    }

    stamp = time.strftime("%Y%m%d_%H%M%S")
    out_path = OUT_DIR / f"catalog_sources_{stamp}.json"
    out_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"WROTE {out_path}")
    print("COUNTS", summary["counts"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
