import argparse
import json
import sys
import time
from pathlib import Path

# Inject streamlit shim for headless runs
from streamlit_shim import session_state  # noqa: F401
import streamlit_shim as st
sys.modules['streamlit'] = st

from api_client import APITCGClient
from optcg_client import OPTcgClient
from onepiecetopdecks_client import OnePieceTopDecksClient
from data_processor import DataProcessor
from image_downloader import ImageDownloader
from export_manager import ExportManager
from utils import create_directories

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = PROJECT_ROOT / "output"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run One Piece TCG scraper headlessly")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--images", action="store_true")
    parser.add_argument("--no-optcg", action="store_true")
    parser.add_argument("--no-github", action="store_true")
    parser.add_argument("--topdecks", action="store_true")
    parser.add_argument("--topdecks-urls", default="")
    # Python 3.9+: supports both --ocg and --no-ocg (same for tcg)
    parser.add_argument("--ocg", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--tcg", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--no-translate", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    output_dir = Path(args.output)
    create_directories(str(output_dir))

    card_types = {
        "Sets": True,
        "Decks": True,
        "Promos": True,
        "Tournaments": True,
        "Don Cards": True,
        "Alt Arts": True
    }

    include_ocg = args.ocg
    include_tcg = args.tcg
    translate_ocg = not args.no_translate
    include_github = not args.no_github
    include_optcg = not args.no_optcg
    download_images = args.images
    include_topdecks = args.topdecks
    topdecks_urls = [u.strip() for u in args.topdecks_urls.split(",") if u.strip()]

    api_client = APITCGClient(api_key="")
    optcg_client = OPTcgClient() if include_optcg else None
    topdecks_client = OnePieceTopDecksClient() if include_topdecks else None
    data_processor = DataProcessor()
    image_downloader = ImageDownloader(str(output_dir)) if download_images else None
    export_manager = ExportManager(
        str(output_dir),
        auto_copy_decks=True,
        export_complete_deck_json=False,
    )

    scraped_data = {}

    st.write("Starting headless scrape...")

    apitcg_data = api_client.fetch_all_data(card_types, include_ocg, include_tcg)
    scraped_data["apitcg"] = apitcg_data

    if include_github:
        scraped_data["github"] = api_client.fetch_github_data()

    if include_optcg:
        set_list = apitcg_data.get("sets", [])
        set_ids = []
        for pack in set_list:
            if pack.get("language") != "tcg":
                continue
            set_ids.append(pack.get("label", pack.get("id", "")))

        optcg_data = optcg_client.fetch_cards_for_sets(
            set_ids,
            include_sets=card_types.get("Sets", True),
            include_decks=card_types.get("Decks", True),
            include_promos=card_types.get("Promos", True),
            include_optcg_catalog=True,
        )
        scraped_data["optcg"] = optcg_data

    if include_topdecks and topdecks_client:
        scraped_data["onepiecetopdecks"] = topdecks_client.fetch_all_data(extra_urls=topdecks_urls)

    processed_data = data_processor.process_all_data(scraped_data, translate_ocg=translate_ocg)

    if download_images and image_downloader:
        image_downloader.download_all_images(processed_data)
        image_downloader.sync_to_godot_assets(processed_data)

    export_manager.export_data(processed_data, "JSON")

    _write_scrape_stamp(output_dir, processed_data)

    st.write("Headless scrape complete")
    return 0


def _write_scrape_stamp(output_dir: Path, processed_data: dict) -> None:
    stamp = {
        "completed_at": time.time(),
        "total_cards": len(processed_data.get("cards", [])),
        "total_sets": len(processed_data.get("sets", []))
    }
    stamp_path = output_dir / "last_scrape.json"
    stamp_path.write_text(json.dumps(stamp, indent=2), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
