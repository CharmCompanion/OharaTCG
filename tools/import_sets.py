#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
OharaTCG card database converter.

Reads the punk-records JSON dump (static per-language snapshots of the official
onepiece-cardgame.com card list) and writes per-set JSON files into
res://data/cards/ using the game's card schema.

Union rules:
  - primary region source : english-asia (freshest English snapshot)
  - fill gaps with        : english
  - Japanese-only cards   : japanese (OCG exclusives, kept as Japanese text)

Every card is keyed by its unique serial id ("OP01-001" base, "OP01-001_p1"
parallel/prize variants). "card_code" is always the BASE id (variant-agnostic)
used for deck files, the 4-copy rule and ban lists.

DON!! cards are NOT in the official card list, so a synthetic DON registry is
built in data/cards/alts/Don.json. Its art is scanned from assets/cards/Don.

Usage:
  python import_sets.py [punk-records-root] [ohara-project-root]
  (defaults to the sketchy temp clone and this project's parent)
"""

import json
import os
import re
import sys

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DEFAULT_RECORDS_ROOT = r"C:\Users\RY0M\AppData\Local\Temp\opencode\punk-records"
DEFAULT_PROJECT_ROOT = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
)

SET_TITLE_PATTERN = re.compile(r"^(STARTER DECK|ULTRA DECK|STARTER DECK EX|BOOSTER PACK|EXTRA BOOSTER|PREMIUM BOOSTER)")

HARDCODED_SET_TITLES = {
    "ST01": "Starter Deck - Straw Hat Crew [ST-01]",
    "ST02": "Starter Deck - Worst Generation [ST-02]",
    "ST03": "Starter Deck - The Seven Warlords of the Sea [ST-03]",
    "ST04": "Starter Deck - Animal Kingdom Pirates [ST-04]",
    "ST05": "Starter Deck - ONE PIECE FILM edition [ST-05]",
    "ST06": "Starter Deck - Absolute Justice [ST-06]",
    "ST07": "Starter Deck - Big Mom Pirates [ST-07]",
    "ST08": "Starter Deck - Monkey D. Luffy [ST-08]",
    "ST09": "Starter Deck - Yamato [ST-09]",
    "ST10": "Ultra Deck - The Three Captains [ST-10]",
    "ST11": "Starter Deck - Uta [ST-11]",
    "ST12": "Starter Deck - Zoro and Sanji [ST-12]",
    "ST13": "Ultra Deck - The Three Brothers [ST-13]",
    "ST14": "Starter Deck - 3D2Y [ST-14]",
    "ST15": "Starter Deck - Red Edward.Newgate [ST-15]",
    "ST16": "Starter Deck - Green Uta [ST-16]",
    "ST17": "Starter Deck - Blue Donquixote Doflamingo [ST-17]",
    "ST18": "Starter Deck - Purple Monkey.D.Luffy [ST-18]",
    "ST19": "Starter Deck - Black Smoker [ST-19]",
    "ST20": "Starter Deck - Yellow Charlotte Katakuri [ST-20]",
    "ST21": "Starter Deck EX - GEAR5 [ST-21]",
    "ST22": "Starter Deck - Ace & Newgate [ST-22]",
    "ST23": "Starter Deck - RED Shanks [ST-23]",
    "ST24": "Starter Deck - GREEN Jewelry Bonney [ST-24]",
    "ST25": "Starter Deck - BLUE Buggy [ST-25]",
    "ST26": "Starter Deck - PURPLE/BLACK Monkey.D.Luffy [ST-26]",
    "ST27": "Starter Deck - BLACK Marshall.D.Teach [ST-27]",
    "ST28": "Starter Deck - GREEN/YELLOW Yamato [ST-28]",
    "ST29": "Starter Deck - Egghead [ST-29]",
    "ST30": "Starter Deck EX - Luffy & Ace [ST-30]",
    "ST31": "Starter Deck - RED Monkey.D.Luffy [ST-31]",
    "ST32": "Starter Deck - GREEN Roronoa Zoro [ST-32]",
    "ST33": "Starter Deck - BLUE Kuzan [ST-33]",
    "ST34": "Starter Deck - PURPLE Charlotte Katakuri [ST-34]",
    "ST35": "Starter Deck - RED/BLACK Sabo [ST-35]",
    "ST36": "Starter Deck - YELLOW Eustass'Captain'Kid [ST-36]",
    "OP01": "Booster Pack - Romance Dawn [OP-01]",
    "OP02": "Booster Pack - Paramount War [OP-02]",
    "OP03": "Booster Pack - Pillars of Strength [OP-03]",
    "OP04": "Booster Pack - Kingdoms of Intrigue [OP-04]",
    "OP05": "Booster Pack - Awakening of the New Era [OP-05]",
    "OP06": "Booster Pack - Wings of the Captain [OP-06]",
    "OP07": "Booster Pack - 500 Years in the Future [OP-07]",
    "OP08": "Booster Pack - Two Legends [OP-08]",
    "OP09": "Booster Pack - Emperors in the New World [OP-09]",
    "OP10": "Booster Pack - Royal Blood [OP-10]",
    "OP11": "Booster Pack - A Fist of Divine Speed [OP-11]",
    "OP12": "Booster Pack - Legacy of the Master [OP-12]",
    "OP13": "Booster Pack - Carrying on His Will [OP-13]",
    "OP14": "Booster Pack - The Azure Sea's Seven [OP-14]",
    "OP15": "Booster Pack - The New Era of Power [OP-15]",
    "OP16": "Booster Pack - The Time of Battle [OP-16]",
    "OP17": "Booster Pack - The World's Strongest Warriors [OP-17]",
    "EB01": "Extra Booster - Memorial Collection [EB-01]",
    "EB02": "Extra Booster - Anime 25th Collection [EB-02]",
    "EB03": "Extra Booster - One Piece Heroines Edition [EB-03]",
    "EB04": "Extra Booster - Side of the Seven [EB-04]",
    "PRB01": "Premium Booster - One Piece Card The Best [PRB-01]",
    "PRB02": "Premium Booster - One Piece Card The Best vol.2 [PRB-02]",
    "P": "Promotional Cards [P]",
}

KNOWN_ARCHETYPES = ("Straw Hat", "Navy", "Animal", "Supernovas", "Donquixote")


def base_id(variant_id: str) -> str:
    return variant_id.split("_")[0]


def set_code_of(variant_id: str) -> str:
    return base_id(variant_id).split("-")[0]


def number_of(variant_id: str) -> str:
    sub = base_id(variant_id).split("-", 1)
    return sub[1] if len(sub) > 1 else ""


def is_variant(variant_id: str) -> bool:
    return "_" in variant_id


def normalize_card(raw: dict, region: str, set_titles: dict) -> dict:
    vid = str(raw.get("id", ""))
    base = base_id(vid)
    sc = set_code_of(vid)

    effect = raw.get("effect") or ""
    trigger = raw.get("trigger") or ""
    # The official JP text uses the full-width minus "\u2212"; keep both as-is
    # (Godot outputs UTF-8, so the symbol survives; no special handling needed).

    colors = raw.get("colors") or []
    attributes = raw.get("attributes") or []
    traits = raw.get("types") or []

    archetype = ""
    for t in traits:
        t_l = t.lower()
        for known in KNOWN_ARCHETYPES:
            if known.lower() in t_l:
                archetype = known
                break
        if archetype:
            break

    # Foil grade for the holographic card treatment:
    #   "prize"    - promotional / tournament / winner prints
    #   "parallel" - alternative-art (_pN) prints
    #   ""         - regular print
    if sc == "P":
        foil_grade = "prize"
    elif is_variant(vid):
        foil_grade = "parallel"
    else:
        foil_grade = ""

    return {
        "name": str(raw.get("name", "")),
        "type": str(raw.get("category", "")),
        "color": "/".join(colors),
        "cost": int(raw.get("cost") or 0),
        "power": int(raw.get("power") or 0),
        "life": 0,
        "counter": int(raw.get("counter") or 0),
        "rarity": str(raw.get("rarity", "")),
        "attribute": attributes[0] if attributes else "",
        "traits": traits,
        "tags": attributes,
        "archetype": archetype,
        "effect": effect,
        "trigger": trigger,
        "set_code": sc,
        "set_name": set_titles.get(sc, "Set %s" % sc),
        "number": number_of(vid),
        "card_code": base,
        "variant_id": vid,
        "art_type": "AA" if is_variant(vid) else "",
        "foil_grade": foil_grade,
        "variant_index": 0,
        "block_number": int(raw.get("block_number") or 0),
        "region": region,
        "count": 1,
        "img_url": str(raw.get("img_full_url", "")),
    }


def load_language_data(records_root: str, lang: str) -> list:
    """Loads every pack array for a language from data/<packid>.json."""
    data_dir = os.path.join(records_root, lang, "data")
    cards = []
    if not os.path.isdir(data_dir):
        print("  [warn] no data dir for", lang)
        return cards
    for fname in sorted(os.listdir(data_dir)):
        if fname.endswith(".json"):
            try:
                arr = json.load(open(os.path.join(data_dir, fname), encoding="utf-8"))
            except Exception as exc:  # noqa: BLE001
                print("  [warn] could not parse %s: %s" % (fname, exc))
                continue
            if isinstance(arr, list):
                cards.extend(arr)
    return cards


def build_union(records_root: str, set_titles: dict):
    """Returns dict variant_id -> normalized card (region priority order)."""
    # region priority: english-asia > english > japanese
    sources = [
        ("english-asia", "EN"),
        ("english", "EN"),
        ("japanese", "JP"),
    ]
    union: dict = {}
    for lang, region_tag in sources:
        print("Loading %s (%s)..." % (lang, region_tag))
        for raw in load_language_data(records_root, lang):
            vid = str(raw.get("id", ""))
            if not vid:
                continue
            if vid in union:
                continue  # higher-priority region already won
            union[vid] = normalize_card(raw, region_tag, set_titles)
    return union


def assign_variant_indexes(union: dict) -> None:
    """Number variants of the same base card: base=0, _p1.._pN in order."""
    seen: dict = {}
    def sort_key(vid: str):
        base = base_id(vid)
        if not is_variant(vid):
            return (base, -1)
        m = re.search(r"_p(\d+)?$", vid)
        n = int(m.group(1)) if m and m.group(1) else 0
        return (base, n)

    for vid in sorted(union, key=sort_key):
        base = base_id(vid)
        idx = seen.get(base, 0)
        union[vid]["variant_index"] = idx
        seen[base] = idx + 1


def build_don_registry(project_root: str, set_titles: dict) -> dict:
    """Creates the DON!! card + all art variants.

    All DON!! artworks anywhere under assets/cards (folder "Don", the promo
    folder "P", or any file that looks like a DON art) are registered so every
    variant is reachable from the deck editor / card objects.
    """
    don_assets = os.path.join(project_root, "assets", "cards")
    art = []  # (display_name, full_path)
    if os.path.isdir(don_assets):
        for root, _dirs, files in os.walk(don_assets):
            for fname in files:
                low = fname.lower()
                if not low.endswith((".png", ".jpg", ".jpeg", ".webp")):
                    continue
                if "back" in low:
                    continue  # card backs are not DON arts
                rel = os.path.relpath(os.path.join(root, fname), project_root).replace("\\", "/")
                if not (rel.startswith("assets/cards/Don/") or rel == "assets/cards/P/Don.png"):
                    continue  # only genuine DON art locations
                art.append((os.path.splitext(fname)[0], os.path.join(root, fname)))

    # Base Don/Don.png first, then the rest by filename keeping folder origin.
    art.sort(key=lambda t: (
        0 if t[1].replace("\\", "/").endswith("cards/Don/Don.png") else 1,
        t[1].lower()
    ))

    cards = []
    index = 0
    used_vids = set()
    for stem, full_path in art:
        rel = os.path.relpath(full_path, project_root).replace("\\", "/")
        is_base = stem.lower() == "don" and "cards/Don" in rel
        vid = "DON-001" if is_base else (
            "DON-001_" + re.sub(r"[\s()]+", "", stem.lower().replace("/", "_").replace("\\", "_"))
        )
        if vid in used_vids:
            vid += "_%d" % index
        used_vids.add(vid)
        card = {
            "name": "Don!!",
            "type": "DON!!",
            "color": "",
            "cost": 0,
            "power": 0,
            "life": 0,
            "counter": 0,
            "rarity": "Promo",
            "attribute": "",
            "traits": [],
            "tags": [],
            "archetype": "",
            "effect": "",
            "trigger": "",
            "set_code": "DON",
            "set_name": set_titles.get("DON", "DON!! Card"),
            "number": "",
            "card_code": "DON-001",
            "variant_id": vid,
            "art_type": "" if is_base else "AA",
            "variant_index": index,
            "block_number": 0,
            "region": "EN",
            "count": 1,
            "image_override": "res://%s" % rel,
        }
        cards.append(card)
        index += 1

    # Fallback base if the Don folder is empty
    if not cards:
        cards.append({
            "name": "Don!!", "type": "DON!!", "color": "", "cost": 0,
            "power": 0, "life": 0, "counter": 0, "rarity": "Promo",
            "attribute": "", "traits": [], "tags": [], "archetype": "",
            "effect": "", "trigger": "", "set_code": "DON",
            "set_name": "DON!! Card", "number": "",
            "card_code": "DON-001", "variant_id": "DON-001",
            "art_type": "", "variant_index": 0, "block_number": 0,
            "region": "EN", "count": 1,
            "image_override": "res://assets/cards/Don/Don.png",
        })

    return {"main": cards}


def write_json(path: str, payload) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent="\t")
    print("  wrote %s" % path)


def main() -> None:
    records_root = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_RECORDS_ROOT
    project_root = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_PROJECT_ROOT

    print("Records root : %s" % records_root)
    print("Project root : %s" % project_root)

    set_titles = dict(HARDCODED_SET_TITLES)
    union = build_union(records_root, set_titles)
    assign_variant_indexes(union)

    print("\nUnion size: %d unique cards (incl. variants)" % len(union))

    # Group by set_code
    by_set: dict = {}
    for card in union.values():
        by_set.setdefault(card["set_code"], []).append(card)

    sets_dir = os.path.join(project_root, "data", "cards", "sets")
    manifest = {}
    for sc in sorted(by_set):
        cards = sorted(by_set[sc], key=lambda c: c["variant_id"])
        write_json(os.path.join(sets_dir, sc + ".json"), {"main": cards})
        bases = set(c.get("card_code") for c in cards)
        manifest[sc] = {
            "title": set_titles.get(sc, "Set %s" % sc),
            "base_cards": len(bases),
            "total_cards_incl_variants": len(cards),
            "variants": sum(1 for c in cards if c["art_type"] == "AA"),
        }

    # DON registry
    don = build_don_registry(project_root, set_titles)
    write_json(os.path.join(project_root, "data", "cards", "alts", "Don.json"), don)
    manifest["DON"] = {
        "title": "DON!! Card",
        "base_cards": 1,
        "total_cards_incl_variants": len(don["main"]),
        "variants": sum(1 for c in don["main"] if c["art_type"] == "AA"),
    }

    write_json(os.path.join(project_root, "data", "cards", "manifest.json"), {
        "generated_from": "punk-records",
        "note": "Union of english-asia + english + japanese-only cards."
                 " Regenerated by tools/import_sets.py.",
        "sets": manifest,
    })

    print("\nSummary:")
    for sc in sorted(manifest):
        m = manifest[sc]
        print("  %-6s base=%-4d total=%-4d variants=%d  %s"
              % (sc, m["base_cards"], m["total_cards_incl_variants"],
                 m["variants"], m["title"]))
    print("\nDone.")


if __name__ == "__main__":
    main()