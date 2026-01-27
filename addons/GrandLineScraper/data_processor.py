import json
import re
from typing import Dict, List, Any, Optional
import streamlit as st

class DataProcessor:
    """Process and normalize card data from different sources"""
    
    def __init__(self):
        self.translation_map = {
            # Common Japanese to English translations
            'キャラクター': 'Character',
            'イベント': 'Event',
            'ステージ': 'Stage',
            'リーダー': 'Leader',
            'ドン': 'Don',
            'コスト': 'Cost',
            'パワー': 'Power',
            'カウンター': 'Counter',
            'ライフ': 'Life',
            '効果': 'Effect',
            '特徴': 'Trait',
            'レアリティ': 'Rarity'
        }
    
    def process_all_data(self, scraped_data: Dict[str, Any], translate_ocg: bool = True) -> Dict[str, Any]:
        """Process and merge all scraped data"""
        processed_data = {
            'cards': [],
            'sets': [],
            'metadata': {
                'total_cards': 0,
                'total_sets': 0,
                'sources': [],
                'languages': [],
                'processed_at': None
            }
        }
        
        all_cards = []
        all_sets = []
        sources = set()
        languages = set()
        
        # Process APITCG data
        if 'apitcg' in scraped_data:
            apitcg_data = scraped_data['apitcg']
            apitcg_cards = self._process_apitcg_cards(apitcg_data.get('cards', []), translate_ocg)
            all_cards.extend(apitcg_cards)
            all_sets.extend(apitcg_data.get('sets', []))
            sources.add('apitcg')
            
            if apitcg_data.get('metadata', {}).get('languages'):
                languages.update(apitcg_data['metadata']['languages'])
        
        # Process GitHub data
        if 'github' in scraped_data:
            github_data = scraped_data['github']
            github_cards = self._process_github_cards(github_data.get('cards', []), translate_ocg)
            all_cards.extend(github_cards)
            all_sets.extend(github_data.get('sets', []))
            sources.add('github')

            if github_data.get('metadata', {}).get('languages'):
                languages.update(github_data['metadata']['languages'])

        # Process OPTCG data
        if 'optcg' in scraped_data:
            optcg_data = scraped_data['optcg']
            optcg_cards = self._process_optcg_cards(optcg_data.get('cards', []))
            all_cards.extend(optcg_cards)
            all_sets.extend(optcg_data.get('sets', []))
            sources.add('optcg')
            languages.add('tcg')

        # Process OnePieceTopDecks data
        if 'onepiecetopdecks' in scraped_data:
            topdecks_data = scraped_data['onepiecetopdecks']
            topdecks_cards = self._process_topdecks_cards(topdecks_data.get('cards', []))
            all_cards.extend(topdecks_cards)
            all_sets.extend(topdecks_data.get('sets', []))
            sources.add('onepiecetopdecks')
            languages.add('tcg')
        
        # Merge and deduplicate cards
        merged_cards = self._merge_duplicate_cards(all_cards)
        
        # Normalize card data
        normalized_cards = self._normalize_cards(merged_cards)
        
        # Process sets
        normalized_sets = self._normalize_sets(all_sets)
        
        processed_data['cards'] = normalized_cards
        processed_data['sets'] = normalized_sets
        processed_data['metadata'].update({
            'total_cards': len(normalized_cards),
            'total_sets': len(normalized_sets),
            'sources': list(sources),
            'languages': list(languages),
            'processed_at': st.session_state.get('scraping_started_at', None)
        })
        
        return processed_data

    def _process_topdecks_cards(self, cards: List[Dict]) -> List[Dict]:
        """Process cards from OnePieceTopDecks (fan-translated)"""
        processed_cards = []

        for card in cards:
            processed_card = self._normalize_card_structure(card)
            processed_card['language'] = 'tcg'
            processed_card['source'] = 'onepiecetopdecks'
            processed_cards.append(processed_card)

        return processed_cards

    def _process_optcg_cards(self, cards: List[Dict]) -> List[Dict]:
        """Process cards from OPTCG API (English overlay)"""
        processed_cards = []

        for card in cards:
            processed_card = self._normalize_card_structure(card)
            processed_card['language'] = 'tcg'
            processed_card['source'] = 'optcg'
            processed_cards.append(processed_card)

        return processed_cards
    
    def _process_apitcg_cards(self, cards: List[Dict], translate_ocg: bool) -> List[Dict]:
        """Process cards from APITCG API"""
        processed_cards = []
        
        for card in cards:
            processed_card = self._normalize_card_structure(card)
            
            # Translate OCG cards if requested
            if translate_ocg and card.get('language') == 'ocg':
                processed_card = self._translate_card_text(processed_card)
            
            processed_cards.append(processed_card)
        
        return processed_cards
    
    def _process_github_cards(self, cards: List[Dict], translate_ocg: bool) -> List[Dict]:
        """Process cards from GitHub repository"""
        processed_cards = []
        
        for card in cards:
            processed_card = self._normalize_card_structure(card)
            
            # Assume GitHub data is primarily Japanese if no language specified
            if not card.get('language'):
                processed_card['language'] = 'ocg'
            
            # Translate if requested and appears to be Japanese
            if translate_ocg and self._is_japanese_text(card.get('name', '')):
                processed_card = self._translate_card_text(processed_card)
            
            processed_cards.append(processed_card)
        
        return processed_cards
    
    def _normalize_card_structure(self, card: Dict) -> Dict:
        """Normalize card structure across different sources"""
        set_id = self._normalize_set_id(card.get('set_id', ''))
        set_code = card.get('set_code') or self._normalize_set_code(set_id)

        number = card.get('number', '')
        if not number:
            number = self._extract_number_from_code(card.get('card_code', '') or card.get('id', ''))

        card_code = card.get('card_code') or (f"{set_code}-{number}" if set_code and number else '')

        card_type = self._normalize_card_type(card.get('type', ''))

        normalized = {
            'id': card.get('id') or f"{card.get('set_id', 'unknown')}-{card.get('number', 'unknown')}",
            'name': card.get('name', ''),
            'name_english': card.get('name_english', ''),
            'name_japanese': card.get('name_japanese', ''),
            'set_id': set_id,
            'set_name': card.get('set_name', ''),
            'set_code': set_code,
            'card_code': card_code,
            'number': number,
            'rarity': card.get('rarity', ''),
            'type': card_type,
            'cost': card.get('cost', 0),
            'power': card.get('power', 0),
            'counter': card.get('counter', 0),
            'life': card.get('life', 0),
            'effect': card.get('effect', ''),
            'effect_english': card.get('effect_english', ''),
            'effect_japanese': card.get('effect_japanese', ''),
            'traits': card.get('traits', []),
            'colors': card.get('colors', []),
            'attribute': card.get('attribute', ''),
            'image_url': card.get('image_url', ''),
            'image_urls': card.get('image_urls', {}),
            'language': card.get('language', 'unknown'),
            'source': card.get('source', 'unknown'),
            'card_type': card.get('card_type', ''),
            'deck_id': card.get('deck_id', ''),
            'deck_name': card.get('deck_name', ''),
            'release_date': card.get('release_date', ''),
            'artist': card.get('artist', ''),
            'parallel_id': card.get('parallel_id', ''),
            'is_alternate_art': card.get('is_alternate_art', False),
            'is_promo': card.get('is_promo', False),
            'is_tournament': card.get('is_tournament', False)
        }
        
        # Ensure numeric fields are properly typed
        for field in ['cost', 'power', 'counter', 'life']:
            try:
                normalized[field] = int(normalized[field]) if normalized[field] else 0
            except (ValueError, TypeError):
                normalized[field] = 0
        
        # Ensure list fields are properly typed
        for field in ['traits', 'colors']:
            if isinstance(normalized[field], str):
                normalized[field] = [t.strip() for t in normalized[field].split(',') if t.strip()]
            elif not isinstance(normalized[field], list):
                normalized[field] = []
        
        # Determine card type flags
        name_lower = normalized['name'].lower()
        source_lower = normalized['source'].lower()
        
        if 'promo' in source_lower or 'promo' in name_lower:
            normalized['is_promo'] = True
        if 'tournament' in source_lower or 'tournament' in name_lower:
            normalized['is_tournament'] = True
        if 'alt' in source_lower or 'alternate' in name_lower or 'parallel' in name_lower:
            normalized['is_alternate_art'] = True
        
        return normalized
    
    def _translate_card_text(self, card: Dict) -> Dict:
        """Translate Japanese text fields to English"""
        translated_card = card.copy()
        
        # Store original Japanese text
        if card.get('language') == 'ocg' and not card.get('name_japanese'):
            translated_card['name_japanese'] = card.get('name', '')
            translated_card['effect_japanese'] = card.get('effect', '')
        
        # Simple translation using mapping (in a real implementation, you'd use a proper translation service)
        name = card.get('name', '')
        effect = card.get('effect', '')
        
        for japanese, english in self.translation_map.items():
            name = name.replace(japanese, english)
            effect = effect.replace(japanese, english)
        
        # Basic romanization of remaining Japanese characters (simplified)
        name = self._romanize_japanese(name)
        effect = self._romanize_japanese(effect)
        
        translated_card['name_english'] = name
        translated_card['effect_english'] = effect
        
        # Update main fields with English versions
        translated_card['name'] = name
        translated_card['effect'] = effect
        
        return translated_card

    def _normalize_set_code(self, set_id: str) -> str:
        if not set_id:
            return ''
        return set_id.replace('-', '')

    def _normalize_set_id(self, set_id: str) -> str:
        if not set_id:
            return ''
        set_id = set_id.strip().upper()
        # Handle composite/quirky upstream IDs like "OP14-EB04" by normalizing
        # the leading set code into our canonical "OP-14" form.
        composite = re.match(r'^([A-Z]+)(\d{2})-(.+)$', set_id)
        if composite:
            prefix, digits, _suffix = composite.groups()
            # Only normalize known numeric set prefixes; keep things like "EB-02" as-is.
            if prefix in {"OP", "ST"}:
                return f"{prefix}-{digits}"
            return set_id
        if '-' in set_id:
            return set_id
        match = re.match(r'^([A-Z]+)(\d+)$', set_id)
        if match:
            prefix, digits = match.groups()
            return f"{prefix}-{digits.zfill(2)}"
        return set_id

    def _extract_number_from_code(self, value: str) -> str:
        if not value:
            return ''
        match = re.search(r'(\d{3})$', value)
        return match.group(1) if match else ''

    def _normalize_card_type(self, value: str) -> str:
        if not value:
            return ''
        value_upper = str(value).strip().upper()
        if 'DON' in value_upper:
            return 'DON!!'
        return str(value).strip().title()
    
    def _romanize_japanese(self, text: str) -> str:
        """Basic romanization of Japanese text (simplified approach)"""
        # This is a very basic implementation
        # In a real application, you would use a proper romanization library
        
        # Remove common Japanese punctuation
        text = re.sub(r'[。、！？]', ' ', text)
        
        # Replace some common characters
        replacements = {
            'の': 'no',
            'と': 'to',
            'は': 'wa',
            'が': 'ga',
            'を': 'wo',
            'に': 'ni',
            'で': 'de',
            'から': 'kara',
            'まで': 'made'
        }
        
        for jp, romaji in replacements.items():
            text = text.replace(jp, romaji)
        
        return text.strip()
    
    def _is_japanese_text(self, text: str) -> bool:
        """Check if text contains Japanese characters"""
        japanese_pattern = re.compile(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF]')
        return bool(japanese_pattern.search(text))
    
    def _merge_duplicate_cards(self, cards: List[Dict]) -> List[Dict]:
        """Merge duplicate cards from different sources"""
        merged_cards = {}
        
        for card in cards:
            # Create a unique key for the card
            key = self._generate_card_key(card)
            
            if key in merged_cards:
                # Merge with existing card
                existing_card = merged_cards[key]
                merged_card = self._merge_card_data(existing_card, card)
                merged_cards[key] = merged_card
            else:
                merged_cards[key] = card
        
        return list(merged_cards.values())
    
    def _generate_card_key(self, card: Dict) -> str:
        """Generate a unique key for a card"""
        # Use set_id, number, and name to identify unique cards - safe None handling
        set_id = (card.get('set_id') or '').upper()
        number = (card.get('number') or '').upper()
        name = re.sub(r'[^\w\s]', '', card.get('name') or '').upper()
        
        return f"{set_id}-{number}-{name[:20]}"
    
    def _merge_card_data(self, card1: Dict, card2: Dict) -> Dict:
        """Merge data from two card objects"""
        merged = card1.copy()

        source2 = str(card2.get('source', '')).lower()
        prefer_optcg = source2 == 'optcg'
        override_fields = {
            'name', 'effect', 'name_english', 'effect_english', 'image_url',
            'rarity', 'type', 'traits', 'colors', 'attribute', 'cost',
            'power', 'counter', 'life', 'language', 'set_name', 'set_code',
            'card_code', 'number'
        }
        
        # Prefer non-empty values from either card
        for key, value in card2.items():
            if prefer_optcg and key in override_fields and value:
                merged[key] = value
            elif key not in merged or not merged[key]:
                merged[key] = value
            elif key == 'sources':
                # Merge source lists
                sources = set(merged.get('sources', []))
                sources.update(card2.get('sources', []))
                merged['sources'] = list(sources)
            elif key == 'image_urls':
                # Merge image URL dictionaries
                merged_urls = merged.get('image_urls', {})
                merged_urls.update(card2.get('image_urls', {}))
                merged['image_urls'] = merged_urls
        
        # Add sources tracking
        if 'sources' not in merged:
            merged['sources'] = []
        
        source1 = card1.get('source', 'unknown')
        source2 = card2.get('source', 'unknown')
        
        sources = set(merged['sources'])
        sources.add(source1)
        sources.add(source2)
        merged['sources'] = list(sources)
        
        return merged
    
    def _normalize_cards(self, cards: List[Dict]) -> List[Dict]:
        """Final normalization and cleanup of cards"""
        normalized_cards = []
        
        for card in cards:
            # Ensure all required fields exist
            normalized_card = self._ensure_required_fields(card)
            
            # Clean up text fields
            normalized_card = self._clean_text_fields(normalized_card)
            
            # Validate and fix data types
            normalized_card = self._validate_data_types(normalized_card)
            
            normalized_cards.append(normalized_card)
        
        return normalized_cards
    
    def _normalize_sets(self, sets: List[Dict]) -> List[Dict]:
        """Normalize set data"""
        normalized_sets = []
        seen_sets = set()
        
        for set_data in sets:
            set_id = str(set_data.get('id', '') or '')
            language = str(set_data.get('language', 'unknown') or 'unknown')
            dedupe_key = (set_id, language)
            if dedupe_key in seen_sets:
                continue

            label = (
                str(set_data.get('label', '') or '')
                or str(set_data.get('set_code', '') or '')
                or str(set_data.get('code', '') or '')
            )
            title = (
                str(set_data.get('title', '') or '')
                or str(set_data.get('name', '') or '')
                or label
            )
            name = str(set_data.get('name', '') or '') or title
            
            normalized_set = {
                'id': set_id,
                'name': name,
                'name_english': set_data.get('name_english', ''),
                'name_japanese': set_data.get('name_japanese', ''),
                'title': title,
                'label': label,
                'prefix': set_data.get('prefix', ''),
                'release_date': set_data.get('release_date', ''),
                'card_count': set_data.get('card_count', 0),
                'language': language,
                'type': set_data.get('type', 'booster'),
                'source': set_data.get('source', ''),
                'block': set_data.get('block', ''),
                'symbol': set_data.get('symbol', ''),
                'code': str(set_data.get('code', '') or '') or label,
                'url': set_data.get('url', ''),
                'image_url': set_data.get('image_url', '')
            }
            
            normalized_sets.append(normalized_set)
            seen_sets.add(dedupe_key)
        
        return normalized_sets
    
    def _ensure_required_fields(self, card: Dict) -> Dict:
        """Ensure all required fields exist with default values"""
        required_fields = {
            'id': 'unknown',
            'name': 'Unknown Card',
            'set_id': 'unknown',
            'number': '000',
            'rarity': 'Common',
            'type': 'Character',
            'cost': 0,
            'power': 0,
            'language': 'unknown',
            'source': 'unknown'
        }
        
        for field, default_value in required_fields.items():
            if field not in card or not card[field]:
                card[field] = default_value
        
        return card
    
    def _clean_text_fields(self, card: Dict) -> Dict:
        """Clean up text fields"""
        text_fields = ['name', 'effect', 'name_english', 'effect_english', 'artist']
        
        for field in text_fields:
            if field in card and isinstance(card[field], str):
                # Remove extra whitespace
                card[field] = ' '.join(card[field].split())
                
                # Remove HTML tags if present
                card[field] = re.sub(r'<[^>]+>', '', card[field])

                # Remove disclaimer text from sources that add it
                card[field] = re.sub(r'Disclaimer:.*$', '', card[field]).strip()

                # Normalize literal NULL strings
                if card[field].upper() == 'NULL':
                    card[field] = ''
        
        return card
    
    def _validate_data_types(self, card: Dict) -> Dict:
        """Validate and fix data types"""
        # Ensure boolean fields
        boolean_fields = ['is_alternate_art', 'is_promo', 'is_tournament']
        for field in boolean_fields:
            if field in card:
                card[field] = bool(card[field])
        
        # Ensure integer fields
        integer_fields = ['cost', 'power', 'counter', 'life']
        for field in integer_fields:
            if field in card:
                try:
                    card[field] = int(card[field]) if card[field] else 0
                except (ValueError, TypeError):
                    card[field] = 0
        
        # Ensure list fields
        list_fields = ['traits', 'colors', 'sources']
        for field in list_fields:
            if field in card and not isinstance(card[field], list):
                if isinstance(card[field], str):
                    card[field] = [item.strip() for item in card[field].split(',') if item.strip()]
                else:
                    card[field] = []
        
        return card
