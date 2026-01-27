import re
import time
from typing import Dict, List, Any, Optional
import requests
import streamlit as st

class OPTcgClient:
    """Client for OPTCG API (English TCG data + images)"""

    def __init__(self):
        self.api_root = "https://optcgapi.com/api"
        self.session = requests.Session()
        self.session.headers.update({
            "Content-Type": "application/json",
            "User-Agent": "OnePieceTCGScraper/1.0"
        })

    def fetch_cards_for_sets(
        self,
        set_ids: List[str],
        *,
        include_sets: bool = True,
        include_decks: bool = True,
        include_promos: bool = True,
        include_optcg_catalog: bool = True,
    ) -> Dict[str, Any]:
        """Fetch OPTCG cards for requested IDs.

        This client can fetch:
        - set cards via /api/sets/{set_id}/
        - starter deck cards via /api/decks/{st_id}/
        - promo cards via /api/allPromos/

        If include_optcg_catalog=True, we also include all set/deck IDs discovered
        from /api/allSets/ and /api/allDecks/ so new releases (e.g. OP14, ST-27)
        are pulled even if upstream pack lists are stale.
        """

        all_cards: List[Dict[str, Any]] = []

        requested_ids = [sid for sid in self._unique_non_empty(set_ids)]

        available_sets = self.fetch_available_sets() if (include_optcg_catalog and include_sets) else []
        available_decks = self.fetch_available_decks() if (include_optcg_catalog and include_decks) else []

        # Merge requested IDs with catalog IDs.
        ids_to_fetch: List[str] = []
        ids_to_fetch.extend(requested_ids)
        if include_sets:
            ids_to_fetch.extend([s.get("set_id", "") for s in available_sets if s.get("set_id")])
        ids_to_fetch.extend([d.get("structure_deck_id", "") for d in available_decks if d.get("structure_deck_id")])
        ids_to_fetch = self._unique_non_empty([i for i in ids_to_fetch if i])
        ids_to_fetch = sorted(ids_to_fetch, key=self._id_sort_key)

        set_count = 0
        deck_count = 0

        for raw_id in ids_to_fetch:
            normalized = self._normalize_any_id_for_optcg(raw_id)
            if not normalized:
                continue

            try:
                if normalized.startswith("ST-"):
                    if not include_decks:
                        continue
                    cards = self._fetch_deck_cards(normalized)
                    deck_count += 1
                    label = normalized
                else:
                    if not include_sets:
                        continue
                    resolved_set_id = self._resolve_set_id_for_optcg(normalized, available_sets)
                    if not resolved_set_id:
                        continue
                    cards = self._fetch_set_cards(resolved_set_id)
                    set_count += 1
                    label = resolved_set_id

                if cards:
                    all_cards.extend(cards)
                    st.write(f"✅ OPTCG: {label} - {len(cards)} cards")
                time.sleep(0.1)
            except Exception as e:
                st.warning(f"OPTCG failed for {normalized}: {str(e)}")
                continue

        promo_cards: List[Dict[str, Any]] = []
        if include_promos:
            try:
                promo_cards = self._fetch_all_promos()
                if promo_cards:
                    all_cards.extend(promo_cards)
                    st.write(f"✅ OPTCG: promos - {len(promo_cards)} cards")
            except Exception as e:
                st.warning(f"OPTCG promos failed: {str(e)}")

        optcg_sets_normalized = [self._normalize_optcg_set(s) for s in (available_sets or [])]
        optcg_decks_normalized = [self._normalize_optcg_deck(d) for d in (available_decks or [])]
        optcg_sets_normalized = [s for s in optcg_sets_normalized if s]
        optcg_decks_normalized = [d for d in optcg_decks_normalized if d]

        return {
            "cards": all_cards,
            "sets": optcg_sets_normalized + optcg_decks_normalized,
            "metadata": {
                "source": "optcg",
                "total_cards": len(all_cards),
                "requested_ids": len(requested_ids),
                "total_ids_fetched": len(ids_to_fetch),
                "sets_fetched": set_count,
                "decks_fetched": deck_count,
                "promos_fetched": len(promo_cards),
                "language": "tcg",
                "fetched_at": time.time(),
            },
        }

    def fetch_available_sets(self) -> List[Dict[str, Any]]:
        """Return OPTCG's advertised set list from /api/allSets/."""
        url = f"{self.api_root}/allSets/"
        response = self.session.get(url, timeout=30)
        response.raise_for_status()
        data = response.json()
        return data if isinstance(data, list) else []

    def fetch_available_decks(self) -> List[Dict[str, Any]]:
        """Return OPTCG's advertised starter deck list from /api/allDecks/."""
        url = f"{self.api_root}/allDecks/"
        response = self.session.get(url, timeout=30)
        response.raise_for_status()
        data = response.json()
        return data if isinstance(data, list) else []

    def _fetch_set_cards(self, set_id: str) -> List[Dict[str, Any]]:
        """Fetch cards from OPTCG API for a specific set"""
        url = f"{self.api_root}/sets/{set_id}/"
        response = self.session.get(url, timeout=30)
        response.raise_for_status()
        data = response.json()

        cards_raw = data.get("value", []) if isinstance(data, dict) else data
        normalized_cards = [self._normalize_optcg_card(card) for card in cards_raw]
        return [c for c in normalized_cards if c]

    def _fetch_deck_cards(self, deck_id: str) -> List[Dict[str, Any]]:
        """Fetch cards from OPTCG API for a specific starter deck (ST-xx)."""
        url = f"{self.api_root}/decks/{deck_id}/"
        response = self.session.get(url, timeout=30)
        response.raise_for_status()
        data = response.json()

        cards_raw = data.get("value", []) if isinstance(data, dict) else data
        normalized_cards = [self._normalize_optcg_card(card) for card in cards_raw]
        return [c for c in normalized_cards if c]

    def _fetch_all_promos(self) -> List[Dict[str, Any]]:
        """Fetch promo cards.

        Documentation lists /api/allPromoCards/, but the live API currently serves
        promo data from /api/allPromos/.
        """
        url = f"{self.api_root}/allPromos/"
        response = self.session.get(url, timeout=30)
        response.raise_for_status()
        data = response.json()
        cards_raw = data.get("value", []) if isinstance(data, dict) else data
        normalized_cards = [self._normalize_optcg_card(card, force_promo=True) for card in cards_raw]
        return [c for c in normalized_cards if c]

    def _normalize_optcg_card(self, card: Dict[str, Any], *, force_promo: bool = False) -> Optional[Dict[str, Any]]:
        """Normalize OPTCG card structure to app schema"""
        if not isinstance(card, dict):
            return None

        card_set_id = str(card.get("card_set_id", "") or "").strip()
        set_id = str(card.get("set_id", "") or "").strip()
        set_name = str(card.get("set_name", "") or "").strip()
        card_name = str(card.get("card_name", "") or "").strip()
        card_text = card.get("card_text")
        card_text = "" if card_text in [None, "NULL"] else str(card_text).strip()

        # Some OPTCG promo entries are malformed and use a color list as set_id/card_set_id.
        # Example: set_id == "Blue Green Purple Red Black Yellow" with card_color == "Leader".
        if self._is_malformed_rainbow_leader_entry(set_id, card_set_id, card.get("card_color"), card.get("card_type")):
            normalized_set_id = "Promos"
            set_code = "P"
            number = ""
            card_code = self._make_synthetic_promo_code(card_name)

            return {
                "id": card_code,
                "name": card_name,
                "name_english": card_name,
                "name_japanese": "",
                "set_id": normalized_set_id,
                "set_name": set_name or "One Piece Promotion Cards",
                "set_code": set_code,
                "card_code": card_code,
                "number": "000",
                "rarity": card.get("rarity", "") or "",
                "type": "Leader",
                "cost": 0,
                "power": self._safe_int(card.get("life")),
                "counter": 0,
                "life": 5,
                "effect": card_text,
                "effect_english": card_text,
                "traits": self._parse_traits(card.get("card_power")),
                "colors": ["Red", "Green", "Blue", "Purple", "Black", "Yellow"],
                "attribute": str(card.get("sub_types", "") or "").strip(),
                "image_url": "",
                "image_urls": {
                    "large": "",
                    "normal": "",
                },
                "language": "tcg",
                "source": "optcg",
                "release_date": card.get("date_scraped", "") or "",
                "artist": "",
                "parallel_id": "",
                "variant": "",
                "is_alternate_art": False,
                "is_promo": True,
                "is_tournament": False,
            }

        normalized_set_id = self._normalize_set_id_for_optcg(set_id) or set_id
        normalized_set_id = self._normalize_set_id_for_app(normalized_set_id)
        number = self._extract_card_number(card_set_id)
        set_code = self._normalize_set_code(normalized_set_id)
        card_code = f"{set_code}-{number}" if set_code and number else card_set_id

        card_type = str(card.get("card_type", "") or "").strip()
        card_type = self._normalize_card_type(card_type)

        traits = self._parse_traits(card.get("sub_types"))
        colors = self._parse_colors(card.get("card_color"))

        image_url = str(card.get("card_image", "") or "").strip()
        card_image_id = str(card.get("card_image_id", "") or "").strip()

        is_parallel = self._is_parallel_variant(card_name)

        # promos are either explicit P-xxx codes or entries from /api/allPromos/
        is_promo = force_promo or card_set_id.startswith("P")

        return {
            "id": card_image_id or card_set_id or card_code,
            "name": card_name,
            "name_english": card_name,
            "name_japanese": "",
            "set_id": normalized_set_id,
            "set_name": set_name,
            "set_code": set_code,
            "card_code": card_code,
            "number": number,
            "rarity": card.get("rarity", "") or "",
            "type": card_type,
            "cost": self._safe_int(card.get("card_cost")),
            "power": self._safe_int(card.get("card_power")),
            "counter": self._safe_int(card.get("counter_amount")),
            "life": self._safe_int(card.get("life")),
            "effect": card_text,
            "effect_english": card_text,
            "traits": traits,
            "colors": colors,
            "attribute": card.get("attribute", "") or "",
            "image_url": image_url,
            "image_urls": {
                "large": image_url,
                "normal": image_url
            },
            "language": "tcg",
            "source": "optcg",
            "release_date": card.get("date_scraped", "") or "",
            "artist": "",
            "parallel_id": "",
            "variant": "Parallel" if is_parallel else "",
            "is_alternate_art": is_parallel,
            "is_promo": is_promo,
            "is_tournament": False
        }

    def _is_malformed_rainbow_leader_entry(self, set_id: str, card_set_id: str, card_color: Any, card_type: Any) -> bool:
        value = str(set_id or "").strip().upper()
        card_set = str(card_set_id or "").strip().upper()
        color = str(card_color or "").strip().upper()
        ctype = str(card_type or "").strip()

        if not value:
            return False

        if value == "BLUE GREEN PURPLE RED BLACK YELLOW":
            return True
        if card_set == "BLUE GREEN PURPLE RED BLACK YELLOW":
            return True

        # Heuristic: looks like a list of colors, and OPTCG also marks card_color as Leader.
        if "BLUE" in value and "GREEN" in value and "RED" in value and "BLACK" in value and "YELLOW" in value and "PURPLE" in value:
            if color == "LEADER":
                return True

        # Another heuristic: card_type is numeric in these broken entries.
        if color == "LEADER" and ctype.isdigit():
            if "BLUE" in value and "GREEN" in value:
                return True

        return False

    def _make_synthetic_promo_code(self, name: str) -> str:
        if not name:
            return "PROMO-UNKNOWN"
        slug = re.sub(r"[^A-Z0-9]+", "-", name.strip().upper())
        slug = re.sub(r"-+", "-", slug).strip("-")
        if len(slug) > 48:
            slug = slug[:48].strip("-")
        return f"PROMO-{slug}"

    def _normalize_optcg_set(self, item: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        if not isinstance(item, dict):
            return None
        set_id = str(item.get("set_id", "") or "").strip()
        set_name = str(item.get("set_name", "") or "").strip()
        if not set_id:
            return None
        set_id = self._normalize_set_id_for_app(set_id)
        return {
            "id": set_id,
            "name": set_name or set_id,
            "title": set_name or set_id,
            "prefix": "",
            "label": set_id,
            "type": "booster_pack",
            "language": "tcg",
            "source": "optcg",
        }

    def _normalize_optcg_deck(self, item: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        if not isinstance(item, dict):
            return None
        deck_id = str(item.get("structure_deck_id", "") or "").strip()
        deck_name = str(item.get("structure_deck_name", "") or "").strip()
        if not deck_id:
            return None
        deck_id = self._normalize_set_id_for_optcg(deck_id)
        return {
            "id": deck_id,
            "name": deck_name or deck_id,
            "title": deck_name or deck_id,
            "prefix": "",
            "label": deck_id,
            "type": "starter_deck",
            "language": "tcg",
            "source": "optcg",
        }

    def _normalize_set_id_for_app(self, set_id: str) -> str:
        """Normalize OPTCG set IDs into this app's canonical format."""
        value = str(set_id or "").strip().upper()
        if not value:
            return ""
        # Convert composite OPTCG ids like OP14-EB04 -> OP-14 for sane ordering/folders.
        m = re.match(r'^(OP|ST)(\d{2})-.*$', value)
        if m:
            prefix, digits = m.groups()
            return f"{prefix}-{digits}"
        return self._normalize_set_id_for_optcg(value)

    def _id_sort_key(self, raw_id: str):
        v = self._normalize_any_id_for_optcg(raw_id)
        v_up = str(v or '').upper()
        # Canonicalize composite OPxx-... for ordering.
        m = re.match(r'^(OP)(\d{2})-.*$', v_up)
        if m:
            v_up = f"OP-{m.group(2)}"
        if v_up.startswith('OP-'):
            return (0, int(re.sub(r'\D', '', v_up) or 0), v_up)
        if v_up.startswith(('EB-', 'PRB-')):
            return (1, int(re.sub(r'\D', '', v_up) or 0), v_up)
        if v_up.startswith('ST-'):
            return (2, int(re.sub(r'\D', '', v_up) or 0), v_up)
        if v_up.startswith('P'):
            return (3, 0, v_up)
        return (9, 0, v_up)

    def _normalize_any_id_for_optcg(self, raw_id: str) -> str:
        """Normalize user/pack IDs into OPTCG's expected ID formats."""
        if not raw_id:
            return ""

        value = str(raw_id).strip().upper()
        if not value:
            return ""

        # Starter decks commonly come through as ST01 or ST-01.
        if value.startswith("ST"):
            return self._normalize_set_id_for_optcg(value.replace("_", "-"))

        # Promos (individual card ids) are not used as set IDs; ignore here.
        if value.startswith("P"):
            return value

        return self._normalize_set_id_for_optcg(value.replace("_", "-"))

    def _resolve_set_id_for_optcg(self, set_id: str, available_sets: List[Dict[str, Any]]) -> str:
        """Resolve a requested set_id against OPTCG's catalog.

        OPTCG set IDs are mostly like OP-01/EB-02/PRB-02, but newer IDs may be
        combined (e.g. OP14-EB04). If the exact ID isn't present, we try to find
        the best matching catalog entry.
        """
        if not set_id:
            return ""

        if not available_sets:
            return set_id

        catalog = [str(s.get("set_id", "") or "").strip().upper() for s in available_sets if s.get("set_id")]
        if set_id.upper() in catalog:
            return set_id

        # Attempt to map OP14/OP-14/OP14 -> OP14-EB04 (or any OP14* entry).
        prefix = set_id.upper().replace("-", "")
        m = re.match(r"^([A-Z]+)(\d+)$", prefix)
        if m:
            alpha, digits = m.groups()
            starts = f"{alpha}{digits}"
            for candidate in catalog:
                if candidate.replace("-", "").startswith(starts):
                    return candidate

        return set_id

    def _normalize_set_id_for_optcg(self, set_id: str) -> str:
        """Normalize set IDs to OPTCG format (e.g. OP01 -> OP-01)"""
        if not set_id:
            return ""

        set_id = set_id.strip().upper()
        if "-" in set_id:
            return set_id

        match = re.match(r"^([A-Z]+)(\d+)$", set_id)
        if match:
            prefix, digits = match.groups()
            return f"{prefix}-{digits.zfill(2)}"

        return set_id

    def _normalize_set_code(self, set_id: str) -> str:
        """Normalize set code to non-hyphen form (e.g. OP-01 -> OP01)"""
        if not set_id:
            return ""
        return set_id.replace("-", "")

    def _extract_card_number(self, card_set_id: str) -> str:
        """Extract numeric card number from card_set_id"""
        if not card_set_id:
            return ""

        if "-" in card_set_id:
            return card_set_id.split("-")[-1]

        match = re.search(r"(\d{3})$", card_set_id)
        return match.group(1) if match else ""

    def _parse_colors(self, value: Any) -> List[str]:
        if not value:
            return []
        if isinstance(value, list):
            return [str(v).strip() for v in value if str(v).strip()]
        value_str = str(value).strip()
        return [v.strip() for v in value_str.split() if v.strip()]

    def _parse_traits(self, value: Any) -> List[str]:
        if not value:
            return []
        if isinstance(value, list):
            return [str(v).strip() for v in value if str(v).strip()]
        value_str = str(value).strip()
        if "," in value_str:
            return [v.strip() for v in value_str.split(",") if v.strip()]
        if " / " in value_str:
            return [v.strip() for v in value_str.split(" / ") if v.strip()]
        return [value_str] if value_str else []

    def _normalize_card_type(self, value: str) -> str:
        if not value:
            return ""
        value_upper = value.strip().upper()
        if "DON" in value_upper:
            return "DON!!"
        return value.title()

    def _is_parallel_variant(self, name: str) -> bool:
        if not name:
            return False
        name_upper = name.upper()
        return any(keyword in name_upper for keyword in ["PARALLEL", "ALTERNATE ART", "MANGA"])

    def _safe_int(self, value: Any) -> int:
        try:
            if value is None or value == "":
                return 0
            return int(value)
        except (ValueError, TypeError):
            return 0

    def _unique_non_empty(self, values: List[str]) -> List[str]:
        seen = set()
        result = []
        for value in values:
            if not value:
                continue
            if value not in seen:
                seen.add(value)
                result.append(value)
        return result
