# Deck recipe inputs (counts)

Paste starter deck recipes here (with quantities). These files are consumed by:

- `python tools/import_deck_recipe_text.py --input data/recipes/ ...`

## Supported formats
Any mix of these per line:

- `4xST06-010`
- `4 x ST06-010`
- `ST06-010 x4`
- `ST06-010 4`
- `ST06-010` (defaults to 1; repeated lines accumulate)

You can also paste a JSON array export containing repeated card codes:

- `["Exported from ...", "ST06-010", "ST06-010", ...]`

## Tips
- Don’t include DON!! lines; the importer always forces `DON!!` to exactly 10.
- The importer validates: 1 Leader + 50 non-leader cards (51 total) + 10 DON.

## Common commands
Dry-run (report only):

- `python tools/import_deck_recipe_text.py --input data/recipes/ST-06.txt --deck-id ST-06`

Write JSON into both `data/` and `output/`:

- `python tools/import_deck_recipe_text.py --input data/recipes/ --write --dest data --also output`

If you need to write even when totals don’t match yet:

- `python tools/import_deck_recipe_text.py --input data/recipes/ST-06.txt --deck-id ST-06 --write --allow-invalid`
