"""Sync OPTCGSim card images into this project's `assets/cards/`.

Offline-only: copies from
`addons/Builds_Windows/OPTCGSim_Data/StreamingAssets/Cards/<SET>/<CODE>.png`
into
`assets/cards/<SET>/<CODE>.png`

By default:
- Skips if destination file already exists
- Skips `Don/` (project already has many DON variants)

Usage:
  python tools/sync_optcgsim_card_images_to_assets.py
  python tools/sync_optcgsim_card_images_to_assets.py --overwrite
  python tools/sync_optcgsim_card_images_to_assets.py --dry-run
"""

from __future__ import annotations

import argparse
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = ROOT / "addons" / "Builds_Windows" / "OPTCGSim_Data" / "StreamingAssets" / "Cards"
DST_ROOT = ROOT / "assets" / "cards"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--overwrite", action="store_true", help="Overwrite existing files")
    ap.add_argument("--dry-run", action="store_true", help="Do not copy, only report")
    ap.add_argument(
        "--include-don", action="store_true", help="Also sync Cards/Don/*.png"
    )
    args = ap.parse_args()

    if not SRC_ROOT.exists():
        raise SystemExit(f"Missing source cards folder: {SRC_ROOT}")

    copied = 0
    skipped_exists = 0
    skipped_other = 0

    for set_dir in sorted([p for p in SRC_ROOT.iterdir() if p.is_dir()]):
        set_code = set_dir.name
        if set_code.lower() == "don" and not args.include_don:
            skipped_other += len(list(set_dir.glob("*.png")))
            continue

        dst_set_dir = DST_ROOT / set_code
        if not args.dry_run:
            dst_set_dir.mkdir(parents=True, exist_ok=True)

        for src in sorted(set_dir.glob("*.png")):
            dst = dst_set_dir / src.name
            if dst.exists() and not args.overwrite:
                skipped_exists += 1
                continue

            if args.dry_run:
                copied += 1
                continue

            dst.write_bytes(src.read_bytes())
            copied += 1

    print("SOURCE", SRC_ROOT)
    print("DEST", DST_ROOT)
    print("COPIED", copied, "(dry-run)" if args.dry_run else "")
    print("SKIPPED_EXISTS", skipped_exists)
    print("SKIPPED_OTHER", skipped_other)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
