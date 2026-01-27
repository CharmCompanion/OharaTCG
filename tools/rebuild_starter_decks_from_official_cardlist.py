"""Rebuild starter deck *unique card lists* from the official EN site cardlist.

What this solves:
- Many ST-06..ST-28 decks in this repo appear to be derived from sources that
  only list unique card codes (no quantities), so deck totals are incomplete.
- The official site provides the authoritative *unique card list* for each
  starter deck via its cardlist pages.

What this does NOT solve by itself:
- The official site does not expose per-card quantities in an easily-consumable
  format, so this script cannot reconstruct canonical counts unless you supply
  them.

Outputs (always):
- output/reports/starter_official_cardlist_unique.json
- output/reports/starter_official_cardlist_unique.md

Optional:
- With --guess-counts, produces a 51-card deck by applying a heuristic for
  quantities (clearly labeled as heuristic in the JSON).
- With --write, writes generated decks to:
    data/decks/<ST-XX>.json
    output/decks/starter/<ST-XX>.json

Usage:
  python tools/rebuild_starter_decks_from_official_cardlist.py --from 6 --to 28
  python tools/rebuild_starter_decks_from_official_cardlist.py --from 6 --to 28 --guess-counts
  python tools/rebuild_starter_decks_from_official_cardlist.py --from 6 --to 28 --guess-counts --write
"""

from __future__ import annotations

import argparse
import json
import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable
import socket
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen

try:
    import requests  # type: ignore
except Exception:  # pragma: no cover
    requests = None  # type: ignore


ROOT = Path(__file__).resolve().parents[1]
REPORT_DIR = ROOT / "output" / "reports"
REPORT_DIR.mkdir(parents=True, exist_ok=True)

SETS_ROOT = ROOT / "output" / "sets"
OUT_DECKS = ROOT / "output" / "decks" / "starter"
DATA_DECKS = ROOT / "data" / "decks"

USER_AGENT = "OharaTCG-OfficialCardlist/1.0 (+https://github.com/)"


CARD_CODE_RE = re.compile(r"\b([A-Z]{2}\d{2}-\d{3}(?:_[A-Za-z0-9]+)?)\b")


def _fetch_text(url: str, timeout: float) -> str:
    # Prefer requests for more reliable timeout behavior across repeated HTTPS calls.
    if requests is not None:
        resp = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=timeout)
        resp.raise_for_status()
        resp.encoding = resp.encoding or "utf-8"
        return resp.text

    # Fallback to urllib.
    socket.setdefaulttimeout(timeout)
    req = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
    return raw.decode("utf-8", "replace")


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


def _build_entry(card: dict, count: int, zone: str) -> dict:
    # Match existing deck json shape (keys used by your Godot importer).
    entry = {
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
    return entry


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


def _find_cardlist_url(product_html: str, base_root: str) -> str | None:
    # Typical link is like: /cardlist/?series=569006
    m = re.search(r'href="([^"]*/cardlist/\?series=\d+[^"]*)"', product_html, flags=re.I)
    if not m:
        return None
    href = m.group(1)
    # Normalize relative and scheme-relative links.
    if href.startswith("http://") or href.startswith("https://"):
        return href
    if href.startswith("//"):
        return "https:" + href
    return urljoin(base_root, href)


def _extract_card_codes(cardlist_html: str) -> list[str]:
    # The cardlist page contains card codes in multiple places.
    raw_codes = [m.group(1).upper() for m in CARD_CODE_RE.finditer(cardlist_html)]

    # Normalize variant suffixes (e.g. OP01-016_P3) to their base code.
    # If both variant + base exist, prefer base and skip the variant.
    base_present = {c for c in raw_codes if "_" not in c}

    normalized: list[str] = []
    for c in raw_codes:
        base = c.split("_", 1)[0]
        if "_" in c and base in base_present:
            continue
        normalized.append(base)

    # De-dupe preserving order
    seen: set[str] = set()
    out: list[str] = []
    for c in normalized:
        if c not in seen:
            seen.add(c)
            out.append(c)
    return out


def _identify_leader(codes: Iterable[str], card_index: dict[str, dict], deck_prefix: str | None = None) -> str | None:
    leader_candidates: list[str] = []
    for code in codes:
        c = card_index.get(code)
        if not isinstance(c, dict):
            continue
        t = str(c.get("type") or "").strip().lower()
        r = str(c.get("rarity") or "").strip().upper()
        if t == "leader" or r == "L":
            leader_candidates.append(code)

    if len(leader_candidates) == 1:
        return leader_candidates[0]

    # If multiple candidates, pick the one that is explicitly type=Leader.
    for code in leader_candidates:
        c = card_index.get(code)
        if not isinstance(c, dict):
            continue
        if str(c.get("type") or "").strip().lower() == "leader":
            return code

    # Fallback: for starter decks, -001 is almost always the leader.
    if deck_prefix:
        expected = f"{deck_prefix}-001".upper()
        if expected in set(codes):
            return expected

    return None


def _choose_x2_set(non_leader_codes: list[str], card_index: dict[str, dict], want: int) -> set[str]:
    """Heuristic: select which cards should be 2x (rest become 4x).

    This is only to produce a playable 51-card list; it is NOT guaranteed canonical.
    """

    def score(code: str) -> tuple[int, int, int, str]:
        c = card_index.get(code, {})
        rarity = str(c.get("rarity") or "").upper()
        t = str(c.get("type") or "").lower()
        cost = int(c.get("cost") or 0)

        # Lower score sorts earlier for 2x selection.
        rarity_priority = 0
        if rarity in {"SR", "SEC"}:
            rarity_priority = -100
        elif rarity in {"R"}:
            rarity_priority = -10

        type_priority = 0
        if t in {"event", "stage"}:
            type_priority = -5

        # Prefer higher-cost cards for 2x (feel more "top-end").
        return (rarity_priority, type_priority, -cost, code)

    sorted_codes = sorted(non_leader_codes, key=score)
    return set(sorted_codes[:want])


@dataclass
class DeckExtract:
    deck_id: str
    product_url: str
    cardlist_url: str | None
    extracted_codes: list[str]
    leader_code: str | None
    non_leader_codes: list[str]
    errors: list[str]


def _deck_id(n: int) -> str:
    return f"ST-{n:02d}"


def _product_url_en(n: int) -> str:
    return f"https://en.onepiece-cardgame.com/products/decks/st{n:02d}.php"


def _product_url_jp(n: int) -> str:
    return f"https://onepiece-cardgame.com/products/decks/st{n:02d}.php"


def _base_root(url: str) -> str:
    parts = urlsplit(url)
    return f"{parts.scheme}://{parts.netloc}/"


def extract_deck(n: int, card_index: dict[str, dict], timeout: float) -> DeckExtract:
    did = _deck_id(n)
    product_urls = [_product_url_en(n), _product_url_jp(n)]
    errors: list[str] = []

    product_html: str | None = None
    product_url_used: str | None = None
    cardlist_url: str | None = None

    for url in product_urls:
        try:
            product_html = _fetch_text(url, timeout=timeout)
        except Exception as e:
            errors.append(f"product_fetch_failed: {url} :: {e}")
            continue

        product_url_used = url
        cardlist_url = _find_cardlist_url(product_html, base_root=_base_root(url))
        if not cardlist_url:
            errors.append(f"cardlist_link_not_found: {url}")
            product_html = None
            product_url_used = None
            continue

        break

    # Fallback: some ST product pages may 404, but the cardlist series id pattern
    # often remains accessible. Try direct series URLs (EN first).
    if not product_url_used or not cardlist_url:
        series_id = 569000 + int(n)
        direct_cardlists = [
            f"https://en.onepiece-cardgame.com/cardlist/?series={series_id}",
            f"https://onepiece-cardgame.com/cardlist/?series={series_id}",
        ]
        for cu in direct_cardlists:
            try:
                cardlist_html = _fetch_text(cu, timeout=timeout)
            except Exception as e:
                errors.append(f"direct_cardlist_fetch_failed: {cu} :: {e}")
                continue

            codes = _extract_card_codes(cardlist_html)
            if not codes:
                errors.append(f"direct_cardlist_no_codes: {cu}")
                continue

            leader = _identify_leader(codes, card_index, deck_prefix=f"ST{n:02d}")
            if not leader:
                errors.append("leader_not_identified")
            non_leader = [c for c in codes if c != leader]

            return DeckExtract(
                deck_id=did,
                product_url=product_urls[0],
                cardlist_url=cu,
                extracted_codes=codes,
                leader_code=leader,
                non_leader_codes=non_leader,
                errors=errors,
            )

    if not product_url_used or not cardlist_url:
        return DeckExtract(
            deck_id=did,
            product_url=product_urls[0],
            cardlist_url=None,
            extracted_codes=[],
            leader_code=None,
            non_leader_codes=[],
            errors=errors or ["product_fetch_failed"],
        )

    try:
        cardlist_html = _fetch_text(cardlist_url, timeout=timeout)
    except Exception as e:
        return DeckExtract(
            deck_id=did,
            product_url=product_url_used,
            cardlist_url=cardlist_url,
            extracted_codes=[],
            leader_code=None,
            non_leader_codes=[],
            errors=errors + [f"cardlist_fetch_failed: {cardlist_url} :: {e}"],
        )

    codes = _extract_card_codes(cardlist_html)
    if not codes:
        errors.append("no_codes_extracted")

    leader = _identify_leader(codes, card_index, deck_prefix=f"ST{n:02d}")
    if not leader:
        errors.append("leader_not_identified")

    non_leader = [c for c in codes if c != leader]

    # Sanity checks
    if leader and leader not in codes:
        errors.append("leader_not_in_code_list")

    return DeckExtract(
        deck_id=did,
        product_url=product_url_used,
        cardlist_url=cardlist_url,
        extracted_codes=codes,
        leader_code=leader,
        non_leader_codes=non_leader,
        errors=errors,
    )


def _make_deck_json(
    extract: DeckExtract,
    card_index: dict[str, dict],
    guess_counts: bool,
) -> dict:
    main: list[dict] = []

    # Build leader entry
    if extract.leader_code and extract.leader_code in card_index:
        main.append(_build_entry(card_index[extract.leader_code], 1, "main"))
    elif extract.leader_code:
        main.append(
            {
                "id": extract.leader_code,
                "name": "",
                "type": "Leader",
                "color": [],
                "cost": 0,
                "power": 0,
                "life": 0,
                "counter": 0,
                "rarity": "L",
                "attribute": "",
                "traits": [],
                "effect": "",
                "set_code": extract.leader_code.split("-")[0],
                "number": extract.leader_code.split("-")[1] if "-" in extract.leader_code else "",
                "card_code": extract.leader_code,
                "count": 1,
                "zone": "main",
            }
        )

    non_leader = extract.non_leader_codes

    counts: dict[str, int] = {c: 1 for c in non_leader}
    if guess_counts:
        # Only apply the common starter pattern when the unique list looks like 1 leader + 16 non-leader.
        if extract.leader_code and len(non_leader) == 16:
            x2_set = _choose_x2_set(non_leader, card_index, want=7)
            for c in non_leader:
                counts[c] = 2 if c in x2_set else 4
        else:
            # Keep count=1 to avoid pretending it is canonical.
            pass

    for code in non_leader:
        card = card_index.get(code)
        if isinstance(card, dict):
            main.append(_build_entry(card, counts.get(code, 1), "main"))
        else:
            main.append(
                {
                    "id": code,
                    "name": "",
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
                    "set_code": code.split("-")[0],
                    "number": code.split("-")[1] if "-" in code else "",
                    "card_code": code,
                    "count": counts.get(code, 1),
                    "zone": "main",
                }
            )

    deck: dict[str, Any] = {
        "deck_id": extract.deck_id,
        "source": "official_en_cardlist_unique" + ("+heuristic_counts" if guess_counts else ""),
        "fetched_at": int(time.time()),
        "product_url": extract.product_url,
        "cardlist_url": extract.cardlist_url or "",
        "main": main,
        "don": [_don_entry()],
    }
    return deck


def _sum_counts(entries: Iterable[dict]) -> int:
    s = 0
    for e in entries:
        if not isinstance(e, dict):
            continue
        s += int(e.get("count", 0) or 0)
    return s


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="from_n", type=int, default=6)
    ap.add_argument("--to", dest="to_n", type=int, default=28)
    ap.add_argument("--timeout", type=float, default=15.0, help="Per-request timeout in seconds.")
    ap.add_argument("--sleep", type=float, default=0.2, help="Delay between deck fetches in seconds.")
    ap.add_argument(
        "--append",
        action="store_true",
        help="Merge results into existing report files instead of overwriting.",
    )
    ap.add_argument("--guess-counts", action="store_true", help="Apply heuristic 2x/4x counts (NOT canonical).")
    ap.add_argument("--write", action="store_true", help="Write deck JSON files to data/ and output/.")
    args = ap.parse_args()

    card_index = _index_cards()

    extracts: list[DeckExtract] = []
    for n in range(args.from_n, args.to_n + 1):
        did = _deck_id(n)
        print(f"[fetch] {did}", flush=True)
        extracts.append(extract_deck(n, card_index, timeout=float(args.timeout)))
        if args.sleep:
            time.sleep(float(args.sleep))

    # Merge with existing report if requested.
    report_json_path = REPORT_DIR / "starter_official_cardlist_unique.json"

    merged_by_id: dict[str, dict[str, Any]] = {}
    if args.append and report_json_path.exists():
        try:
            existing = _load_json(report_json_path)
            if isinstance(existing, dict):
                for d in existing.get("decks", []) or []:
                    if isinstance(d, dict) and d.get("deck_id"):
                        merged_by_id[str(d.get("deck_id"))] = d
        except Exception:
            merged_by_id = {}

    for e in extracts:
        merged_by_id[e.deck_id] = {
            "deck_id": e.deck_id,
            "product_url": e.product_url,
            "cardlist_url": e.cardlist_url,
            "extracted_unique_codes": e.extracted_codes,
            "unique_count": len(e.extracted_codes),
            "leader_code": e.leader_code,
            "non_leader_count": len(e.non_leader_codes),
            "errors": e.errors,
        }

    def _deck_sort_key(deck_id: str) -> tuple[int, str]:
        m = re.search(r"(\d+)$", deck_id)
        return (int(m.group(1)) if m else 9999, deck_id)

    merged_decks = [merged_by_id[k] for k in sorted(merged_by_id.keys(), key=_deck_sort_key)]

    # Save report JSON
    report = {
        "generated_at": int(time.time()),
        "from": args.from_n,
        "to": args.to_n,
        "guess_counts": bool(args.guess_counts),
        "append": bool(args.append),
        "decks": merged_decks,
    }
    _save_json(report_json_path, report)

    # Save report MD
    lines: list[str] = []
    lines.append(f"# Official starter deck unique cardlist report\n")
    lines.append(f"Range: ST-{args.from_n:02d}..ST-{args.to_n:02d}")
    lines.append(f"Generated: {time.ctime(report['generated_at'])}")
    lines.append(f"Guess counts: {args.guess_counts} (NOT canonical)\n")

    for d in merged_decks:
        did = str(d.get("deck_id") or "")
        lines.append(f"## {did}")
        lines.append(f"- Product: {d.get('product_url') or ''}")
        lines.append(f"- Cardlist: {d.get('cardlist_url') or 'N/A'}")
        lines.append(f"- Unique codes extracted: {int(d.get('unique_count') or 0)}")
        lines.append(f"- Leader: {d.get('leader_code') or 'UNKNOWN'}")
        errs = d.get("errors")
        if isinstance(errs, list) and errs:
            lines.append(f"- Errors: {', '.join(str(x) for x in errs)}")
        lines.append("")

    report_md_path = REPORT_DIR / "starter_official_cardlist_unique.md"
    report_md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    if args.write:
        OUT_DECKS.mkdir(parents=True, exist_ok=True)
        DATA_DECKS.mkdir(parents=True, exist_ok=True)

        for e in extracts:
            if not e.cardlist_url or not e.extracted_codes:
                continue
            deck_json = _make_deck_json(e, card_index, guess_counts=bool(args.guess_counts))

            # Quick totals for safety logging.
            main_total = _sum_counts(deck_json.get("main", []))
            don_total = _sum_counts(deck_json.get("don", []))
            deck_json["_totals"] = {
                "main_total_including_leader": main_total,
                "don_total": don_total,
            }

            out_path = OUT_DECKS / f"{e.deck_id}.json"
            data_path = DATA_DECKS / f"{e.deck_id}.json"
            _save_json(out_path, deck_json)
            _save_json(data_path, deck_json)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
