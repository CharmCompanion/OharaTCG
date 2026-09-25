#!/usr/bin/env python3
"""tools/refresh_content.py — quiet refresh of cards, blocks, banlists, reports.

Run by the game on launch (at most once a week). Safe to run by hand:

  python tools/refresh_content.py <OharaTCG project>

Official card list and restriction notices come from en.onepiece-cardgame.com.
Existing card files are kept; only variant ids the list has and we do not
are added, so a new set or promo shows up without rewriting old text.

onepiecetopdecks.com articles are matchup writeups (mulligan, seat, key
cards), not a recording of each turn. Those lines are saved for the AI.
The cards played inside a game are not on that site.
"""
import html as htmlmod
import json, os, re, subprocess, sys, time
import urllib.request

BASE = "https://en.onepiece-cardgame.com"
LIST = BASE + "/cardlist/"
ARTICLES = "https://onepiecetopdecks.com/articles-deck-review-tournament-reports/"
UA = {"User-Agent": "OharaTCG-refresh/1.0 (local game update)"}

def get(url, sleep):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=40) as r:
        text = r.read().decode("utf-8", "replace")
    time.sleep(sleep)
    return text

def plain(fragment):
    text = re.sub(r"<br\s*/?>", "\n", fragment, flags=re.I)
    text = re.sub(r"<[^>]+>", " ", text)
    text = htmlmod.unescape(text)
    return re.sub(r"[ \t]+", " ", text).strip()

def after_h3(modal, label):
    m = re.search(
        r"<h3>(?:(?!</h3>).)*%s(?:(?!</h3>).)*</h3>([\s\S]*?)(?=<h3>|</dd>)" % re.escape(label),
        modal, re.I)
    return plain(m.group(1)) if m else ""

def series_options(page):
    out = []
    for value, label in re.findall(r'<option[^>]*value="(\d+)"[^>]*>([\s\S]*?)</option>', page):
        name = plain(label)
        codes = re.findall(r"\[([A-Z]{1,4}\d{0,2}(?:-[A-Z]{0,4}\d{2})?)\]", name)
        out.append({"id": value, "name": name, "codes": codes})
    return out

def parse_modal(modal):
    mid = re.search(r'\bid="([A-Z0-9]+-\d+(?:_p\d+)?)"', modal)
    if not mid:
        return None
    vid = mid.group(1)
    base = vid.split("_")[0]
    set_code = re.match(r"([A-Z]+\d*)", base)
    set_code = set_code.group(1) if set_code else ""
    info = re.search(r'class="infoCol"[^>]*>([\s\S]*?)</div>', modal)
    bits = [plain(x) for x in re.findall(r"<span>([\s\S]*?)</span>", info.group(1) if info else "")]
    rarity = bits[1] if len(bits) > 1 else ""
    kind = bits[2].title() if len(bits) > 2 else "Character"
    if kind == "Character":
        kind = "Character"
    name_m = re.search(r'class="cardName"[^>]*>([\s\S]*?)</div>', modal)
    name = plain(name_m.group(1)) if name_m else vid
    def num(label, default=0):
        raw = after_h3(modal, label)
        m = re.search(r"-?\d+", raw.replace(",", ""))
        return int(m.group(0)) if m else default
    counter_raw = after_h3(modal, "Counter")
    counter = 0 if counter_raw in ("", "-") else num("Counter", 0)
    block_raw = after_h3(modal, "Block")
    block_m = re.search(r"\d+", block_raw)
    traits = [t.strip() for t in after_h3(modal, "Type").split("/") if t.strip()]
    effect = after_h3(modal, "Effect")
    trigger = after_h3(modal, "Trigger")
    p = 1 if "_p" in vid else 0
    if p:
        p = int(vid.rsplit("_p", 1)[-1] or "1")
    return {
        "name": name,
        "type": kind if kind in ("Leader", "Character", "Event", "Stage") else kind.title(),
        "color": after_h3(modal, "Color"),
        "cost": num("Cost"),
        "power": num("Power"),
        "life": num("Life"),
        "counter": counter,
        "rarity": rarity,
        "attribute": after_h3(modal, "Attribute"),
        "traits": traits,
        "tags": [after_h3(modal, "Attribute")] if after_h3(modal, "Attribute") else [],
        "archetype": traits[0] if traits else "",
        "effect": effect,
        "trigger": trigger,
        "set_code": set_code,
        "set_name": "",
        "number": base.split("-")[-1],
        "card_code": base,
        "variant_id": vid,
        "art_type": "parallel" if "_p" in vid else "",
        "foil_grade": "",
        "variant_index": p,
        "block_number": int(block_m.group(0)) if block_m else 0,
        "region": "EN",
        "count": 1,
        "img_url": "%s/images/cardlist/card/%s.png" % (BASE, vid),
    }

def parse_list(page):
    cards = []
    parts = re.split(r'class="modalCol"', page)
    for part in parts[1:]:
        card = parse_modal(part[:12000])
        if card:
            cards.append(card)
    return cards

def have_ids(project):
    ids = set()
    folder = os.path.join(project, "data", "cards", "sets")
    if not os.path.isdir(folder):
        return ids
    for name in os.listdir(folder):
        if not name.endswith(".json"):
            continue
        try:
            data = json.load(open(os.path.join(folder, name), encoding="utf-8"))
        except Exception:
            continue
        rows = data if isinstance(data, list) else data.get("main", [])
        for c in rows:
            if isinstance(c, dict) and c.get("variant_id"):
                ids.add(c["variant_id"])
    return ids

def merge_set(project, set_code, cards, set_name):
    folder = os.path.join(project, "data", "cards", "sets")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, set_code + ".json")
    current = []
    if os.path.exists(path):
        try:
            data = json.load(open(path, encoding="utf-8"))
            current = data if isinstance(data, list) else data.get("main", [])
        except Exception:
            current = []
    known = {c.get("variant_id") for c in current if isinstance(c, dict)}
    added = 0
    for c in cards:
        if c["variant_id"] in known:
            continue
        c["set_name"] = set_name
        current.append(c)
        known.add(c["variant_id"])
        added += 1
    if added:
        json.dump({"main": current}, open(path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    return added

def sync_cards(project, sleep):
    page = get(LIST, sleep)
    options = series_options(page)
    owned = have_ids(project)
    added = 0
    # Newest boosters and promos can gain cards inside an existing file.
    # Everything else is fetched only when we have never seen the series id.
    stamp_path = os.path.join(project, "data", "meta", "series_seen.json")
    seen = {}
    first = not os.path.exists(stamp_path)
    if not first:
        try:
            seen = json.load(open(stamp_path, encoding="utf-8"))
        except Exception:
            seen = {}
    if first:
        for opt in options:
            seen[opt["id"]] = opt["name"]
    def set_missing(opt):
        for raw in opt["codes"]:
            sc = raw.replace("-", "")
            if not re.match(r"^(OP|ST|EB|PRB)\d+$", sc):
                continue
            if not os.path.exists(os.path.join(project, "data", "cards", "sets", sc + ".json")):
                return True
        return False
    boosters = 0
    todo = []
    for opt in options:
        if opt["id"] not in seen or set_missing(opt):
            todo.append(opt)
            seen[opt["id"]] = opt["name"]
            continue
        name = opt["name"].upper()
        if "PROMOTION" in name or "OTHER PRODUCT" in name:
            todo.append(opt)
            continue
        if "BOOSTER PACK" in name and boosters < 2:
            todo.append(opt)
            boosters += 1
    print("card series to check: %d" % len(todo), flush=True)
    for opt in todo:
        try:
            body = get(LIST + "?series=" + opt["id"], sleep)
        except Exception as exc:
            print("  series %s failed (%s)" % (opt["id"], type(exc).__name__), flush=True)
            continue
        cards = parse_list(body)
        by_set = {}
        for c in cards:
            if not c["set_code"] or c["variant_id"] in owned:
                continue
            by_set.setdefault(c["set_code"], []).append(c)
        got = 0
        for sc, rows in by_set.items():
            got += merge_set(project, sc, rows, opt["name"])
            for c in rows:
                owned.add(c["variant_id"])
        seen[opt["id"]] = opt["name"]
        added += got
        print("  %s +%d" % (opt["name"][:60], got), flush=True)
    os.makedirs(os.path.dirname(stamp_path), exist_ok=True)
    json.dump(seen, open(stamp_path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print("cards added: %d" % added, flush=True)
    return added

def _keep_words(text):
    skip = {
        "this", "that", "with", "your", "from", "when", "they", "them",
        "have", "will", "against", "while", "getting", "another", "usually",
        "these", "look", "obviously", "depends", "matchup",
    }
    keep = []
    for word in re.findall(r"\b([A-Z][a-zA-Z']{3,})\b", text):
        bit = word[:-1] if word.endswith("s") and len(word) > 5 else word
        if bit.lower() in skip or bit in keep:
            continue
        keep.append(bit)
    return keep

def sync_articles(project, sleep, limit=12, reset=False):
    path = os.path.join(project, "data", "ai", "matchup_notes.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    store = {"notes": [], "seen": []}
    if os.path.exists(path) and not reset:
        try:
            store = json.load(open(path, encoding="utf-8"))
        except Exception:
            store = {"notes": [], "seen": []}
    seen = set() if reset else set(store.get("seen", []))
    if reset:
        store = {"notes": [], "seen": []}
    try:
        index = get(ARTICLES, sleep)
    except Exception as exc:
        print("articles index failed (%s)" % type(exc).__name__, flush=True)
        return 0
    links = []
    for href in re.findall(r'href="(https://onepiecetopdecks.com/[^"#?]+/)"', index):
        if href.rstrip("/") == ARTICLES.rstrip("/"):
            continue
        if any(b in href for b in ("/feed", "/comments/", "contact-us", "/deck-list/", "/news-", "/cards/", "/category/", "/tag/")):
            continue
        if href.count("-") < 4:
            continue
        if href not in links:
            links.append(href)
    added = 0
    fetched = 0
    for href in links:
        if href in seen or fetched >= limit:
            continue
        fetched += 1
        try:
            body = get(href, sleep)
        except Exception:
            continue
        title = plain(re.search(r"<title>([\s\S]*?)</title>", body).group(1)) if re.search(r"<title>", body) else ""
        self_name = ""
        m = re.search(r"\bwith\s+([A-Za-z][A-Za-z .']{2,30})", title)
        if m:
            self_name = m.group(1).strip()
        marked = re.sub(r"<h[23][^>]*>", "\n@@", body, flags=re.I)
        chunks = plain(marked).split("@@")
        if len(chunks) == 1:
            chunks = ["", chunks[0]]
        heading = ""
        for chunk in chunks:
            lines = [ln.strip() for ln in chunk.split("\n") if ln.strip()]
            if not lines:
                continue
            if chunk is not chunks[0] and len(lines) > 1:
                heading = lines[0][:80]
                section = " ".join(lines[1:])
            else:
                heading = ""
                section = " ".join(lines)
            km = re.search(r"mullig\w*\s*[:,]|for mulligans?\b", section, re.I)
            if not km:
                continue
            window = section[km.start():km.start() + 520]
            seat = ""
            if re.search(r"\b(go|choose|going)\s+first\b", window, re.I):
                seat = "first"
            elif re.search(r"\b(go|choose|going)\s+second\b", window, re.I):
                seat = "second"
            pieces = re.split(r"\bagainst\s+", window, flags=re.I)
            if len(pieces) < 2:
                continue
            for piece in pieces[1:]:
                om = re.match(r"([A-Z][A-Za-z.'-]{2,24})", piece.strip())
                if not om:
                    continue
                opp = om.group(1).strip()
                keep = [w for w in _keep_words(piece[:180]) if w.lower() != opp.lower()]
                if len(opp) < 3 or not keep:
                    continue
                store["notes"].append({
                    "self": self_name, "opp": opp, "seat": seat,
                    "keep": keep[:8], "source": href,
                })
                added += 1
        seen.add(href)
        print("  article %s" % href.rsplit("/", 2)[-2][:70], flush=True)
    store["seen"] = sorted(seen)
    json.dump(store, open(path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print("matchup notes: %d" % len(store["notes"]), flush=True)
    return added

def run(cmd):
    print(" ".join(cmd), flush=True)
    subprocess.check_call(cmd)

def main():
    project = sys.argv[1] if len(sys.argv) > 1 else "."
    sleep = 0.4
    if "--check" in sys.argv:
        body = get(LIST + "?series=569001", 0)
        cards = parse_list(body)
        print("parsed", len(cards), flush=True)
        if cards:
            print(json.dumps(cards[0], ensure_ascii=False, indent=1)[:900], flush=True)
        return 0 if cards and cards[0].get("name") else 1
    if "--notes-only" in sys.argv:
        sync_articles(project, sleep, reset=True)
        return 0
    sync_cards(project, sleep)
    here = os.path.dirname(os.path.abspath(__file__))
    py = sys.executable
    run([py, os.path.join(here, "fetch_banlists.py"), project])
    run([py, os.path.join(here, "build_blocks.py"), project])
    sync_articles(project, sleep)
    stamp = os.path.join(project, "data", "meta", "refresh_ok.txt")
    open(stamp, "w", encoding="utf-8").write("ok\n")
    print("REFRESH OK", flush=True)
    return 0

if __name__ == "__main__":
    sys.exit(main())
