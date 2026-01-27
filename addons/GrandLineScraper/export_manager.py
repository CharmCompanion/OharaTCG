import json
import csv
import os
import re
import sqlite3
import zipfile
from pathlib import Path
from typing import Dict, List, Any, Optional
from datetime import datetime
import streamlit as st
from game_mechanics import GameMechanicsExtractor

class ExportManager:
    """Manage data export in various formats"""
    
    def __init__(
        self,
        output_dir: str,
        project_root: Optional[Path] = None,
        auto_copy_decks: bool = False,
        export_complete_deck_json: bool = False,
    ):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.project_root = project_root or Path(__file__).resolve().parents[2]
        self.auto_copy_decks = auto_copy_decks
        self.export_complete_deck_json = export_complete_deck_json
        
        # Create organized folder structure
        self._create_export_structure()
    
    def export_data(self, processed_data: Dict[str, Any], export_format: str) -> List[str]:
        """Export processed data in organized folder structure"""
        exported_files = []
        
        # Export organized by sets
        set_files = self._export_organized_sets(processed_data, export_format)
        exported_files.extend(set_files)
        
        # Export organized decks 
        deck_files = self._export_organized_decks(processed_data)
        exported_files.extend(deck_files)
        
        # Export databases
        database_files = self._export_databases(processed_data)
        exported_files.extend(database_files)
        
        # Create bulk download packages
        bulk_files = self._create_bulk_packages(processed_data, export_format)
        exported_files.extend(bulk_files)
        
        # Export Godot-specific files
        godot_files = self._export_godot_format(processed_data)
        exported_files.extend(godot_files)
        
        # Export archetype/keyword database for Godot search filters
        archetype_files = self._export_archetype_database(processed_data)
        exported_files.extend(archetype_files)

        # Export banlist filters for room rules
        banlist_files = self._export_banlist_filters(processed_data)
        exported_files.extend(banlist_files)
        
        # Export recipe format (.txt deck lists)
        recipe_files = self._export_recipes(processed_data)
        exported_files.extend(recipe_files)
        
        # Export game mechanics database for dueling
        mechanics_files = self._export_game_mechanics(processed_data)
        exported_files.extend(mechanics_files)
        
        return exported_files
    
    def _create_export_structure(self):
        """Create organized export folder structure by card category"""
        # Main category folders matching card types
        folders = [
            'sets',
            'decks',
            'promos',
            'tournaments',
            'don',
            'alt_arts',
            'databases',
            'bulk'
        ]
        
        for folder in folders:
            (self.output_dir / folder).mkdir(parents=True, exist_ok=True)
    
    def _export_organized_sets(self, data: Dict[str, Any], export_format: str) -> List[str]:
        """Export sets in organized folder structure"""
        exported_files = []
        cards = data.get('cards', [])
        
        # Group cards by set
        sets_organized = self._organize_cards_by_set(cards)

        for set_id in self._sorted_set_ids(list(sets_organized.keys())):
            set_cards = sets_organized.get(set_id, [])
            if not set_id or not set_cards:
                continue

            set_cards = self._sort_cards_within_set(set_cards)
                
            # Determine set category and folder
            folder_path = self._get_set_folder_path(set_id)
            folder_path.mkdir(parents=True, exist_ok=True)
            
            # Export JSON if requested
            if export_format in ['JSON', 'Both']:
                json_file = folder_path / f"{set_id}.json"
                with open(json_file, 'w', encoding='utf-8') as f:
                    json.dump({
                        'set_id': set_id,
                        'set_name': self._get_set_name(set_id),
                        'cards': set_cards,
                        'card_count': len(set_cards),
                        'export_timestamp': datetime.now().isoformat()
                    }, f, ensure_ascii=False, indent=2)
                exported_files.append(str(json_file))
            
            # Export CSV if requested
            if export_format in ['CSV', 'Both']:
                csv_file = folder_path / f"{set_id}.csv"
                self._write_cards_csv(set_cards, csv_file)
                exported_files.append(str(csv_file))
        
        return exported_files
    
    def _export_organized_decks(self, data: Dict[str, Any]) -> List[str]:
        """Export deck files in organized structure.
        
        Uses recipe files from data/decks/recipes/ as the source of truth for deck compositions.
        Recipe files are NEVER modified - they serve as hard backups for cross-checking.
        """
        exported_files = []
        
        # Export starter decks
        starter_decks = self._extract_starter_decks(data.get('cards', []))
        decks_folder = self.output_dir / 'decks'
        decks_folder.mkdir(parents=True, exist_ok=True)
        
        # Build card lookup by card_code for fast access
        card_lookup = self._build_card_lookup(data.get('cards', []))
        
        for deck_id in sorted(starter_decks.keys(), key=self._deck_sort_key):
            deck_info = starter_decks[deck_id]
            
            # Load recipe quantities from data/decks/recipes/ (NEVER modified)
            recipe_quantities = self._load_recipe_from_file(deck_id)
            
            # YDL file for dueling simulators
            ydl_file = decks_folder / f"{deck_id}.ydl"
            with open(ydl_file, 'w', encoding='utf-8') as f:
                f.write(self._format_deck_list_from_recipe(deck_info, recipe_quantities, card_lookup))
            exported_files.append(str(ydl_file))
            
            # Optional JSON file with complete deck info (can be very noisy across runs)
            if self.export_complete_deck_json:
                json_file = decks_folder / f"{deck_id}_complete.json"

                # Get all cards from the deck (main_deck + don_cards + life_cards)
                all_deck_cards = deck_info.get('main_deck', []) + deck_info.get('don_cards', []) + deck_info.get('life_cards', [])

                with open(json_file, 'w', encoding='utf-8') as f:
                    json.dump({
                        'deck_id': deck_id,
                        'name': deck_info.get('name', deck_id),
                        'main_deck': deck_info.get('main_deck', []),
                        'don_cards': deck_info.get('don_cards', []),
                        'life_cards': deck_info.get('life_cards', []),
                        'total_cards': len(all_deck_cards),
                        'theme': deck_info.get('theme', ''),
                        'colors': deck_info.get('colors', []),
                        'is_ultra_deck': deck_info.get('is_ultra_deck', False),
                        'export_timestamp': datetime.now().isoformat()
                    }, f, ensure_ascii=False, indent=2)
                exported_files.append(str(json_file))

            # Godot-friendly deck file with proper quantities from recipe
            godot_file = decks_folder / f"{deck_id}.json"
            godot_main = []
            
            # If we have recipe quantities, use them; otherwise fall back to API data
            if recipe_quantities:
                # Build deck from recipe quantities + card lookup
                for card_code, qty in sorted(recipe_quantities.items(), key=lambda x: self._recipe_card_sort_key(x[0])):
                    card_data = card_lookup.get(card_code.upper())
                    if not card_data:
                        # Try without hyphen normalization
                        card_data = card_lookup.get(card_code.replace('-', '').upper())
                    
                    if card_data:
                        card_type = card_data.get('type', '')
                        zone = 'main'
                        if card_type == 'Leader':
                            zone = 'main'  # Leader goes in main but count is always 1
                            qty = 1
                        
                        godot_main.append({
                            'id': card_data.get('id'),
                            'name': card_data.get('name'),
                            'type': card_type,
                            'color': card_data.get('colors', []),
                            'cost': card_data.get('cost', 0),
                            'power': card_data.get('power', 0),
                            'life': card_data.get('life', 0),
                            'counter': card_data.get('counter', 0),
                            'rarity': card_data.get('rarity', ''),
                            'attribute': card_data.get('attribute', ''),
                            'traits': card_data.get('traits', []),
                            'effect': card_data.get('effect', ''),
                            'set_code': card_data.get('set_code', ''),
                            'number': card_data.get('number', ''),
                            'card_code': card_code,
                            'count': qty,
                            'zone': zone
                        })
                    else:
                        # Card not found in API data - add placeholder
                        godot_main.append({
                            'id': card_code,
                            'name': f"Unknown ({card_code})",
                            'type': 'Unknown',
                            'color': [],
                            'cost': 0,
                            'power': 0,
                            'life': 0,
                            'counter': 0,
                            'rarity': '',
                            'attribute': '',
                            'traits': [],
                            'effect': '',
                            'set_code': '',
                            'number': '',
                            'card_code': card_code,
                            'count': qty,
                            'zone': 'main'
                        })
            else:
                # No recipe file - fall back to API data (original behavior)
                leader_data = deck_info.get('leader')
                if leader_data:
                    leader_code = leader_data.get('card_code')
                    leader_set_code = leader_data.get('set_code')
                    leader_number = leader_data.get('number', '')
                    if not leader_code and leader_set_code and leader_number:
                        leader_code = f"{leader_set_code}-{leader_number}"
                    godot_main.append({
                        'id': leader_data.get('id'),
                        'name': leader_data.get('name'),
                        'type': leader_data.get('type'),
                        'color': leader_data.get('colors', []),
                        'cost': leader_data.get('cost', 0),
                        'power': leader_data.get('power', 0),
                        'life': leader_data.get('life', 0),
                        'counter': leader_data.get('counter', 0),
                        'rarity': leader_data.get('rarity', ''),
                        'attribute': leader_data.get('attribute', ''),
                        'traits': leader_data.get('traits', []),
                        'effect': leader_data.get('effect', ''),
                        'set_code': leader_set_code,
                        'number': leader_number,
                        'card_code': leader_code,
                        'count': 1,
                        'zone': 'main'
                    })
                
                for card in deck_info.get('main_deck', []):
                    card_code = card.get('card_code')
                    set_code = card.get('set_code')
                    number = card.get('number', '')
                    if not card_code and set_code and number:
                        card_code = f"{set_code}-{number}"

                    godot_main.append({
                        'id': card.get('id'),
                        'name': card.get('name'),
                        'type': card.get('type'),
                        'color': card.get('colors', []),
                        'cost': card.get('cost', 0),
                        'power': card.get('power', 0),
                        'life': card.get('life', 0),
                        'counter': card.get('counter', 0),
                        'rarity': card.get('rarity', ''),
                        'attribute': card.get('attribute', ''),
                        'traits': card.get('traits', []),
                        'effect': card.get('effect', ''),
                        'set_code': set_code,
                        'number': number,
                        'card_code': card_code,
                        'count': card.get('copies', 1),
                        'zone': 'main'
                    })

            don_grouped = {}
            for card in deck_info.get('don_cards', []):
                code = card.get('card_code')
                set_code = card.get('set_code')
                number = card.get('number', '')
                if not code and set_code and number:
                    code = f"{set_code}-{number}"

                if code == "":
                    code = "DON!!"

                if code not in don_grouped:
                    card_copy = dict(card)
                    card_copy['copies'] = int(card.get('copies', 1))
                    don_grouped[code] = card_copy
                else:
                    don_grouped[code]['copies'] += int(card.get('copies', 1))

            godot_don = []
            for card in don_grouped.values():
                don_code = card.get('card_code', '')
                don_set_code = card.get('set_code', '')
                don_number = card.get('number', '')
                if not don_code and don_set_code and don_number:
                    don_code = f"{don_set_code}-{don_number}"

                godot_don.append({
                    'id': card.get('id'),
                    'name': card.get('name', 'DON!!'),
                    'type': card.get('type', 'DON!!'),
                    'color': card.get('colors', []),
                    'cost': card.get('cost', 0),
                    'power': card.get('power', 0),
                    'life': card.get('life', 0),
                    'counter': card.get('counter', 0),
                    'rarity': card.get('rarity', ''),
                    'attribute': card.get('attribute', ''),
                    'traits': card.get('traits', []),
                    'effect': card.get('effect', ''),
                    'set_code': don_set_code,
                    'number': don_number,
                    'card_code': don_code if don_code else 'DON!!',
                    'count': int(card.get('copies', 1)),
                    'zone': 'don'
                })

            if not godot_don:
                godot_don.append({
                    'id': 'DON!!',
                    'name': 'DON!!',
                    'type': 'DON!!',
                    'color': [],
                    'cost': 0,
                    'power': 0,
                    'life': 0,
                    'counter': 0,
                    'rarity': '',
                    'attribute': '',
                    'traits': [],
                    'effect': '',
                    'set_code': 'DON',
                    'number': '001',
                    'card_code': 'DON!!',
                    'count': 10,
                    'zone': 'don'
                })

            with open(godot_file, 'w', encoding='utf-8') as f:
                json.dump({
                    'main': godot_main,
                    'don': godot_don
                }, f, ensure_ascii=False, indent=2)
            exported_files.append(str(godot_file))

        if self.auto_copy_decks:
            self._copy_starter_decks_to_project()
        
        return exported_files

    def _export_recipes(self, data: Dict[str, Any]) -> List[str]:
        """Export starter decks in recipe format (.txt files matching data/recipes format)
        
        Recipe format:
        - Line 1: # <Deck Name> recipe
        - Lines 2+: <count>x<card_code> (e.g., 4xST01-002)
        """
        exported_files = []
        
        starter_decks = self._extract_starter_decks(data.get('cards', []))
        recipes_folder = self.output_dir / 'decks'
        recipes_folder.mkdir(parents=True, exist_ok=True)
        
        for deck_id in sorted(starter_decks.keys(), key=self._deck_sort_key):
            deck_info = starter_decks[deck_id]
            recipe_file = recipes_folder / f"{deck_id}.txt"
            
            lines = []
            deck_name = deck_info.get('name', deck_id)
            lines.append(f"# {deck_name} recipe")
            
            card_counts: Dict[str, int] = {}
            
            leader = deck_info.get('leader')
            if leader:
                card_code = self._get_recipe_card_code(leader)
                if card_code:
                    card_counts[card_code] = card_counts.get(card_code, 0) + 1
            
            for card in deck_info.get('main_deck', []):
                card_code = self._get_recipe_card_code(card)
                if card_code:
                    copies = int(card.get('copies', 1))
                    card_counts[card_code] = card_counts.get(card_code, 0) + copies
            
            sorted_codes = sorted(card_counts.keys(), key=self._recipe_card_sort_key)
            for card_code in sorted_codes:
                count = card_counts[card_code]
                lines.append(f"{count}x{card_code}")
            
            with open(recipe_file, 'w', encoding='utf-8') as f:
                f.write('\n'.join(lines) + '\n')
            exported_files.append(str(recipe_file))
        
        if exported_files:
            st.write(f"✅ Exported {len(exported_files)} deck recipes")
        
        return exported_files
    
    def _get_recipe_card_code(self, card: Dict[str, Any]) -> str:
        """Get card code in recipe format (e.g., ST01-002)"""
        card_code = card.get('card_code', '')
        if card_code:
            return card_code.replace('-', '').upper() if '-' not in card_code else card_code
        
        set_code = card.get('set_code', '')
        number = card.get('number', '')
        if set_code and number:
            return f"{set_code}-{number}"
        
        return ''
    
    def _recipe_card_sort_key(self, card_code: str):
        """Sort cards in recipe format: Leaders first, then by set, then by number"""
        match = re.match(r'^([A-Z]+)-?(\d+)-(\d+)$', card_code.upper())
        if match:
            prefix, set_num, card_num = match.groups()
            is_leader = card_num == '001'
            return (0 if is_leader else 1, prefix, int(set_num), int(card_num))
        return (2, card_code, 0, 0)

    def _load_recipe_from_file(self, deck_id: str) -> Dict[str, int]:
        """Load a recipe from data/decks/recipes/ and return card_code -> quantity mapping.
        
        These files are the user's hard backups and are NEVER modified by the export system.
        Returns empty dict if recipe file doesn't exist.
        """
        recipes_dir = self.project_root / 'data' / 'recipes'
        recipe_file = recipes_dir / f"{deck_id}.txt"
        
        if not recipe_file.exists():
            return {}
        
        card_quantities: Dict[str, int] = {}
        try:
            with open(recipe_file, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    # Parse format: 4xST01-002 or 4xST01002
                    match = re.match(r'^(\d+)x(.+)$', line)
                    if match:
                        qty = int(match.group(1))
                        card_code = match.group(2).strip()
                        # Normalize card code (ensure hyphen format like ST01-002)
                        normalized = self._normalize_card_code(card_code)
                        card_quantities[normalized] = qty
        except Exception as e:
            st.warning(f"Failed to load recipe {deck_id}: {e}")
        
        return card_quantities

    def _normalize_card_code(self, card_code: str) -> str:
        """Normalize card code to standard format (e.g., ST01-002)"""
        # Already has hyphen in correct format
        if re.match(r'^[A-Z]+-?\d+-\d+$', card_code.upper()):
            return card_code.upper()
        # Format like ST01002 -> ST01-002
        match = re.match(r'^([A-Z]+)(\d{2})(\d{3})$', card_code.upper())
        if match:
            return f"{match.group(1)}{match.group(2)}-{match.group(3)}"
        return card_code.upper()

    def _build_card_lookup(self, cards: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
        """Build a lookup dictionary from card_code -> card data for fast access."""
        lookup = {}
        for card in cards:
            # Get card code in various formats
            card_code = card.get('card_code', '')
            set_code = card.get('set_code', '')
            number = card.get('number', '')
            
            if not card_code and set_code and number:
                card_code = f"{set_code}-{number}"
            
            if card_code:
                # Store with normalized format (uppercase with hyphen)
                normalized = card_code.upper()
                lookup[normalized] = card
                
                # Also store without hyphen for fallback lookups
                no_hyphen = normalized.replace('-', '')
                if no_hyphen not in lookup:
                    lookup[no_hyphen] = card
        
        return lookup

    def _format_deck_list_from_recipe(
        self, 
        deck_info: Dict[str, Any], 
        recipe_quantities: Dict[str, int],
        card_lookup: Dict[str, Dict[str, Any]]
    ) -> str:
        """Format deck list for YDL export using recipe quantities."""
        lines = []
        deck_name = deck_info.get('name', 'Unknown Deck')
        lines.append(f"# {deck_name}")
        lines.append("")
        
        if recipe_quantities:
            # Use recipe quantities as source of truth
            for card_code, qty in sorted(recipe_quantities.items(), key=lambda x: self._recipe_card_sort_key(x[0])):
                card_data = card_lookup.get(card_code.upper())
                if not card_data:
                    card_data = card_lookup.get(card_code.replace('-', '').upper())
                
                if card_data:
                    name = card_data.get('name', card_code)
                    lines.append(f"{qty}x {card_code} - {name}")
                else:
                    lines.append(f"{qty}x {card_code} - Unknown")
        else:
            # Fall back to original deck_info
            leader = deck_info.get('leader')
            if leader:
                code = self._get_recipe_card_code(leader)
                name = leader.get('name', 'Leader')
                lines.append(f"1x {code} - {name}")
            
            for card in deck_info.get('main_deck', []):
                code = self._get_recipe_card_code(card)
                name = card.get('name', 'Unknown')
                qty = card.get('copies', 1)
                lines.append(f"{qty}x {code} - {name}")
        
        # Add DON!! cards
        lines.append("")
        lines.append("# DON!! Deck")
        lines.append("10x DON!!")
        
        return '\n'.join(lines)

    def _export_game_mechanics(self, data: Dict[str, Any]) -> List[str]:
        """Export game mechanics database for dueling implementation"""
        exported_files = []
        cards = data.get('cards', [])
        
        if not cards:
            return exported_files
        
        try:
            extractor = GameMechanicsExtractor()
            mechanics_folder = self.output_dir / 'databases'
            mechanics_folder.mkdir(parents=True, exist_ok=True)
            
            mechanics_file = mechanics_folder / 'game_mechanics.json'
            exported_path = extractor.export_mechanics_database(cards, mechanics_file)
            exported_files.append(exported_path)
            
            dueling_terms_file = mechanics_folder / 'dueling_terms.json'
            dueling_terms = extractor.get_mechanics_for_dueling()
            with open(dueling_terms_file, 'w', encoding='utf-8') as f:
                import json
                json.dump(dueling_terms, f, ensure_ascii=False, indent=2)
            exported_files.append(str(dueling_terms_file))
            
        except Exception as e:
            st.warning(f"Failed to export game mechanics: {str(e)}")
        
        return exported_files

    def _copy_starter_decks_to_project(self) -> None:
        """Copy exported starter decks into res://data/decks for in-game use"""
        try:
            source_dir = self.output_dir / 'decks'
            target_dir = self.project_root / 'data' / 'decks'
            target_dir.mkdir(parents=True, exist_ok=True)

            if not source_dir.exists():
                return

            for file in source_dir.glob('*.json'):
                if file.name.endswith('_complete.json'):
                    continue
                target_path = target_dir / file.name
                target_path.write_bytes(file.read_bytes())

            st.write(f"✅ Auto-copied starter decks to {target_dir}")
        except Exception as e:
            st.warning(f"Failed to auto-copy starter decks: {str(e)}")
    
    def _export_databases(self, data: Dict[str, Any]) -> List[str]:
        """Export databases to dedicated folder"""
        exported_files = []
        databases_folder = self.output_dir / 'databases'
        
        # Create YGO Pro Percy database
        db_file = databases_folder / 'one_piece_dueling_database.db'
        self._create_sqlite_cdb_database(data, db_file)
        exported_files.append(str(db_file))
        
        # Create complete card database JSON
        complete_db = databases_folder / 'complete_card_database.json'
        with open(complete_db, 'w', encoding='utf-8') as f:
            json.dump({
                'metadata': data.get('metadata', {}),
                'cards': data.get('cards', []),
                'sets': data.get('sets', []),
                'total_cards': len(data.get('cards', [])),
                'export_timestamp': datetime.now().isoformat()
            }, f, ensure_ascii=False, indent=2)
        exported_files.append(str(complete_db))
        
        return exported_files
    
    def _create_bulk_packages(self, data: Dict[str, Any], export_format: str) -> List[str]:
        """Create bulk download packages"""
        exported_files = []
        bulk_folder = self.output_dir / 'bulk'
        
        # Complete package - everything in one JSON
        complete_file = bulk_folder / 'complete' / 'one_piece_tcg_complete.json'
        complete_file.parent.mkdir(parents=True, exist_ok=True)
        
        with open(complete_file, 'w', encoding='utf-8') as f:
            json.dump({
                'metadata': data.get('metadata', {}),
                'cards': data.get('cards', []),
                'sets': data.get('sets', []),
                'organized_by_set': self._organize_cards_by_set(data.get('cards', [])),
                'organized_by_type': self._organize_cards_by_type(data.get('cards', [])),
                'starter_decks': self._extract_starter_decks(data.get('cards', [])),
                'total_cards': len(data.get('cards', [])),
                'export_timestamp': datetime.now().isoformat()
            }, f, ensure_ascii=False, indent=2)
        exported_files.append(str(complete_file))
        
        # Sets-only package
        sets_file = bulk_folder / 'sets-only' / 'one_piece_tcg_sets_only.json'
        sets_file.parent.mkdir(parents=True, exist_ok=True)
        
        with open(sets_file, 'w', encoding='utf-8') as f:
            json.dump({
                'organized_by_set': self._organize_cards_by_set(data.get('cards', [])),
                'sets_metadata': data.get('sets', []),
                'export_timestamp': datetime.now().isoformat()
            }, f, ensure_ascii=False, indent=2)
        exported_files.append(str(sets_file))
        
        # Decks-only package
        decks_file = bulk_folder / 'decks-only' / 'one_piece_tcg_decks_only.json'
        decks_file.parent.mkdir(parents=True, exist_ok=True)
        
        with open(decks_file, 'w', encoding='utf-8') as f:
            json.dump({
                'starter_decks': self._extract_starter_decks(data.get('cards', [])),
                'export_timestamp': datetime.now().isoformat()
            }, f, ensure_ascii=False, indent=2)
        exported_files.append(str(decks_file))
        
        return exported_files
    
    def _export_archetype_database(self, data: Dict[str, Any]) -> List[str]:
        """Export comprehensive archetype/keyword database for Godot search filters"""
        exported_files = []
        cards = data.get('cards', [])
        
        if not cards:
            return exported_files
        
        # Extract all archetype keywords from multiple sources
        archetype_data = self._extract_all_archetypes(cards)
        
        # Create archetype folder
        archetype_folder = self.output_dir / 'archetypes'
        archetype_folder.mkdir(parents=True, exist_ok=True)
        
        # Export comprehensive archetype database
        archetype_file = archetype_folder / 'one_piece_tcg_archetypes.json'
        with open(archetype_file, 'w', encoding='utf-8') as f:
            json.dump(archetype_data, f, ensure_ascii=False, indent=2)
        exported_files.append(str(archetype_file))
        
        # Export simplified archetype list for easy integration
        simple_list_file = archetype_folder / 'archetype_keywords_list.json'
        with open(simple_list_file, 'w', encoding='utf-8') as f:
            json.dump({
                'all_keywords': sorted(archetype_data['all_unique_keywords']),
                'total_count': len(archetype_data['all_unique_keywords']),
                'export_timestamp': datetime.now().isoformat()
            }, f, ensure_ascii=False, indent=2)
        exported_files.append(str(simple_list_file))
        
        # Export archetype mapping for each card (for advanced filtering)
        mapping_file = archetype_folder / 'card_archetype_mapping.json'
        with open(mapping_file, 'w', encoding='utf-8') as f:
            json.dump(archetype_data['card_mappings'], f, ensure_ascii=False, indent=2)
        exported_files.append(str(mapping_file))
        
        st.write(f"✅ Exported {len(archetype_data['all_unique_keywords'])} unique archetype keywords")
        
        return exported_files

    def _export_banlist_filters(self, data: Dict[str, Any]) -> List[str]:
        """Export banlist filters for room rules"""
        exported_files = []
        cards = data.get('cards', [])

        if not cards:
            return exported_files

        banlist_path = self.project_root / 'assets' / 'JSON' / 'banned.json'
        if not banlist_path.exists():
            st.warning("Banlist file not found: assets/JSON/banned.json")
            return exported_files

        try:
            with open(banlist_path, 'r', encoding='utf-8') as f:
                banlist_data = json.load(f)

            banned_codes = [entry.get('code') for entry in banlist_data.get('banned', []) if entry.get('code')]
            restricted_codes = [entry.get('code') for entry in banlist_data.get('restricted', []) if entry.get('code')]

            all_codes = set()
            for card in cards:
                code = self._get_card_code_for_banlist(card)
                if code:
                    all_codes.add(code)

            banned_set = set(banned_codes)
            restricted_set = set(restricted_codes)
            allowed_set = all_codes.difference(banned_set)

            banlist_dir = self.output_dir / 'banlists'
            banlist_dir.mkdir(parents=True, exist_ok=True)

            rules_file = banlist_dir / 'banlist_rules.json'
            with open(rules_file, 'w', encoding='utf-8') as f:
                json.dump({
                    'generated_at': datetime.now().isoformat(),
                    'rule_sets': [
                        {
                            'id': 'all_allowed',
                            'name': 'All Cards Allowed',
                            'banned': [],
                            'restricted': []
                        },
                        {
                            'id': 'official',
                            'name': 'Official Banlist',
                            'banned': sorted(list(banned_set)),
                            'restricted': sorted(list(restricted_set))
                        }
                    ]
                }, f, ensure_ascii=False, indent=2)
            exported_files.append(str(rules_file))

            legal_file = banlist_dir / 'legal_cards_official.json'
            with open(legal_file, 'w', encoding='utf-8') as f:
                json.dump({
                    'rule_set': 'official',
                    'allowed_cards': sorted(list(allowed_set)),
                    'blocked_cards': sorted(list(banned_set)),
                    'restricted_cards': sorted(list(restricted_set)),
                    'generated_at': datetime.now().isoformat()
                }, f, ensure_ascii=False, indent=2)
            exported_files.append(str(legal_file))

        except Exception as e:
            st.warning(f"Failed to export banlist filters: {str(e)}")

        return exported_files

    def _get_card_code_for_banlist(self, card: Dict[str, Any]) -> str:
        """Resolve card code for banlist comparisons"""
        card_code = card.get('card_code')
        if card_code:
            return card_code

        set_code = card.get('set_code', '')
        number = card.get('number', '')
        if set_code and number:
            return f"{set_code}-{number}"

        return ''
    
    def _extract_all_archetypes(self, cards: List[Dict]) -> Dict[str, Any]:
        """Extract comprehensive archetype keywords from all card sources"""
        all_keywords = set()
        keyword_sources = {
            'traits': set(),
            'character_names': set(),
            'locations': set(),
            'organizations': set(),
            'abilities': set(),
            'colors': set(),
            'card_types': set(),
            'set_themes': set()
        }
        card_mappings = {}
        
        for card in cards:
            card_id = card.get('id', '')
            card_keywords = []
            
            # Extract from traits (primary source)
            traits = card.get('traits', [])
            if isinstance(traits, list):
                for trait in traits:
                    if trait and trait.strip():
                        clean_trait = trait.strip()
                        all_keywords.add(clean_trait)
                        keyword_sources['traits'].add(clean_trait)
                        card_keywords.append(clean_trait)
            
            # Extract character/organization names from card names
            name = card.get('name', '')
            if name:
                extracted_names = self._extract_character_organizations(name)
                for name_keyword in extracted_names:
                    all_keywords.add(name_keyword)
                    keyword_sources['character_names'].add(name_keyword)
                    card_keywords.append(name_keyword)
            
            # Extract from colors
            colors = card.get('colors', [])
            if isinstance(colors, list):
                for color in colors:
                    if color and color.strip():
                        clean_color = color.strip()
                        all_keywords.add(clean_color)
                        keyword_sources['colors'].add(clean_color)
                        card_keywords.append(clean_color)
            
            # Extract card types
            card_type = card.get('type', '')
            if card_type and card_type.strip():
                clean_type = card_type.strip()
                all_keywords.add(clean_type)
                keyword_sources['card_types'].add(clean_type)
                card_keywords.append(clean_type)
            
            # Extract from effect text (abilities and locations)
            effect = card.get('effect', '')
            if effect:
                effect_keywords = self._extract_effect_keywords(effect)
                for effect_keyword in effect_keywords:
                    all_keywords.add(effect_keyword)
                    keyword_sources['abilities'].add(effect_keyword)
                    card_keywords.append(effect_keyword)
            
            # Extract set themes
            set_name = card.get('set_name', '')
            if set_name:
                set_theme = self._extract_set_theme(set_name)
                if set_theme:
                    all_keywords.add(set_theme)
                    keyword_sources['set_themes'].add(set_theme)
                    card_keywords.append(set_theme)
            
            # Store card mapping
            if card_keywords:
                card_mappings[card_id] = {
                    'name': name,
                    'archetypes': sorted(list(set(card_keywords)))
                }
        
        # Convert sets to sorted lists for JSON serialization
        keywords_by_source = {}
        for source_type, keyword_set in keyword_sources.items():
            keywords_by_source[source_type] = sorted(list(keyword_set))
        
        return {
            'all_unique_keywords': sorted(list(all_keywords)),
            'total_keywords': len(all_keywords),
            'keywords_by_source': keywords_by_source,
            'card_mappings': card_mappings,
            'extraction_stats': {
                'total_cards_processed': len(cards),
                'cards_with_keywords': len(card_mappings),
                'coverage_percentage': round((len(card_mappings) / len(cards)) * 100, 2) if cards else 0
            },
            'export_timestamp': datetime.now().isoformat(),
            'godot_ready': True
        }
    
    def _extract_character_organizations(self, name: str) -> List[str]:
        """Extract character and organization names from card names"""
        keywords = []
        
        # Common One Piece organizations and groups
        organizations = [
            'Navy', 'Marines', 'Straw Hat Crew', 'Straw Hat Pirates', 'Straw Hats',
            'Cross Guild', 'Baroque Works', 'CP9', 'CP-9', 'Cipher Pol',
            'Red Hair Pirates', 'Whitebeard Pirates', 'Big Mom Pirates', 'Animal Kingdom Pirates',
            'Revolutionary Army', 'World Government', 'Seven Warlords', 'Shichibukai',
            'Four Emperors', 'Yonko', 'Eleven Supernovas', 'Worst Generation',
            'Donquixote Pirates', 'Heart Pirates', 'Kid Pirates', 'Bonney Pirates',
            'Hawkins Pirates', 'On Air Pirates', 'Fallen Monk Pirates',
            'Fire Tank Pirates', 'Beautiful Pirates', 'Rumbar Pirates',
            'Arlong Pirates', 'Krieg Pirates', 'Black Cat Pirates',
            'Buggy Pirates', 'Foxy Pirates', 'Thriller Bark Pirates',
            'Flying Fish Riders', 'Kuja Pirates', 'Sun Pirates',
            'Fisher Tiger', 'Germa 66', 'Vinsmoke Family',
            'Charlotte Family', 'Rocks Pirates', 'Roger Pirates'
        ]
        
        # Locations and regions
        locations = [
            'East Blue', 'West Blue', 'North Blue', 'South Blue',
            'Grand Line', 'New World', 'Red Line', 'Calm Belt',
            'Land of Wano', 'Wano', 'Alabasta', 'Skypiea', 'Fishman Island',
            'Thriller Bark', 'Sabaody Archipelago', 'Amazon Lily',
            'Impel Down', 'Marineford', 'Enies Lobby', 'Water 7',
            'Ohara', 'Loguetown', 'Whisky Peak', 'Little Garden',
            'Drum Island', 'Jaya', 'Long Ring Long Land', 'Zou',
            'Whole Cake Island', 'Totto Land', 'Egghead Island',
            'Dressrosa', 'Punk Hazard', 'Fishman District'
        ]
        
        # Check for organizations
        for org in organizations:
            if org.lower() in name.lower():
                keywords.append(org)
        
        # Check for locations
        for loc in locations:
            if loc.lower() in name.lower():
                keywords.append(loc)
        
        return keywords
    
    def _extract_effect_keywords(self, effect: str) -> List[str]:
        """Extract ability and mechanic keywords from effect text"""
        keywords = []
        
        # Common One Piece TCG abilities and mechanics
        abilities = [
            'Blocker', 'Rush', 'Banish', 'Double Attack', 'Counter',
            'On Play', 'When Attacking', 'When K.O.', 'End of Turn',
            'Start of Turn', 'DON!', 'Life', 'Power', 'Cost',
            'Activate', 'Trigger', 'Search', 'Draw', 'Discard',
            'Rest', 'Active', 'Leader', 'Character', 'Event', 'Stage'
        ]
        
        for ability in abilities:
            if ability.lower() in effect.lower():
                keywords.append(ability)
        
        return keywords
    
    def _extract_set_theme(self, set_name: str) -> Optional[str]:
        """Extract theme from set name"""
        theme_map = {
            'Romance Dawn': 'East Blue',
            'Paramount War': 'Marineford',
            'Pillars of Strength': 'Alabasta',
            'Kingdoms of Intrigue': 'Dressrosa',
            'Awakening of the New Era': 'New World',
            'Wings of the Captain': 'Sky Island',
            '500 Years in the Future': 'Future',
            'Two Legends': 'Legends',
            'Emperors in the New World': 'Four Emperors',
            'Straw Hat Crew': 'Straw Hats',
            'Film Red': 'Uta',
            'Land of Wano': 'Wano'
        }
        
        for set_theme, theme in theme_map.items():
            if set_theme.lower() in set_name.lower():
                return theme
        
        return None
    
    def _get_set_folder_path(self, set_id: str) -> Path:
        """Get appropriate folder path for a set based on category"""
        set_id_upper = set_id.upper()
        
        # Starter Decks go to decks folder
        if set_id_upper.startswith('ST-') or re.match(r'^ST\d', set_id_upper):
            return self.output_dir / 'decks'
        # Promos
        elif set_id_upper == 'P' or set_id_upper.startswith(('P-', 'W-', 'SF-')) or set_id_upper in ('PROMOS', 'PROMO'):
            return self.output_dir / 'promos'
        # Tournament cards
        elif set_id_upper.startswith(('TP-', 'PTP-')):
            return self.output_dir / 'tournaments'
        # All booster sets (OP, EB, PRB)
        else:
            return self.output_dir / 'sets'
    
    def _get_set_name(self, set_id: str) -> str:
        """Get readable name for a set"""
        set_names = {
            'OP-01': 'Romance Dawn',
            'OP-02': 'Paramount War', 
            'OP-03': 'Pillars of Strength',
            'OP-04': 'Kingdoms of Intrigue',
            'OP-05': 'Awakening of the New Era',
            'OP-06': 'Wings of the Captain',
            'OP-07': '500 Years in the Future',
            'OP-08': 'Two Legends',
            'OP-09': 'Emperors in the New World',
            'OP-10': 'Straw Hat Crew',
            'OP-11': 'Egghead Island',
            'OP-12': 'Zephyr vs Luffy',
            'ST-01': 'Straw Hat Crew Starter',
            'ST-02': 'Worst Generation Starter',
            'PRB-01': 'One Piece Film Red Premium'
        }
        return set_names.get(set_id, set_id)
    
    def _export_json(self, data: Dict[str, Any]) -> List[str]:
        """Export data as JSON files"""
        exported_files = []
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        try:
            # Main card database
            cards_file = self.output_dir / f"one_piece_tcg_cards_{timestamp}.json"
            with open(cards_file, 'w', encoding='utf-8') as f:
                json.dump({
                    'metadata': data.get('metadata', {}),
                    'cards': data.get('cards', [])
                }, f, ensure_ascii=False, indent=2)
            exported_files.append(str(cards_file))
            
            # Sets data
            sets_file = self.output_dir / f"one_piece_tcg_sets_{timestamp}.json"
            with open(sets_file, 'w', encoding='utf-8') as f:
                json.dump({
                    'metadata': data.get('metadata', {}),
                    'sets': data.get('sets', [])
                }, f, ensure_ascii=False, indent=2)
            exported_files.append(str(sets_file))
            
            # Organized by set
            sets_organized = self._organize_cards_by_set(data.get('cards', []))
            for set_id, set_cards in sets_organized.items():
                set_file = self.output_dir / f"set_{set_id}_{timestamp}.json"
                with open(set_file, 'w', encoding='utf-8') as f:
                    json.dump({
                        'set_id': set_id,
                        'cards': set_cards,
                        'card_count': len(set_cards)
                    }, f, ensure_ascii=False, indent=2)
                exported_files.append(str(set_file))
            
            # Organized by type
            types_organized = self._organize_cards_by_type(data.get('cards', []))
            for card_type, type_cards in types_organized.items():
                type_file = self.output_dir / f"type_{card_type}_{timestamp}.json"
                with open(type_file, 'w', encoding='utf-8') as f:
                    json.dump({
                        'type': card_type,
                        'cards': type_cards,
                        'card_count': len(type_cards)
                    }, f, ensure_ascii=False, indent=2)
                exported_files.append(str(type_file))
            
            st.write(f"✅ Exported {len(exported_files)} JSON files")
            
        except Exception as e:
            st.error(f"Failed to export JSON files: {str(e)}")
        
        return exported_files
    
    def _export_csv(self, data: Dict[str, Any]) -> List[str]:
        """Export data as CSV files"""
        exported_files = []
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        try:
            cards = data.get('cards', [])
            if not cards:
                return exported_files
            
            # Main cards CSV
            cards_file = self.output_dir / f"one_piece_tcg_cards_{timestamp}.csv"
            self._write_cards_csv(cards, cards_file)
            exported_files.append(str(cards_file))
            
            # Sets CSV
            sets = data.get('sets', [])
            if sets:
                sets_file = self.output_dir / f"one_piece_tcg_sets_{timestamp}.csv"
                self._write_sets_csv(sets, sets_file)
                exported_files.append(str(sets_file))
            
            st.write(f"✅ Exported {len(exported_files)} CSV files")
            
        except Exception as e:
            st.error(f"Failed to export CSV files: {str(e)}")
        
        return exported_files
    
    def _export_godot_format(self, data: Dict[str, Any]) -> List[str]:
        """Export data in Godot-friendly format"""
        exported_files = []
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        try:
            cards = data.get('cards', [])
            if not cards:
                return exported_files
            
            # Godot resource format (simplified JSON)
            godot_data = self._convert_to_godot_format(data)
            
            # Use stable filenames to avoid accumulating timestamped JSONs every run.
            godot_file = self.output_dir / "godot_card_database.json"
            with open(godot_file, 'w', encoding='utf-8') as f:
                json.dump(godot_data, f, ensure_ascii=False, indent=2)
            exported_files.append(str(godot_file))
            
            # Image mapping file
            image_mapping = self._create_image_mapping(cards)
            mapping_file = self.output_dir / "godot_image_mapping.json"
            with open(mapping_file, 'w', encoding='utf-8') as f:
                json.dump(image_mapping, f, ensure_ascii=False, indent=2)
            exported_files.append(str(mapping_file))
            
            # Godot autoload script
            autoload_script = self._generate_godot_autoload_script(godot_data)
            script_file = self.output_dir / f"CardDatabase.gd"
            with open(script_file, 'w', encoding='utf-8') as f:
                f.write(autoload_script)
            exported_files.append(str(script_file))
            
            st.write(f"✅ Exported {len(exported_files)} Godot files")
            
        except Exception as e:
            st.error(f"Failed to export Godot files: {str(e)}")
        
        return exported_files
    
    def _organize_cards_by_set(self, cards: List[Dict]) -> Dict[str, List[Dict]]:
        """Organize cards by set ID"""
        organized = {}
        
        for card in cards:
            set_id = card.get('set_id')
            if not set_id or set_id == 'unknown':
                continue
            if set_id not in organized:
                organized[set_id] = []
            organized[set_id].append(card)
        
        # Return in stable, sorted order for deterministic exports.
        sorted_ids = self._sorted_set_ids(list(organized.keys()))
        return {sid: organized[sid] for sid in sorted_ids}

    def _sorted_set_ids(self, set_ids: List[str]) -> List[str]:
        return sorted([s for s in set_ids if s], key=self._set_sort_key)

    def _set_sort_key(self, set_id: str):
        sid = str(set_id or '').upper()
        # Canonicalize composite IDs like OP14-EB04 for ordering.
        m = re.match(r'^(OP|ST)(\d{2})-.*$', sid)
        if m:
            prefix, digits = m.groups()
            sid = f"{prefix}-{digits}"

        # Category priority
        if sid.startswith('OP-'):
            num = self._safe_int(re.sub(r'\D', '', sid))
            return (0, num, sid)
        if sid.startswith('EB-'):
            num = self._safe_int(re.sub(r'\D', '', sid))
            return (1, num, sid)
        if sid.startswith('PRB-'):
            num = self._safe_int(re.sub(r'\D', '', sid))
            return (2, num, sid)
        if sid.startswith('ST-'):
            num = self._safe_int(re.sub(r'\D', '', sid))
            return (3, num, sid)
        if sid in ('P', 'PROMOS', 'PROMO') or sid.startswith('P-'):
            return (4, 0, sid)
        if sid.startswith(('TP-', 'PTP-')):
            return (5, 0, sid)
        return (9, 0, sid)

    def _deck_sort_key(self, deck_id: str):
        did = str(deck_id or '').upper()
        if did.startswith('ST-'):
            return (0, self._safe_int(re.sub(r'\D', '', did)), did)
        return (9, 0, did)

    def _sort_cards_within_set(self, cards: List[Dict]) -> List[Dict]:
        def key(card: Dict[str, Any]):
            number = str(card.get('number', '') or '')
            num_i = self._safe_int(number) if number.isdigit() else 999999
            code = str(card.get('card_code', '') or '')
            name = str(card.get('name', '') or '')
            return (num_i, code, name)

        return sorted(cards, key=key)

    def _safe_int(self, value: Any) -> int:
        try:
            if value is None or value == "":
                return 0
            return int(value)
        except (ValueError, TypeError):
            return 0
    
    def _organize_cards_by_type(self, cards: List[Dict]) -> Dict[str, List[Dict]]:
        """Organize cards by type"""
        organized = {}
        
        for card in cards:
            card_type = card.get('type', 'unknown').lower()
            if card_type not in organized:
                organized[card_type] = []
            organized[card_type].append(card)
        
        return organized
    
    def _write_cards_csv(self, cards: List[Dict], file_path: Path):
        """Write cards data to CSV file"""
        if not cards:
            return
        
        # Define CSV columns
        columns = [
            'id', 'name', 'name_english', 'set_id', 'set_name', 'number',
            'rarity', 'type', 'cost', 'power', 'counter', 'life',
            'effect', 'traits', 'colors', 'attribute', 'language',
            'source', 'is_promo', 'is_tournament', 'is_alternate_art',
            'release_date', 'artist', 'image_url'
        ]
        
        with open(file_path, 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=columns, extrasaction='ignore')
            writer.writeheader()
            
            for card in cards:
                # Convert lists to comma-separated strings
                row = card.copy()
                for field in ['traits', 'colors', 'sources']:
                    if field in row and isinstance(row[field], list):
                        row[field] = ', '.join(row[field])
                
                writer.writerow(row)
    
    def _write_sets_csv(self, sets: List[Dict], file_path: Path):
        """Write sets data to CSV file"""
        if not sets:
            return
        
        columns = [
            'id', 'name', 'name_english', 'release_date', 'card_count',
            'language', 'type', 'block', 'symbol', 'code'
        ]
        
        with open(file_path, 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=columns, extrasaction='ignore')
            writer.writeheader()
            writer.writerows(sets)
    
    def _convert_to_godot_format(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Convert data to Godot-friendly format"""
        cards = data.get('cards', [])
        sets = data.get('sets', [])
        
        # Simplify card data for Godot
        godot_cards = {}
        for card in cards:
            card_id = card.get('id', 'unknown')
            godot_cards[card_id] = {
                'name': card.get('name', ''),
                'set_id': card.get('set_id', ''),
                'number': card.get('number', ''),
                'rarity': card.get('rarity', ''),
                'type': card.get('type', ''),
                'cost': card.get('cost', 0),
                'power': card.get('power', 0),
                'counter': card.get('counter', 0),
                'life': card.get('life', 0),
                'effect': card.get('effect', ''),
                'traits': card.get('traits', []),
                'colors': card.get('colors', []),
                'image_path': f"res://images/cards/{self._get_image_filename(card)}",
                'thumbnail_path': f"res://images/thumbnails/{self._get_image_filename(card)}",
                'is_promo': card.get('is_promo', False),
                'is_tournament': card.get('is_tournament', False),
                'is_alternate_art': card.get('is_alternate_art', False)
            }
        
        # Organize sets
        godot_sets = {}
        for set_data in sets:
            set_id = set_data.get('id', 'unknown')
            godot_sets[set_id] = {
                'name': set_data.get('name', ''),
                'release_date': set_data.get('release_date', ''),
                'card_count': set_data.get('card_count', 0),
                'type': set_data.get('type', 'booster')
            }
        
        return {
            'metadata': {
                'version': '1.0',
                'generated_at': datetime.now().isoformat(),
                'total_cards': len(godot_cards),
                'total_sets': len(godot_sets)
            },
            'cards': godot_cards,
            'sets': godot_sets
        }
    
    def _create_image_mapping(self, cards: List[Dict]) -> Dict[str, str]:
        """Create mapping of card IDs to image file paths"""
        mapping = {}
        
        for card in cards:
            card_id = card.get('id', 'unknown')
            filename = self._get_image_filename(card)
            mapping[card_id] = {
                'full_image': f"res://images/cards/{filename}",
                'thumbnail': f"res://images/thumbnails/{filename}"
            }
        
        return mapping
    
    def _get_image_filename(self, card: Dict[str, Any]) -> str:
        """Get the expected image filename for a card"""
        card_id = card.get('id', '')
        if card_id:
            return f"{self._sanitize_filename(card_id)}.png"
        
        set_id = card.get('set_id', 'unknown')
        number = card.get('number', '000')
        name = card.get('name', 'unknown')
        
        set_id = self._sanitize_filename(set_id)
        number = self._sanitize_filename(number)
        name = self._sanitize_filename(name)[:20]
        
        return f"{set_id}-{number}-{name}.png"
    
    def _sanitize_filename(self, filename: str) -> str:
        """Sanitize filename for filesystem compatibility"""
        import re
        
        filename = re.sub(r'[<>:"/\\|?*]', '_', filename)
        filename = re.sub(r'\s+', '_', filename)
        filename = re.sub(r'_+', '_', filename)
        filename = filename.strip('_')
        
        return filename or 'unknown'
    
    def _generate_godot_autoload_script(self, godot_data: Dict[str, Any]) -> str:
        """Generate Godot autoload script for easy access to card data"""
        script = '''# CardDatabase.gd
# Auto-generated One Piece TCG Card Database
# Add this script as an AutoLoad in Project Settings

extends Node

# Card database loaded from JSON
var cards: Dictionary = {}
var sets: Dictionary = {}
var metadata: Dictionary = {}

func _ready():
        load_database()

func load_database():
        var file = FileAccess.open("res://godot_card_database.json", FileAccess.READ)
        if file:
                var json_text = file.get_as_text()
                file.close()
                
                var json = JSON.new()
                var parse_result = json.parse(json_text)
                
                if parse_result == OK:
                        var data = json.data
                        cards = data.get("cards", {})
                        sets = data.get("sets", {})
                        metadata = data.get("metadata", {})
                        print("Loaded ", cards.size(), " cards from ", sets.size(), " sets")
                else:
                        print("Error parsing card database JSON")
        else:
                print("Error loading card database file")

# Get card by ID
func get_card(card_id: String) -> Dictionary:
        return cards.get(card_id, {})

# Get all cards from a set
func get_cards_by_set(set_id: String) -> Array:
        var set_cards = []
        for card_id in cards:
                var card = cards[card_id]
                if card.get("set_id", "") == set_id:
                        set_cards.append(card)
        return set_cards

# Get cards by type
func get_cards_by_type(card_type: String) -> Array:
        var type_cards = []
        for card_id in cards:
                var card = cards[card_id]
                if card.get("type", "").to_lower() == card_type.to_lower():
                        type_cards.append(card)
        return type_cards

# Get cards by rarity
func get_cards_by_rarity(rarity: String) -> Array:
        var rarity_cards = []
        for card_id in cards:
                var card = cards[card_id]
                if card.get("rarity", "").to_lower() == rarity.to_lower():
                        rarity_cards.append(card)
        return rarity_cards

# Search cards by name
func search_cards(query: String) -> Array:
        var results = []
        query = query.to_lower()
        for card_id in cards:
                var card = cards[card_id]
                var name = card.get("name", "").to_lower()
                if query in name:
                        results.append(card)
        return results

# Get set information
func get_set(set_id: String) -> Dictionary:
        return sets.get(set_id, {})

# Get all available sets
func get_all_sets() -> Dictionary:
        return sets

# Get promo cards
func get_promo_cards() -> Array:
        var promos = []
        for card_id in cards:
                var card = cards[card_id]
                if card.get("is_promo", false):
                        promos.append(card)
        return promos

# Get tournament cards
func get_tournament_cards() -> Array:
        var tournaments = []
        for card_id in cards:
                var card = cards[card_id]
                if card.get("is_tournament", false):
                        tournaments.append(card)
        return tournaments

# Get alternate art cards
func get_alt_art_cards() -> Array:
        var alt_arts = []
        for card_id in cards:
                var card = cards[card_id]
                if card.get("is_alternate_art", false):
                        alt_arts.append(card)
        return alt_arts
'''
        return script
    
    def _create_sqlite_cdb_database(self, data: Dict[str, Any], db_path: Path):
        """Create proper SQLite database for YGO Pro Percy compatibility (.db format)"""
        cards = data.get('cards', [])
        
        # Remove existing database if it exists
        if db_path.exists():
            db_path.unlink()
        
        # Create SQLite database
        conn = sqlite3.connect(str(db_path))
        cursor = conn.cursor()
        
        try:
            # Create YGO Pro Percy compatible tables
            
            # Main card data table
            cursor.execute('''
                CREATE TABLE datas (
                    id INTEGER PRIMARY KEY,
                    ot INTEGER,
                    alias INTEGER,
                    setcode INTEGER,
                    type INTEGER,
                    atk INTEGER,
                    def INTEGER,
                    level INTEGER,
                    race INTEGER,
                    attribute INTEGER,
                    category INTEGER
                )
            ''')
            
            # Card text table
            cursor.execute('''
                CREATE TABLE texts (
                    id INTEGER PRIMARY KEY,
                    name TEXT,
                    desc TEXT,
                    str1 TEXT,
                    str2 TEXT,
                    str3 TEXT,
                    str4 TEXT,
                    str5 TEXT,
                    str6 TEXT,
                    str7 TEXT,
                    str8 TEXT,
                    str9 TEXT,
                    str10 TEXT,
                    str11 TEXT,
                    str12 TEXT,
                    str13 TEXT,
                    str14 TEXT,
                    str15 TEXT,
                    str16 TEXT
                )
            ''')
            
            # Forbidden/Limited list table
            cursor.execute('''
                CREATE TABLE lflist (
                    id INTEGER PRIMARY KEY,
                    count INTEGER
                )
            ''')
            
            # Insert card data
            for i, card in enumerate(cards):
                card_id = self._generate_numeric_id(card, i)
                
                # Convert One Piece card data to Percy format
                percy_data = self._convert_card_to_percy_sqlite(card, card_id)
                
                # Insert into datas table
                cursor.execute('''
                    INSERT INTO datas (id, ot, alias, setcode, type, atk, def, level, race, attribute, category)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ''', (
                    percy_data['id'],
                    percy_data['ot'],
                    percy_data['alias'],
                    percy_data['setcode'],
                    percy_data['type'],
                    percy_data['atk'],
                    percy_data['def'],
                    percy_data['level'],
                    percy_data['race'],
                    percy_data['attribute'],
                    percy_data['category']
                ))
                
                # Insert into texts table
                cursor.execute('''
                    INSERT INTO texts (id, name, desc, str1, str2, str3, str4, str5)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ''', (
                    percy_data['id'],
                    percy_data['name'],
                    percy_data['desc'],
                    percy_data.get('str1', ''),
                    percy_data.get('str2', ''),
                    percy_data.get('str3', ''),
                    percy_data.get('str4', ''),
                    percy_data.get('str5', '')
                ))
                
                # Default to unlimited (3 copies) unless specified
                cursor.execute('INSERT INTO lflist (id, count) VALUES (?, ?)', (percy_data['id'], 3))
            
            conn.commit()
            st.write(f"✅ Created SQLite database with {len(cards)} cards (Percy-compatible format)")
            
        except Exception as e:
            st.error(f"Error creating SQLite database: {str(e)}")
        finally:
            conn.close()
    
    def _generate_numeric_id(self, card: Dict, index: int) -> int:
        """Generate numeric ID for Percy database compatibility"""
        # Use index + offset to ensure unique IDs
        base_id = 100000000 + index  # Start from 100M to avoid conflicts
        
        # Try to incorporate set info if available
        set_id = card.get('set_id', '')
        if set_id:
            # Extract set number if it's in format like OP-01, ST-01, etc.
            import re
            match = re.search(r'(\d+)', set_id)
            if match:
                set_num = int(match.group(1))
                base_id = 100000000 + (set_num * 10000) + index
        
        return base_id
    
    def _convert_card_to_percy_sqlite(self, card: Dict, card_id: int) -> Dict[str, Any]:
        """Convert One Piece card to Percy SQLite format"""
        
        # Map One Piece types to YGO type flags
        type_flags = self._get_percy_type_flags(card.get('type', ''))
        
        # Map colors to attributes
        attribute = self._map_colors_to_attribute(card.get('colors', []))
        
        # Map traits to race
        race = self._map_traits_to_race(card.get('traits', []))
        
        return {
            'id': card_id,
            'ot': 1,  # OCG/TCG (1 = OCG, 2 = TCG, 3 = Both)
            'alias': 0,  # No aliases for One Piece cards
            'setcode': self._encode_setcode(card.get('set_id', '')),
            'type': type_flags,
            'atk': card.get('power', 0),
            'def': card.get('counter', 0),
            'level': card.get('cost', 0),
            'race': race,
            'attribute': attribute,
            'category': 0,  # Special categories (not used for One Piece)
            'name': card.get('name', ''),
            'desc': self._format_card_description(card),
            'str1': card.get('set_id', ''),
            'str2': card.get('rarity', ''),
            'str3': ', '.join(card.get('colors', [])),
            'str4': ', '.join(card.get('traits', [])),
            'str5': f"Life: {card.get('life', 0)}"
        }
    
    def _get_percy_type_flags(self, card_type: str) -> int:
        """Convert One Piece card type to YGO type flags"""
        type_map = {
            'character': 0x1,      # Monster
            'event': 0x2,          # Spell
            'stage': 0x4,          # Trap (using for Stage)
            'leader': 0x40,        # Extra Deck (using for Leader)
            'don': 0x80,           # Token (using for Don)
        }
        return type_map.get(card_type.lower(), 0x1)  # Default to Monster
    
    def _map_colors_to_attribute(self, colors: List[str]) -> int:
        """Map One Piece colors to YGO attributes"""
        if not colors:
            return 0  # No attribute
        
        # Primary color mapping
        color_map = {
            'red': 1,      # EARTH
            'green': 2,    # WATER  
            'blue': 3,     # FIRE
            'purple': 4,   # WIND
            'black': 5,    # LIGHT
            'yellow': 6,   # DARK
        }
        
        # Use first color or combine somehow
        primary_color = colors[0].lower() if colors else ''
        return color_map.get(primary_color, 0)
    
    def _map_traits_to_race(self, traits: List[str]) -> int:
        """Map One Piece traits to YGO races"""
        if not traits:
            return 1  # Default race
        
        # Simple mapping - in real implementation, you'd have a comprehensive mapping
        trait_map = {
            'pirate': 1,
            'marine': 2,
            'revolutionary': 3,
            'cp': 4,
            'animal': 5,
            'giant': 6,
            'fishman': 7,
            'mink': 8,
        }
        
        # Use first trait or default
        primary_trait = traits[0].lower() if traits else ''
        for trait, race_id in trait_map.items():
            if trait in primary_trait:
                return race_id
        
        return 1  # Default
    
    def _encode_setcode(self, set_id: str) -> int:
        """Encode set ID as integer for setcode field"""
        if not set_id:
            return 0
        
        # Convert set ID like "OP-01" to numeric code
        import re
        
        # Extract letters and numbers
        letters_match = re.search(r'^([A-Z]+)', set_id.upper())
        numbers_match = re.search(r'(\d+)', set_id)
        
        if letters_match and numbers_match:
            letters = letters_match.group(1)
            numbers = int(numbers_match.group(1))
            
            # Create unique code based on letters and numbers
            letter_code = sum(ord(c) - ord('A') + 1 for c in letters)
            return (letter_code * 1000) + numbers
        
        return 0
    
    def _format_card_description(self, card: Dict) -> str:
        """Format card description for Percy database"""
        desc_parts = []
        
        # Basic info
        card_type = card.get('type', '').title()
        if card_type:
            desc_parts.append(f"[{card_type}]")
        
        # Colors
        colors = card.get('colors', [])
        if colors:
            desc_parts.append(f"Colors: {', '.join(colors)}")
        
        # Traits
        traits = card.get('traits', [])
        if traits:
            desc_parts.append(f"Traits: {', '.join(traits)}")
        
        # Stats
        cost = card.get('cost', 0)
        power = card.get('power', 0)
        counter = card.get('counter', 0)
        life = card.get('life', 0)
        
        stats = []
        if cost > 0:
            stats.append(f"Cost: {cost}")
        if power > 0:
            stats.append(f"Power: {power}")
        if counter > 0:
            stats.append(f"Counter: {counter}")
        if life > 0:
            stats.append(f"Life: {life}")
        
        if stats:
            desc_parts.append(" | ".join(stats))
        
        # Effect text
        effect = card.get('effect', '')
        if effect:
            desc_parts.append(f"\n{effect}")
        
        return "\n".join(desc_parts)
    
    def _export_percy_format(self, data: Dict[str, Any]) -> List[str]:
        """Export data in YGO Pro Percy-style format for dueling simulator"""
        exported_files = []
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        try:
            cards = data.get('cards', [])
            if not cards:
                return exported_files
            
            # Main dueling database (proper SQLite format for Percy compatibility)
            percy_file = self.output_dir / f"one_piece_dueling_database_{timestamp}.db"
            self._create_sqlite_cdb_database(data, percy_file)
            exported_files.append(str(percy_file))
            
            # Enhanced card database with game mechanics
            mechanics_db = self._create_card_mechanics_database(cards)
            mechanics_file = self.output_dir / f"card_mechanics_database_{timestamp}.json"
            with open(mechanics_file, 'w', encoding='utf-8') as f:
                json.dump(mechanics_db, f, ensure_ascii=False, indent=2)
            exported_files.append(str(mechanics_file))
            
            # Starter deck exports
            starter_decks = self._extract_starter_decks(cards)
            if starter_decks:
                for deck_id, deck_data in starter_decks.items():
                    deck_file = self.output_dir / f"starter_deck_{deck_id}_{timestamp}.ydl"
                    with open(deck_file, 'w', encoding='utf-8') as f:
                        f.write(self._format_deck_list(deck_data))
                    exported_files.append(str(deck_file))
            
            # Deck building constraints
            constraints = self._create_deck_constraints(cards)
            constraints_file = self.output_dir / f"deck_constraints_{timestamp}.json"
            with open(constraints_file, 'w', encoding='utf-8') as f:
                json.dump(constraints, f, ensure_ascii=False, indent=2)
            exported_files.append(str(constraints_file))
            
            # Game rules configuration
            rules_config = self._create_game_rules_config(data)
            rules_file = self.output_dir / f"one_piece_game_rules_{timestamp}.json"
            with open(rules_file, 'w', encoding='utf-8') as f:
                json.dump(rules_config, f, ensure_ascii=False, indent=2)
            exported_files.append(str(rules_file))
            
            st.write(f"✅ Exported {len(exported_files)} dueling simulator files")
            
        except Exception as e:
            st.error(f"Failed to export dueling simulator files: {str(e)}")
        
        return exported_files
    
    def _convert_to_percy_format(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Convert data to YGO Pro Percy-style database format"""
        cards = data.get('cards', [])
        
        percy_cards = {}
        for card in cards:
            card_id = card.get('id', 'unknown')
            
            # Parse effect text for game mechanics
            effect_data = self._parse_card_effect(card.get('effect', ''))
            
            percy_cards[card_id] = {
                # Basic card info
                'id': card_id,
                'name': card.get('name', ''),
                'type': self._convert_card_type(card.get('type', '')),
                'attribute': self._convert_attribute(card.get('attribute', '')),
                'level': card.get('cost', 0),  # Cost as level equivalent
                'atk': card.get('power', 0),
                'def': card.get('counter', 0),  # Counter as defense equivalent
                'life': card.get('life', 0),
                
                # One Piece specific mechanics
                'cost': card.get('cost', 0),
                'power': card.get('power', 0),
                'counter': card.get('counter', 0),
                'colors': card.get('colors', []),
                'traits': card.get('traits', []),
                
                # Parsed effect data
                'effect': card.get('effect', ''),
                'effect_triggers': effect_data.get('triggers', []),
                'effect_conditions': effect_data.get('conditions', []),
                'effect_costs': effect_data.get('costs', []),
                'effect_targets': effect_data.get('targets', []),
                
                # Game mechanics flags
                'is_leader': card.get('type', '').lower() == 'leader',
                'is_don': card.get('type', '').lower() == 'don',
                'is_blocker': 'blocker' in card.get('effect', '').lower(),
                'is_rush': 'rush' in card.get('effect', '').lower(),
                'is_banish': 'banish' in card.get('effect', '').lower(),
                'is_counter': card.get('counter', 0) > 0,
                
                # Set information
                'set_id': card.get('set_id', ''),
                'set_name': card.get('set_name', ''),
                'number': card.get('number', ''),
                'rarity': card.get('rarity', ''),
                
                # Flags
                'is_promo': card.get('is_promo', False),
                'is_alternate_art': card.get('is_alternate_art', False),
                'is_starter_deck': card.get('is_starter_deck', False),
                
                # Image paths
                'image_path': f"pics/{card_id}.jpg",
                'thumbnail_path': f"pics/thumbnail/{card_id}.jpg"
            }
        
        return {
            'database_info': {
                'name': 'One Piece TCG Database',
                'version': '1.0',
                'format_version': 'percy_compatible',
                'total_cards': len(percy_cards),
                'generated_at': datetime.now().isoformat()
            },
            'cards': percy_cards
        }
    
    def _parse_card_effect(self, effect_text: str) -> Dict[str, List[str]]:
        """Parse card effect text to extract game mechanics"""
        if not effect_text:
            return {'triggers': [], 'conditions': [], 'costs': [], 'targets': []}
        
        effect_lower = effect_text.lower()
        
        # Extract trigger conditions
        triggers = []
        trigger_patterns = [
            'when this character attacks',
            'when this character is played',
            'on play',
            'when ko\'d',
            'end of turn',
            'start of turn',
            'when attacking',
            'when played'
        ]
        for pattern in trigger_patterns:
            if pattern in effect_lower:
                triggers.append(pattern)
        
        # Extract conditions
        conditions = []
        condition_patterns = [
            'if you have',
            'if your leader',
            'if this character',
            'if you control',
            'during your turn',
            'during opponent\'s turn'
        ]
        for pattern in condition_patterns:
            if pattern in effect_lower:
                conditions.append(pattern)
        
        # Extract costs
        costs = []
        cost_patterns = [
            'pay',
            'discard',
            'sacrifice',
            'banish',
            'remove from life'
        ]
        for pattern in cost_patterns:
            if pattern in effect_lower:
                costs.append(pattern)
        
        # Extract targets
        targets = []
        target_patterns = [
            'target character',
            'target card',
            'all characters',
            'your leader',
            'opponent\'s leader',
            'this character'
        ]
        for pattern in target_patterns:
            if pattern in effect_lower:
                targets.append(pattern)
        
        return {
            'triggers': triggers,
            'conditions': conditions,
            'costs': costs,
            'targets': targets
        }
    
    def _convert_card_type(self, card_type: str) -> str:
        """Convert One Piece card type to dueling simulator format"""
        type_map = {
            'character': 'monster',
            'event': 'spell',
            'stage': 'field',
            'leader': 'extra',
            'don': 'token'
        }
        return type_map.get(card_type.lower(), 'unknown')
    
    def _convert_attribute(self, attribute: str) -> str:
        """Convert attribute to dueling simulator format"""
        if not attribute:
            return 'NONE'
        return attribute.upper()
    
    def _create_card_mechanics_database(self, cards: List[Dict]) -> Dict[str, Any]:
        """Create enhanced database with game mechanics for dueling simulator"""
        mechanics_db = {
            'mechanics_info': {
                'version': '1.0',
                'game': 'One Piece TCG',
                'total_cards': len(cards)
            },
            'card_mechanics': {},
            'keywords': {},
            'interactions': {}
        }
        
        keywords = set()
        
        for card in cards:
            card_id = card.get('id', 'unknown')
            effect = card.get('effect', '').lower()
            
            # Extract keywords from effect text
            card_keywords = []
            keyword_patterns = [
                'blocker', 'rush', 'banish', 'counter', 'trigger',
                'search', 'draw', 'discard', 'shuffle', 'reveal',
                'destroy', 'return', 'bounce', 'heal', 'damage'
            ]
            
            for keyword in keyword_patterns:
                if keyword in effect:
                    card_keywords.append(keyword)
                    keywords.add(keyword)
            
            mechanics_db['card_mechanics'][card_id] = {
                'keywords': card_keywords,
                'mechanics_complexity': len(card_keywords),
                'interaction_types': self._classify_interactions(effect),
                'timing': self._extract_timing(effect),
                'resource_costs': self._extract_resource_costs(card),
                'stat_modifiers': self._extract_stat_modifiers(effect)
            }
        
        # Build keyword database
        for keyword in keywords:
            mechanics_db['keywords'][keyword] = {
                'description': self._get_keyword_description(keyword),
                'cards_with_keyword': [
                    card_id for card_id, mech in mechanics_db['card_mechanics'].items()
                    if keyword in mech['keywords']
                ]
            }
        
        return mechanics_db
    
    def _classify_interactions(self, effect: str) -> List[str]:
        """Classify types of card interactions"""
        interactions = []
        if 'target' in effect:
            interactions.append('targeting')
        if 'all' in effect or 'each' in effect:
            interactions.append('mass_effect')
        if 'draw' in effect:
            interactions.append('card_advantage')
        if 'search' in effect:
            interactions.append('deck_manipulation')
        if 'damage' in effect or 'heal' in effect:
            interactions.append('life_manipulation')
        return interactions
    
    def _extract_timing(self, effect: str) -> str:
        """Extract timing information from effect"""
        if 'on play' in effect or 'when played' in effect:
            return 'on_play'
        elif 'when attacks' in effect or 'when attacking' in effect:
            return 'on_attack'
        elif 'end of turn' in effect:
            return 'end_phase'
        elif 'start of turn' in effect:
            return 'start_phase'
        else:
            return 'continuous'
    
    def _extract_resource_costs(self, card: Dict) -> Dict[str, int]:
        """Extract resource costs for the card"""
        return {
            'cost': card.get('cost', 0),
            'life_cost': 0,  # Extract from effect if present
            'discard_cost': 0  # Extract from effect if present
        }
    
    def _extract_stat_modifiers(self, effect: str) -> Dict[str, Any]:
        """Extract stat modification effects"""
        modifiers = {
            'power_boost': 0,
            'cost_reduction': 0,
            'temporary_effects': [],
            'permanent_effects': []
        }
        
        # Simple pattern matching for common stat modifications
        if '+' in effect and 'power' in effect:
            modifiers['temporary_effects'].append('power_boost')
        if 'reduce' in effect and 'cost' in effect:
            modifiers['temporary_effects'].append('cost_reduction')
        
        return modifiers
    
    def _get_keyword_description(self, keyword: str) -> str:
        """Get description for game keywords"""
        descriptions = {
            'blocker': 'Can block attacks directed at your leader',
            'rush': 'Can attack the turn it\'s played',
            'banish': 'Remove from game temporarily or permanently',
            'counter': 'Can be used to counter attacks',
            'trigger': 'Activates under specific conditions',
            'search': 'Look through deck for specific cards',
            'draw': 'Add cards from deck to hand',
            'discard': 'Send cards from hand to trash',
            'destroy': 'Send cards from field to trash',
            'heal': 'Restore life points',
            'damage': 'Deal damage to characters or leader'
        }
        return descriptions.get(keyword, 'No description available')
    
    def _extract_starter_decks(self, cards: List[Dict]) -> Dict[str, Dict]:
        """Extract starter deck compositions.

        IMPORTANT: The upstream card list is a merged, multi-source dataset.
        We must not treat cross-source duplicates as additional deck copies.
        Prefer a single authoritative source (OPTCG) when available.
        """

        def normalize_deck_id(raw_set_id: str) -> Optional[str]:
            raw = str(raw_set_id or '').strip().upper()
            if raw == '':
                return None

            # Accept ST01 / ST-01 / ST 01 / ST-1
            m = re.match(r'^ST\s*[- ]?\s*(\d{1,2})$', raw)
            if m:
                return f"ST-{int(m.group(1)):02d}"

            # Keep already-normalized values like ST-10.
            if re.match(r'^ST-\d{2}$', raw):
                return raw

            return raw if raw.startswith('ST-') else None

        def is_starter_card(card: Dict[str, Any]) -> bool:
            set_id = str(card.get('set_id', '') or '').strip()
            set_name = str(card.get('set_name', '') or '').strip()
            if card.get('is_starter_deck'):
                return True
            if normalize_deck_id(set_id):
                return True
            upper_name = set_name.upper()
            return ('STARTER DECK' in upper_name) or ('ULTRA DECK' in upper_name)

        def make_card_entry(card: Dict[str, Any]) -> Dict[str, Any]:
            return {
                'id': card.get('id'),
                'name': card.get('name'),
                'type': card.get('type'),
                'cost': card.get('cost', 0),
                'power': card.get('power', 0),
                'counter': card.get('counter', 0),
                'life': card.get('life', 0),
                'colors': card.get('colors', []),
                'traits': card.get('traits', []),
                'rarity': card.get('rarity', ''),
                'effect': card.get('effect', ''),
                'attribute': card.get('attribute', ''),
                'set_id': card.get('set_id', ''),
                'set_code': card.get('set_code', (card.get('set_id', '') or '').replace('-', '')),
                'card_code': card.get('card_code', ''),
                'number': card.get('number', ''),
                'copies': 1,
            }

        def is_don(card: Dict[str, Any]) -> bool:
            t = str(card.get('type', '') or '').strip().lower()
            code = str(card.get('card_code', '') or '').strip().upper()
            return (t in {'don', 'don!!'}) or code.startswith('DON')

        # Group candidate cards per normalized deck ID.
        cards_by_deck: Dict[str, List[Dict[str, Any]]] = {}
        for card in cards:
            if not isinstance(card, dict):
                continue
            if not is_starter_card(card):
                continue

            deck_id = normalize_deck_id(card.get('set_id', ''))
            if not deck_id:
                continue
            cards_by_deck.setdefault(deck_id, []).append(card)

        starter_decks: Dict[str, Dict[str, Any]] = {}
        source_preference = ['optcg', 'apitcg', 'onepiecetopdecks']

        for deck_id in sorted(cards_by_deck.keys(), key=self._deck_sort_key):
            deck_cards = cards_by_deck[deck_id]
            set_name = ''
            for c in deck_cards:
                if c.get('set_name'):
                    set_name = str(c.get('set_name'))
                    break

            # Prefer a single source to avoid cross-source duplicate inflation.
            chosen_source = None
            for s in source_preference:
                if any((c.get('source') == s) for c in deck_cards):
                    chosen_source = s
                    break
            if chosen_source:
                deck_cards = [c for c in deck_cards if c.get('source') == chosen_source]

            deck_info = self._get_starter_deck_info(deck_id, set_name)
            deck_data: Dict[str, Any] = {
                'id': deck_id,
                'name': deck_info['name'],
                'theme': deck_info['theme'],
                'release_date': deck_info['release_date'],
                'colors': deck_info['colors'],
                'leader': None,
                'main_deck': [],
                'don_cards': [],
                'life_cards': [],
                'total_cards': 0,
                'is_ultra_deck': 'ULTRA' in str(set_name or '').upper(),
                'deck_strategy': deck_info['strategy'],
                'recommended_play_style': deck_info['play_style'],
                'deck_source': chosen_source or '',
            }

            grouped_main: Dict[str, Dict[str, Any]] = {}
            grouped_don: Dict[str, Dict[str, Any]] = {}

            for card in deck_cards:
                entry = make_card_entry(card)
                card_type = str(card.get('type', '') or '').strip().lower()

                if card_type == 'leader':
                    # Keep the first leader encountered.
                    if deck_data['leader'] is None:
                        deck_data['leader'] = entry
                    continue

                key = str(entry.get('card_code') or entry.get('id') or '').strip()
                if key == '':
                    continue

                if is_don(card):
                    if key not in grouped_don:
                        grouped_don[key] = entry
                    else:
                        grouped_don[key]['copies'] += 1
                else:
                    if key not in grouped_main:
                        grouped_main[key] = entry
                    else:
                        grouped_main[key]['copies'] += 1

            # Clamp illegal copy counts.
            for entry in grouped_main.values():
                if entry.get('copies', 1) > 4:
                    entry['copies'] = 4

            deck_data['main_deck'] = list(grouped_main.values())
            deck_data['don_cards'] = list(grouped_don.values())

            # Normalize DON!! to 10 total.
            total_don = sum(int(c.get('copies', 1)) for c in deck_data['don_cards'])
            if total_don == 0:
                deck_data['don_cards'] = [{
                    'id': 'DON!!',
                    'name': 'DON!!',
                    'type': 'DON!!',
                    'cost': 0,
                    'power': 0,
                    'counter': 0,
                    'life': 0,
                    'colors': [],
                    'traits': [],
                    'rarity': '',
                    'effect': '',
                    'attribute': '',
                    'set_id': deck_id,
                    'set_code': 'DON',
                    'card_code': 'DON!!',
                    'number': '001',
                    'copies': 10,
                }]
            elif total_don != 10:
                # Adjust first DON entry to hit 10 total, and clamp extras.
                deck_data['don_cards'].sort(key=lambda d: str(d.get('card_code', '')))
                # First, reduce if too many.
                while total_don > 10 and deck_data['don_cards']:
                    last = deck_data['don_cards'][-1]
                    last_copies = int(last.get('copies', 1))
                    reduction = min(last_copies, total_don - 10)
                    last['copies'] = last_copies - reduction
                    total_don -= reduction
                    if int(last.get('copies', 0)) <= 0:
                        deck_data['don_cards'].pop()
                # Then, add missing to first.
                if deck_data['don_cards'] and total_don < 10:
                    deck_data['don_cards'][0]['copies'] = int(deck_data['don_cards'][0].get('copies', 1)) + (10 - total_don)

            deck_data['total_cards'] = (
                sum(int(c.get('copies', 1)) for c in deck_data.get('main_deck', []))
                + sum(int(c.get('copies', 1)) for c in deck_data.get('don_cards', []))
                + (1 if deck_data.get('leader') else 0)
            )

            self._validate_starter_deck(deck_data)
            self._add_deck_statistics(deck_data)
            starter_decks[deck_id] = deck_data

        return starter_decks
    
    def _format_deck_list(self, deck_data: Dict) -> str:
        """Format deck data as YDK-style deck list"""
        deck_list = f"#deck\n"
        deck_list += f"#created by One Piece TCG Scraper\n"
        deck_list += f"#main\n"
        
        # Add main deck cards
        for card in deck_data.get('main_deck', []):
            deck_list += f"{card.get('id', 'unknown')}\n"
        
        deck_list += f"#extra\n"
        # Add leader
        if deck_data.get('leader'):
            deck_list += f"{deck_data['leader'].get('id', 'unknown')}\n"
        
        deck_list += f"#side\n"
        # Add Don cards to side deck
        for card in deck_data.get('don_cards', []):
            deck_list += f"{card.get('id', 'unknown')}\n"
        
        deck_list += f"!side\n"
        
        return deck_list
    
    def _get_starter_deck_info(self, deck_id: str, set_name: str) -> Dict[str, Any]:
        """Get official information about starter decks"""
        # Official One Piece TCG starter deck information
        deck_database = {
            'ST-01': {
                'name': 'Straw Hat Crew',
                'theme': 'Monkey D. Luffy',
                'colors': ['RED'],
                'release_date': '2022-07-08',
                'strategy': 'Aggressive rush strategy with strong character synergy',
                'play_style': 'Offensive'
            },
            'ST-02': {
                'name': 'Worst Generation',
                'theme': 'Eustass Kid',
                'colors': ['GREEN'],
                'release_date': '2022-07-08',
                'strategy': 'Midrange control with powerful late-game threats',
                'play_style': 'Control'
            },
            'ST-03': {
                'name': 'The Seven Warlords of the Sea',
                'theme': 'Crocodile',
                'colors': ['PURPLE'],
                'release_date': '2022-09-30',
                'strategy': 'Control and manipulation with special abilities',
                'play_style': 'Control'
            },
            'ST-04': {
                'name': 'Animal Kingdom Pirates',
                'theme': 'Kaido',
                'colors': ['GREEN'],
                'release_date': '2022-09-30',
                'strategy': 'Beast tribal synergy with high power creatures',
                'play_style': 'Midrange'
            },
            'ST-05': {
                'name': 'One Piece Film Edition',
                'theme': 'Film Red',
                'colors': ['RED', 'GREEN'],
                'release_date': '2022-11-25',
                'strategy': 'Film-themed characters with special interactions',
                'play_style': 'Combo'
            },
            'ST-06': {
                'name': 'Navy',
                'theme': 'Absolute Justice',
                'colors': ['BLUE'],
                'release_date': '2023-02-25',
                'strategy': 'Defensive control with marine synergy',
                'play_style': 'Control'
            },
            'ST-07': {
                'name': 'Big Mom Pirates',
                'theme': 'Charlotte Linlin',
                'colors': ['YELLOW'],
                'release_date': '2023-05-26',
                'strategy': 'Life manipulation and soul-based effects',
                'play_style': 'Combo'
            },
            'ST-08': {
                'name': 'Monkey D. Luffy',
                'theme': 'Gear5 Luffy',
                'colors': ['RED'],
                'release_date': '2023-05-26',
                'strategy': 'Advanced Luffy forms with transformation effects',
                'play_style': 'Combo'
            },
            'ST-09': {
                'name': 'Yamato',
                'theme': 'Yamato',
                'colors': ['GREEN'],
                'release_date': '2023-08-25',
                'strategy': 'Yamato-focused with guardian abilities',
                'play_style': 'Midrange'
            },
            'ST-10': {
                'name': 'Three Captains',
                'theme': 'Luffy, Law, Kid',
                'colors': ['RED', 'BLUE', 'GREEN'],
                'release_date': '2023-10-28',
                'strategy': 'Ultra deck with three leader synergy',
                'play_style': 'Versatile'
            },
            'ST-11': {
                'name': 'Uta',
                'theme': 'Uta',
                'colors': ['RED', 'PURPLE'],
                'release_date': '2023-11-25',
                'strategy': 'Music-themed effects and special abilities',
                'play_style': 'Combo'
            },
            'ST-12': {
                'name': 'Zoro and Sanji',
                'theme': 'Zoro & Sanji',
                'colors': ['GREEN', 'BLUE'],
                'release_date': '2024-02-24',
                'strategy': 'Dual character synergy and combo effects',
                'play_style': 'Combo'
            },
            'ST-13': {
                'name': 'Three Brothers',
                'theme': 'Luffy, Ace, Sabo',
                'colors': ['RED', 'BLUE', 'YELLOW'],
                'release_date': '2024-05-25',
                'strategy': 'Ultra deck with brother bond synergy',
                'play_style': 'Versatile'
            },
            'ST-14': {
                'name': 'The Three Sworn Brothers',
                'theme': 'Luffy, Ace, Sabo',
                'colors': ['RED', 'BLUE', 'YELLOW'],
                'release_date': '2024-05-25',
                'strategy': 'Brotherhood synergy with special bond effects',
                'play_style': 'Combo'
            },
            'ST-15': {
                'name': 'Edward Newgate',
                'theme': 'Whitebeard',
                'colors': ['BLUE'],
                'release_date': '2024-08-24',
                'strategy': 'Whitebeard Pirates with family synergy',
                'play_style': 'Midrange'
            },
            'ST-16': {
                'name': 'Black Smoker',
                'theme': 'Smoker',
                'colors': ['BLACK'],
                'release_date': '2024-11-23',
                'strategy': 'Marine control with smoke abilities',
                'play_style': 'Control'
            },
            'ST-17': {
                'name': 'Portgas D. Ace',
                'theme': 'Ace',
                'colors': ['RED'],
                'release_date': '2024-11-23',
                'strategy': 'Fire-based attacks and Whitebeard synergy',
                'play_style': 'Aggressive'
            },
            'ST-18': {
                'name': 'Charlotte Katakuri',
                'theme': 'Katakuri',
                'colors': ['PURPLE'],
                'release_date': '2025-02-22',
                'strategy': 'Future sight and mochi abilities',
                'play_style': 'Control'
            },
            'ST-19': {
                'name': 'Monkey D. Garp',
                'theme': 'Garp',
                'colors': ['BLUE'],
                'release_date': '2025-02-22',
                'strategy': 'Marine hero with powerful punches',
                'play_style': 'Aggressive'
            },
            'ST-20': {
                'name': 'Yellow Monkey',
                'theme': 'Borsalino',
                'colors': ['YELLOW'],
                'release_date': '2025-05-24',
                'strategy': 'Light-speed attacks and marine coordination',
                'play_style': 'Combo'
            },
            'ST-21': {
                'name': 'Vegapunk',
                'theme': 'Dr. Vegapunk',
                'colors': ['BLUE', 'YELLOW'],
                'release_date': '2025-05-24',
                'strategy': 'Science and technology synergy',
                'play_style': 'Control'
            }
        }
        
        # Get deck info or create default
        if deck_id in deck_database:
            return deck_database[deck_id]
        else:
            # Create default info for unknown decks
            return {
                'name': set_name or f'Starter Deck {deck_id}',
                'theme': 'Unknown',
                'colors': [],
                'release_date': 'Unknown',
                'strategy': 'Unknown strategy',
                'play_style': 'Unknown'
            }
    
    def _validate_starter_deck(self, deck_data: Dict) -> None:
        """Validate starter deck composition"""
        deck_id = deck_data.get('id', 'unknown')
        
        # Standard starter deck validation (count total copies, not unique entries)
        main_deck_size = sum(int(c.get('copies', 1)) for c in deck_data.get('main_deck', []))
        don_deck_size = sum(int(c.get('copies', 1)) for c in deck_data.get('don_cards', []))
        has_leader = deck_data.get('leader') is not None
        
        validation_issues = []
        
        # Check deck sizes
        if main_deck_size != 50:
            validation_issues.append(f"Main deck has {main_deck_size} cards (expected 50)")
        if don_deck_size != 10:
            validation_issues.append(f"Don deck has {don_deck_size} cards (expected 10)")
        if not has_leader:
            validation_issues.append("No leader card found")
        
        # Check for proper card distribution
        for card in deck_data.get('main_deck', []):
            card_name = card.get('name', 'unknown')
            count = int(card.get('copies', 1))
            if count > 4:
                validation_issues.append(f"Too many copies of {card_name}: {count} (max 4)")
        
        deck_data['validation_issues'] = validation_issues
        deck_data['is_valid'] = len(validation_issues) == 0
    
    def _add_deck_statistics(self, deck_data: Dict) -> None:
        """Add statistical analysis to deck data"""
        main_deck = deck_data.get('main_deck', [])
        
        # Cost curve analysis
        cost_distribution = {}
        total_power = 0
        total_counter = 0
        card_types = {}
        
        for card in main_deck:
            cost = card.get('cost', 0)
            cost_distribution[cost] = cost_distribution.get(cost, 0) + card.get('copies', 1)
            
            total_power += card.get('power', 0) * card.get('copies', 1)
            total_counter += card.get('counter', 0) * card.get('copies', 1)
            
            card_type = card.get('type', 'unknown')
            card_types[card_type] = card_types.get(card_type, 0) + card.get('copies', 1)
        
        deck_data['statistics'] = {
            'cost_distribution': cost_distribution,
            'average_cost': sum(cost * count for cost, count in cost_distribution.items()) / max(sum(cost_distribution.values()), 1),
            'total_power': total_power,
            'total_counter': total_counter,
            'type_distribution': card_types,
            'unique_cards': len(main_deck),
            'total_main_deck_cards': sum(card.get('copies', 1) for card in main_deck)
        }
    
    def _create_deck_constraints(self, cards: List[Dict]) -> Dict[str, Any]:
        """Create deck building constraints for the dueling simulator"""
        return {
            'deck_rules': {
                'main_deck_size': {'min': 50, 'max': 50},
                'don_deck_size': {'min': 10, 'max': 10},
                'leader_count': {'min': 1, 'max': 1},
                'max_copies_per_card': 4,
                'color_restrictions': {
                    'description': 'Deck must match leader colors or be multicolor',
                    'enforcement': 'warning'
                }
            },
            'banned_cards': [],
            'limited_cards': {},
            'format_specific': {
                'standard': {
                    'allowed_sets': [card.get('set_id') for card in cards if card.get('set_id')],
                    'restrictions': []
                }
            },
            'color_combinations': [
                ['RED'], ['GREEN'], ['BLUE'], ['PURPLE'], ['BLACK'], ['YELLOW'],
                ['RED', 'GREEN'], ['RED', 'BLUE'], ['GREEN', 'BLUE'],
                # Add more combinations as needed
            ]
        }
    
    def _create_game_rules_config(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Create game rules configuration for the dueling simulator"""
        return {
            'game_info': {
                'name': 'One Piece Trading Card Game',
                'version': '1.0',
                'players': 2,
                'starting_life': 5,
                'starting_hand_size': 5,
                'max_hand_size': 7
            },
            'phase_structure': [
                'refresh_phase',
                'draw_phase',
                'don_phase',
                'main_phase',
                'attack_phase',
                'end_phase'
            ],
            'win_conditions': [
                'reduce_opponent_life_to_0',
                'deck_out',
                'special_win_condition'
            ],
            'card_zones': [
                'deck',
                'hand',
                'leader_area',
                'character_area',
                'stage_area',
                'don_deck',
                'don_area',
                'life_area',
                'trash'
            ],
            'battle_mechanics': {
                'attack_declaration': 'Select attacker and target',
                'counter_timing': 'Before damage calculation',
                'damage_calculation': 'Attacker power vs defender power',
                'ko_condition': 'Power reduced to 0 or below'
            },
            'special_mechanics': {
                'leader_attack': 'Leader can attack once per turn',
                'don_attachment': 'Attach Don cards to increase power/cost',
                'life_cards': 'Can add life cards to hand under certain conditions',
                'blocker': 'Can redirect attacks to blocker characters'
            }
        }
    
    def validate_card_coverage(self, cards: List[Dict]) -> Dict[str, Any]:
        """Comprehensive validation system to ensure complete card coverage"""
        validation_results = {
            'total_cards_found': len(cards),
            'validation_timestamp': datetime.now().isoformat(),
            'coverage_analysis': {},
            'missing_cards': [],
            'duplicate_detection': [],
            'set_completeness': {},
            'variant_coverage': {},
            'export_validation': {},
            'overall_score': 0.0,
            'recommendations': []
        }
        
        # Comprehensive expected set structure based on complete official One Piece TCG releases
        expected_sets = {
            # Core Booster Sets (Current through 2025)
            'OP-01': {'name': 'Romance Dawn', 'expected_cards': 121, 'type': 'booster'},
            'OP-02': {'name': 'Paramount War', 'expected_cards': 121, 'type': 'booster'},
            'OP-03': {'name': 'Pillars of Strength', 'expected_cards': 121, 'type': 'booster'},
            'OP-04': {'name': 'Kingdoms of Intrigue', 'expected_cards': 121, 'type': 'booster'},
            'OP-05': {'name': 'Awakening of the New Era', 'expected_cards': 121, 'type': 'booster'},
            'OP-06': {'name': 'Wings of the Captain', 'expected_cards': 121, 'type': 'booster'},
            'OP-07': {'name': '500 Years in the Future', 'expected_cards': 121, 'type': 'booster'},
            'OP-08': {'name': 'Two Legends', 'expected_cards': 121, 'type': 'booster'},
            'OP-09': {'name': 'Emperors in the New World', 'expected_cards': 121, 'type': 'booster'},
            'OP-10': {'name': 'Straw Hat Crew', 'expected_cards': 121, 'type': 'booster'},
            'OP-11': {'name': 'Egghead Island', 'expected_cards': 121, 'type': 'booster'},
            'OP-12': {'name': 'Zephyr vs Luffy', 'expected_cards': 121, 'type': 'booster'},
            
            # Premium Booster Sets
            'PRB-01': {'name': 'One Piece Film Red', 'expected_cards': 45, 'type': 'premium'},
            
            # Event Boxes  
            'EB-01': {'name': 'Memorial Collection', 'expected_cards': 35, 'type': 'event'},
            
            # Extra Booster Sets
            'EX-01': {'name': 'Memorial Collection', 'expected_cards': 25, 'type': 'extra'},
            
            # Starter Decks (Complete through ST-25)
            'ST-01': {'name': 'Straw Hat Crew', 'expected_cards': 51, 'type': 'starter'},
            'ST-02': {'name': 'Worst Generation', 'expected_cards': 51, 'type': 'starter'},
            'ST-03': {'name': 'The Seven Warlords of the Sea', 'expected_cards': 51, 'type': 'starter'},
            'ST-04': {'name': 'Animal Kingdom Pirates', 'expected_cards': 51, 'type': 'starter'},
            'ST-05': {'name': 'One Piece Film Edition', 'expected_cards': 51, 'type': 'starter'},
            'ST-06': {'name': 'Navy', 'expected_cards': 51, 'type': 'starter'},
            'ST-07': {'name': 'Big Mom Pirates', 'expected_cards': 51, 'type': 'starter'},
            'ST-08': {'name': 'Monkey D. Luffy', 'expected_cards': 51, 'type': 'starter'},
            'ST-09': {'name': 'Yamato', 'expected_cards': 51, 'type': 'starter'},
            'ST-10': {'name': 'Three Captains', 'expected_cards': 51, 'type': 'ultra'},
            'ST-11': {'name': 'Uta', 'expected_cards': 51, 'type': 'starter'},
            'ST-12': {'name': 'Zoro and Sanji', 'expected_cards': 51, 'type': 'starter'},
            'ST-13': {'name': 'Three Brothers', 'expected_cards': 51, 'type': 'ultra'},
            'ST-14': {'name': 'The Three Sworn Brothers', 'expected_cards': 51, 'type': 'starter'},
            'ST-15': {'name': 'Edward Newgate', 'expected_cards': 51, 'type': 'starter'},
            'ST-16': {'name': 'Black Smoker', 'expected_cards': 51, 'type': 'starter'},
            'ST-17': {'name': 'Portgas D. Ace', 'expected_cards': 51, 'type': 'starter'},
            'ST-18': {'name': 'Charlotte Katakuri', 'expected_cards': 51, 'type': 'starter'},
            'ST-19': {'name': 'Monkey D. Garp', 'expected_cards': 51, 'type': 'starter'},
            'ST-20': {'name': 'Yellow Monkey', 'expected_cards': 51, 'type': 'starter'},
            'ST-21': {'name': 'Vegapunk', 'expected_cards': 51, 'type': 'starter'},
            'ST-22': {'name': 'Rocks Pirates', 'expected_cards': 51, 'type': 'starter'},
            'ST-23': {'name': 'Cross Guild', 'expected_cards': 51, 'type': 'starter'},
            'ST-24': {'name': 'Revolutionary Army', 'expected_cards': 51, 'type': 'starter'},
            'ST-25': {'name': 'Germa 66', 'expected_cards': 51, 'type': 'starter'},
            
            # Tournament Packs
            'TP-01': {'name': 'Tournament Pack Vol. 1', 'expected_cards': 20, 'type': 'tournament'},
            'TP-02': {'name': 'Tournament Pack Vol. 2', 'expected_cards': 20, 'type': 'tournament'},
            'TP-03': {'name': 'Tournament Pack Vol. 3', 'expected_cards': 20, 'type': 'tournament'},
            'TP-04': {'name': 'Tournament Pack Vol. 4', 'expected_cards': 20, 'type': 'tournament'},
            'TP-05': {'name': 'Tournament Pack Vol. 5', 'expected_cards': 20, 'type': 'tournament'},
            
            # Ultra Decks (Special Limited)
            'UT-01': {'name': 'Ultimate Deck - The Four Emperors', 'expected_cards': 60, 'type': 'ultra'},
            'UT-02': {'name': 'Ultimate Deck - The Worst Generation', 'expected_cards': 60, 'type': 'ultra'},
            
            # Premium Tournament Packs
            'PTP-01': {'name': 'Premium Tournament Pack Vol. 1', 'expected_cards': 15, 'type': 'premium'},
            'PTP-02': {'name': 'Premium Tournament Pack Vol. 2', 'expected_cards': 15, 'type': 'premium'},
            
            # Special Limited Sets
            'SL-01': {'name': 'Special Limited Set - Grand Line', 'expected_cards': 30, 'type': 'special'},
            'SL-02': {'name': 'Special Limited Set - New World', 'expected_cards': 30, 'type': 'special'},
            
            # Anniversary Sets
            'AN-01': {'name': 'Anniversary Collection 2023', 'expected_cards': 25, 'type': 'anniversary'},
            'AN-02': {'name': 'Anniversary Collection 2024', 'expected_cards': 25, 'type': 'anniversary'},
            'AN-03': {'name': 'Anniversary Collection 2025', 'expected_cards': 25, 'type': 'anniversary'},
            
            # Promotional Card Categories (Enhanced)
            'P-001': {'name': 'Convention Promos', 'expected_cards': 50, 'type': 'promo'},
            'P-002': {'name': 'Store Championship Promos', 'expected_cards': 30, 'type': 'promo'},
            'P-003': {'name': 'Judge Promos', 'expected_cards': 25, 'type': 'promo'},
            'P-004': {'name': 'Event Participation Promos', 'expected_cards': 40, 'type': 'promo'},
            'P-005': {'name': 'Magazine Promotional Cards', 'expected_cards': 35, 'type': 'promo'},
            'P-006': {'name': 'Online Campaign Promos', 'expected_cards': 20, 'type': 'promo'},
            
            # Winner Cards (High-Value Tournament Prizes)
            'W-001': {'name': 'World Championship Winner Cards', 'expected_cards': 10, 'type': 'winner'},
            'W-002': {'name': 'Regional Championship Winner Cards', 'expected_cards': 15, 'type': 'winner'},
            
            # Staff Cards (Exclusive Staff/Judge Cards)
            'SF-01': {'name': 'Staff Exclusive Cards', 'expected_cards': 12, 'type': 'staff'}
        }
        
        # Analyze card distribution by sets
        found_sets = {}
        card_variants = {}
        duplicate_ids = set()
        seen_ids = set()
        
        for card in cards:
            card_id = card.get('id', 'unknown')
            set_id = card.get('set_id', 'unknown')
            
            # Check for duplicates
            if card_id in seen_ids:
                duplicate_ids.add(card_id)
            seen_ids.add(card_id)
            
            # Track sets
            if set_id not in found_sets:
                found_sets[set_id] = []
            found_sets[set_id].append(card)
            
            # Track variants
            base_name = card.get('name', 'unknown')
            if base_name not in card_variants:
                card_variants[base_name] = []
            card_variants[base_name].append(card)
        
        # Validate set completeness
        for set_id, expected_info in expected_sets.items():
            found_count = len(found_sets.get(set_id, []))
            expected_count = expected_info['expected_cards']
            completion_rate = (found_count / expected_count) * 100 if expected_count > 0 else 0
            
            validation_results['set_completeness'][set_id] = {
                'expected': expected_count,
                'found': found_count,
                'completion_rate': completion_rate,
                'status': 'complete' if completion_rate >= 90 else 'incomplete',
                'missing_count': max(0, expected_count - found_count)
            }
        
        # Analyze variants and special cards
        alt_art_count = sum(1 for card in cards if card.get('is_alternate_art', False))
        promo_count = sum(1 for card in cards if card.get('is_promo', False))
        starter_count = sum(1 for card in cards if card.get('is_starter_deck', False))
        
        validation_results['variant_coverage'] = {
            'alternate_arts': alt_art_count,
            'promotional_cards': promo_count,
            'starter_deck_cards': starter_count,
            'unique_card_names': len(card_variants),
            'cards_with_variants': sum(1 for variants in card_variants.values() if len(variants) > 1)
        }
        
        # Check for missing critical sets
        critical_missing = []
        for set_id, info in validation_results['set_completeness'].items():
            if info['completion_rate'] < 50 and set_id in ['OP-01', 'OP-02', 'OP-03', 'ST-01', 'ST-02']:
                critical_missing.append(f"{set_id} ({info['found']}/{info['expected']} cards)")
        
        # Generate recommendations
        recommendations = []
        if critical_missing:
            recommendations.append(f"Critical sets missing: {', '.join(critical_missing)}")
        if alt_art_count < 100:
            recommendations.append("Consider checking for more alternate art variants")
        if promo_count < 50:
            recommendations.append("Promotional card coverage may be incomplete")
        if len(duplicate_ids) > 0:
            recommendations.append(f"Found {len(duplicate_ids)} duplicate card IDs - review data processing")
        
        # Calculate overall score
        set_scores = [info['completion_rate'] for info in validation_results['set_completeness'].values()]
        average_completion = sum(set_scores) / len(set_scores) if set_scores else 0
        variant_bonus = min(20, (alt_art_count + promo_count) / 10)  # Bonus for variants
        duplicate_penalty = min(10, len(duplicate_ids))  # Penalty for duplicates
        
        validation_results['overall_score'] = max(0, average_completion + variant_bonus - duplicate_penalty)
        validation_results['recommendations'] = recommendations
        validation_results['duplicate_detection'] = list(duplicate_ids)
        
        # Summary statistics
        validation_results['coverage_analysis'] = {
            'total_expected_cards': sum(info['expected_cards'] for info in expected_sets.values()),
            'total_found_cards': len(cards),
            'coverage_percentage': (len(cards) / sum(info['expected_cards'] for info in expected_sets.values())) * 100,
            'sets_complete': sum(1 for info in validation_results['set_completeness'].values() if info['completion_rate'] >= 90),
            'sets_partial': sum(1 for info in validation_results['set_completeness'].values() if 50 <= info['completion_rate'] < 90),
            'sets_missing': sum(1 for info in validation_results['set_completeness'].values() if info['completion_rate'] < 50)
        }
        
        return validation_results
