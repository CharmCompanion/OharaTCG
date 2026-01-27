import re
import time
from typing import Dict, List, Any, Optional
from urllib.parse import urljoin, urlparse

import requests
import streamlit as st
BeautifulSoupType = Any


class OnePieceTopDecksClient:
    """Client for One Piece Top Decks (fan-translated leaks/sets)"""

    def __init__(self, base_url: str = "https://onepiecetopdecks.com"):
        self.base_url = base_url.rstrip("/")
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "OnePieceTCGScraper/1.0",
            "Accept": "text/html,application/xhtml+xml"
        })

    def fetch_all_data(self, extra_urls: Optional[List[str]] = None) -> Dict[str, Any]:
        """Fetch cards from the TopDecks cards index and optional extra URLs."""
        extra_urls = [u for u in (extra_urls or []) if u]
        all_cards: List[Dict[str, Any]] = []
        all_sets: List[Dict[str, Any]] = []
        discovered_urls = self._discover_leak_urls()
        candidate_urls = set(extra_urls) | set(discovered_urls)
        extra_set_urls = list(candidate_urls)

        try:
            index_html = self._fetch_html(f"{self.base_url}/cards/")
            sets = self._parse_cards_index(index_html)
            all_sets.extend(sets)

            set_urls = {s.get("url") for s in sets if s.get("url")}
            extra_set_urls = [u for u in candidate_urls if u not in set_urls]

            for set_entry in sets:
                url = set_entry.get("url")
                if not url:
                    continue
                try:
                    cards = self._fetch_cards_from_set_url(url, set_entry)
                    if cards:
                        all_cards.extend(cards)
                        st.write(f"✅ TopDecks: {set_entry.get('label', url)} - {len(cards)} cards")
                except Exception as e:
                    st.warning(f"TopDecks failed for set {url}: {str(e)}")
                time.sleep(0.15)
        except Exception as e:
            st.warning(f"TopDecks index fetch failed: {str(e)}")

        for url in extra_set_urls:
            try:
                cards, set_entry = self._fetch_cards_from_leak_url(url)
                if set_entry:
                    all_sets.append(set_entry)
                if cards:
                    all_cards.extend(cards)
                    st.write(f"✅ TopDecks leak: {url} - {len(cards)} cards")
            except Exception as e:
                st.warning(f"TopDecks leak failed for {url}: {str(e)}")
            time.sleep(0.15)

        return {
            "cards": all_cards,
            "sets": all_sets,
            "metadata": {
                "source": "onepiecetopdecks",
                "total_cards": len(all_cards),
                "total_sets": len(all_sets),
                "language": "tcg",
                "fetched_at": time.time()
            }
        }

    def _fetch_cards_from_set_url(self, url: str, set_entry: Dict[str, Any]) -> List[Dict[str, Any]]:
        html = self._fetch_html(url)
        return self._parse_set_page(html, url, set_entry)

    def _fetch_cards_from_leak_url(self, url: str) -> tuple[List[Dict[str, Any]], Optional[Dict[str, Any]]]:
        html = self._fetch_html(url)
        set_entry = self._infer_set_from_html(html, url)
        cards = self._parse_set_page(html, url, set_entry)
        return cards, set_entry

    def _fetch_html(self, url: str) -> str:
        response = self.session.get(url, timeout=30)
        response.raise_for_status()
        return response.text

    def _fetch_json(self, url: str) -> Optional[Any]:
        try:
            response = self.session.get(url, timeout=30)
            response.raise_for_status()
            return response.json()
        except Exception:
            return None

    def _parse_cards_index(self, html: str) -> List[Dict[str, Any]]:
        soup = self._require_soup(html)
        anchors = soup.select("a[href*='/cards/']")
        urls = []
        for a in anchors:
            href = a.get("href", "")
            if not href:
                continue
            if href.rstrip("/") == f"{self.base_url}/cards":
                continue
            if "/cards/" not in href:
                continue
            urls.append(href)

        seen = set()
        set_entries: List[Dict[str, Any]] = []
        for url in urls:
            url = urljoin(self.base_url + "/", url)
            if url in seen:
                continue
            seen.add(url)

            label, set_id, set_name = self._infer_set_from_url(url)
            set_type = self._infer_set_type(url, set_id)

            set_entries.append({
                "id": set_id or label,
                "label": label or set_id or url,
                "name": set_name or label or set_id or url,
                "type": set_type,
                "language": "tcg",
                "source": "onepiecetopdecks",
                "url": url
            })

        return set_entries

    def _discover_leak_urls(self) -> List[str]:
        """Discover leak/set URLs from WP API and homepage/news pages."""
        discovered = set()
        discovered.update(self._discover_from_wp_api("posts"))
        discovered.update(self._discover_from_wp_api("pages"))
        discovered.update(self._discover_from_html("/"))
        discovered.update(self._discover_from_html("/news-2/"))
        return list(discovered)

    def _discover_from_wp_api(self, endpoint: str) -> List[str]:
        urls = []
        for page in range(1, 6):
            api_url = f"{self.base_url}/wp-json/wp/v2/{endpoint}?per_page=100&page={page}"
            payload = self._fetch_json(api_url)
            if not isinstance(payload, list) or not payload:
                break
            for item in payload:
                link = item.get("link")
                slug = item.get("slug", "")
                title = ""
                title_obj = item.get("title")
                if isinstance(title_obj, dict):
                    title = title_obj.get("rendered", "")
                if self._looks_like_set_or_leak(link, slug, title):
                    urls.append(link)
        return urls

    def _discover_from_html(self, path: str) -> List[str]:
        urls = []
        try:
            html = self._fetch_html(urljoin(self.base_url + "/", path.lstrip("/")))
            soup = self._require_soup(html)
            for anchor in soup.select("a[href]"):
                href = anchor.get("href", "")
                if self._looks_like_set_or_leak(href, "", anchor.get_text(" ", strip=True)):
                    urls.append(href)
        except Exception:
            return []
        return urls

    def _looks_like_set_or_leak(self, url: Optional[str], slug: str, title: str) -> bool:
        if not url:
            return False
        if not self._is_same_domain(url):
            return False
        blob = f"{url} {slug} {title}".lower()
        if "/cards/" in blob:
            return True
        if "leaks" in blob or "leak" in blob:
            return True
        if re.search(r"\b(op|eb|st|prb|p)-?\d{2,3}\b", blob):
            return True
        if "starter" in blob or "deck" in blob or "promo" in blob:
            return True
        return False

    def _is_same_domain(self, url: str) -> bool:
        try:
            return urlparse(url).netloc.endswith(urlparse(self.base_url).netloc)
        except Exception:
            return False

    def _parse_set_page(self, html: str, url: str, set_entry: Optional[Dict[str, Any]]) -> List[Dict[str, Any]]:
        soup = self._require_soup(html)
        if soup.select_one(".ngg-galleryoverview"):
            return self._parse_nextgen_gallery(soup, set_entry)
        return self._parse_elementor_leak_page(soup, url, set_entry)

    def _parse_nextgen_gallery(self, soup: BeautifulSoupType, set_entry: Optional[Dict[str, Any]]) -> List[Dict[str, Any]]:
        cards: List[Dict[str, Any]] = []
        for anchor in soup.select(".ngg-gallery-thumbnail a[href]"):
            image_url = anchor.get("href") or anchor.get("data-src")
            data_title = anchor.get("data-title") or anchor.get("title") or ""
            data_desc = anchor.get("data-description") or ""

            base_code = data_title.strip()
            if not base_code:
                base_code = self._extract_code_from_url(image_url or "")

            base_code = self._strip_parallel_suffix(base_code)
            set_code, number = self._split_code(base_code)
            set_id = self._normalize_set_id(set_code)
            card_code = f"{set_code}-{number}" if set_code and number else base_code

            color_tokens = self._extract_colors(data_desc)
            rarity = self._extract_rarity(data_desc)
            cost = self._extract_cost(data_desc)
            counter = self._extract_counter(data_desc)
            card_type = self._extract_card_type(data_desc)
            attribute = self._extract_attribute(data_desc)
            traits = self._extract_traits_from_description(data_desc)
            is_parallel = self._is_parallel_variant(data_title or image_url or "")

            cards.append({
                "id": base_code or card_code,
                "name": base_code or card_code,
                "name_english": base_code or card_code,
                "name_japanese": "",
                "set_id": set_id or (set_entry or {}).get("id", ""),
                "set_name": (set_entry or {}).get("name", ""),
                "set_code": set_code,
                "card_code": card_code,
                "number": number,
                "rarity": rarity,
                "type": card_type,
                "cost": cost,
                "power": 0,
                "counter": counter,
                "life": 0,
                "effect": "",
                "effect_english": "",
                "traits": traits,
                "colors": color_tokens,
                "attribute": attribute,
                "image_url": image_url or "",
                "image_urls": {
                    "large": image_url or "",
                    "normal": image_url or ""
                },
                "language": "tcg",
                "source": "onepiecetopdecks",
                "release_date": "",
                "artist": "",
                "parallel_id": "",
                "variant": "Parallel" if is_parallel else "",
                "is_alternate_art": is_parallel,
                "is_promo": False,
                "is_tournament": False
            })

        return cards

    def _parse_elementor_leak_page(self, soup: BeautifulSoupType, url: str, set_entry: Optional[Dict[str, Any]]) -> List[Dict[str, Any]]:
        cards: List[Dict[str, Any]] = []
        sections = soup.select("section.elementor-section")
        for section in sections:
            text_editor = section.select_one(".elementor-widget-text-editor")
            if not text_editor:
                continue

            text = text_editor.get_text("\n", strip=True)
            if not self._find_card_code(text):
                continue

            image_url = self._extract_image_url(section)
            card = self._parse_leak_text(text)
            if not card:
                continue

            set_id = card.get("set_id") or (set_entry or {}).get("id", "")
            set_name = card.get("set_name") or (set_entry or {}).get("name", "")
            set_code = card.get("set_code") or self._normalize_set_code(set_id)

            card.update({
                "set_id": set_id,
                "set_name": set_name,
                "set_code": set_code,
                "image_url": image_url or card.get("image_url", ""),
                "image_urls": {
                    "large": image_url or card.get("image_url", ""),
                    "normal": image_url or card.get("image_url", "")
                },
                "language": "tcg",
                "source": "onepiecetopdecks"
            })
            cards.append(card)

        return cards

    def _parse_leak_text(self, text: str) -> Optional[Dict[str, Any]]:
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        joined = " ".join(lines)
        card_code = self._find_card_code(joined)
        if not card_code:
            return None

        set_code, number = self._split_code(card_code)
        set_id = self._normalize_set_id(set_code)
        card_type = self._extract_card_type(joined)
        colors = self._extract_colors(joined)
        rarity = self._extract_rarity(joined)
        cost = self._extract_cost(joined)
        power = self._extract_power(joined)
        life = self._extract_life(joined)
        counter = self._extract_counter(joined)
        attribute = self._extract_attribute(joined)
        traits = self._extract_traits_from_lines(lines)
        effect = self._extract_effect(lines)

        name = self._extract_name_from_lines(lines, card_code) or card_code
        card_code_normalized = f"{set_code}-{number}" if set_code and number else card_code

        return {
            "id": card_code_normalized,
            "name": name,
            "name_english": name,
            "name_japanese": "",
            "set_id": set_id,
            "set_name": "",
            "set_code": set_code,
            "card_code": card_code_normalized,
            "number": number,
            "rarity": rarity,
            "type": card_type,
            "cost": cost,
            "power": power,
            "counter": counter,
            "life": life,
            "effect": effect,
            "effect_english": effect,
            "traits": traits,
            "colors": colors,
            "attribute": attribute,
            "image_url": "",
            "image_urls": {},
            "language": "tcg",
            "source": "onepiecetopdecks",
            "release_date": "",
            "artist": "",
            "parallel_id": "",
            "variant": "",
            "is_alternate_art": False,
            "is_promo": False,
            "is_tournament": False
        }

    def _extract_image_url(self, section: BeautifulSoupType) -> str:
        img = section.select_one(".elementor-widget-image img")
        if not img:
            return ""
        for attr in ["data-src", "data-lazy-src", "src"]:
            url = img.get(attr, "")
            if url and not url.startswith("data:image"):
                return url
        return ""

    def _infer_set_from_url(self, url: str) -> tuple[str, str, str]:
        slug = url.rstrip("/").split("/")[-1]
        label = slug.replace("-", " ").upper()
        set_id = self._extract_set_id(slug)
        set_name = label
        return label, set_id, set_name

    def _infer_set_from_html(self, html: str, url: str) -> Dict[str, Any]:
        soup = self._require_soup(html)
        title = soup.title.get_text(strip=True) if soup.title else url
        set_id = self._extract_set_id(title) or self._extract_set_id(url)
        label = set_id or title
        return {
            "id": set_id or label,
            "label": label,
            "name": title,
            "type": self._infer_set_type(url, set_id),
            "language": "tcg",
            "source": "onepiecetopdecks",
            "url": url
        }

    def _infer_set_type(self, url: str, set_id: str) -> str:
        slug = url.lower()
        if set_id and set_id.startswith("ST-"):
            return "starter_deck"
        if "promo" in slug or (set_id and set_id.startswith("P-")):
            return "promo"
        if "event" in slug or "bonus" in slug:
            return "other"
        return "booster_pack"

    def _extract_code_from_url(self, url: str) -> str:
        if not url:
            return ""
        filename = url.split("/")[-1]
        filename = filename.split(".")[0]
        return filename.strip()

    def _strip_parallel_suffix(self, code: str) -> str:
        return re.sub(r"(_p\d+)$", "", code, flags=re.IGNORECASE)

    def _split_code(self, code: str) -> tuple[str, str]:
        if not code:
            return "", ""
        match = re.match(r"^([A-Z]+\d{2,3})-(\d{3})$", code.upper())
        if match:
            return match.group(1), match.group(2)
        match = re.match(r"^([A-Z]+\d{2,3})(\d{3})$", code.upper())
        if match:
            return match.group(1), match.group(2)
        return code.upper(), ""

    def _require_soup(self, html: str) -> BeautifulSoupType:
        try:
            from bs4 import BeautifulSoup as _BeautifulSoup  # pyright: ignore[reportMissingImports]
        except ImportError as exc:  # pragma: no cover - handled by dependency install
            raise ImportError("beautifulsoup4 is required for OnePieceTopDecks parsing") from exc
        return _BeautifulSoup(html, "html.parser")

    def _extract_set_id(self, text: str) -> str:
        if not text:
            return ""
        match = re.search(r"\b(OP|EB|ST|PRB|P)(?:-|\s)?(\d{2,3})\b", text.upper())
        if not match:
            return ""
        prefix, digits = match.groups()
        return f"{prefix}-{digits.zfill(2)}"

    def _normalize_set_id(self, set_code: str) -> str:
        if not set_code:
            return ""
        set_code = set_code.replace("-", "").upper()
        match = re.match(r"^([A-Z]+)(\d{2,3})$", set_code)
        if match:
            prefix, digits = match.groups()
            return f"{prefix}-{digits.zfill(2)}"
        return set_code

    def _normalize_set_code(self, set_id: str) -> str:
        if not set_id:
            return ""
        return set_id.replace("-", "")

    def _find_card_code(self, text: str) -> str:
        if not text:
            return ""
        match = re.search(r"\b([A-Z]{1,3}\d{2,3}-\d{3})\b", text.upper())
        if match:
            return match.group(1)
        return ""

    def _extract_name_from_lines(self, lines: List[str], code: str) -> str:
        for line in lines:
            if code in line.upper():
                name = line.replace(code, "").replace("(", "").replace(")", "").strip()
                name = re.sub(r"\b(SR|R|UC|C|L|SEC)\b", "", name).strip()
                if name:
                    return name
        if lines:
            return lines[0]
        return ""

    def _extract_colors(self, text: str) -> List[str]:
        colors = []
        for color in ["RED", "BLUE", "GREEN", "PURPLE", "BLACK", "YELLOW"]:
            if color in text.upper():
                colors.append(color.title())
        return colors

    def _extract_rarity(self, text: str) -> str:
        for rarity in ["SEC", "SR", "R", "UC", "C", "L", "P"]:
            if re.search(rf"\b{rarity}\b", text.upper()):
                return rarity
        return ""

    def _extract_cost(self, text: str) -> int:
        match = re.search(r"(\d+)\s*COST", text.upper())
        if match:
            return int(match.group(1))
        return 0

    def _extract_power(self, text: str) -> int:
        match = re.search(r"(\d{3,5})\s*POWER", text.upper())
        if match:
            return int(match.group(1))
        return 0

    def _extract_life(self, text: str) -> int:
        match = re.search(r"(\d+)\s*LIFE", text.upper())
        if match:
            return int(match.group(1))
        return 0

    def _extract_counter(self, text: str) -> int:
        match = re.search(r"C(\d)K", text.upper())
        if match:
            return int(match.group(1)) * 1000
        match = re.search(r"COUNTER\s*\+?(\d{3,4})", text.upper())
        if match:
            return int(match.group(1))
        return 0

    def _extract_card_type(self, text: str) -> str:
        upper = text.upper()
        if "LEADER" in upper:
            return "Leader"
        if "STAGE" in upper:
            return "Stage"
        if "EVENT" in upper:
            return "Event"
        if "DON" in upper:
            return "DON!!"
        if "CHARACTER" in upper:
            return "Character"
        return ""

    def _extract_attribute(self, text: str) -> str:
        match = re.search(r"\((STRIKE|SLASH|SPECIAL|RANGED|WISDOM)\)", text.upper())
        if match:
            return match.group(1).title()
        return ""

    def _extract_traits_from_lines(self, lines: List[str]) -> List[str]:
        traits = []
        for line in lines:
            if "/" in line and not any(keyword in line.upper() for keyword in ["COST", "POWER", "LIFE"]):
                parts = [part.strip() for part in line.split("/") if part.strip()]
                traits.extend(parts)
        return traits

    def _extract_traits_from_description(self, text: str) -> List[str]:
        words = [w.strip() for w in text.replace("\n", " ").split() if w.strip()]
        blacklist = {"COST", "POWER", "C1K", "C2K", "RUSH", "BLOCKER", "DOUBLE", "ATTACK"}
        traits = [w.title() for w in words if w.isalpha() and w.upper() not in blacklist]
        return list(dict.fromkeys(traits))

    def _extract_effect(self, lines: List[str]) -> str:
        effect_lines = []
        for line in lines:
            if "[" in line or "ON PLAY" in line.upper() or "ACTIVATE" in line.upper() or "TRIGGER" in line.upper():
                effect_lines.append(line)
        return "\n".join(effect_lines).strip()

    def _is_parallel_variant(self, text: str) -> bool:
        return bool(re.search(r"(_P\d+|PARALLEL|ALTERNATE ART|MANGA)", text.upper()))
