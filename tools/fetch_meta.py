#!/usr/bin/env python3
"""tools/fetch_meta.py — tournament decklists from Limitless One Piece TCG.

Reads recent tournament top cuts and writes engine-ready data:
  data/meta/decks.json         [{tournament, format, placement, player, leader, main:[{code,count}]}]
  data/meta/card_weights.json  {weights: {CODE: avg_copies_per_deck/4}, meta: {...}}

Card codes match our DB exactly (e.g. ST02-004), validated against
data/cards/sets/*.json; unknown codes are dropped with a warning count.

Polite scraper: stdlib only, browser UA, --sleep between requests (default
1.0s), bounded page counts. Re-run any time to refresh the meta.

Usage:
  python tools/fetch_meta.py <OharaTCG project> [--tournaments 4] [--top 8] [--sleep 1.0]
  python tools/fetch_meta.py <OharaTCG project> --since 2025-09-23

Limitless publishes standings and decklists. It does not publish the cards
played each round. --since walks recent event ids and keeps lists dated on
or after that day. Who-beat-whom by round is on TopDeck.gg and needs a free
API key. The cards played inside a match are not published.
"""
import json, re, sys, time, glob, os
import urllib.request
import urllib.error

BASE = "https://onepiece.limitlesstcg.com"
UA = {"User-Agent": "OharaTCG-meta/1.0 (research; contact via repo)"}

def get(url, sleep):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        html = r.read().decode("utf-8", "replace")
    time.sleep(sleep)
    return html

def tourney_ids(html):
    seen, out = set(), []
    for m in re.finditer(r'/tournaments/(\d+)"', html):
        i = int(m.group(1))
        if i not in seen:
            seen.add(i)
            out.append(i)
    return out

def parse_tourney(html, tid):
    name = re.search(r'infobox-heading">\s*([^<]+)', html)
    info = re.search(r'infobox-line">\s*([^<]+?)\s*•\s*([\d,]+)\s*Players\s*•\s*(.*?)</div>', html, re.S)
    fmt = "?"
    if info:
        fmt = re.sub(r"<[^>]+>", "", info.group(3)).strip()
    rows = []
    for m in re.finditer(
            r'<td>(\d+)</td>\s*<td>\s*<a href="/players/\d+">([^<]+)</a>.*?'
            r'<a class="deck-link" href="/decks/(\d+)">.*?</a>.*?</td>\s*'
            r'<td>\s*(?:<a href="(/decks/list/\d+)">)?',
            html, re.S):
        rows.append({"placement": int(m.group(1)), "player": m.group(2).strip(),
                     "archetype": int(m.group(3)), "list": m.group(4)})
    return {"id": tid,
            "name": name.group(1).strip() if name else "?",
            "date": info.group(1).strip() if info else "?",
            "players": info.group(2) if info else "?",
            "format": fmt,
            "rows": rows}

def parse_decklist(html):
    """Returns (leader_code, [(code, count), ...]) in listed order."""
    cols = re.findall(
        r'decklist-column-heading">\s*([^<(]+).*?(?=(?:decklist-column-heading">|$))(.*)',
        html, re.S)
    # Simpler: walk headings + cards in document order.
    toks = re.findall(
        r'decklist-column-heading">\s*([^<(]+)|<div class="decklist-card" data-count="(\d+)" data-id="([A-Z0-9-]+)"',
        html)
    leader, main, cur = "", [], ""
    counts = {}
    order = []
    for heading, count, code in toks:
        if heading:
            cur = heading.strip()
        elif code:
            if cur == "Leader":
                leader = code
            else:
                # Merge parallel prints of the same number: the 4-copy limit
                # counts all prints together, and so must we.
                if code not in counts:
                    counts[code] = 0
                    order.append(code)
                counts[code] += int(count)
    for code in order:
        n = counts[code]
        if n > 4:
            # Parallel prints are listed as separate rows; the 4-copy rule
            # counts all prints together, so cap (source data quirk).
            print("  NOTE %s listed %dx, capped at 4" % (code, n))
            n = 4
        main.append([code, n])
    return leader, main

MONTHS = {
    "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6,
    "july": 7, "august": 8, "september": 9, "october": 10, "november": 11,
    "december": 12,
}

def parse_date(text):
    m = re.search(r"(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]+)\s+(\d{4})", text or "")
    if not m:
        return None
    mon = MONTHS.get(m.group(2).lower())
    if not mon:
        return None
    return (int(m.group(3)), mon, int(m.group(1)))

def get_or_none(url, sleep):
    try:
        return get(url, sleep)
    except urllib.error.HTTPError:
        time.sleep(sleep)
        return None
    except Exception as exc:
        print("  skip %s (%s)" % (url, type(exc).__name__))
        time.sleep(sleep)
        return None

def take_lists(t, top, sleep, valid):
    """Top published lists from one event. Returns (decks, dropped_copies)."""
    decks, dropped = [], 0
    taken = 0
    for row in t["rows"][:top]:
        if not row["list"]:
            continue
        html = get_or_none(BASE + row["list"], sleep)
        if html is None:
            continue
        leader, main = parse_decklist(html)
        clean = []
        for code, count in main:
            if code in valid:
                clean.append({"code": code, "count": count})
            else:
                dropped += count
        total = sum(c["count"] for c in clean)
        if total != 50 or leader not in valid:
            print("  DROP %s total=%d leader=%s" % (row["list"], total, leader))
            continue
        decks.append({"tournament": t["name"], "date": t["date"], "format": t["format"],
                      "placement": row["placement"], "player": row["player"],
                      "leader": leader, "main": clean, "src": BASE + row["list"]})
        taken += 1
        print("  #%d %-22s %-12s %d cards" % (row["placement"], row["player"][:22], leader, total))
    return decks, dropped

def valid_codes(project):
    codes = set()
    for f in glob.glob(os.path.join(project, "data", "cards", "sets", "*.json")):
        try:
            data = json.load(open(f, encoding="utf-8"))
        except Exception:
            continue
        cards = data if isinstance(data, list) else data.get("main", [])
        for c in cards:
            if isinstance(c, dict) and c.get("card_code"):
                codes.add(c["card_code"])
    return codes

def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    project = sys.argv[1]
    n_t = int(sys.argv[sys.argv.index("--tournaments") + 1]) if "--tournaments" in sys.argv else 4
    top = int(sys.argv[sys.argv.index("--top") + 1]) if "--top" in sys.argv else 8
    sleep = float(sys.argv[sys.argv.index("--sleep") + 1]) if "--sleep" in sys.argv else 1.0
    since = None
    if "--since" in sys.argv:
        y, m, d = sys.argv[sys.argv.index("--since") + 1].split("-")
        since = (int(y), int(m), int(d))

    valid = valid_codes(project)
    print("known codes: %d" % len(valid))
    index = get(BASE + "/tournaments", sleep)
    listed = tourney_ids(index)
    if since is None:
        tids = listed[:n_t]
    else:
        hi = max(listed) if listed else 0
        tids = list(range(hi, max(1, hi - 220), -1))
        print("since %04d-%02d-%02d, scanning ids %d..%d" % (since[0], since[1], since[2], tids[-1], tids[0]))
    decks, dropped, kept_events = [], 0, 0
    for tid in tids:
        html = get_or_none("%s/tournaments/%d" % (BASE, tid), sleep)
        if html is None or "infobox-heading" not in html:
            continue
        t = parse_tourney(html, tid)
        when = parse_date(t["date"])
        if since is not None and when is not None and when < since:
            continue
        players = 0
        try:
            players = int(str(t["players"]).replace(",", "") or "0")
        except ValueError:
            players = 0
        if since is not None and 0 < players < 64:
            continue
        print("%s | %s | %s | %d rows" % (t["name"], t["date"].split("\n")[0], t["format"], len(t["rows"])))
        got, drop = take_lists(t, top, sleep, valid)
        dropped += drop
        if got:
            kept_events += 1
            decks.extend(got)
    # 1st-place lists count fully. 8th counts 0.3. Scale stays copies/4.
    copies, mass = {}, 0.0
    for d in decks:
        w = {1: 1.0, 2: 0.85, 3: 0.75, 4: 0.65, 5: 0.5, 6: 0.4, 7: 0.35, 8: 0.3}.get(int(d["placement"]), 0.3)
        mass += w
        for c in d["main"]:
            copies[c["code"]] = copies.get(c["code"], 0.0) + c["count"] * w
    mass = max(mass, 1.0)
    weights = {k: round(v / mass / 4.0, 4) for k, v in copies.items()}
    meta_dir = os.path.join(project, "data", "meta")
    os.makedirs(meta_dir, exist_ok=True)
    json.dump(decks, open(os.path.join(meta_dir, "decks.json"), "w"), indent=1)
    json.dump({"weights": weights,
               "meta": {"decks": len(decks), "tournaments": kept_events,
                        "since": "%04d-%02d-%02d" % since if since else "",
                        "dropped": dropped,
                        "source": "https://onepiece.limitlesstcg.com/tournaments"}},
              open(os.path.join(meta_dir, "card_weights.json"), "w"), indent=1)
    print("wrote %d decks from %d events, %d weights, dropped %d unknown copies" % (
        len(decks), kept_events, len(weights), dropped))
    return 0

if __name__ == "__main__":
    sys.exit(main())
