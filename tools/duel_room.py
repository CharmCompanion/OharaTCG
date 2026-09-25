#!/usr/bin/env python3
"""tools/duel_room.py — YGO-style AI duel setup room (tkinter, stdlib only).

Pick who's dueling (AI Easy/Medium/Pro per side), which decks, which banlist
(None/TCG/OCG), who goes first (rock-paper-scissors auto/manual, P0, P1,
random), then watch two AIs duel the FULL match with play-by-play log.
Run as many games as you want; results tally at the bottom.

Each game shells out to the real Godot engine (tests/duel_room.gd), so the
duels are the actual adjudicated game — not a reimplementation.

Usage: python tools/duel_room.py
"""
import json, os, random, re, subprocess, sys, threading, queue
import tkinter as tk
from tkinter import ttk, scrolledtext

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = r"D:\Development\GODOT\Godot_v4.4.1-stable_win64_console.exe"
LEVELS = ["Easy", "Medium", "Pro"]
THROWS = ["Rock", "Paper", "Scissors"]

RESULT_RE = re.compile(r"DUEL RESULT winner=(-?\d+) turns=(\d+) steps=(\d+) reason=(.*)")


def find_godot(preferred):
    """Resolve the Godot console binary: field value, PATH, then siblings."""
    cands = []
    if preferred and preferred.strip():
        cands.append(preferred.strip())
    import shutil
    for name in ("Godot_v4.4.1-stable_win64_console.exe", "godot.exe",
                 "godot"):
        w = shutil.which(name)
        if w:
            cands.append(w)
    for c in cands:
        if os.path.isfile(c):
            return c
    return ""


def load_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


class DuelRoom(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("OharaTCG — AI Duel Room")
        self.geometry("980x720")
        self.proc = None
        self.queue = queue.Queue()
        self.tally = {"P0": 0, "P1": 0, "draw": 0}
        self._build()
        self._poll()

    # ----- data -----
    def meta_decks(self):
        return load_json(os.path.join(PROJECT, "data", "meta", "decks.json"), [])

    def deck_choices(self):
        out = [("ST01 Starter (both random ST01)", {"kind": "st01"})]
        for i, d in enumerate(self.meta_decks()):
            out.append(("Meta #%d: %s (%s, %s)" % (
                i, d.get("leader", "?"), d.get("player", "?"),
                d.get("tournament", "?")[:28]), {"kind": "meta", "index": i}))
        deck_dir = os.path.join(PROJECT, "data", "decks")
        if os.path.isdir(deck_dir):
            for f in sorted(os.listdir(deck_dir)):
                if f.endswith(".json"):
                    out.append(("File: %s" % f, {"kind": "file",
                        "path": "res://data/decks/" + f}))
        return out

    def ban_choices(self):
        # Actually the FORMAT list (banlist + blocks travel inside each entry).
        out = [("Open / Casual (no banlist, all blocks)", {})]
        fmts = load_json(os.path.join(PROJECT, "data", "formats.json"),
                         {}).get("formats", [])
        for f in fmts:
            if f.get("id") == "open":
                continue
            out.append(("%s — %s" % (f.get("id"), f.get("description", "")[:60]), f))
        return out

    # ----- ui -----
    def _build(self):
        top = ttk.Frame(self, padding=8)
        top.pack(fill=tk.X)
        ttk.Label(top, text="Godot:").grid(row=0, column=0, sticky=tk.W)
        self.godot_e = ttk.Entry(top, width=70)
        self.godot_e.insert(0, GODOT)
        self.godot_e.grid(row=0, column=1, columnspan=4, sticky=tk.W)

        self.decks = self.deck_choices()
        self.sides = []
        for col, name in ((0, "P0 (bottom)"), (1, "P1 (top)")):
            fr = ttk.LabelFrame(top, text="Duelist " + name, padding=6)
            fr.grid(row=1, column=col, padx=6, pady=6, sticky=tk.NSEW)
            ttk.Label(fr, text="AI level:").grid(row=0, column=0, sticky=tk.W)
            lv = ttk.Combobox(fr, values=LEVELS, width=8, state="readonly")
            lv.set("Medium" if col == 1 else "Easy")
            lv.grid(row=0, column=1, sticky=tk.W)
            ttk.Label(fr, text="Deck:").grid(row=1, column=0, sticky=tk.W)
            dk = ttk.Combobox(fr, values=[n for n, _ in self.decks],
                              width=44, state="readonly")
            dk.current(0)
            dk.grid(row=1, column=1, sticky=tk.W)
            self.sides.append((lv, dk))

        mid = ttk.Frame(top, padding=4)
        mid.grid(row=2, column=0, columnspan=2, sticky=tk.W)
        ttk.Label(mid, text="Format:").grid(row=0, column=0)
        self.bans = self.ban_choices()
        self.ban_c = ttk.Combobox(mid, values=[n for n, _ in self.bans],
                                  width=52, state="readonly")
        self.ban_c.current(0)
        self.ban_c.grid(row=0, column=1, padx=4)
        ttk.Label(mid, text="First:").grid(row=0, column=2)
        self.first_c = ttk.Combobox(mid, values=["RPS Auto", "RPS Manual",
            "P0", "P1", "Random"], width=12, state="readonly")
        self.first_c.set("RPS Auto")
        self.first_c.grid(row=0, column=3, padx=4)
        ttk.Label(mid, text="RPS winner:").grid(row=0, column=4)
        self.win_c = ttk.Combobox(mid, values=["goes First", "goes Second"],
                                  width=12, state="readonly")
        self.win_c.set("goes First")
        self.win_c.grid(row=0, column=5, padx=4)

        thr = ttk.Frame(top)
        thr.grid(row=3, column=0, columnspan=2, sticky=tk.W, padx=8)
        ttk.Label(thr, text="P0 throw (RPS Manual):").pack(side=tk.LEFT)
        self.throw_v = tk.StringVar(value="Rock")
        for t in THROWS:
            ttk.Radiobutton(thr, text=t, value=t,
                            variable=self.throw_v).pack(side=tk.LEFT)
        ttk.Label(thr, text="Games:").pack(side=tk.LEFT, padx=(16, 2))
        self.n_v = tk.StringVar(value="1")
        ttk.Spinbox(thr, from_=1, to=20, width=4,
                    textvariable=self.n_v).pack(side=tk.LEFT)
        self.rps_lbl = ttk.Label(thr, text="", foreground="blue")
        self.rps_lbl.pack(side=tk.LEFT, padx=12)

        btns = ttk.Frame(top)
        btns.grid(row=4, column=0, columnspan=2, sticky=tk.W, padx=8, pady=4)
        self.run_b = ttk.Button(btns, text="DUEL!", command=self.on_run)
        self.run_b.pack(side=tk.LEFT)
        ttk.Button(btns, text="Watch (Godot window)",
                   command=self.on_watch).pack(side=tk.LEFT, padx=6)
        ttk.Button(btns, text="Stop",
                   command=self.on_stop).pack(side=tk.LEFT, padx=6)

        pan = ttk.PanedWindow(self, orient=tk.VERTICAL)
        pan.pack(fill=tk.BOTH, expand=True, padx=8, pady=4)
        self.log = scrolledtext.ScrolledText(pan, height=22, wrap=tk.WORD,
                                             state=tk.DISABLED)
        pan.add(self.log, weight=3)
        bot = ttk.Frame(pan)
        pan.add(bot, weight=1)
        ttk.Label(bot, text="History:").pack(anchor=tk.W)
        self.hist = tk.Listbox(bot, height=6)
        self.hist.pack(fill=tk.BOTH, expand=True)
        self.tally_lbl = ttk.Label(bot, text="P0: 0  P1: 0  unfinished: 0")
        self.tally_lbl.pack(anchor=tk.W)
        ttk.Button(bot, text="Clear history",
                   command=self.on_clear).pack(anchor=tk.W)

    # ----- rps -----
    def decide_first(self):
        mode = self.first_c.get()
        if mode == "P0":
            return 0, "set P0"
        if mode == "P1":
            return 1, "set P1"
        if mode == "Random":
            f = random.randrange(2)
            return f, "random -> P%d" % f
        t0 = self.throw_v.get() if mode == "RPS Manual" else random.choice(THROWS)
        t1 = random.choice(THROWS)
        info = "RPS P0=%s P1=%s " % (t0, t1)
        if t0 == t1:
            f = random.randrange(2)
            return f, info + "tie -> random P%d" % f
        p0win = (t0, t1) in [("Rock", "Scissors"), ("Scissors", "Paper"),
                             ("Paper", "Rock")]
        w = 0 if p0win else 1
        first = w if self.win_c.get() == "goes First" else 1 - w
        return first, info + "P%d wins -> P%d first" % (w, first)

    # ----- run -----
    def on_run(self):
        if self.proc is not None:
            return
        try:
            n = max(1, min(20, int(self.n_v.get())))
        except ValueError:
            n = 1
        self._launch([self._make_cfg() for _ in range(n)], False)

    def on_watch(self):
        # One game in a real Godot window: playfield, both hands, active play.
        if self.proc is not None:
            return
        self._launch([self._make_cfg()], True)

    def _make_cfg(self):
        first, info = self.decide_first()
        self.rps_lbl.config(text=info)
        return {
            "seed": random.randrange(1, 1 << 30),
            "deck_a": self.decks[self.sides[0][1].current()][1],
            "deck_b": self.decks[self.sides[1][1].current()][1],
            "level_a": LEVELS.index(self.sides[0][0].get()),
            "level_b": LEVELS.index(self.sides[1][0].get()),
            "first": first,
            "format": self.bans[self.ban_c.current()][1],
            "banlist": "",
        }

    def _launch(self, cfgs, windowed):
        self.run_b.config(state=tk.DISABLED)
        threading.Thread(target=self._worker, args=(cfgs, windowed),
                         daemon=True).start()

    def on_stop(self):
        if self.proc is not None:
            try:
                self.proc.terminate()
            except Exception:
                pass

    def on_clear(self):
        self.hist.delete(0, tk.END)
        self.tally = {"P0": 0, "P1": 0, "draw": 0}
        self._tally()

    def _tally(self):
        self.tally_lbl.config(text="P0: %d  P1: %d  unfinished: %d" % (
            self.tally["P0"], self.tally["P1"], self.tally["draw"]))

    def _worker(self, cfgs, windowed):
        exe = find_godot(self.godot_e.get())
        if not exe:
            self.queue.put(("line", "ROOM ERROR: Godot binary not found. "
                "Set the correct path in the Godot field (tried field value "
                "and PATH)."))
            self.queue.put(("done", None))
            return
        if not os.path.isdir(PROJECT):
            self.queue.put(("line", "ROOM ERROR: project not found at %s"
                % PROJECT))
            self.queue.put(("done", None))
            return
        self.queue.put(("line", "Engine: %s" % exe))
        for i, cfg in enumerate(cfgs):
            path = os.path.join(PROJECT, "data", "duel_config.json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(cfg, f)
            self.queue.put(("mark",
                "=== Game %d/%d seed=%d first=P%d ===" % (
                    i + 1, len(cfgs), cfg["seed"], cfg["first"])))
            try:
                args = [exe]
                if not windowed:
                    args.append("--headless")
                args += ["--path", PROJECT, "--script",
                         "res://tests/watch_duel.gd" if windowed else "res://tests/duel_room.gd",
                         "--", "--duel-config=" + path]
                self.proc = subprocess.Popen(
                    args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    text=True, bufsize=1)
                for line in self.proc.stdout:
                    self.queue.put(("line", line.rstrip("\n")))
                    m = RESULT_RE.search(line)
                    if m:
                        self.queue.put(("result", (int(m.group(1)),
                            m.group(2), m.group(4), i + 1, len(cfgs))))
                self.proc.wait(timeout=900)
            except Exception as e:
                self.queue.put(("line", "ROOM ERROR: %s" % e))
            finally:
                self.proc = None
        self.queue.put(("done", None))

    def _poll(self):
        try:
            while True:
                kind, payload = self.queue.get_nowait()
                if kind == "line":
                    self.log.config(state=tk.NORMAL)
                    self.log.insert(tk.END, payload + "\n")
                    self.log.see(tk.END)
                    self.log.config(state=tk.DISABLED)
                elif kind == "mark":
                    self.log.config(state=tk.NORMAL)
                    self.log.insert(tk.END, "\n" + payload + "\n")
                    self.log.see(tk.END)
                    self.log.config(state=tk.DISABLED)
                elif kind == "result":
                    w, turns, reason, i, n = payload
                    key = "P0" if w == 0 else ("P1" if w == 1 else "draw")
                    self.tally[key] += 1
                    self._tally()
                    self.hist.insert(tk.END,
                        "G%d/%d: %s in %s turns (%s)" % (
                            i, n, key, turns, reason[:60]))
                elif kind == "done":
                    self.run_b.config(state=tk.NORMAL)
        except queue.Empty:
            pass
        self.after(120, self._poll)


if __name__ == "__main__":
    DuelRoom().mainloop()
