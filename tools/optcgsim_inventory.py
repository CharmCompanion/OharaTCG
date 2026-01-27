"""Inventory OPTCGSim (Unity) StreamingAssets.

Offline-only: reads from `addons/Builds_Windows/OPTCGSim_Data/StreamingAssets`.

Outputs:
- output/catalog/optcgsim_inventory.json
- output/catalog/optcgsim_inventory.md
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SIM_ROOT = ROOT / "addons" / "Builds_Windows" / "OPTCGSim_Data" / "StreamingAssets"
CARDS_ROOT = SIM_ROOT / "Cards"
DECKS_ROOT = ROOT / "addons" / "Builds_Windows" / "Decks"
OUT_DIR = ROOT / "output" / "catalog"
OUT_DIR.mkdir(parents=True, exist_ok=True)


@dataclass
class DeckFile:
    name: str
    path: str
    total_cards_including_leader: int
    unique_codes: int


def _parse_deck_file(path: Path) -> DeckFile:
    total = 0
    unique = 0
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line:
            continue
        # Format: 4xST01-006
        if "x" not in line:
            continue
        left, right = line.split("x", 1)
        try:
            count = int(left)
        except Exception:
            continue
        code = right.strip()
        if not code:
            continue
        total += count
        unique += 1
    return DeckFile(
        name=path.name,
        path=str(path.relative_to(ROOT)).replace("\\", "/"),
        total_cards_including_leader=total,
        unique_codes=unique,
    )


def main() -> int:
    if not SIM_ROOT.exists():
        raise SystemExit(f"Missing OPTCGSim StreamingAssets at: {SIM_ROOT}")

    fetched_at = time.time()

    sets: dict[str, int] = {}
    if CARDS_ROOT.exists():
        for set_dir in sorted([p for p in CARDS_ROOT.iterdir() if p.is_dir()]):
            png_count = len(list(set_dir.glob("*.png")))
            sets[set_dir.name] = png_count

    decks: list[DeckFile] = []
    if DECKS_ROOT.exists():
        for deck_path in sorted(DECKS_ROOT.glob("*.deck")):
            decks.append(_parse_deck_file(deck_path))

    translation_path = SIM_ROOT / "TRANSLATION.txt"
    translation_keys = 0
    translation_lines = 0
    if translation_path.exists():
        for raw in translation_path.read_text(encoding="utf-8", errors="replace").splitlines():
            translation_lines += 1
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                translation_keys += 1

    playmats = []
    playmats_root = SIM_ROOT / "Playmats"
    if playmats_root.exists():
        for p in sorted(playmats_root.glob("*.png")):
            playmats.append(p.name)
        for p in sorted(playmats_root.glob("*.jpg")):
            playmats.append(p.name)

    summary: dict[str, Any] = {
        "generated_at_unix": fetched_at,
        "paths": {
            "streaming_assets": str(SIM_ROOT.relative_to(ROOT)).replace("\\", "/"),
            "cards": str(CARDS_ROOT.relative_to(ROOT)).replace("\\", "/"),
            "decks": str(DECKS_ROOT.relative_to(ROOT)).replace("\\", "/"),
        },
        "cards": {
            "set_folders": sorted(sets.keys()),
            "png_counts_by_set": sets,
            "total_png": sum(sets.values()),
        },
        "decks": {
            "count": len(decks),
            "files": [d.__dict__ for d in decks],
        },
        "translation": {
            "file": str(translation_path.relative_to(ROOT)).replace("\\", "/")
            if translation_path.exists()
            else None,
            "lines": translation_lines,
            "keys": translation_keys,
        },
        "playmats": {
            "count": len(playmats),
            "files": playmats,
        },
    }

    (OUT_DIR / "optcgsim_inventory.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    # Markdown report
    md = []
    md.append("# OPTCGSim (Builds_Windows) Inventory")
    md.append("")
    md.append("Offline inventory from Unity StreamingAssets.")
    md.append("")
    md.append(f"- StreamingAssets: `{summary['paths']['streaming_assets']}`")
    md.append(f"- Total card images (PNG): {summary['cards']['total_png']}")
    md.append(f"- Card set folders: {len(summary['cards']['set_folders'])}")
    md.append(f"- Deck files: {summary['decks']['count']}")
    md.append(f"- Translation keys: {summary['translation']['keys']}")
    md.append(f"- Playmats: {summary['playmats']['count']}")
    md.append("")

    md.append("## Card sets (PNG counts)")
    md.append("")
    for set_code in sorted(sets.keys()):
        md.append(f"- {set_code}: {sets[set_code]}")
    md.append("")

    md.append("## Deck files")
    md.append("")
    for d in decks:
        md.append(
            f"- {d.name}: total(incl leader)={d.total_cards_including_leader}, unique={d.unique_codes} ({d.path})"
        )
    md.append("")

    (OUT_DIR / "optcgsim_inventory.md").write_text("\n".join(md), encoding="utf-8")
    print(f"WROTE {OUT_DIR / 'optcgsim_inventory.json'}")
    print(f"WROTE {OUT_DIR / 'optcgsim_inventory.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
