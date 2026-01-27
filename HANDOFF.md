# OharaTCG — Full Handoff for Continuing in ChatGPT (2026-01-27)

Use this file as a “single prompt” you can paste into ChatGPT (browser) so it can continue work on this repo without VS Code prompts.

Project folder: `D:/DEVELOPMENT/Files/OharaTCG`
Engine: Godot 4.6.rc2

---

## 1) What the game/app is
OharaTCG is a Godot project centered around an OPTCG-style deck experience:

- A **menu flow** (Login → PostLogin → DeckSelection → DeckEdit)
- A **Deck Selection** screen that shows deck “tiles/panels” (starter/meta/custom) and opens a chosen deck
- A **Deck Editor** screen where you search cards, drag/drop cards into zones, stack cards, and manage decks
- A tooling pipeline (Python scripts) for syncing card images, building catalogs, importing decks, and validating assets

The UI scale is very large (`gui/theme/custom_constant/ui_scale=9.0`), which can amplify layout overlaps.

---

## 2) How navigation is supposed to work

Main scene: `res://scenes/Main.tscn` (uid `uid://cfqu7c3fgy2vg`)

- `Main.tscn` contains:
  - a Background instance
  - `UIContainer` with script `res://scripts/ui/UIManager.gd`
- `UIManager.gd` is responsible for swapping UI scenes.
- Normal flow:
  - `UIManager._ready()` loads `res://scenes/ui/Login.tscn`
  - Login → PostLogin
  - PostLogin button “Decks” loads DeckSelection
  - DeckSelection tile click loads DeckEdit

Back behavior requirements:
- DeckSelection Back → PostLogin (main menu)
- DeckEdit Back → DeckSelection

---

## 3) Deck + image pipeline goals (older, still valid)
Goal: ensure deck editor only loads valid decks and card images resolve cleanly.

Deck rules:
- Main contains exactly **1 Leader + 50 non-leader** (total main = 51)
- Don deck contains **10 DON!!**

Earlier work already added/updated:
- Deck dropdown validation/disable for invalid decks in `scripts/decks/Decks.gd`
- Image resolution handles variant suffixes (like `_R1`, `_P1`) in `scripts/decks/DeckManager.gd`
- Import decks tooling and validation scripts

See previous handoff section “Deck Editor + Images” history below (kept for completeness).

---

## 4) Biggest UI/input problems we fought
Two repeated blockers:

### A) “Nothing works” clicking UI
Symptoms:
- In DeckSelection: clicking tiles or Back sometimes did nothing (or had no visible effect)
- In DeckEdit: top header buttons (Back/Rename/Save/Delete/Export/Clear Deck) were reported as not responding

What we found & fixed:
- The background scene could intercept clicks if it sits above UI; `scenes/Background.tscn` now ignores mouse:
  - Root Control: `mouse_filter = IGNORE`
  - ColorOverlay ColorRect: `mouse_filter = IGNORE`

- DeckSelection previously assumed its parent was the UI manager.
  - In some runs the UIManager node wasn’t found at `get_parent()` or even at `Main/UIContainer`, so it errored:
    - `ERROR: DeckSelection: UIManager not found for DeckEdit`
  - Fix: DeckSelection now falls back to `get_tree().change_scene_to_file(...)` if UIManager doesn’t exist.
  - File: `scripts/decks/DeckSelection.gd`

- DeckEdit header buttons were likely unclickable because DeckField (drag-drop field) was “on top” of them.
  - Fix: raise HeaderBar and the filter/search control via `z_index` above the DeckField.
  - File: `scenes/DeckEdit.tscn`

### B) Deck name dropdown overlaps the Starter/Meta/Custom dropdown
Symptoms:
- Deck dropdown (deck name list) visually overlapped the StarterToggle next to it.

What we fixed:
- Hard-shrunk the `DeckDropdown` width in `scenes/DeckEdit.tscn` via `offset_right`.
- Then made it robust at runtime (no pixel guessing): `Decks.gd` now auto-sizes deck dropdown so its right edge never crosses the StarterToggle.
  - File: `scripts/decks/Decks.gd` (function `_fix_header_overlap()` called deferred).

---

## 5) Card stacking issue (split stack won’t merge back)
Symptom:
- When splitting a stack of cards in the main deck, you could not merge it back.

Fix applied:
- Updated stack merge logic in `addons/smart_drag_drop/field/deck_field.gd` to allow merging back into main deck even when drag started inside main deck.

---

## 6) Key files to know (UI)

Navigation and UI root:
- `scenes/Main.tscn`
- `scripts/ui/UIManager.gd`
- `scenes/ui/Login.tscn` + `scripts/ui/Login.gd`
- `scenes/ui/PostLogin.tscn` + `scripts/ui/PostLogin.gd`

Deck selection:
- `scenes/DeckSelection.tscn`
- `scripts/decks/DeckSelection.gd`
- Deck tile prefab: `scenes/ui/DeckItem.tscn`
- Deck tile scripts: `scripts/decks/DeckItem.gd`, `scripts/decks/DeckItemOutline.gd`

Deck edit:
- `scenes/DeckEdit.tscn`
- `scripts/decks/Decks.gd` (large file; owns most deck editor behaviors)

Always-on autoloads (from `project.godot`):
- `Background` (scene)
- `ChatManager` (script)
- `DeckManager`, `Don`, `AltArtManager`, `CardDataHelper`, `CardTweenManager`, `AutoUpdate`

---

## 7) Key files to know (drag/drop + cards)

Addon state machine:
- `addons/smart_drag_drop/card/card.gd`
- `addons/smart_drag_drop/field/deck_field.gd`
- state machine scripts under `addons/smart_drag_drop/card/state_machine/...`

Alt-art behavior:
- `scripts/decks/AltArtManager.gd` uses `_unhandled_input` for middle mouse alt-art dragging (should not block left click).

---

## 8) What’s still to do / watchouts

UI/UX TODOs (not fully re-verified after latest fixes):
- Search cards centering / name overlap near selector in DeckEdit (reported by user early in `To Do.md`).
- Confirm all DeckEdit header buttons now work after raising z_index above DeckField.
- Confirm DeckSelection tile click and Back work in both cases:
  - launched from Main flow (UIManager present)
  - running DeckSelection as the “play scene” standalone (no UIManager)

Noise in console:
- There are lots of prints like `current state Hover/Idle/Drag/Release` from the drag state machine.
  - These are debug spam and can hide real errors.

---

## 9) “Paste into ChatGPT” prompt template
If you’re using ChatGPT browser, paste something like:

"""
You are continuing work on a Godot 4.6 project (OharaTCG). Read HANDOFF.md fully.

Immediate tasks:
1) Ensure DeckSelection tiles always open DeckEdit and Back always returns to PostLogin.
2) Ensure DeckEdit header buttons (Back/Rename/Save/Delete/Export/Clear Deck) are clickable.
3) Ensure deck name dropdown never overlaps Starter/Meta/Custom dropdown.

Constraints:
- Keep the existing strict anchored layout (do not refactor into new container layouts unless required).
- Prefer small, surgical changes.

When proposing changes, always name the exact file paths and node names.
"""

---

## 10) History: Deck Editor + Images (kept from earlier handoff)

### Starter deck JSONs
- `data/decks/ST-01..ST-28.json` and `output/decks/starter/ST-01..ST-28.json` exist, but many were incomplete.
- Quick audit showed:
  - **ST-01..ST-05**: valid (51 total in main + 10 DON)
  - **ST-06..ST-28**: incomplete (main totals far below 51)

### .deck sources
- Only 5 `.deck` files exist (ST01–ST05) under `addons/Builds_Windows/Decks/`.

### Image resolution improvements
- `_resolve_card_image_path()` handles codes with `_` suffix by trying base code too.

### Importer improvements
- `tools/import_optcgsim_decks.py` supports `--dest` and `--also`.

### Deck image audits
- `python tools/validate_deck_images.py` writes reports under `output/reports/`.

