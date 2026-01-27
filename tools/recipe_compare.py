#!/usr/bin/env python3
"""
Recipe Comparison Tool for OharaTCG

Compares recipe files (data/recipes/) against scraped/API card data.
Outputs a JSON report that Godot can read and display.

Run from project root:
    python tools/recipe_compare.py

Output: output/reports/recipe_comparison.json
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Any, Optional
from datetime import datetime

class RecipeComparer:
    def __init__(self, project_root: Optional[Path] = None):
        self.project_root = project_root or Path(__file__).resolve().parents[1]
        self.recipes_dir = self.project_root / 'data' / 'recipes'
        self.output_dir = self.project_root / 'output' / 'reports'
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
    def load_recipe(self, recipe_file: Path) -> Dict[str, int]:
        """Load a recipe file and return card_code -> quantity mapping."""
        quantities = {}
        try:
            with open(recipe_file, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    match = re.match(r'^(\d+)x(.+)$', line)
                    if match:
                        qty = int(match.group(1))
                        card_code = match.group(2).strip().upper()
                        quantities[card_code] = qty
        except Exception as e:
            print(f"Error loading {recipe_file}: {e}")
        return quantities
    
    def load_all_recipes(self) -> Dict[str, Dict[str, int]]:
        """Load all recipe files. Returns deck_id -> {card_code: qty}"""
        recipes = {}
        for recipe_file in sorted(self.recipes_dir.glob('*.txt')):
            deck_id = recipe_file.stem
            recipes[deck_id] = self.load_recipe(recipe_file)
        return recipes
    
    def load_scraped_cards(self) -> Dict[str, Dict[str, Any]]:
        """Load all scraped card data from output/ recursively."""
        cards = {}
        
        # Load from all JSON files in output directory recursively
        output_dir = self.project_root / 'output'
        if output_dir.exists():
            for json_file in output_dir.rglob('*.json'):
                # Skip report files and non-card data
                if 'report' in json_file.name.lower() or 'comparison' in json_file.name.lower():
                    continue
                if 'mechanics' in json_file.name.lower() or 'terms' in json_file.name.lower():
                    continue
                    
                try:
                    with open(json_file, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                        
                        # Handle different JSON structures
                        card_list = []
                        if isinstance(data, dict):
                            if 'cards' in data:
                                card_list = data.get('cards', [])
                            elif 'main' in data:
                                # Godot deck format
                                card_list = data.get('main', [])
                        elif isinstance(data, list):
                            card_list = data
                        
                        for card in card_list:
                            if isinstance(card, dict):
                                code = self._get_card_code(card)
                                if code and code not in cards:
                                    cards[code] = card
                except Exception as e:
                    # Silently skip invalid JSON files
                    pass
        
        return cards
    
    def _get_card_code(self, card: Dict[str, Any]) -> str:
        """Get normalized card code from card data."""
        code = card.get('card_code', '')
        if not code:
            set_code = card.get('set_code', '')
            number = card.get('number', '')
            if set_code and number:
                code = f"{set_code}-{number}"
        return code.upper() if code else ''
    
    def load_exported_deck(self, deck_id: str) -> Dict[str, int]:
        """Load exported deck JSON and return card_code -> count mapping."""
        deck_file = self.project_root / 'output' / 'decks' / f"{deck_id}.json"
        counts = {}
        
        if not deck_file.exists():
            # Try data/decks as fallback
            deck_file = self.project_root / 'data' / 'decks' / f"{deck_id}.json"
        
        if deck_file.exists():
            try:
                with open(deck_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    for card in data.get('main', []):
                        code = self._get_card_code(card)
                        if code:
                            counts[code] = card.get('count', 1)
            except Exception:
                pass
        
        return counts

    def compare_deck(self, deck_id: str, recipe: Dict[str, int], scraped_cards: Dict[str, Dict[str, Any]]) -> Dict[str, Any]:
        """Compare a single deck recipe against scraped data."""
        differences = {
            'deck_id': deck_id,
            'recipe_total': sum(recipe.values()),
            'missing_from_api': [],      # Cards in recipe but not found in scraped data
            'count_mismatches': [],       # Cards where exported counts don't match recipe
            'data_changes': [],           # Cards where name/effect/stats differ
            'extra_in_api': [],           # Cards in API for this set but not in recipe
            'status': 'ok'
        }
        
        # Load exported deck for count comparison
        exported_counts = self.load_exported_deck(deck_id)
        
        # Get set prefix variations for matching
        set_prefixes = self._get_set_prefixes(deck_id)
        
        # Check each card in recipe
        for card_code, recipe_qty in recipe.items():
            normalized_code = card_code.replace('-', '').upper()
            
            # Find matching card in scraped data
            scraped_card = None
            for code, card in scraped_cards.items():
                if code.replace('-', '').upper() == normalized_code:
                    scraped_card = card
                    break
            
            if not scraped_card:
                differences['missing_from_api'].append({
                    'card_code': card_code,
                    'recipe_qty': recipe_qty,
                    'reason': 'Card not found in scraped data'
                })
            else:
                # Check count mismatches against exported deck
                exported_qty = exported_counts.get(card_code.upper(), 0)
                if exported_qty == 0:
                    # Try normalized code
                    for exp_code, exp_qty in exported_counts.items():
                        if exp_code.replace('-', '').upper() == normalized_code:
                            exported_qty = exp_qty
                            break
                
                if exported_qty > 0 and exported_qty != recipe_qty:
                    differences['count_mismatches'].append({
                        'card_code': card_code,
                        'recipe_qty': recipe_qty,
                        'exported_qty': exported_qty,
                        'name': scraped_card.get('name', 'Unknown')
                    })
        
        # Find cards in API that are in this set but not in recipe
        for code, card in scraped_cards.items():
            card_set = card.get('set_code', '').replace('-', '').upper()
            if card_set in set_prefixes:
                normalized_code = code.replace('-', '').upper()
                recipe_has_it = any(
                    rc.replace('-', '').upper() == normalized_code 
                    for rc in recipe.keys()
                )
                if not recipe_has_it:
                    differences['extra_in_api'].append({
                        'card_code': code,
                        'name': card.get('name', 'Unknown'),
                        'type': card.get('type', 'Unknown')
                    })
        
        # Set status
        if differences['missing_from_api'] or differences['extra_in_api'] or differences['count_mismatches']:
            differences['status'] = 'differences_found'
        
        return differences
    
    def _get_set_prefixes(self, deck_id: str) -> set:
        """Get possible set prefixes for a deck ID."""
        prefixes = set()
        # ST-01, ST01, ST-01.2 etc
        base = deck_id.split('.')[0].replace('-', '').upper()
        prefixes.add(base)
        # Also add with hyphen normalized
        if '-' in deck_id:
            prefixes.add(deck_id.split('.')[0].upper())
        return prefixes
    
    def compare_all(self) -> Dict[str, Any]:
        """Compare all recipes against scraped data."""
        print("Loading recipes...")
        recipes = self.load_all_recipes()
        print(f"  Found {len(recipes)} recipe files")
        
        print("Loading scraped card data...")
        scraped_cards = self.load_scraped_cards()
        print(f"  Found {len(scraped_cards)} cards in scraped data")
        
        report = {
            'timestamp': datetime.now().isoformat(),
            'recipe_count': len(recipes),
            'scraped_card_count': len(scraped_cards),
            'decks': {},
            'summary': {
                'total_missing': 0,
                'total_extra': 0,
                'decks_with_issues': []
            }
        }
        
        print("\nComparing decks...")
        for deck_id, recipe in sorted(recipes.items()):
            diff = self.compare_deck(deck_id, recipe, scraped_cards)
            report['decks'][deck_id] = diff
            
            if diff['status'] != 'ok':
                report['summary']['decks_with_issues'].append(deck_id)
                report['summary']['total_missing'] += len(diff['missing_from_api'])
                report['summary']['total_extra'] += len(diff['extra_in_api'])
                
                status_icon = "!" if diff['missing_from_api'] else "+"
                print(f"  {status_icon} {deck_id}: {len(diff['missing_from_api'])} missing, {len(diff['extra_in_api'])} extra")
            else:
                print(f"  ✓ {deck_id}: OK")
        
        return report
    
    def save_report(self, report: Dict[str, Any]) -> Path:
        """Save comparison report to JSON file."""
        output_file = self.output_dir / 'recipe_comparison.json'
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
        return output_file
    
    def run(self) -> Path:
        """Run full comparison and save report."""
        report = self.compare_all()
        output_file = self.save_report(report)
        
        print(f"\n{'='*50}")
        print(f"SUMMARY")
        print(f"{'='*50}")
        print(f"Recipes checked: {report['recipe_count']}")
        print(f"Cards in API: {report['scraped_card_count']}")
        print(f"Decks with issues: {len(report['summary']['decks_with_issues'])}")
        print(f"Total missing cards: {report['summary']['total_missing']}")
        print(f"Total extra cards: {report['summary']['total_extra']}")
        print(f"\nReport saved to: {output_file}")
        
        return output_file


if __name__ == '__main__':
    comparer = RecipeComparer()
    comparer.run()
