#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
OharaTCG wanted-poster asset generator.

Creates placeholder art in res://assets/profiles/:

  posters/poster_<tier>.png  - full wanted posters. Layer 1. Each has a
                               transparent CUTOUT window (the pfp shows through).
  symbols/symbol_<n>.png     - tier emblem PNGs (layer drawn over the poster).
  pfps/avatar_<n>.png        - default profile pictures (Layer 0). Drop your own
                               images here to replace them.

Cutout window (in poster-local pixels) is shared with scripts/Profile.gd.
Run again after changing anything here to regenerate.

Usage: python generate_profile_assets.py [ohara-project-root]
"""

import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

DEFAULT_PROJECT_ROOT = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
)

# --- Shared geometry ---------------------------------------------------------
POSTER_W, POSTER_H = 450, 640
CUTOUT = (90, 170, 360, 460)  # (x0, y0, x1, y1) transparent pfp window
HEAD_ZONE = (40, 28, 410, 120)   # "WANTED" ribbon zone
FOOT_ZONE = (36, 505, 414, 600)  # bounty text zone

# Tier -> (id, accent bg color, frame color, ribbon color, edge color)
TIERS = [
    ("rookie",      (216, 184, 120), (122, 92, 58),  (110, 84, 50),  (96, 72, 42)),
    ("supernova",   (186, 206, 224), (70, 92, 118),  (60, 84, 112),  (40, 62, 90)),
    ("warlord",     (168, 142, 200), (80, 52, 122),  (86, 54, 128),  (58, 34, 92)),
    ("emperor",     (168, 96, 88),   (110, 38, 34),  (118, 42, 36),  (74, 22, 20)),
    ("pirateking",  (46, 48, 62),    (196, 160, 60), (210, 176, 68), (150, 120, 32)),
]

SYMBOL_COLOR = (222, 178, 74)      # gold emblem
N_TIER_IMAGES = 5                   # poster_rookie .. poster_pirateking
N_AVATARS = 8


def _font(size: int, bold: bool = True):
    candidates = [
        r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf",
        r"C:\Windows\Fonts\calibrib.ttf" if bold else r"C:\Windows\Fonts\calibri.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for c in candidates:
        if os.path.exists(c):
            return ImageFont.truetype(c, size)
    return ImageFont.load_default()


def _shade(base, factor):
    return tuple(max(0, min(255, int(c * factor))) for c in base)


def draw_poster(idx: int) -> Image.Image:
    tier, accent, frame, ribbon, edge = TIERS[idx]
    img = Image.new("RGBA", (POSTER_W, POSTER_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # background gradient (tier accent -> darker)
    for y in range(POSTER_H):
        t = y / POSTER_H
        col = tuple(int(accent[i] * (1 - t * 0.45) + edge[i] * (t * 0.45)) for i in range(3))
        d.line([(0, y), (POSTER_W, y)], fill=col + (255,))

    # outer frame
    d.rectangle([8, 8, POSTER_W - 9, POSTER_H - 9], outline=frame, width=8)
    d.rectangle([20, 20, POSTER_W - 21, POSTER_H - 21], outline=_shade(frame, 1.3), width=3)
    d.rectangle([30, 30, POSTER_W - 31, POSTER_H - 31], outline=_shade(frame, 0.8), width=2)

    # corner ornaments
    for cx, cy in [(30, 30), (POSTER_W - 30, 30), (30, POSTER_H - 30), (POSTER_W - 30, POSTER_H - 30)]:
        r = 16
        d.polygon([(cx - r, cy), (cx + r, cy), (cx, cy + r)], fill=frame)
        d.polygon([(cx, cy - r), (cx + r, cy), (cx - r, cy)], fill=frame)

    # WANTED ribbon (top zone)
    x0, y0, x1, y1 = HEAD_ZONE
    d.rectangle([x0, y0, x1, y1], fill=ribbon)
    d.rectangle([x0, y0, x1, y1], outline=_shade(ribbon, 1.4), width=3)
    f = _font(54, bold=True)
    text = "WANTED"
    bbox = d.textbbox((0, 0), text, font=f)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(((x0 + x1 - tw) // 2 - bbox[0], (y0 + y1 - th) // 2 - bbox[1]),
           text, font=f, fill=(255, 255, 255, 255))

    # Cutout frame - the pfp window (keep interior transparent)
    cx0, cy0, cx1, cy1 = CUTOUT
    d.rounded_rectangle([cx0 - 6, cy0 - 6, cx1 + 6, cy1 + 6], radius=18,
                        outline=_shade(edge, 1.6), width=6)
    d.rounded_rectangle([cx0 - 2, cy0 - 2, cx1 + 2, cy1 + 2], radius=14,
                        outline=edge, width=2)

    # faint side flourishes
    for yy in range(120, 480, 56):
        d.ellipse([48, yy, 66, yy + 18], outline=_shade(edge, 1.2), width=2)
        d.ellipse([POSTER_W - 66, yy, POSTER_W - 48, yy + 18], outline=_shade(edge, 1.2), width=2)

    # footer zone separating line + tier chevrons
    fx0, fy0, fx1, fy1 = FOOT_ZONE
    d.line([(fx0, fy0), (fx1, fy0)], fill=_shade(edge, 1.2), width=2)
    d.line([(fx0, fy1), (fx1, fy1)], fill=_shade(edge, 1.2), width=2)

    return img


def star_pts(cx, cy, r_out, r_in, points=5, rot=-math.pi / 2):
    pts = []
    for i in range(points * 2):
        ang = rot + i * math.pi / points
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    return pts


def draw_symbols(out_dir: str) -> None:
    # symbol_0 is an empty transparent placeholder (tier 0 -> no symbols shown)
    Image.new("RGBA", (96, 96), (0, 0, 0, 0)).save(os.path.join(out_dir, "symbol_0.png"))
    for n in range(1, N_TIER_IMAGES):
        img = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        pts = star_pts(48, 48, 40, 16, points=5)
        d.polygon(pts, fill=SYMBOL_COLOR + (255,))
        d.line(pts + [pts[0]], fill=(120, 90, 30, 255), width=2)
        img.save(os.path.join(out_dir, "symbol_%d.png" % n))


def draw_avatar(idx: int, out_path: str) -> None:
    img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    palette = [
        (198, 60, 60), (60, 130, 198), (90, 170, 70), (210, 150, 40),
        (140, 80, 180), (40, 160, 160), (200, 90, 140), (90, 90, 100),
    ]
    base = palette[idx % len(palette)]
    for y in range(256):
        t = y / 256
        col = tuple(int(base[i] * (1 - t * 0.5)) for i in range(3))
        d.line([(0, y), (256, y)], fill=col + (255,))
    # inner ring
    d.ellipse([16, 16, 240, 240], outline=(255, 255, 255, 220), width=10)
    d.ellipse([34, 34, 222, 222], outline=(255, 255, 255, 120), width=3)
    # initial letter
    letter = chr(ord("A") + idx)
    f = _font(120, bold=True)
    bbox = d.textbbox((0, 0), letter, font=f)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(((256 - tw) // 2 - bbox[0], (256 - th) // 2 - bbox[1]),
           letter, font=f, fill=(255, 255, 255, 255))
    img.save(out_path)


def main() -> None:
    project_root = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PROJECT_ROOT
    base = os.path.join(project_root, "assets", "profiles")
    posters_dir = os.path.join(base, "posters")
    symbols_dir = os.path.join(base, "symbols")
    pfps_dir = os.path.join(base, "pfps")
    os.makedirs(posters_dir, exist_ok=True)
    os.makedirs(symbols_dir, exist_ok=True)
    os.makedirs(pfps_dir, exist_ok=True)

    for idx, (tier, *_) in enumerate(TIERS):
        draw_poster(idx).save(os.path.join(posters_dir, "poster_%s.png" % tier))
        print("  poster_%s.png" % tier)

    draw_symbols(symbols_dir)
    print("  symbol_0..%d.png" % (N_TIER_IMAGES - 1))

    for i in range(N_AVATARS):
        draw_avatar(i, os.path.join(pfps_dir, "avatar_%d.png" % (i + 1)))
    print("  avatar_1..%d.png" % N_AVATARS)

    print("\nProfile assets written to", base)
    print("Cutout window: %s  POSTER: %dx%d" % (CUTOUT, POSTER_W, POSTER_H))


if __name__ == "__main__":
    main()