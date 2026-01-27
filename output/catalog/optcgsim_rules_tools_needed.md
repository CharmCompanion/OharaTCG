# OPTCGSim rules/mechanics extraction: tools needed

OPTCGSim is a Unity (Mono) build. There are two “tiers” of data:

## Tier 1: Plain files (easy, already accessible)

Look in:
- `addons/Builds_Windows/OPTCGSim_Data/StreamingAssets/`

You already have:
- `TRANSLATION.txt` (UI strings, log text, some action prompts)
- `Cards/<SET>/<CODE>.(png|jpg)` (card images)
- `Playmats/*.png`
- `Decks/*.deck` (some starter decklists)

No special tools required.

## Tier 2: Unity asset bundles + C# gameplay logic (needs extraction)

Where it lives:
- `addons/Builds_Windows/OPTCGSim_Data/*.assets`
- `addons/Builds_Windows/OPTCGSim_Data/resources.assets` / `sharedassets*.assets`
- `addons/Builds_Windows/OPTCGSim_Data/Managed/Assembly-CSharp.dll` (game logic)

### Recommended tools

**Unity assets / scenes / prefabs**
- AssetRipper (recommended) — export assets + scenes + prefabs into readable formats
- AssetStudio — browse assets, export textures, TextAssets, etc.

**C# code (rules/mechanics implementation)**
- dnSpyEx or ILSpy — decompile `Managed/Assembly-CSharp.dll` and inspect gameplay code

**Optional / programmatic extraction**
- UnityPy (Python) — programmatically read Unity `*.assets` and export things (more effort)

### What we can get from these

- Field layout references (Unity scenes/prefabs)
- Rules/mechanics state machine logic (turn phases, trigger resolution, counter step, etc.)
- Any embedded decklists/text assets not present in StreamingAssets

## Safety note

These tools are for inspecting your locally installed build to understand data formats and to create compatible systems. Avoid redistributing extracted proprietary content.
