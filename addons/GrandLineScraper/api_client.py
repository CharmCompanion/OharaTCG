import requests
import json
import time
import os
import re
from urllib.parse import urljoin
from typing import Dict, List, Any, Optional
import streamlit as st

class APITCGClient:
    """Client for comprehensive One Piece TCG data from GitHub repositories"""
    
    def __init__(self, api_key: str):
        self.api_key = api_key  # Keep for compatibility, not needed for GitHub
        # Primary comprehensive data sources (TCG = English, OCG = Japanese)
        self.vegapull_tcg_base = "https://raw.githubusercontent.com/Coko7/vegapull-records/main/data/english"
        self.vegapull_ocg_base = "https://raw.githubusercontent.com/Coko7/vegapull-records/main/data/japanese"
        self.vegapull_images_url = "https://github.com/Coko7/vegapull-records/releases/download/2025-04-27/english-images-2025-04-27.zip"
        # Secondary data source
        self.github_base = "https://raw.githubusercontent.com/apitcg/one-piece-tcg-data/main"
        
        self.session = requests.Session()
        self.session.headers.update({
            'Content-Type': 'application/json',
            'User-Agent': 'OnePieceTCGScraper/1.0'
        })
    
    def fetch_all_data(self, card_types: Dict[str, bool], include_ocg: bool, include_tcg: bool) -> Dict[str, Any]:
        """Fetch comprehensive card data from GitHub repositories"""
        all_data = {
            'cards': [],
            'sets': [],
            'decks': [],
            'metadata': {
                'scraped_at': time.time(),
                'sources': ['vegapull-records', 'github'],
                'languages': [],
                'total_packs': 0,
                'image_archive_url': self.vegapull_images_url
            }
        }
        
        try:
            # Step 1: Fetch comprehensive pack lists for requested languages
            st.write("🔍 Fetching comprehensive pack list...")

            ocg_data: Optional[Dict[str, Any]] = None

            packs_data = []

            if include_tcg:
                tcg_packs = self._fetch_all_packs(self.vegapull_tcg_base, "tcg")
                packs_data.extend(tcg_packs)
                all_data['metadata']['languages'].append('tcg')

            if include_ocg:
                # OCG dataset format differs (single cards.json in japanese/)
                ocg_data = self._fetch_ocg_cards_json()
                ocg_packs = ocg_data.get('sets', [])
                packs_data.extend(ocg_packs)
                all_data['metadata']['languages'].append('ocg')

            all_data['sets'] = packs_data
            all_data['metadata']['total_packs'] = len(packs_data)
            st.write(f"✅ Found {len(packs_data)} total packs (booster, starter, promo, etc.)")
            
            # Step 2: Fetch all cards from all packs
            st.write("📋 Fetching cards from all packs...")
            all_cards = []

            # OCG: cards are already available from cards.json
            if include_ocg:
                ocg_cards = (ocg_data or {}).get('cards', [])
                if ocg_cards:
                    all_cards.extend(ocg_cards)
                    st.write(f"✅ OCG: {len(ocg_cards)} cards")
            
            for pack in packs_data:
                pack_id = pack.get('id')

                # OCG cards are handled in bulk from cards.json
                if pack.get('language') == 'ocg':
                    continue
                
                # Filter based on user selections
                if not self._should_include_pack(pack, card_types):
                    continue
                    
                try:
                    base_url = self.vegapull_ocg_base if pack.get('language') == 'ocg' else self.vegapull_tcg_base
                    cards = self._fetch_cards_from_pack(base_url, pack_id, pack)
                    all_cards.extend(cards)
                    st.write(f"✅ {pack.get('title', pack_id)} ({pack.get('language', 'tcg')}): {len(cards)} cards")
                    time.sleep(0.1)  # Rate limiting
                    
                except Exception as e:
                    st.warning(f"Failed to fetch cards from pack {pack_id}: {str(e)}")
                    continue
            
            all_data['cards'] = all_cards
            
            # Step 3: Fetch additional GitHub data if enabled
            if card_types.get('Alt Arts', False) or card_types.get('Promos', False):
                github_cards = self._fetch_github_supplementary_data()
                all_data['cards'].extend(github_cards)
                st.write(f"✅ Fetched {len(github_cards)} supplementary cards from GitHub")
            
            # Remove duplicates and finalize
            unique_cards = self._deduplicate_cards(all_data['cards'])
            all_data['cards'] = unique_cards
            
            st.write(f"🎉 Total unique cards collected: {len(unique_cards)}")
            
        except Exception as e:
            st.error(f"Error fetching comprehensive card data: {str(e)}")
            raise
        
        return all_data

    def fetch_set_list(self, include_ocg: bool, include_tcg: bool) -> List[Dict[str, Any]]:
        """Fetch set list without card data (for downstream clients)"""
        packs_data = []
        if include_tcg:
            packs_data.extend(self._fetch_all_packs(self.vegapull_tcg_base, "tcg"))
        if include_ocg:
            packs_data.extend(self._fetch_all_packs(self.vegapull_ocg_base, "ocg"))
        return packs_data
    
    def _fetch_all_packs(self, base_url: str, language: str) -> List[Dict[str, Any]]:
        """Fetch comprehensive pack list from vegapull repository for a given language"""
        try:
            response = self.session.get(f"{base_url}/packs.json")
            response.raise_for_status()
            packs_data = response.json()
            
            normalized_packs = []
            for pack in packs_data:
                pack_type = self._determine_pack_type(pack.get('raw_title', ''))
                normalized_pack = {
                    'id': pack.get('id'),
                    'name': pack.get('raw_title', ''),
                    'title': pack.get('title_parts', {}).get('title', ''),
                    'prefix': pack.get('title_parts', {}).get('prefix', ''),
                    'label': pack.get('title_parts', {}).get('label', ''),
                    'type': pack_type,
                    'language': language,
                    'source': 'vegapull'
                }
                normalized_packs.append(normalized_pack)
                
            return normalized_packs
            
        except requests.RequestException as e:
            # Not all languages/feeds expose packs.json (e.g. japanese currently uses cards.json)
            st.warning(f"Failed to fetch pack list: {str(e)}")
            return []

    def _fetch_ocg_cards_json(self) -> Dict[str, Any]:
        """Fetch and normalize OCG data from vegapull japanese/cards.json.

        The japanese feed does not provide packs.json / cards_<pack>.json.
        Instead it contains a top-level JSON with card_sets[].
        """
        try:
            response = self.session.get(f"{self.vegapull_ocg_base}/cards.json")
            response.raise_for_status()
            data = response.json()

            base_url = (data.get('base_url') or '').strip() or 'https://en.onepiece-cardgame.com'
            card_sets = data.get('card_sets') if isinstance(data, dict) else None
            if not isinstance(card_sets, list):
                return {'sets': [], 'cards': []}

            normalized_sets: List[Dict[str, Any]] = []
            normalized_cards: List[Dict[str, Any]] = []

            for card_set in card_sets:
                if not isinstance(card_set, dict):
                    continue

                set_title = str(card_set.get('title', '') or '')
                set_code = self._extract_set_code_from_title(set_title)
                pack_type = self._determine_pack_type_any_language(set_title)

                normalized_set = {
                    'id': str(card_set.get('id', '') or ''),
                    'name': set_title,
                    'title': set_title,
                    'prefix': '',
                    'label': set_code,
                    'type': pack_type,
                    'language': 'ocg',
                    'source': 'vegapull',
                }
                normalized_sets.append(normalized_set)

                cards = card_set.get('cards', [])
                if not isinstance(cards, list):
                    continue

                for card in cards:
                    normalized = self._normalize_vegapull_ocg_card(card, normalized_set, base_url)
                    if normalized:
                        normalized_cards.append(normalized)

            return {'sets': normalized_sets, 'cards': normalized_cards}

        except requests.RequestException as e:
            st.warning(f"Failed to fetch OCG cards.json: {str(e)}")
            return {'sets': [], 'cards': []}

    def _extract_set_code_from_title(self, title: str) -> str:
        """Extract set code from titles like '...【PRB-01】'. Returns normalized non-hyphen code (PRB01)."""
        if not title:
            return ''
        match = re.search(r"【\s*([A-Z]+-?\d+)\s*】", title)
        if not match:
            return ''
        return match.group(1).replace('-', '').strip()

    def _determine_pack_type_any_language(self, title: str) -> str:
        """Determine pack type from either English or Japanese titles."""
        if not title:
            return 'unknown'

        # Japanese heuristics
        if 'スタートデッキ' in title:
            return 'starter_deck'
        if 'ブースター' in title or 'プレミアムブースター' in title:
            return 'booster_pack'
        if 'プロモーション' in title or 'プロモ' in title:
            return 'promo'

        # Fallback to existing English heuristics
        return self._determine_pack_type(title)

    def _normalize_vegapull_ocg_card(self, card: Dict[str, Any], pack_info: Dict[str, Any], base_url: str) -> Optional[Dict[str, Any]]:
        """Normalize OCG card structure (from japanese/cards.json) to app schema."""
        if not isinstance(card, dict):
            return None

        card_id = str(card.get('id', '') or '').strip()
        name = str(card.get('name', '') or '').strip()
        rarity = str(card.get('rarity', '') or '').strip()
        rarity_upper = rarity.upper()

        # Determine set code and number from card id when possible (e.g., OP01-006_p3)
        parsed_set_code = ''
        number = ''
        match = re.match(r"^([A-Z]{1,4}\d{0,2}|PRB\d{2}|EB\d{2}|OP\d{2}|ST\d{2})-(\d{1,4})", card_id)
        if match:
            parsed_set_code = match.group(1)
            number = match.group(2).zfill(3)

        set_code = (pack_info.get('label') or '').strip() or parsed_set_code
        set_id = set_code
        card_code = f"{set_code}-{number}" if set_code and number else card_id

        img_url = str(card.get('img_url', '') or '').strip()
        image_url = urljoin(base_url + '/', img_url)

        category = str(card.get('category', '') or '').strip()

        return {
            'id': card_id or card_code,
            'name': name,
            'set_id': set_id,
            'set_name': pack_info.get('name') or '',
            'set_code': set_code,
            'card_code': card_code,
            'pack_id': pack_info.get('id'),
            'number': number,
            'rarity': rarity,
            'type': category,
            'cost': self._safe_int(card.get('cost', 0)),
            'power': self._safe_int(card.get('power', 0)),
            'counter': self._safe_int(card.get('counter', 0)),
            'life': self._safe_int(card.get('life', 0)),
            'effect': str(card.get('effect', '') or ''),
            'traits': self._ensure_list(card.get('types', [])),
            'colors': self._ensure_list(card.get('colors', [])),
            'attribute': self._ensure_list(card.get('attributes', []))[0] if self._ensure_list(card.get('attributes', [])) else '',
            'image_url': image_url,
            'language': 'ocg',
            'source': 'vegapull',
            'pack_type': pack_info.get('type', 'unknown'),
            'is_promo': pack_info.get('type') == 'promo',
            'is_starter_deck': pack_info.get('type') == 'starter_deck',
            'is_alternate_art': 'ALT' in rarity_upper or 'PARALLEL' in rarity_upper,
            'artist': str(card.get('artist', '') or ''),
            'release_date': str(card.get('release_date', '') or ''),
            'parallel_id': str(card.get('parallel_id', '') or ''),
            'variant': str(card.get('variant', '') or ''),
        }
    
    def _determine_pack_type(self, title: str) -> str:
        """Determine pack type from title"""
        if not title:
            return 'unknown'
            
        title_upper = title.upper()
        if 'STARTER DECK' in title_upper or 'ULTRA DECK' in title_upper:
            return 'starter_deck'
        elif 'BOOSTER' in title_upper:
            return 'booster_pack'
        elif 'PROMOTION' in title_upper:
            return 'promo'
        elif 'OTHER PRODUCT' in title_upper:
            return 'other'
        else:
            return 'unknown'
    
    def _should_include_pack(self, pack: Dict[str, Any], card_types: Dict[str, bool]) -> bool:
        """Determine if pack should be included based on user selections"""
        pack_type = pack.get('type', 'unknown')
        
        if pack_type == 'booster_pack' and card_types.get('Sets', True):
            return True
        elif pack_type == 'starter_deck' and card_types.get('Decks', True):
            return True
        elif pack_type == 'promo' and card_types.get('Promos', True):
            return True
        elif pack_type == 'other' and card_types.get('Alt Arts', True):
            return True
        else:
            # Include everything by default to ensure comprehensive coverage
            return True
    
    def _fetch_cards_from_pack(self, base_url: str, pack_id: str, pack_info: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Fetch all cards from a specific pack and language"""
        try:
            response = self.session.get(f"{base_url}/cards_{pack_id}.json")
            response.raise_for_status()
            cards_data = response.json()
            
            normalized_cards = []
            for card in cards_data:
                normalized_card = self._normalize_vegapull_card(card, pack_info)
                normalized_cards.append(normalized_card)
                
            return normalized_cards
            
        except requests.RequestException as e:
            # Some packs might not have card files, this is normal
            return []
    
    def _normalize_vegapull_card(self, card: Dict[str, Any], pack_info: Dict[str, Any]) -> Dict[str, Any]:
        """Normalize card data from vegapull format"""
        # Safe string handling for None values
        rarity = card.get('rarity') or ''
        rarity_upper = rarity.upper() if rarity else ''

        set_id = pack_info.get('label', pack_info.get('id', ''))
        set_code = (set_id or '').replace('-', '')
        number = card.get('number') or ''
        card_code = f"{set_code}-{number}" if set_code and number else (card.get('id') or '')
        
        return {
            'id': card.get('id', f"{pack_info.get('id', '')}-{card.get('number', '000')}"),
                'name': card.get('name') or '',
            'set_id': set_id,
            'set_name': pack_info.get('name') or '',
            'set_code': set_code,
            'card_code': card_code,
            'pack_id': pack_info.get('id'),
            'number': number,
            'rarity': rarity,
            'type': card.get('type') or '',
            'cost': self._safe_int(card.get('cost', 0)),
            'power': self._safe_int(card.get('power', 0)),
            'counter': self._safe_int(card.get('counter', 0)),
            'life': self._safe_int(card.get('life', 0)),
            'effect': card.get('effect') or '',
            'traits': self._ensure_list(card.get('traits', [])),
            'colors': self._ensure_list(card.get('colors', [])),
            'attribute': card.get('attribute') or '',
            'image_url': card.get('image_url') or '',
            'language': pack_info.get('language', 'tcg'),
            'source': 'vegapull',
            'pack_type': pack_info.get('type', 'unknown'),
            'is_promo': pack_info.get('type') == 'promo',
            'is_starter_deck': pack_info.get('type') == 'starter_deck',
            'is_alternate_art': 'ALT' in rarity_upper or 'PARALLEL' in rarity_upper,
            'artist': card.get('artist') or '',
            'release_date': card.get('release_date') or '',
            'parallel_id': card.get('parallel_id') or '',
            'variant': card.get('variant') or '',
        }
    
    def _safe_int(self, value: Any) -> int:
        """Safely convert value to integer"""
        try:
            if isinstance(value, str) and value.strip() == '':
                return 0
            return int(value) if value else 0
        except (ValueError, TypeError):
            return 0
    
    def _ensure_list(self, value: Any) -> List[str]:
        """Ensure value is a list of strings"""
        if isinstance(value, list):
            return [str(item) for item in value]
        elif isinstance(value, str):
            return [item.strip() for item in value.split(',') if item.strip()]
        else:
            return []
    
    def _fetch_github_supplementary_data(self) -> List[Dict[str, Any]]:
        """Fetch supplementary card data from secondary GitHub repository"""
        supplementary_cards = []
        
        try:
            # Try to fetch additional data from apitcg repository
            paths = ['cards/en/', 'sets/en/']
            
            for path in paths:
                try:
                    response = self.session.get(f"{self.github_base}/{path}")
                    if response.status_code == 200:
                        st.write(f"✅ Found supplementary data at {path}")
                        # Process any additional data found
                        # This would require more investigation of the structure
                except:
                    continue
                    
        except Exception as e:
            st.info(f"No supplementary GitHub data available: {str(e)}")
            
        return supplementary_cards
    
    def _deduplicate_cards(self, cards: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Remove duplicate cards and merge data"""
        unique_cards = {}
        
        for card in cards:
            # Create unique key combining multiple identifiers
            card_id = card.get('id', '')
            card_number = card.get('number', '')
            card_name = card.get('name', '')
            set_id = card.get('set_id', '')
            
            # Primary key: use card ID if available
            if card_id:
                key = card_id
            else:
                # Fallback key: combine set and number
                key = f"{set_id}-{card_number}"
            
            if key in unique_cards:
                # Merge additional data, preferring non-empty values
                existing = unique_cards[key]
                for field, value in card.items():
                    if value and not existing.get(field):
                        existing[field] = value
            else:
                unique_cards[key] = card
                
        return list(unique_cards.values())
    
    def _fetch_deck_cards(self, include_ocg: bool, include_tcg: bool) -> List[Dict[str, Any]]:
        """Legacy method - now handled in comprehensive fetch"""
        st.info("✅ Starter decks are included in comprehensive pack fetching")
        return []
    
    def _fetch_promo_cards(self, include_ocg: bool, include_tcg: bool) -> List[Dict[str, Any]]:
        """Legacy method - now handled in comprehensive fetch"""
        st.info("✅ Promo cards are included in comprehensive pack fetching")
        return []
    
    def _fetch_tournament_cards(self, include_ocg: bool, include_tcg: bool) -> List[Dict[str, Any]]:
        """Legacy method - now handled in comprehensive fetch"""
        st.info("✅ Tournament cards are included in comprehensive pack fetching")
        return []
    
    def _fetch_don_cards(self, include_ocg: bool, include_tcg: bool) -> List[Dict[str, Any]]:
        """Legacy method - now handled in comprehensive fetch"""
        st.info("✅ Don cards are included in comprehensive pack fetching")
        return []
    
    def _fetch_alt_art_cards(self, include_ocg: bool, include_tcg: bool) -> List[Dict[str, Any]]:
        """Legacy method - now handled in comprehensive fetch"""
        st.info("✅ Alt art cards are included in comprehensive pack fetching")
        return []
    
    def fetch_github_data(self) -> Dict[str, Any]:
        """Fetch additional card data from GitHub repository"""
        github_data = {
            'cards': [],
            'metadata': {
                'source': 'github',
                'repository': 'one-piece-tcg/one-piece-tcg-data'
            }
        }
        
        try:
            # Common file paths in the repository
            file_paths = [
                'cards.json',
                'sets.json',
                'promos.json',
                'tournaments.json',
                'data/cards.json',
                'data/sets.json'
            ]
            
            for file_path in file_paths:
                try:
                    url = f"{self.github_base}/{file_path}"
                    response = requests.get(url, timeout=30)
                    
                    if response.status_code == 200:
                        data = response.json()
                        
                        if isinstance(data, list):
                            for item in data:
                                item['source'] = 'github'
                                github_data['cards'].append(item)
                        elif isinstance(data, dict):
                            if 'cards' in data:
                                for card in data['cards']:
                                    card['source'] = 'github'
                                    github_data['cards'].append(card)
                            elif 'data' in data:
                                for card in data['data']:
                                    card['source'] = 'github'
                                    github_data['cards'].append(card)
                        
                        st.write(f"✅ Fetched GitHub data from {file_path}")
                
                except (requests.RequestException, json.JSONDecodeError) as e:
                    # File doesn't exist or invalid JSON, continue to next
                    continue
                
                time.sleep(0.1)
        
        except Exception as e:
            st.warning(f"Failed to fetch GitHub data: {str(e)}")
        
        return github_data
