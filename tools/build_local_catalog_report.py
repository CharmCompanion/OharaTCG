"""Build a local catalog report from generated output files.

This is *offline*: it only reads files already present in this repo.

Outputs:
- output/catalog/local_catalog_summary.json
- output/catalog/local_catalog_report.md
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "output" / "catalog"
OUT_DIR.mkdir(parents=True, exist_ok=True)

SETS_ROOT = ROOT / "output" / "sets"
DECKS_ROOT = ROOT / "output" / "decks"


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _safe_str(v: Any) -> str:
    return "" if v is None else str(v).strip()


def _sum_counts(entries: Iterable[dict]) -> int:
    total = 0
    for e in entries:
        if not isinstance(e, dict):
            continue
        try:
            total += int(e.get("count") or 0)
        except Exception:
            pass
    return total


@dataclass
class SetInfo:
    category: str  # booster/starter/promotional/special
    set_id: str
    set_name: str
    path: str
    card_entries: int
    unique_card_codes: int


@dataclass
class DeckInfo:
    category: str  # starter/ultra/...
    deck_id: str
    path: str
    leader_codes: list[str]
    main_total: int
    don_total: int
    warnings: list[str]


def _scan_sets() -> list[SetInfo]:
    out: list[SetInfo] = []
    if not SETS_ROOT.exists():
        return out

    for category_dir in sorted([p for p in SETS_ROOT.iterdir() if p.is_dir()]):
        category = category_dir.name
        for json_path in sorted(category_dir.rglob("*.json")):
            try:
                data = _load_json(json_path)
            except Exception:
                continue

            set_id = _safe_str(data.get("set_id"))
            set_name = _safe_str(data.get("set_name"))
            cards = data.get("cards")
            if not isinstance(cards, list):
                cards = []

            unique_codes = {
                _safe_str(c.get("card_code")) for c in cards if isinstance(c, dict)
            }
            unique_codes.discard("")

            out.append(
                SetInfo(
                    category=category,
                    set_id=set_id or json_path.stem,
                    set_name=set_name,
                    path=str(json_path.relative_to(ROOT)).replace("\\", "/"),
                    card_entries=len(cards),
                    unique_card_codes=len(unique_codes),
                )
            )

    return out


def _scan_decks() -> list[DeckInfo]:
    out: list[DeckInfo] = []
    if not DECKS_ROOT.exists():
        return out

    for category_dir in sorted([p for p in DECKS_ROOT.iterdir() if p.is_dir()]):
        category = category_dir.name
        for json_path in sorted(category_dir.glob("*.json")):
            deck_id = json_path.stem
            try:
                data = _load_json(json_path)
            except Exception:
                continue

            main = data.get("main")
            don = data.get("don")
            if not isinstance(main, list):
                main = []
            if not isinstance(don, list):
                don = []

            leaders = []
            for e in main:
                if not isinstance(e, dict):
                    continue
                if _safe_str(e.get("type")).lower() == "leader":
                    code = _safe_str(e.get("card_code"))
                    if code:
                        leaders.append(code)

            main_total = _sum_counts(main)
            don_total = _sum_counts(don)

            warnings: list[str] = []
            if len(leaders) != 1:
                warnings.append(f"leader_count={len(leaders)}")

            # Starter deck expectations (OPTCG): 1 leader + 50-card main deck + 10 DON.
            # Some export sources are incomplete; this surfaces that.
            non_leader_main_total = main_total
            for e in main:
                if not isinstance(e, dict):
                    continue
                if _safe_str(e.get("type")).lower() == "leader":
                    try:
                        non_leader_main_total -= int(e.get("count") or 0)
                    except Exception:
                        pass

            if non_leader_main_total != 50:
                warnings.append(f"non_leader_main_total={non_leader_main_total} (expected 50)")
            if don_total != 10:
                warnings.append(f"don_total={don_total} (expected 10)")

            out.append(
                DeckInfo(
                    category=category,
                    deck_id=deck_id,
                    path=str(json_path.relative_to(ROOT)).replace("\\", "/"),
                    leader_codes=leaders,
                    main_total=main_total,
                    don_total=don_total,
                    warnings=warnings,
                )
            )

    return out


def main() -> int:
    sets = _scan_sets()
    decks = _scan_decks()

    summary = {
        "generated_from": {
            "sets_root": str(SETS_ROOT.relative_to(ROOT)).replace("\\", "/"),
            "decks_root": str(DECKS_ROOT.relative_to(ROOT)).replace("\\", "/"),
        },
        "counts": {
            "sets": len(sets),
            "decks": len(decks),
        },
        "sets": [s.__dict__ for s in sets],
        "decks": [d.__dict__ for d in decks],
    }

    (OUT_DIR / "local_catalog_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    # Markdown report for quick scanning.
    lines: list[str] = []
    lines.append("# Local Catalog Report")
    lines.append("")
    lines.append("Offline summary of what currently exists under `output/sets/` and `output/decks/`.")
    lines.append("")
    lines.append(f"- Sets: {len(sets)}")
    lines.append(f"- Decks: {len(decks)}")
    lines.append("")

    # Sets grouped by category
    lines.append("## Sets")
    lines.append("")
    for category in sorted({s.category for s in sets}):
        subset = [s for s in sets if s.category == category]
        lines.append(f"### {category} ({len(subset)})")
        lines.append("")
        for s in sorted(subset, key=lambda x: x.set_id):
            name = f" — {s.set_name}" if s.set_name else ""
            lines.append(
                f"- {s.set_id}{name} (cards: {s.card_entries}, unique codes: {s.unique_card_codes}) — {s.path}"
            )
        lines.append("")

    # Decks grouped by category
    lines.append("## Decks")
    lines.append("")
    for category in sorted({d.category for d in decks}):
        subset = [d for d in decks if d.category == category]
        lines.append(f"### {category} ({len(subset)})")
        lines.append("")
        for d in sorted(subset, key=lambda x: x.deck_id):
            leader = d.leader_codes[0] if d.leader_codes else ""
            warn = f" WARN: {', '.join(d.warnings)}" if d.warnings else ""
            lines.append(
                f"- {d.deck_id} (leader: {leader}, main total: {d.main_total}, DON: {d.don_total}) — {d.path}{warn}"
            )
        lines.append("")

    (OUT_DIR / "local_catalog_report.md").write_text("\n".join(lines), encoding="utf-8")

    print(f"WROTE {OUT_DIR / 'local_catalog_summary.json'}")
    print(f"WROTE {OUT_DIR / 'local_catalog_report.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
