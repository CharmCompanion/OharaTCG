#!/usr/bin/env python3
"""tools/build_blocks.py — max-block-per-card from our variant data.

A card is Standard-legal if ANY print carries a legal block icon, so the
validator needs per-card (not per-set) blocks. Reads data/cards/sets/*.json
(all variants with set_code), maps each variant set through data/blocks.json
"sets", and writes the max per card_code into data/blocks.json "cards".

Usage: python tools/build_blocks.py <OharaTCG project>
"""
import json, glob, sys, os

def main():
    project = sys.argv[1] if len(sys.argv) > 1 else "."
    bpath = os.path.join(project, "data", "blocks.json")
    blocks = json.load(open(bpath, encoding="utf-8"))
    sets = blocks["sets"]
    best = {}
    for f in glob.glob(os.path.join(project, "data", "cards", "sets", "*.json")):
        try:
            data = json.load(open(f, encoding="utf-8"))
        except Exception:
            continue
        cards = data if isinstance(data, list) else data.get("main", [])
        for c in cards:
            if not isinstance(c, dict):
                continue
            code = c.get("card_code", "")
            sc = str(c.get("set_code", ""))
            num = c.get("block_number", 0)
            if sc and isinstance(num, int) and num > int(sets.get(sc, 0)):
                sets[sc] = num
            if not code or sc not in sets:
                continue
            b = int(sets[sc])
            if b > best.get(code, 0):
                best[code] = b
    blocks["cards"] = best
    json.dump(blocks, open(bpath, "w"), indent=1)
    print("cards mapped: %d" % len(best))
    return 0

if __name__ == "__main__":
    sys.exit(main())
