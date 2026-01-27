# OharaTCG Project

## Overview

This repository contains two main components:

1. **OharaTCG (Godot Project)**: A Godot 4.6 desktop application for One Piece Trading Card Game deck management. This is a game project with deck selection, deck editing, card stacking, and a full UI flow.

2. **GrandLineScraper (Streamlit Web App)**: A web-based card data scraper for One Piece TCG that runs on Replit. This tool fetches card data from multiple APIs and repositories, processes the data, downloads card images, and exports in various formats.

## Running on Replit

The Streamlit-based GrandLineScraper app runs in Replit. The Godot game project requires the Godot Engine and cannot run directly in the browser environment.

### Streamlit App (GrandLineScraper)

- **Location**: `addons/GrandLineScraper/`
- **Main File**: `app.py`
- **Port**: 5000
- **Command**: `cd addons/GrandLineScraper && streamlit run app.py --server.port 5000 --server.address 0.0.0.0`

### Features

- Scrapes card data from APITCG API, GitHub repositories, and other sources
- Downloads and processes card images
- Exports data in JSON, CSV, and Godot-specific formats
- Supports OCG (Japanese) and TCG (English) card data

## Project Structure

```
├── addons/
│   ├── GrandLineScraper/     # Streamlit web scraper app
│   │   ├── app.py            # Main Streamlit application
│   │   ├── api_client.py     # APITCG API client
│   │   ├── optcg_client.py   # OPTCG API client
│   │   ├── data_processor.py # Data processing and normalization
│   │   ├── image_downloader.py # Image download manager
│   │   └── export_manager.py # Export functionality
│   └── smart_drag_drop/      # Godot drag-drop addon
├── scenes/                   # Godot scene files
├── scripts/                  # Godot GDScript files
├── tools/                    # Python utility scripts for deck/image management
├── data/                     # Card and deck data files
├── assets/                   # Card images and assets
└── output/                   # Scraper output and reports
```

## Dependencies

### Python (for GrandLineScraper)
- streamlit
- beautifulsoup4
- pandas
- pillow
- requests
- trafilatura

### System Dependencies
- freetype, lcms2, libimagequant, libjpeg, libtiff, libwebp, openjpeg, tcl, tk, zlib

## User Preferences

- Preferred communication style: Simple, everyday language
- UI scale in Godot is set high (9.0) for larger elements

## Recent Changes

- 2026-01-27: Updated OPTCG client to use open API (no authentication required) - covers all English TCG cards
- 2026-01-27: OPTCG API now the primary data source - fetches OP-01 to OP-14, ST-01 to ST-28, and 900+ promos
- 2026-01-27: Fixed GitHub data source dependency - APITCGClient created when either APITCG or GitHub is enabled
- 2026-01-27: Fixed duplicate signal connection bug in Decks.gd - removed redundant signal hookups from _ready() that were already wired in the scene file
- 2026-01-27: Refactored DeckEdit.tscn HeaderBar from anchor-based positioning to HBoxContainer layout for proper button click handling
- 2026-01-27: Updated DeckSelection.tscn with proper mouse filter settings and signal connections for clickable deck tiles
- 2026-01-27: Set up Replit environment with Streamlit workflow
