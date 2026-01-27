# OPTCGSim quick inventory (offline)

This project includes an OPTCGSim Windows build at:
- `addons/Builds_Windows/`

## What it contains (high value)

### Card images (big win)

Location:
- `addons/Builds_Windows/OPTCGSim_Data/StreamingAssets/Cards/`

Structure:
- One folder per set code (no hyphens), containing PNGs named by card code.
  - Example: `OP01/OP01-001.png`
  - Example: `ST01/ST01-006.png`

Set folders observed:
- `Don/`
- `OP01/` … `OP14/`
- `EB01/` … `EB04/`
- `PRB01/`, `PRB02/`
- `ST01/` … `ST29/`
- `P/`

### Deck files

Location:
- `addons/Builds_Windows/Decks/*.deck`

Observed:
- ST01–ST05 deck files exist.
- Format is line-per-card-code with counts: `4xST01-006`.
- Totals appear to be **Leader + 50-card deck** (= 51 total).

### UI strings / messages

Location:
- `addons/Builds_Windows/OPTCGSim_Data/StreamingAssets/TRANSLATION.txt`

Contains:
- Button labels
- Log message templates
- Some gameplay/choice text

### Playmats

Location:
- `addons/Builds_Windows/OPTCGSim_Data/StreamingAssets/Playmats/`

Contains many color-themed playmat images.

## How we’re using it in OharaTCG

- The Godot image resolver now checks OPTCGSim StreamingAssets as a fallback.
  - This lets you use OPTCGSim’s PNG library immediately (no copying required).

## Limitations

- The Unity `*.assets` files inside `addons/Builds_Windows/OPTCGSim_Data/` likely contain additional logic/assets, but extracting them cleanly typically requires a Unity asset extraction tool.
