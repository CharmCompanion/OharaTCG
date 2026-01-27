import os
import requests
import time
import zipfile
import tempfile
import shutil
from pathlib import Path
from typing import List, Dict, Any, Optional
from PIL import Image
import streamlit as st

class ImageDownloader:
    """Download and organize card images"""
    
    def __init__(self, output_dir: str):
        self.output_dir = Path(output_dir)
        self.images_dir = self.output_dir / "images"
        self.images_dir.mkdir(parents=True, exist_ok=True)
        
        # Create subdirectories for organization
        (self.images_dir / "cards").mkdir(exist_ok=True)
        (self.images_dir / "sets").mkdir(exist_ok=True)
        (self.images_dir / "thumbnails").mkdir(exist_ok=True)
        
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'OnePieceTCGScraper/1.0'
        })
        
        self.downloaded_count = 0
        self.failed_count = 0
        self.skipped_count = 0
    
    def download_all_images(self, processed_data: Dict[str, Any]) -> List[str]:
        """Download all card images from processed data"""
        downloaded_images = []
        cards = processed_data.get('cards', [])
        
        if not cards:
            st.warning("No cards found to download images for")
            return downloaded_images
        
        # Check if we have vegapull data and need bulk download
        vegapull_cards = [card for card in cards if card.get('source') == 'vegapull']
        if vegapull_cards:
            st.write("📦 Detected vegapull cards - downloading bulk image archive...")
            bulk_downloaded = self._download_vegapull_bulk_images(processed_data)
            downloaded_images.extend(bulk_downloaded)
        
        # Process individual URL downloads for non-vegapull cards
        individual_cards = [card for card in cards if card.get('source') != 'vegapull']
        if individual_cards:
            individual_downloaded = self._download_individual_images(individual_cards)
            downloaded_images.extend(individual_downloaded)
        
        # Generate thumbnails
        if downloaded_images:
            st.write("🖼️ Generating thumbnails...")
            self._generate_thumbnails(downloaded_images)
        
        return downloaded_images

    def sync_to_godot_assets(
        self,
        processed_data: Dict[str, Any],
        project_root: Optional[Path] = None,
        overwrite: bool = False,
        download_missing: bool = True,
        only_language: str = "tcg",
        verbose: bool = False,
    ) -> Dict[str, int]:
        """Sync downloaded images into the Godot assets folder.

        Godot expects images at assets/cards/<set_code>/<card_code>.png (and DON!! at assets/cards/Don/Don.png).
        This function primarily copies images already present in output/images/cards. Optionally, it will
        download missing images directly into the expected destination.
        """

        project_root = project_root or Path(__file__).resolve().parents[2]
        assets_cards_dir = project_root / "assets" / "cards"
        assets_cards_dir.mkdir(parents=True, exist_ok=True)

        cards: List[Dict[str, Any]] = processed_data.get("cards", []) or []
        total_cards = len(cards)

        stats = {
            "total": total_cards,
            "skipped": 0,
            "copied": 0,
            "downloaded": 0,
            "failed": 0,
        }

        progress_bar = st.progress(0)
        status_text = st.empty()

        def _emit_status(step: int) -> None:
            if not total_cards:
                return
            if not verbose:
                if step != total_cards and (step % 25) != 0:
                    return
            else:
                if step != total_cards and (step % 5) != 0:
                    return
            msg = (
                f"Syncing images: {step}/{total_cards} "
                f"(copied {stats['copied']}, downloaded {stats['downloaded']}, failed {stats['failed']})"
            )
            try:
                status_text.text(msg)
            except Exception:
                pass
            if verbose:
                print(msg, flush=True)

        for i, card in enumerate(cards):
            if not isinstance(card, dict):
                continue

            if only_language and card.get("language") and card.get("language") != only_language:
                continue

            dest_path = self._get_godot_asset_path(card, assets_cards_dir)
            if not dest_path:
                continue

            if not overwrite and self._godot_asset_exists_any(dest_path):
                stats["skipped"] += 1
                continue

            # Try to copy from existing downloads first.
            source_path = self._find_local_download_for_card(card)
            if source_path:
                try:
                    dest_path.parent.mkdir(parents=True, exist_ok=True)
                    if source_path.suffix.lower() == ".png":
                        shutil.copyfile(source_path, dest_path)
                    else:
                        tmp_copy = dest_path.with_suffix(source_path.suffix.lower())
                        shutil.copyfile(source_path, tmp_copy)
                        png_path = self._convert_to_png(tmp_copy)
                        if png_path != dest_path:
                            shutil.move(str(png_path), str(dest_path))
                    stats["copied"] += 1
                except Exception:
                    stats["failed"] += 1
                finally:
                    if total_cards:
                        progress_bar.progress(min(1.0, (i + 1) / total_cards))
                        _emit_status(i + 1)
                continue

            # Reprint/alias fallback: sometimes decks (or processed data) reference
            # a different asset folder than where the art was originally synced.
            # Example: set_code=ST11, card_code=OP02-028 but art exists at
            # assets/cards/OP02/OP02-028.png.
            aliased = False
            try:
                alias_source = self._find_existing_asset_for_card(card, assets_cards_dir)
                if alias_source:
                    dest_path.parent.mkdir(parents=True, exist_ok=True)
                    if alias_source.suffix.lower() == ".png":
                        shutil.copyfile(alias_source, dest_path)
                    else:
                        tmp_copy = dest_path.with_suffix(alias_source.suffix.lower())
                        shutil.copyfile(alias_source, tmp_copy)
                        png_path = self._convert_to_png(tmp_copy)
                        if png_path != dest_path:
                            shutil.move(str(png_path), str(dest_path))
                    stats["copied"] += 1
                    aliased = True
            except Exception:
                aliased = False

            if aliased:
                if total_cards:
                    progress_bar.progress(min(1.0, (i + 1) / total_cards))
                    _emit_status(i + 1)
                continue

            if not download_missing:
                stats["failed"] += 1
                if total_cards:
                    progress_bar.progress(min(1.0, (i + 1) / total_cards))
                    _emit_status(i + 1)
                continue

            # Fallback: download directly into destination
            image_url = self._get_best_image_url(card)
            if not image_url:
                stats["failed"] += 1
                if total_cards:
                    progress_bar.progress(min(1.0, (i + 1) / total_cards))
                    _emit_status(i + 1)
                continue

            try:
                dest_path.parent.mkdir(parents=True, exist_ok=True)

                # Avoid streaming here: some hosts stall mid-stream. These images are small enough
                # that reading the full response is acceptable and more reliable.
                response = self.session.get(image_url, timeout=(10, 20))
                response.raise_for_status()

                tmp_path = dest_path.with_suffix(".tmp")
                tmp_path.write_bytes(response.content)

                # Convert anything into a PNG at the final destination.
                with Image.open(tmp_path) as img:
                    img.save(dest_path, "PNG", optimize=True)

                try:
                    tmp_path.unlink(missing_ok=True)
                except Exception:
                    pass

                stats["downloaded"] += 1
            except Exception:
                stats["failed"] += 1
                try:
                    tmp_path = dest_path.with_suffix(".tmp")
                    tmp_path.unlink(missing_ok=True)
                except Exception:
                    pass

            if total_cards:
                progress_bar.progress(min(1.0, (i + 1) / total_cards))
                _emit_status(i + 1)

        status_text.text(
            f"✅ Asset sync complete: copied {stats['copied']}, downloaded {stats['downloaded']}, skipped {stats['skipped']}, failed {stats['failed']}"
        )
        if verbose:
            print(
                f"Asset sync complete: copied {stats['copied']}, downloaded {stats['downloaded']}, skipped {stats['skipped']}, failed {stats['failed']}",
                flush=True,
            )
        return stats

    def _godot_asset_exists_any(self, dest_png_path: Path) -> bool:
        """Return True if any acceptable image exists for this asset path.

        We standardize to writing PNGs, but the project (and audit tooling)
        accepts JPG/JPEG as well.
        """

        base = dest_png_path.with_suffix("")
        for ext in (".png", ".jpg", ".jpeg"):
            if (base.with_suffix(ext)).exists():
                return True
        return False

    def _find_existing_asset_for_card(self, card: Dict[str, Any], assets_cards_dir: Path) -> Optional[Path]:
        """Try to find an already-synced asset image for this card under another set folder.

        This is primarily to resolve reprint-style references where the card_code/id prefixes
        don't match the destination set_code folder.
        """

        def _prefix(code: str) -> Optional[str]:
            if not code or not isinstance(code, str):
                return None
            if "-" not in code:
                return None
            return code.split("-", 1)[0].strip()

        def _candidates() -> List[str]:
            out: List[str] = []
            for key in ("id", "card_code"):
                v = card.get(key)
                if isinstance(v, str) and v.strip():
                    out.append(v.strip())
            # Also try base id (strip variant suffixes like _p5)
            v = card.get("id")
            if isinstance(v, str) and v.strip() and "_" in v:
                out.append(v.split("_", 1)[0].strip())
            # De-dupe, preserve order
            seen = set()
            uniq: List[str] = []
            for x in out:
                k = x.lower()
                if k not in seen:
                    seen.add(k)
                    uniq.append(x)
            return uniq

        exts = [".png", ".jpg", ".jpeg"]
        for code in _candidates():
            pfx = _prefix(code)
            if not pfx:
                continue
            safe_pfx = self._sanitize_filename(pfx)
            safe_code = self._sanitize_filename(code)
            if not safe_pfx or not safe_code:
                continue
            for ext in exts:
                path = assets_cards_dir / safe_pfx / f"{safe_code}{ext}"
                if path.exists():
                    return path

        return None

    def _get_godot_asset_path(self, card: Dict[str, Any], assets_cards_dir: Path) -> Optional[Path]:
        """Compute the Godot asset image path for a card."""
        card_code = (card.get("card_code") or "").strip()
        set_code = (card.get("set_code") or "").strip()
        number = (card.get("number") or "").strip()
        card_type = (card.get("type") or card.get("card_type") or "").strip()

        # Special-case DON!!
        if card_code.upper() == "DON!!" or card_type.upper().startswith("DON"):
            return assets_cards_dir / "Don" / "Don.png"

        if not card_code and set_code and number:
            card_code = f"{set_code}-{number}"

        if not card_code or not set_code:
            return None

        safe_set_code = self._sanitize_filename(set_code)
        safe_card_code = self._sanitize_filename(card_code)
        if not safe_set_code or not safe_card_code:
            return None
        return assets_cards_dir / safe_set_code / f"{safe_card_code}.png"

    def _find_local_download_for_card(self, card: Dict[str, Any]) -> Optional[Path]:
        """Try to locate a locally downloaded image for this card in output/images/cards."""
        cards_dir = self.images_dir / "cards"
        if not cards_dir.exists():
            return None

        candidates: List[str] = []
        for key in ("card_code", "id"):
            value = card.get(key)
            if isinstance(value, str) and value.strip():
                candidates.append(value.strip())

        # Fallback composed code
        set_code = (card.get("set_code") or "").strip()
        number = (card.get("number") or "").strip()
        if set_code and number:
            candidates.append(f"{set_code}-{number}")

        # Deduplicate, preserve order
        seen = set()
        unique_candidates: List[str] = []
        for c in candidates:
            key = c.lower()
            if key not in seen:
                seen.add(key)
                unique_candidates.append(c)

        exts = [".png", ".jpg", ".jpeg", ".webp"]
        for name in unique_candidates:
            safe = self._sanitize_filename(name)
            if not safe:
                continue
            for ext in exts:
                p = cards_dir / f"{safe}{ext}"
                if p.exists():
                    return p

        return None
    
    def _download_card_image(self, card: Dict[str, Any]) -> Optional[str]:
        """Download image for a single card"""
        # Get image URL
        image_url = self._get_best_image_url(card)
        if not image_url:
            self.failed_count += 1
            return None
        
        # Generate filename
        filename = self._generate_image_filename(card)
        file_path = self.images_dir / "cards" / filename
        
        # Skip if already exists
        if file_path.exists():
            self.skipped_count += 1
            return str(file_path)
        
        try:
            # Download image
            response = self.session.get(image_url, timeout=30, stream=True)
            response.raise_for_status()
            
            # Verify it's an image
            content_type = response.headers.get('content-type', '')
            if not content_type.startswith('image/'):
                self.failed_count += 1
                return None
            
            # Save image
            with open(file_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    f.write(chunk)
            
            # Convert to PNG if necessary
            png_path = self._convert_to_png(file_path)
            
            self.downloaded_count += 1
            return str(png_path)
            
        except Exception as e:
            self.failed_count += 1
            st.write(f"Failed to download image for {card.get('name', 'unknown')}: {str(e)}")
            return None
    
    def _get_best_image_url(self, card: Dict[str, Any]) -> Optional[str]:
        """Get the best available image URL for a card"""
        # Try different image URL fields
        url_fields = [
            'image_url',
            'image_urls.large',
            'image_urls.medium',
            'image_urls.small',
            'image_urls.normal',
            'imageUrl',
            'image'
        ]
        
        for field in url_fields:
            url = self._get_nested_value(card, field)
            if url and self._is_valid_image_url(url):
                return url
        
        # Try to construct URL from card data
        constructed_url = self._construct_image_url(card)
        if constructed_url:
            return constructed_url
        
        return None
    
    def _get_nested_value(self, data: Dict, key_path: str) -> Any:
        """Get nested value from dictionary using dot notation"""
        keys = key_path.split('.')
        value = data
        
        for key in keys:
            if isinstance(value, dict) and key in value:
                value = value[key]
            else:
                return None
        
        return value
    
    def _is_valid_image_url(self, url: str) -> bool:
        """Check if URL appears to be a valid image URL"""
        if not url or not isinstance(url, str):
            return False
        
        # Check for common image extensions
        image_extensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp']
        url_lower = url.lower()
        
        # Direct extension check
        if any(url_lower.endswith(ext) for ext in image_extensions):
            return True
        
        # Check for image hosting domains
        image_domains = ['imgur.com', 'cloudinary.com', 'amazonaws.com', 'apitcg.com']
        if any(domain in url_lower for domain in image_domains):
            return True
        
        # Check if URL contains image-related keywords
        image_keywords = ['image', 'img', 'photo', 'picture', 'card']
        if any(keyword in url_lower for keyword in image_keywords):
            return True
        
        return False
    
    def _construct_image_url(self, card: Dict[str, Any]) -> Optional[str]:
        """Try to construct image URL from card data"""
        # Common patterns for One Piece TCG images
        set_id = card.get('set_id', '')
        number = card.get('number', '')
        
        if set_id and number:
            # Try common URL patterns
            patterns = [
                f"https://onepiece.apitcg.com/images/cards/{set_id}/{number}.png",
                f"https://onepiece.apitcg.com/images/{set_id}-{number}.png",
                f"https://api.tcgplayer.com/onepiece/cards/{set_id}/{number}/image",
                f"https://images.onepiece-cardgame.com/images/cardlist/{set_id}/{number}.png"
            ]
            
            for pattern in patterns:
                if self._test_url_exists(pattern):
                    return pattern
        
        return None
    
    def _test_url_exists(self, url: str) -> bool:
        """Test if a URL exists without downloading the full content"""
        try:
            response = self.session.head(url, timeout=10)
            return response.status_code == 200
        except:
            return False
    
    def _generate_image_filename(self, card: Dict[str, Any]) -> str:
        """Generate a filename for the card image"""
        # Use card ID if available
        card_id = card.get('id', '')
        if card_id:
            return f"{self._sanitize_filename(card_id)}.png"
        
        # Fallback to set_id and number
        set_id = card.get('set_id', 'unknown')
        number = card.get('number', '000')
        name = card.get('name', 'unknown')
        
        # Sanitize components
        set_id = self._sanitize_filename(set_id)
        number = self._sanitize_filename(number)
        name = self._sanitize_filename(name)[:20]  # Limit name length
        
        return f"{set_id}-{number}-{name}.png"
    
    def _sanitize_filename(self, filename: str) -> str:
        """Sanitize filename for filesystem compatibility"""
        import re
        
        # Remove or replace invalid characters
        filename = re.sub(r'[<>:"/\\|?*]', '_', filename)
        filename = re.sub(r'\s+', '_', filename)
        filename = re.sub(r'_+', '_', filename)
        filename = filename.strip('_')
        
        return filename or 'unknown'
    
    def _convert_to_png(self, file_path: Path) -> Path:
        """Convert image to PNG format if necessary"""
        if file_path.suffix.lower() == '.png':
            return file_path
        
        try:
            # Open and convert image
            with Image.open(file_path) as img:
                # Convert to RGB if necessary (for JPEGs with transparency)
                if img.mode in ('RGBA', 'LA', 'P'):
                    # Keep transparency for PNG
                    pass
                elif img.mode != 'RGB':
                    img = img.convert('RGB')
                
                # Save as PNG
                png_path = file_path.with_suffix('.png')
                img.save(png_path, 'PNG', optimize=True)
                
                # Remove original if conversion successful
                if png_path.exists() and png_path != file_path:
                    file_path.unlink()
                
                return png_path
        
        except Exception as e:
            st.write(f"Failed to convert {file_path.name} to PNG: {str(e)}")
            return file_path
    
    def _generate_thumbnails(self, image_paths: List[str]):
        """Generate thumbnail versions of images"""
        thumbnail_size = (200, 280)  # Standard card aspect ratio
        
        for image_path in image_paths[:50]:  # Limit to first 50 for demo
            try:
                source_path = Path(image_path)
                if not source_path.exists():
                    continue
                
                thumbnail_path = self.images_dir / "thumbnails" / source_path.name
                
                # Skip if thumbnail already exists
                if thumbnail_path.exists():
                    continue
                
                # Create thumbnail
                with Image.open(source_path) as img:
                    img.thumbnail(thumbnail_size, Image.Resampling.LANCZOS)
                    img.save(thumbnail_path, 'PNG', optimize=True)
            
            except Exception as e:
                continue  # Skip failed thumbnails
    
    def _download_vegapull_bulk_images(self, processed_data: Dict[str, Any]) -> List[str]:
        """Download and extract vegapull bulk image archive"""
        vegapull_images_url = "https://github.com/Coko7/vegapull-records/releases/download/2025-04-27/english-images-2025-04-27.zip"
        downloaded_images = []
        
        # Create progress tracking
        progress_bar = st.progress(0)
        status_text = st.empty()
        
        try:
            status_text.text("📥 Downloading vegapull image archive (797MB)...")
            
            # Download the zip file to a temporary location
            with tempfile.NamedTemporaryFile(delete=False, suffix='.zip') as tmp_file:
                response = self.session.get(vegapull_images_url, stream=True)
                response.raise_for_status()
                
                total_size = int(response.headers.get('content-length', 0))
                downloaded_size = 0
                
                for chunk in response.iter_content(chunk_size=8192):
                    tmp_file.write(chunk)
                    downloaded_size += len(chunk)
                    if total_size > 0:
                        progress = downloaded_size / total_size * 0.5  # First 50% for download
                        progress_bar.progress(progress)
                        status_text.text(f"📥 Downloading archive: {downloaded_size / (1024*1024):.1f} MB / {total_size / (1024*1024):.1f} MB")
                
                tmp_zip_path = tmp_file.name
            
            status_text.text("📂 Extracting images from archive...")
            progress_bar.progress(0.5)
            
            # Extract images to our cards directory
            cards_dir = self.images_dir / "cards"
            extracted_count = 0
            
            with zipfile.ZipFile(tmp_zip_path, 'r') as zip_file:
                image_files = [f for f in zip_file.namelist() if f.lower().endswith(('.png', '.jpg', '.jpeg'))]
                total_images = len(image_files)
                
                for i, file_name in enumerate(image_files):
                    # Extract to cards directory with original filename
                    output_path = cards_dir / Path(file_name).name
                    
                    if not output_path.exists():
                        with zip_file.open(file_name) as source, open(output_path, 'wb') as target:
                            target.write(source.read())
                        extracted_count += 1
                    
                    downloaded_images.append(str(output_path))
                    
                    # Update progress (second 50% for extraction)
                    progress = 0.5 + (i + 1) / total_images * 0.5
                    progress_bar.progress(progress)
                    status_text.text(f"📂 Extracting: {i + 1}/{total_images} images")
            
            # Clean up temporary file
            os.unlink(tmp_zip_path)
            
            self.downloaded_count += extracted_count
            status_text.text(f"✅ Bulk download complete: {extracted_count} images extracted from archive")
            
        except Exception as e:
            st.error(f"Failed to download vegapull bulk images: {str(e)}")
            status_text.text("❌ Bulk download failed - falling back to individual downloads")
            
            # Fallback to individual downloads
            cards = [card for card in processed_data.get('cards', []) if card.get('source') == 'vegapull']
            downloaded_images = self._download_individual_images(cards)
        
        return downloaded_images
    
    def _download_individual_images(self, cards: List[Dict[str, Any]]) -> List[str]:
        """Download images individually for cards that have direct URLs"""
        downloaded_images = []
        
        if not cards:
            return downloaded_images
        
        # Create progress tracking
        progress_bar = st.progress(0)
        status_text = st.empty()
        
        total_cards = len(cards)
        
        for i, card in enumerate(cards):
            # Update progress
            progress = (i + 1) / total_cards
            progress_bar.progress(progress)
            status_text.text(f"Downloading images: {i + 1}/{total_cards} ({self.downloaded_count} downloaded, {self.failed_count} failed)")
            
            # Download card image
            image_path = self._download_card_image(card)
            if image_path:
                downloaded_images.append(image_path)
            
            # Small delay to avoid overwhelming servers
            time.sleep(0.1)
        
        # Final status update
        status_text.text(f"✅ Individual download complete: {self.downloaded_count} downloaded, {self.failed_count} failed, {self.skipped_count} skipped")
        
        return downloaded_images

    def get_download_stats(self) -> Dict[str, int]:
        """Get download statistics"""
        return {
            'downloaded': self.downloaded_count,
            'failed': self.failed_count,
            'skipped': self.skipped_count,
            'total': self.downloaded_count + self.failed_count + self.skipped_count
        }
