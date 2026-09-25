#!/usr/bin/env python3
"""tools/fetch_banlists.py — rebuild the TCG restricted list from officials.

Fetches the known EN restriction revisions (oldest first), parses banned /
restricted / pair / unban sections, and merges CUMULATIVELY: a ban persists
until a later revision explicitly unbans it (the user's rule, and Bandai's).

Writes data/banlists/tcg.json + data/banlists/history.json.
OCG (Japan) scraping is NOT implemented: the JP detail URL is undiscovered.
ocg.json stays a labeled provisional mirror until then (this script never
touches it).

Revision history (all verified by fetch):
  2023-12-08  Dec 8 2023 notice: ban Moby Dick, Cabaji
  2023-12-01  removal notice: (first unbans; content truncated online)
  2024-06-21  ban Sakazuki, Great Eruption, Reject
  2024-09-06  ban Law ST10-001, Enies Lobby
  2025-04-01  ban Moria, Jinbe, Ice Age, Kingdom Come (archive typo says 2025;
              consistent with the 2026 unban wave; treated as a revision)
  2025-08-30  topics/019: ban Nami; unban Sakazuki, Cabaji;
              pairs Luffy+Katakuri, Luffy+Linlin (banned-pair system debuts)
  2026-04-01  topics/029: ban Pudding; unban Jinbe, Kingdom Come,
              Great Eruption, Moby Dick, Enies Lobby, Ice Age
  2026-04-10  restriction-260501: pair Quasar+Borsalino (no ban changes)

Usage: python tools/fetch_banlists.py <OharaTCG project>
"""
import json, re, sys, os
import urllib.request

BASE = "https://en.onepiece-cardgame.com"
UA = {"User-Agent": "OharaTCG-banlist/1.0 (research; contact via repo)"}
# (effective date, path) OLDEST first: the archive holds superseded history,
# later revisions add/remove on top (cumulative merge below).
SOURCES = [
    ("2024-01-01", "/news/restriction-archive.html"),
    ("2025-08-30", "/topics/019.php"),
    ("2026-04-01", "/topics/029.php"),
    ("2026-04-10", "/news/restriction-260501.html"),
]
CODE = r"(?:OP\d+-\d+|ST\d+-\d+|EB\d+-\d+|PRB\d+-\d+|P-\d+)"

def chunks(html):
    """Split page HTML at h3/h4/h5 headings -> [(heading, body)]."""
    parts = re.split(r"<h[345][^>]*>(.*?)</h[345]>", html, flags=re.I | re.S)
    out = [("", parts[0])]
    for i in range(1, len(parts) - 1, 2):
        title = re.sub(r"<[^>]+>", " ", parts[i])
        out.append((re.sub(r"\s+", " ", title).strip(), parts[i + 1]))
    return out

def first_code(s):
    m = re.search(CODE, s)
    return m.group(0) if m else ""

def li_codes(body):
    """Codes inside <li> items (topics-style entries, not reason prose)."""
    return re.findall(r"<li[^>]*>.*?(" + CODE + r")", body, flags=re.I | re.S)

def parse_revision(date, html):
    # Heading state machine. Card entries come either as headings starting
    # with a code ("OP03-040 Nami") or as <li> items under a mode heading.
    # Pairs use "Card A:"/"Card B:" label headings (code may sit in the same
    # heading or in following code headings).
    banned, unbanned, restricted, pairs = set(), set(), {}, []
    mode, pending_a, pending_b, want_a = None, "", False, False
    for title, body in chunks(html):
        t = title.strip()
        tl = t.lower()
        code = first_code(t)
        if t.startswith("Card A:"):
            if code:
                pending_a = code
            else:
                want_a = True
            if not pending_a:
                pending_a = first_code(re.sub(r"<[^>]+>", " ", body[:2000]))
            pending_b = False
            continue
        if t.startswith("Card B:"):
            pending_b = True
            want_a = False
            # Card references only (image alts / card links), never prose:
            # reason paragraphs mention unrelated cards in plain text.
            for bc in dict.fromkeys(re.findall(
                    r"(?:alt=\"|freewords=|/cards/)(" + CODE + r")", body)):
                if pending_a and bc != pending_a and [pending_a, bc] not in pairs:
                    pairs.append([pending_a, bc])
            continue
        if code and (want_a or pending_b or mode in ("ban", "unban", "rest")):
            if want_a:
                pending_a = code
                want_a = False
                continue
            if pending_b and pending_a and code != pending_a:
                if [pending_a, code] not in pairs:
                    pairs.append([pending_a, code])
                continue
            if mode == "ban":
                banned.add(code)
            elif mode == "unban":
                unbanned.add(code)
            elif mode == "rest":
                restricted[code] = restricted.get(code, 1)
            continue
        if "banned cards" in tl and "cannot be included" in re.sub(r"<[^>]+>", " ", body[:3000]).lower():
            mode = "ban"
            pending_b = False
            want_a = False
            banned |= set(li_codes(body))
        elif "banned card" in tl and "effective from" in tl:
            mode = "ban"  # archive history sections
            pending_b = False
            want_a = False
        elif tl.startswith("unban") or "removed from the banned" in tl or "removing the following" in tl:
            mode = "unban"
            pending_b = False
            want_a = False
            unbanned |= set(li_codes(body))
        elif "restricted cards" in tl:
            mode = "rest"
            pending_b = False
            want_a = False
            for c in li_codes(body):
                restricted[c] = restricted.get(c, 1)
        else:
            mode = None
            pending_b = False
            want_a = False
            want_a = False
    # topics/019 safety net: Luffy A with Katakuri+Linlin B run together.
    if "OP11-040" in html and "OP11-067" in html and ["OP11-040", "OP11-067"] not in pairs:
        pairs.append(["OP11-040", "OP11-067"])
    if "OP11-040" in html and "OP08-069" in html and ["OP11-040", "OP08-069"] not in pairs:
        pairs.append(["OP11-040", "OP08-069"])
    return {"date": date, "banned": sorted(banned), "unbanned": sorted(unbanned),
            "restricted": restricted, "pairs": pairs}

def discover_extra():
    """New restriction notices only. Older topics are already in SOURCES."""
    known = {path for _date, path in SOURCES}
    max_topic = 0
    for _date, path in SOURCES:
        m = re.search(r"/topics/(\d+)", path)
        if m:
            max_topic = max(max_topic, int(m.group(1)))
    found = []
    for page in ("/news/", "/topics/"):
        try:
            req = urllib.request.Request(BASE + page, headers=UA)
            with urllib.request.urlopen(req, timeout=30) as r:
                html = r.read().decode("utf-8", "replace")
        except Exception as exc:
            print("discover skip %s (%s)" % (page, type(exc).__name__))
            continue
        for href, text in re.findall(r'href="([^"]+)"[^>]*>([\s\S]*?)</a>', html):
            plain = re.sub(r"<[^>]+>", " ", text).lower()
            path = href
            if path.startswith(BASE):
                path = path[len(BASE):]
            path = path.split("?")[0]
            if not path.startswith("/") or path in known or path in found:
                continue
            if "banned_account" in path or path.startswith("/rules/"):
                continue
            topic = re.search(r"/topics/(\d+)\.php", path)
            if topic:
                if int(topic.group(1)) <= max_topic:
                    continue
                if "ban" not in plain and "restrict" not in plain:
                    continue
                found.append(path)
                continue
            if path.startswith("/news/restriction"):
                found.append(path)
    return found

def main():
    project = sys.argv[1] if len(sys.argv) > 1 else "."
    banned, pairs, history = set(), [], []
    restricted = {}
    jobs = list(SOURCES)
    for path in discover_extra():
        jobs.append(("discovered", path))
        print("new restriction page %s" % path)
    for date, path in jobs:
        try:
            req = urllib.request.Request(BASE + path, headers=UA)
            with urllib.request.urlopen(req, timeout=30) as r:
                html = r.read().decode("utf-8", "replace")
            rev = parse_revision(date, html)
        except Exception as e:
            print("FAIL %s: %s" % (path, e))
            continue
        for c in rev["banned"]:
            banned.add(c)
        for c in rev["unbanned"]:
            banned.discard(c)
            restricted.pop(c, None)
        for c, lim in rev.get("restricted", {}).items():
            restricted[c] = lim
        for p in rev["pairs"]:
            if p not in pairs:
                pairs.append(p)
        history.append(rev)
        print("%s: +%d banned, -%d unbanned, %d restricted, %d pairs" % (
            date, len(rev["banned"]), len(rev["unbanned"]),
            len(rev.get("restricted", {})), len(rev["pairs"])))
    out = {"name": "TCG (NA/EU/LATAM/OC) -- effective %s" % history[-1]["date"] if history else "?",
           "updated": history[-1]["date"] if history else "?",
           "source": "https://en.onepiece-cardgame.com/news/restriction-260501.html",
           "banned": sorted(banned), "restricted": restricted, "pairs": pairs}
    bdir = os.path.join(project, "data", "banlists")
    os.makedirs(bdir, exist_ok=True)
    cur = os.path.join(bdir, "tcg.json")
    old = {}
    if os.path.exists(cur):
        old = json.load(open(cur, encoding="utf-8"))
    json.dump(out, open(cur, "w"), indent=1)
    json.dump(history, open(os.path.join(bdir, "history.json"), "w"), indent=1)
    same = (set(old.get("banned", [])) == banned
            and sorted(old.get("pairs", [])) == sorted(pairs)
            and old.get("restricted", {}) == restricted)
    print("banned=%d pairs=%d same-as-current=%s" % (len(banned), len(pairs), same))
    for c in sorted(banned):
        print("  ban", c)
    for p in pairs:
        print("  pair", p)
    return 0

if __name__ == "__main__":
    sys.exit(main())
