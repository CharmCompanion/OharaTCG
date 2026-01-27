import streamlit as st
import pandas as pd
import json
import os
from datetime import datetime
import time
from api_client import APITCGClient
from optcg_client import OPTcgClient
from onepiecetopdecks_client import OnePieceTopDecksClient
from data_processor import DataProcessor
from image_downloader import ImageDownloader
from export_manager import ExportManager
from utils import create_directories, format_file_size, get_progress_color

# Set page config
st.set_page_config(
    page_title="One Piece TCG Card Scraper",
    page_icon="🏴‍☠️",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS for One Piece theme
st.markdown("""
<style>
.main-header {
    color: #D32F2F;
    text-align: center;
    font-size: 3rem;
    font-weight: bold;
    margin-bottom: 2rem;
}
.section-header {
    color: #1976D2;
    font-size: 1.5rem;
    font-weight: bold;
    margin: 1rem 0;
}
.status-card {
    background-color: white;
    padding: 1rem;
    border-radius: 10px;
    border-left: 4px solid #D32F2F;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    margin: 1rem 0;
}
.success-message {
    color: #388E3C;
    font-weight: bold;
}
.error-message {
    color: #D32F2F;
    font-weight: bold;
}
.progress-container {
    background-color: white;
    padding: 1rem;
    border-radius: 10px;
    margin: 1rem 0;
}
</style>
""", unsafe_allow_html=True)

def main():
    # Main header
    st.markdown('<h1 class="main-header">🏴‍☠️ One Piece TCG Card Scraper</h1>', unsafe_allow_html=True)
    
    # Initialize session state
    if 'scraping_complete' not in st.session_state:
        st.session_state.scraping_complete = False
    if 'current_progress' not in st.session_state:
        st.session_state.current_progress = {}
    if 'scraped_data' not in st.session_state:
        st.session_state.scraped_data = {}
    if 'downloaded_images' not in st.session_state:
        st.session_state.downloaded_images = []
    
    # Sidebar configuration
    with st.sidebar:
        st.markdown('<h2 class="section-header">⚙️ Configuration</h2>', unsafe_allow_html=True)
        
        # API Key input
        api_key = st.text_input(
            "APITCG API Key",
            value=os.getenv("APITCG_API_KEY", ""),
            type="password",
            help="Enter your APITCG API key"
        )
        
        # Data source selection
        st.markdown("### Data Sources")
        include_apitcg = st.checkbox("APITCG (Vegapull) Data", value=True, help="Fetch data from vegapull GitHub data")
        include_github = st.checkbox("GitHub Repository", value=True, help="Fetch data from one-piece-tcg-data repository")
        include_optcg = st.checkbox("OPTCG API (English Overlay)", value=True, help="Overlay OPTCG English text + image URLs")
        include_topdecks = st.checkbox("OnePieceTopDecks (Leaks/Translated)", value=False, help="Scrape fan-translated leaks and set galleries")

        topdecks_extra_urls = ""
        if include_topdecks:
            topdecks_extra_urls = st.text_area(
                "TopDecks Extra URLs (one per line)",
                value="https://onepiecetopdecks.com/one-piece-booster-set-adventure-on-kamis-island-op-15/",
                help="Optional: add specific leak pages to include"
            )
        
        # Card type selection
        st.markdown("### Card Types")
        card_types = {
            "Sets": st.checkbox("Sets", value=True),
            "Decks": st.checkbox("Decks", value=True),
            "Promos": st.checkbox("Promos", value=True),
            "Tournaments": st.checkbox("Tournaments", value=True),
            "Don Cards": st.checkbox("Don Cards", value=True),
            "Alt Arts": st.checkbox("Alt Arts", value=True)
        }
        
        # Language options
        st.markdown("### Language Options")
        include_ocg = st.checkbox("OCG (Japanese)", value=True)
        include_tcg = st.checkbox("TCG (English)", value=True)
        translate_ocg = st.checkbox("Translate OCG to English", value=True)
        
        # Export options
        st.markdown("### Export Options")
        download_images = st.checkbox("Download PNG Images", value=True)
        auto_copy_decks = st.checkbox("Auto-copy starter decks to game data", value=True, help="Copy starter deck JSONs into res://data/decks")
        export_format = st.selectbox("Export Format", ["JSON", "CSV", "Both"])
        
        # Output directory
        output_dir = st.text_input("Output Directory", value="./output")
        
    # Main content area
    col1, col2 = st.columns([2, 1])
    
    with col1:
        st.markdown('<h2 class="section-header">📊 Scraping Dashboard</h2>', unsafe_allow_html=True)
        
        # Validation and start button
        if not api_key and include_apitcg:
            st.warning("⚠️ No API key provided. Current vegapull data source does not require a key.")
        
        if not any([include_apitcg, include_github, include_optcg, include_topdecks]):
            st.error("⚠️ Please select at least one data source")
            st.stop()
        
        if not any(card_types.values()):
            st.error("⚠️ Please select at least one card type")
            st.stop()
        
        # Start scraping button
        if st.button("🚀 Start Scraping", type="primary", use_container_width=True):
            start_scraping(api_key, include_apitcg, include_github, include_optcg, include_topdecks,
                          topdecks_extra_urls, card_types,
                          include_ocg, include_tcg, translate_ocg, download_images, 
                          export_format, output_dir, auto_copy_decks)
    
    with col2:
        st.markdown('<h2 class="section-header">📈 Progress</h2>', unsafe_allow_html=True)
        display_progress_panel()
    
    # Results section
    if st.session_state.scraping_complete:
        display_results()

def start_scraping(api_key, include_apitcg, include_github, include_optcg, include_topdecks,
                   topdecks_extra_urls, card_types, include_ocg, include_tcg, translate_ocg, download_images,
                   export_format, output_dir, auto_copy_decks):
    """Start the scraping process"""
    
    # Create output directories
    create_directories(output_dir)
    
    # Initialize progress
    progress_container = st.empty()
    status_container = st.empty()
    
    try:
        # Initialize clients and processors
        api_client = APITCGClient(api_key) if (include_apitcg or include_optcg) else None
        optcg_client = OPTcgClient() if include_optcg else None
        topdecks_client = OnePieceTopDecksClient() if include_topdecks else None
        data_processor = DataProcessor()
        image_downloader = ImageDownloader(output_dir) if download_images else None
        export_manager = ExportManager(
            output_dir,
            auto_copy_decks=auto_copy_decks,
            export_complete_deck_json=False,
        )
        
        total_steps = sum([
            include_apitcg,
            include_github,
            include_optcg,
            include_topdecks,
            any(card_types.values()),
            download_images,
            True  # Export step
        ])
        
        current_step = 0
        
        # Step 1: Fetch APITCG data
        if include_apitcg:
            current_step += 1
            update_progress(progress_container, current_step, total_steps, "Fetching APITCG data...")
            
            try:
                if api_client:
                    apitcg_data = api_client.fetch_all_data(card_types, include_ocg, include_tcg)
                    st.session_state.scraped_data['apitcg'] = apitcg_data
                    st.session_state.current_progress['apitcg'] = f"✅ Fetched {len(apitcg_data.get('cards', []))} cards"
                else:
                    st.error("API client not initialized")
                    return
            except Exception as e:
                st.error(f"Failed to fetch APITCG data: {str(e)}")
                return
        
        # Step 2: Fetch GitHub data
        if include_github:
            current_step += 1
            update_progress(progress_container, current_step, total_steps, "Fetching GitHub repository data...")
            
            try:
                github_data = api_client.fetch_github_data() if api_client else {}
                st.session_state.scraped_data['github'] = github_data
                st.session_state.current_progress['github'] = f"✅ Fetched {len(github_data)} additional cards"
            except Exception as e:
                st.warning(f"Failed to fetch GitHub data: {str(e)}")
                st.session_state.scraped_data['github'] = {}

        # Step 3: Fetch OPTCG data (English overlay)
        if include_optcg:
            current_step += 1
            update_progress(progress_container, current_step, total_steps, "Fetching OPTCG English overlay...")

            try:
                if optcg_client:
                    set_list = []
                    if include_apitcg and 'apitcg' in st.session_state.scraped_data:
                        set_list = st.session_state.scraped_data['apitcg'].get('sets', [])
                    elif api_client:
                        set_list = api_client.fetch_set_list(False, True)

                    # Filter to TCG sets using current card type selections
                    set_ids = []
                    for pack in set_list:
                        if not pack or pack.get('language') != 'tcg':
                            continue
                        pack_type = pack.get('type', 'unknown')
                        if pack_type == 'booster_pack' and not card_types.get('Sets', True):
                            continue
                        if pack_type == 'starter_deck' and not card_types.get('Decks', True):
                            continue
                        if pack_type == 'promo' and not card_types.get('Promos', True):
                            continue
                        if pack_type == 'other' and not card_types.get('Alt Arts', True):
                            continue
                        set_ids.append(pack.get('label', pack.get('id', '')))

                    optcg_data = optcg_client.fetch_cards_for_sets(
                        set_ids,
                        include_sets=card_types.get('Sets', True),
                        include_decks=card_types.get('Decks', True),
                        include_promos=card_types.get('Promos', True),
                        include_optcg_catalog=True,
                    )
                    st.session_state.scraped_data['optcg'] = optcg_data
                    st.session_state.current_progress['optcg'] = f"✅ Fetched {len(optcg_data.get('cards', []))} OPTCG cards"
                else:
                    st.error("OPTCG client not initialized")
            except Exception as e:
                st.warning(f"Failed to fetch OPTCG data: {str(e)}")
                st.session_state.scraped_data['optcg'] = {}

        # Step 4: Fetch OnePieceTopDecks data
        if include_topdecks:
            current_step += 1
            update_progress(progress_container, current_step, total_steps, "Fetching OnePieceTopDecks data...")

            try:
                extra_urls = [line.strip() for line in (topdecks_extra_urls or "").splitlines() if line.strip()]
                topdecks_data = topdecks_client.fetch_all_data(extra_urls=extra_urls) if topdecks_client else {}
                st.session_state.scraped_data['onepiecetopdecks'] = topdecks_data
                st.session_state.current_progress['onepiecetopdecks'] = f"✅ Fetched {len(topdecks_data.get('cards', []))} TopDecks cards"
            except Exception as e:
                st.warning(f"Failed to fetch TopDecks data: {str(e)}")
                st.session_state.scraped_data['onepiecetopdecks'] = {}
        
        # Step 5: Process and merge data
        current_step += 1
        update_progress(progress_container, current_step, total_steps, "Processing and merging data...")
        
        processed_data = data_processor.process_all_data(
            st.session_state.scraped_data,
            translate_ocg=translate_ocg
        )
        st.session_state.scraped_data['processed'] = processed_data
        
        # Validate card coverage
        validation_results = export_manager.validate_card_coverage(processed_data.get('cards', []))
        st.session_state.validation_results = validation_results
        st.session_state.current_progress['validation'] = f"✅ Validation Score: {validation_results['overall_score']:.1f}%"
        
        # Step 5: Download images
        if download_images and image_downloader:
            current_step += 1
            update_progress(progress_container, current_step, total_steps, "Downloading card images...")
            
            downloaded_images = image_downloader.download_all_images(processed_data)
            st.session_state.downloaded_images = downloaded_images
            st.session_state.current_progress['images'] = f"✅ Downloaded {len(downloaded_images)} images"
            st.write("📁 Syncing downloaded images into Godot assets...")
            image_downloader.sync_to_godot_assets(processed_data)
        
        # Step 6: Export data
        current_step += 1
        update_progress(progress_container, current_step, total_steps, "Exporting data...")
        
        export_paths = export_manager.export_data(processed_data, export_format)
        st.session_state.current_progress['export'] = f"✅ Exported to {len(export_paths)} files"
        
        # Complete
        update_progress(progress_container, total_steps, total_steps, "✅ Scraping completed successfully!")
        st.session_state.scraping_complete = True
        
        # Show success message
        st.success("🎉 Scraping completed successfully! Check the results below.")
        
    except Exception as e:
        st.error(f"❌ Scraping failed: {str(e)}")

def update_progress(container, current, total, message):
    """Update progress display"""
    progress = current / total
    with container:
        st.progress(progress)
        st.write(f"**Step {current}/{total}:** {message}")

def display_progress_panel():
    """Display current progress in sidebar"""
    if st.session_state.current_progress:
        for source, status in st.session_state.current_progress.items():
            st.markdown(f"**{source.title()}:** {status}")
    else:
        st.info("No scraping in progress")

def display_results():
    """Display scraping results"""
    st.markdown('<h2 class="section-header">📋 Scraping Results</h2>', unsafe_allow_html=True)
    
    # Summary statistics
    col1, col2, col3, col4 = st.columns(4)
    
    processed_data = st.session_state.scraped_data.get('processed', {})
    validation_results = st.session_state.get('validation_results', {})
    
    with col1:
        total_cards = len(processed_data.get('cards', []))
        st.metric("Total Cards", total_cards)
    
    with col2:
        coverage_score = validation_results.get('overall_score', 0)
        st.metric("Coverage Score", f"{coverage_score:.1f}%", 
                  delta=f"{coverage_score-70:.1f}%" if coverage_score > 70 else None)
    
    with col3:
        validation_coverage = validation_results.get('coverage_analysis', {})
        coverage_percentage = validation_coverage.get('coverage_percentage', 0)
        st.metric("Expected Coverage", f"{coverage_percentage:.1f}%")
    
    with col4:
        total_images = len(st.session_state.get('downloaded_images', {}))
        st.metric("Downloaded Images", total_images)
    
    # Validation Results Section
    if validation_results:
        st.markdown("### 🔍 Validation Results")
        
        # Coverage Analysis
        col1, col2, col3 = st.columns(3)
        
        coverage_analysis = validation_results.get('coverage_analysis', {})
        set_completeness = validation_results.get('set_completeness', {})
        variant_coverage = validation_results.get('variant_coverage', {})
        
        with col1:
            st.markdown("**📊 Coverage Statistics**")
            st.write(f"• Total Cards Found: {coverage_analysis.get('total_found_cards', 0):,}")
            st.write(f"• Expected Cards: {coverage_analysis.get('total_expected_cards', 0):,}")
            st.write(f"• Coverage: {coverage_analysis.get('coverage_percentage', 0):.1f}%")
            st.write(f"• Complete Sets: {coverage_analysis.get('sets_complete', 0)}")
            st.write(f"• Partial Sets: {coverage_analysis.get('sets_partial', 0)}")
            st.write(f"• Missing Sets: {coverage_analysis.get('sets_missing', 0)}")
        
        with col2:
            st.markdown("**🎴 Variant Coverage**")
            st.write(f"• Alternate Arts: {variant_coverage.get('alternate_arts', 0)}")
            st.write(f"• Promotional Cards: {variant_coverage.get('promotional_cards', 0)}")
            st.write(f"• Starter Deck Cards: {variant_coverage.get('starter_deck_cards', 0)}")
            st.write(f"• Unique Card Names: {variant_coverage.get('unique_card_names', 0)}")
            st.write(f"• Cards with Variants: {variant_coverage.get('cards_with_variants', 0)}")
        
        with col3:
            st.markdown("**⚠️ Issues & Recommendations**")
            recommendations = validation_results.get('recommendations', [])
            duplicates = validation_results.get('duplicate_detection', [])
            
            if duplicates:
                st.write(f"• Duplicate IDs: {len(duplicates)}")
            
            if recommendations:
                for rec in recommendations[:4]:  # Show first 4 recommendations
                    st.write(f"• {rec}")
            else:
                st.write("• No issues found ✅")
        
        # Set Completeness Details
        if st.expander("📋 Detailed Set Analysis", expanded=False):
            st.markdown("**Set Completeness Overview:**")
            
            # Group sets by type
            booster_sets = {k: v for k, v in set_completeness.items() if k.startswith('OP-')}
            starter_sets = {k: v for k, v in set_completeness.items() if k.startswith('ST-')}
            promo_sets = {k: v for k, v in set_completeness.items() if k.startswith('P-') or k.startswith('PRB-')}
            
            col1, col2, col3 = st.columns(3)
            
            with col1:
                st.markdown("**🎯 Booster Sets**")
                for set_id, info in booster_sets.items():
                    status_icon = "✅" if info['completion_rate'] >= 90 else "⚠️" if info['completion_rate'] >= 50 else "❌"
                    st.write(f"{status_icon} {set_id}: {info['found']}/{info['expected']} ({info['completion_rate']:.1f}%)")
            
            with col2:
                st.markdown("**🏁 Starter Sets**")
                for set_id, info in starter_sets.items():
                    status_icon = "✅" if info['completion_rate'] >= 90 else "⚠️" if info['completion_rate'] >= 50 else "❌"
                    st.write(f"{status_icon} {set_id}: {info['found']}/{info['expected']} ({info['completion_rate']:.1f}%)")
            
            with col3:
                st.markdown("**🎁 Promotional Sets**")
                for set_id, info in promo_sets.items():
                    status_icon = "✅" if info['completion_rate'] >= 90 else "⚠️" if info['completion_rate'] >= 50 else "❌"
                    st.write(f"{status_icon} {set_id}: {info['found']}/{info['expected']} ({info['completion_rate']:.1f}%)")
    
    # Data preview
    st.markdown("### 🔍 Data Preview")
    if processed_data.get('cards'):
        df = pd.DataFrame(processed_data['cards'][:100])  # Show first 100 cards
        st.dataframe(df, use_container_width=True)
    
    # Download section
    st.markdown("### 📥 Download Files")
    
    # Bulk download options
    st.markdown("#### 🎯 Bulk Downloads")
    col1, col2, col3 = st.columns(3)
    
    output_dir = "./output"
    if os.path.exists(output_dir):
        # Complete package download
        complete_file = os.path.join(output_dir, "bulk", "complete", "one_piece_tcg_complete.json")
        if os.path.exists(complete_file):
            with col1:
                with open(complete_file, 'rb') as f:
                    st.download_button(
                        label="📦 Complete Package",
                        data=f.read(),
                        file_name="one_piece_tcg_complete.json",
                        mime="application/json",
                        help="Download everything - cards, sets, decks, metadata"
                    )
        
        # Sets-only download
        sets_file = os.path.join(output_dir, "bulk", "sets-only", "one_piece_tcg_sets_only.json")
        if os.path.exists(sets_file):
            with col2:
                with open(sets_file, 'rb') as f:
                    st.download_button(
                        label="🎴 Sets Only",
                        data=f.read(),
                        file_name="one_piece_tcg_sets_only.json",
                        mime="application/json",
                        help="Download only set-organized card data"
                    )
        
        # Decks-only download  
        decks_file = os.path.join(output_dir, "bulk", "decks-only", "one_piece_tcg_decks_only.json")
        if os.path.exists(decks_file):
            with col3:
                with open(decks_file, 'rb') as f:
                    st.download_button(
                        label="🏴‍☠️ Decks Only",
                        data=f.read(),
                        file_name="one_piece_tcg_decks_only.json",
                        mime="application/json",
                        help="Download only starter deck data"
                    )
        
        # Database download
        st.markdown("#### 🎮 Dueling Simulator Files")
        db_file = os.path.join(output_dir, "databases", "one_piece_dueling_database.db")
        if os.path.exists(db_file):
            col1, col2 = st.columns(2)
            with col1:
                with open(db_file, 'rb') as f:
                    st.download_button(
                        label="🎯 YGO Pro Percy Database",
                        data=f.read(),
                        file_name="one_piece_dueling_database.db",
                        mime="application/octet-stream",
                        help="SQLite database for dueling simulators"
                    )
        
        # Show organized folder structure
        st.markdown("#### 📁 Organized Files by Category")
        
        # Display folder structure
        folder_categories = {
            "🎯 Booster Sets": "sets/booster",
            "🏁 Starter Sets": "sets/starter", 
            "📣 Promotional Sets": "sets/promotional",
            "✨ Special Sets": "sets/special",
            "🏴‍☠️ Starter Decks": "decks/starter",
            "🎮 Databases": "databases",
            "🔍 Archetype Keywords": "archetypes"
        }
        
        for category_name, folder_path in folder_categories.items():
            full_path = os.path.join(output_dir, folder_path)
            if os.path.exists(full_path):
                with st.expander(f"{category_name}"):
                    display_folder_contents(full_path, folder_path)
        
        # Legacy individual files (if any remain)
        files = [f for f in os.listdir(output_dir) if os.path.isfile(os.path.join(output_dir, f))]
        if files:
            st.markdown("#### 📄 Individual Files")
            for file in files:
                file_path = os.path.join(output_dir, file)
                file_size = format_file_size(os.path.getsize(file_path))
                
                col1, col2 = st.columns([3, 1])
                with col1:
                    st.write(f"📄 **{file}** ({file_size})")
                with col2:
                    with open(file_path, 'rb') as f:
                        st.download_button(
                            label="Download",
                            data=f.read(),
                            file_name=file,
                            mime="application/octet-stream"
                        )

def display_folder_contents(folder_path, relative_path):
    """Display contents of a folder with download buttons"""
    if not os.path.exists(folder_path):
        st.info(f"No files found in {relative_path}")
        return
    
    # Get all files and subdirectories
    items = []
    for root, dirs, files in os.walk(folder_path):
        for file in files:
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, folder_path)
            items.append((full_path, rel_path, os.path.getsize(full_path)))
    
    if not items:
        st.info(f"No files found in {relative_path}")
        return
    
    # Sort by relative path
    items.sort(key=lambda x: x[1])
    
    # Display files
    for full_path, rel_path, file_size in items:
        col1, col2 = st.columns([3, 1])
        
        with col1:
            # Determine file icon
            if rel_path.endswith('.json'):
                icon = "📄"
            elif rel_path.endswith('.db'):
                icon = "🗄️"
            elif rel_path.endswith('.ydl'):
                icon = "🎮"
            elif rel_path.endswith('.csv'):
                icon = "📊"
            else:
                icon = "📁"
            
            st.write(f"{icon} **{rel_path}** ({format_file_size(file_size)})")
        
        with col2:
            with open(full_path, 'rb') as f:
                file_name = os.path.basename(full_path)
                mime_type = "application/json" if file_name.endswith('.json') else "application/octet-stream"
                st.download_button(
                    label="Download",
                    data=f.read(),
                    file_name=file_name,
                    mime=mime_type,
                    key=f"download_{rel_path.replace('/', '_').replace('.', '_')}"
                )

if __name__ == "__main__":
    main()
