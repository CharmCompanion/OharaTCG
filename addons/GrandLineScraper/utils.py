import os
from pathlib import Path
from typing import List, Dict, Any, Optional
import streamlit as st

def create_directories(base_dir: str) -> None:
    """Create necessary output directories"""
    base_path = Path(base_dir)
    
    # Create main directories
    directories = [
        base_path,
        base_path / "images",
        base_path / "images" / "cards",
        base_path / "images" / "sets",
        base_path / "images" / "thumbnails",
        base_path / "exports",
        base_path / "logs"
    ]
    
    for directory in directories:
        directory.mkdir(parents=True, exist_ok=True)

def format_file_size(size_bytes: int) -> str:
    """Format file size in human readable format"""
    if size_bytes == 0:
        return "0 B"
    
    size_names = ["B", "KB", "MB", "GB", "TB"]
    i = 0
    size_float = float(size_bytes)
    while size_float >= 1024.0 and i < len(size_names) - 1:
        size_float /= 1024.0
        i += 1
    
    return f"{size_float:.1f} {size_names[i]}"

def get_progress_color(progress: float) -> str:
    """Get color for progress based on completion percentage"""
    if progress < 0.3:
        return "#D32F2F"  # Red
    elif progress < 0.7:
        return "#FF9800"  # Orange
    else:
        return "#388E3C"  # Green

def validate_api_key(api_key: str) -> bool:
    """Basic validation for API key format"""
    if not api_key:
        return False
    
    # Basic checks - adjust based on actual API key format
    if len(api_key) < 10:
        return False
    
    # Check for obvious placeholder values
    placeholder_values = ["your_api_key", "api_key_here", "test", "demo"]
    if api_key.lower() in placeholder_values:
        return False
    
    return True

def sanitize_json_data(data: Any) -> Any:
    """Sanitize data for JSON serialization"""
    if isinstance(data, dict):
        return {key: sanitize_json_data(value) for key, value in data.items()}
    elif isinstance(data, list):
        return [sanitize_json_data(item) for item in data]
    elif isinstance(data, (str, int, float, bool, type(None))):
        return data
    else:
        # Convert other types to string
        return str(data)

def merge_card_databases(databases: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Merge multiple card databases into one"""
    merged = {
        'cards': [],
        'sets': [],
        'metadata': {
            'sources': [],
            'total_cards': 0,
            'total_sets': 0
        }
    }
    
    seen_cards = set()
    seen_sets = set()
    
    for db in databases:
        # Merge cards
        for card in db.get('cards', []):
            card_id = card.get('id', '')
            if card_id and card_id not in seen_cards:
                merged['cards'].append(card)
                seen_cards.add(card_id)
        
        # Merge sets
        for set_data in db.get('sets', []):
            set_id = set_data.get('id', '')
            if set_id and set_id not in seen_sets:
                merged['sets'].append(set_data)
                seen_sets.add(set_id)
        
        # Merge metadata
        if 'metadata' in db:
            metadata = db['metadata']
            if 'sources' in metadata:
                merged['metadata']['sources'].extend(metadata['sources'])
    
    # Update counts
    merged['metadata']['total_cards'] = len(merged['cards'])
    merged['metadata']['total_sets'] = len(merged['sets'])
    merged['metadata']['sources'] = list(set(merged['metadata']['sources']))
    
    return merged

def log_operation(message: str, level: str = "INFO"):
    """Log operation with timestamp"""
    from datetime import datetime
    
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_message = f"[{timestamp}] {level}: {message}"
    
    # Write to Streamlit
    if level == "ERROR":
        st.error(log_message)
    elif level == "WARNING":
        st.warning(log_message)
    else:
        st.write(log_message)

def estimate_download_time(total_images: int, avg_image_size_kb: int = 200) -> str:
    """Estimate download time for images"""
    # Assume average download speed of 1MB/s
    total_size_mb = (total_images * avg_image_size_kb) / 1024
    estimated_seconds = total_size_mb  # 1MB/s
    
    if estimated_seconds < 60:
        return f"~{int(estimated_seconds)} seconds"
    elif estimated_seconds < 3600:
        return f"~{int(estimated_seconds / 60)} minutes"
    else:
        return f"~{int(estimated_seconds / 3600)} hours"

def get_card_statistics(cards: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Generate statistics for card collection"""
    if not cards:
        return {}
    
    stats = {
        'total_cards': len(cards),
        'sets': set(),
        'types': {},
        'rarities': {},
        'colors': {},
        'languages': {},
        'sources': {},
        'promo_count': 0,
        'tournament_count': 0,
        'alt_art_count': 0
    }
    
    for card in cards:
        # Count sets
        if card.get('set_id'):
            stats['sets'].add(card['set_id'])
        
        # Count types
        card_type = card.get('type', 'Unknown')
        stats['types'][card_type] = stats['types'].get(card_type, 0) + 1
        
        # Count rarities
        rarity = card.get('rarity', 'Unknown')
        stats['rarities'][rarity] = stats['rarities'].get(rarity, 0) + 1
        
        # Count colors
        colors = card.get('colors', [])
        if isinstance(colors, list):
            for color in colors:
                stats['colors'][color] = stats['colors'].get(color, 0) + 1
        
        # Count languages
        language = card.get('language', 'Unknown')
        stats['languages'][language] = stats['languages'].get(language, 0) + 1
        
        # Count sources
        source = card.get('source', 'Unknown')
        stats['sources'][source] = stats['sources'].get(source, 0) + 1
        
        # Count special types
        if card.get('is_promo'):
            stats['promo_count'] += 1
        if card.get('is_tournament'):
            stats['tournament_count'] += 1
        if card.get('is_alternate_art'):
            stats['alt_art_count'] += 1
    
    stats['total_sets'] = len(stats['sets'])
    stats['sets'] = list(stats['sets'])
    
    return stats

def display_card_preview(card: Dict[str, Any], image_path: Optional[str] = None):
    """Display a card preview in Streamlit"""
    col1, col2 = st.columns([1, 2])
    
    with col1:
        # Display image if available
        if image_path and os.path.exists(image_path):
            st.image(image_path, width=200)
        else:
            st.write("🎴 No image available")
    
    with col2:
        # Display card information
        st.write(f"**{card.get('name', 'Unknown Card')}**")
        st.write(f"Set: {card.get('set_name', 'Unknown')} ({card.get('set_id', '')})")
        st.write(f"Number: {card.get('number', '')}")
        st.write(f"Type: {card.get('type', '')}")
        st.write(f"Rarity: {card.get('rarity', '')}")
        
        if card.get('cost'):
            st.write(f"Cost: {card.get('cost')}")
        if card.get('power'):
            st.write(f"Power: {card.get('power')}")
        effect = card.get('effect')
        if effect:
            st.write(f"Effect: {effect[:100]}...")

def create_download_summary(exported_files: List[str], image_count: int) -> str:
    """Create a summary of downloaded/exported files"""
    summary = "## Download Summary\n\n"
    summary += f"- **Total exported files:** {len(exported_files)}\n"
    summary += f"- **Total images downloaded:** {image_count}\n\n"
    
    summary += "### Exported Files:\n"
    for file_path in exported_files:
        filename = os.path.basename(file_path)
        file_size = format_file_size(os.path.getsize(file_path)) if os.path.exists(file_path) else "Unknown"
        summary += f"- {filename} ({file_size})\n"
    
    return summary
