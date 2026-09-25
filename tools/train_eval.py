#!/usr/bin/env python3
"""tools/train_eval.py — offline learning from self-play logs.

Reads data/ai/games.jsonl (MtGameLog entries) and writes:
  data/ai/eval_weights.json  {mean[5], std[5], w[5], bias, games, accuracy}
  data/ai/move_priors.json   {priors: {CODE: Laplace winrate}}
  data/ai/book.json          {entries: {poskey: {mover, moves: {canon: [wins, plays]}}}}

Features (GDScript MtGameLog.features, P0 perspective, RAW):
  [life_diff, power_diff, hand_diff, don_diff, meta_raw_diff]
The runtime (MtMctsAi._reward) standardizes identically and applies sigmoid.
Canon action form matches MtMctsAi.canon: sorted keys, compact separators.

Usage: python tools/train_eval.py <OharaTCG project>
"""
import json, math, sys, os
from collections import defaultdict

FEATS = 5

def load_games(project):
    path = os.path.join(project, "data", "ai", "games.jsonl")
    out = []
    seen = set()
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if line:
            g = json.loads(line)
            if g.get("seed") in seen:
                continue
            seen.add(g.get("seed"))
            out.append(g)
    return [g for g in out if g.get("winner", -1) in (0, 1)]

def train_eval(games):
    xs, ys = [], []
    for g in games:
        y = 1.0 if g["winner"] == 0 else 0.0
        for p in g["plies"]:
            xs.append([float(v) for v in p["feat"]])
            ys.append(y)
    n = len(xs)
    mean = [sum(x[i] for x in xs) / n for i in range(FEATS)]
    std = []
    for i in range(FEATS):
        v = sum((x[i] - mean[i]) ** 2 for x in xs) / n
        std.append(math.sqrt(v) if v > 1e-12 else 1.0)
    z = [[(x[i] - mean[i]) / std[i] for i in range(FEATS)] for x in xs]
    w, b, lr, l2 = [0.0] * FEATS, 0.0, 0.5, 1e-4
    for _ in range(500):
        gw, gb = [0.0] * FEATS, 0.0
        for i in range(n):
            s = b + sum(w[j] * z[i][j] for j in range(FEATS))
            p = 1.0 / (1.0 + math.exp(-max(-30.0, min(30.0, s))))
            e = p - ys[i]
            for j in range(FEATS):
                gw[j] += e * z[i][j]
            gb += e
        for j in range(FEATS):
            w[j] -= lr * (gw[j] / n + l2 * w[j])
        b -= lr * gb / n
    # Clean accuracy pass:
    hits = 0
    for i in range(n):
        s = b + sum(w[j] * z[i][j] for j in range(FEATS))
        p = 1.0 / (1.0 + math.exp(-s))
        if (p >= 0.5) == (ys[i] == 1.0):
            hits += 1
    return {"mean": mean, "std": std, "w": w, "bias": b,
            "games": len(games), "plies": n, "accuracy": round(hits / n, 4)}

def train_priors(games):
    with_c, win_c = defaultdict(int), defaultdict(float)
    for g in games:
        decks = [g["deck_a"], g["deck_b"]]
        for side in (0, 1):
            seen = set()
            for c in decks[side].get("main", []):
                code = c.get("card_code", c.get("code", ""))
                if code:
                    seen.add(code)
            for code in seen:
                with_c[code] += 1
                if g["winner"] == side:
                    win_c[code] += 1
    return {c: round((win_c[c] + 1.0) / (with_c[c] + 2.0), 4) for c in with_c}

def canon(action):
    return json.dumps(action, sort_keys=True, separators=(",", ":"))

def train_book(games):
    entries = {}
    for g in games:
        for p in g["plies"]:
            if int(p.get("turn", 99)) > 4:
                continue
            key = str(p.get("key", ""))
            e = entries.setdefault(key, {"mover": int(p.get("mover", 0)), "moves": {}})
            ck = canon(p.get("action", {}))
            wn = e["moves"].setdefault(ck, [0, 0])
            wn[1] += 1
            if g["winner"] == int(p.get("mover", -1)):
                wn[0] += 1
    return {"entries": entries}

def main():
    project = sys.argv[1] if len(sys.argv) > 1 else "."
    games = load_games(project)
    print("games: %d" % len(games))
    ai_dir = os.path.join(project, "data", "ai")
    os.makedirs(ai_dir, exist_ok=True)
    ew = train_eval(games)
    json.dump({"weights": {k: ew[k] for k in ("mean", "std", "w", "bias")},
               "games": ew["games"], "plies": ew["plies"], "accuracy": ew["accuracy"]},
              open(os.path.join(ai_dir, "eval_weights.json"), "w"), indent=1)
    print("eval: acc=%.3f w=%s bias=%.3f" % (ew["accuracy"],
          [round(v, 3) for v in ew["w"]], ew["bias"]))
    pr = train_priors(games)
    json.dump({"priors": pr}, open(os.path.join(ai_dir, "move_priors.json"), "w"), indent=1)
    print("priors: %d codes" % len(pr))
    bk = train_book(games)
    json.dump(bk, open(os.path.join(ai_dir, "book.json"), "w"))
    print("book: %d positions" % len(bk["entries"]))
    return 0

if __name__ == "__main__":
    sys.exit(main())
