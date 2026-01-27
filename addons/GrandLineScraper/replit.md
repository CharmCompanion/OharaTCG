# One Piece TCG Card Scraper

## Overview

This is a comprehensive One Piece Trading Card Game (TCG) data scraping and management application built with Streamlit. The application fetches card data from the APITCG API and GitHub repositories, processes and normalizes the data, downloads card images, and exports everything in multiple formats suitable for various use cases including game development (specifically Godot engine integration).

The scraper handles both OCG (Original Card Game - Japanese) and TCG (Trading Card Game - English) versions, with built-in translation capabilities and data processing pipelines.

## User Preferences

Preferred communication style: Simple, everyday language.

## System Architecture

### Frontend Architecture
- **Streamlit Web Interface**: Single-page application with custom CSS styling featuring a One Piece theme
- **Interactive Configuration**: Users can select card types, languages, export formats, and image download options
- **Real-time Progress Tracking**: Live progress bars and status updates during scraping and processing operations
- **Responsive Layout**: Wide layout with expandable sidebar for configuration options

### Backend Architecture
- **Modular Class Structure**: Separate classes for distinct responsibilities:
  - `APITCGClient`: Handles API communication and data fetching
  - `DataProcessor`: Normalizes and translates card data
  - `ImageDownloader`: Manages image acquisition and organization
  - `ExportManager`: Handles data export in multiple formats
- **Session Management**: Persistent HTTP sessions with proper headers and authentication
- **Error Handling**: Comprehensive error catching and user feedback throughout the pipeline

### Data Processing Pipeline
- **Multi-source Data Aggregation**: Combines data from APITCG API and GitHub repositories
- **Translation Engine**: Built-in Japanese to English translation for OCG cards
- **Data Normalization**: Standardizes card attributes across different sources
- **Export Flexibility**: Supports JSON, CSV, and Godot-specific formats

### File Organization
- **Structured Output Directory**: Organized folders for images, exports, and logs
- **Image Management**: Separate directories for cards, sets, and thumbnails
- **Timestamped Exports**: All exports include timestamps to prevent overwrites

## External Dependencies

### APIs and Data Sources
- **APITCG API**: Primary data source for One Piece TCG card information (requires API key authentication)
- **GitHub Repository**: Secondary data source from `one-piece-tcg/one-piece-tcg-data` repository
- **Card Image URLs**: Various image hosting services for downloading card artwork

### Third-party Libraries
- **Streamlit**: Web application framework for the user interface
- **Requests**: HTTP client library for API communication and image downloading
- **Pandas**: Data manipulation and CSV export functionality
- **Pillow (PIL)**: Image processing and thumbnail generation
- **JSON**: Built-in Python library for data serialization

### Authentication Requirements
- **API Key**: Required for APITCG API access, configured through the Streamlit interface
- **Rate Limiting**: Built-in delays and session management to respect API limits

### Export Integrations
- **Godot Engine**: Special export format for game development integration
- **CSV Format**: For spreadsheet applications and data analysis
- **JSON Format**: For web applications and general data interchange