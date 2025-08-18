# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

xxread (小元读书) is an elegant Flutter e-book reader application that supports EPUB, TXT, and PDF formats. The app features local storage, reading progress tracking, bookmarks, reading statistics, and responsive design for both mobile and desktop platforms.

## Development Commands

### Core Flutter Commands
- `flutter pub get` - Install dependencies
- `flutter run` - Run the app in debug mode
- `flutter build` - Build the app for production
- `flutter test` - Run unit tests
- `flutter analyze` - Analyze code for issues and lint violations

### Platform-Specific Commands
- `flutter run -d windows` - Run on Windows
- `flutter run -d macos` - Run on macOS
- `flutter run -d linux` - Run on Linux
- `flutter run -d chrome` - Run on web (Chrome)
- `flutter build windows` - Build for Windows
- `flutter build macos` - Build for macOS
- `flutter build linux` - Build for Linux
- `flutter build web` - Build for web

### Testing
- `flutter test` - Run all tests
- `flutter test test/widget_test.dart` - Run specific test file
- `flutter test --coverage` - Run tests with coverage report

## Architecture Overview

### Layer Structure
The app follows a layered architecture:

1. **Presentation Layer** (`lib/pages/`): UI components and screens
   - `home_page_responsive.dart` - Main navigation with responsive design
   - `home_content_enhanced.dart` - Home dashboard with reading stats
   - `library_page.dart` - Book library management
   - `reading_page_enhanced.dart` - Enhanced reading interface
   - `import_book_page.dart` - Book import functionality
   - `settings_page.dart` - App settings and preferences

2. **Business Logic Layer** (`lib/services/`): Core business logic and data access
   - `database_service.dart` - SQLite database management singleton
   - `book_dao.dart` - Book data access operations
   - `reading_stats_dao.dart` - Reading statistics data access
   - `highlight_dao.dart` - Highlight data access operations
   - `note_dao.dart` - Note data access operations
   - `book_import_service.dart` - Book file import and processing
   - `storage_service.dart` - File storage operations

3. **Data Layer** (`lib/models/`): Data models and entities
   - `book.dart` - Book entity with file path, progress tracking
   - `bookmark.dart` - Bookmark entity for reading positions
   - `chapter.dart` - Chapter entity for book structure
   - `highlight.dart` - Text highlight entity
   - `note.dart` - User note entity

4. **Utilities** (`lib/utils/`): Helper functions and extensions
   - `responsive_helper.dart` - Responsive design utilities
   - `color_extensions.dart` - Color manipulation extensions
   - `text_selection_helper.dart` - Text selection utilities

5. **Widget Components** (`lib/widgets/`): Reusable UI components
   - `note_dialog.dart` - Note editing dialog
   - `text_selection_toolbar.dart` - Custom text selection toolbar

### Database Design
The app uses SQLite with five main tables:
- `books` - Stores book metadata and reading progress (with totalPages field)
- `bookmarks` - Stores user bookmarks with notes
- `reading_stats` - Tracks daily reading statistics
- `highlights` - Stores text highlights with positions
- `notes` - Stores user notes with references

Cross-platform database support:
- Mobile: Standard SQLite via sqflite
- Desktop: SQLite FFI via sqflite_common_ffi

### State Management
- **Provider pattern** for theme management (`ThemeNotifier` in main.dart)
- **Shared Preferences** for persistent user settings
- **Local database state** managed through DAO services

### File Handling
Books are stored as files with paths in the database rather than content, supporting:
- EPUB processing via `epubx` package
- PDF support
- TXT file reading
- File picker integration for imports

### Responsive Design
Navigation adapts based on screen size:
- **Mobile**: Bottom navigation bar
- **Desktop/Tablet**: Navigation rail sidebar
- Breakpoints managed in `ResponsiveHelper`

## Key Dependencies

### Core Flutter Packages
- `provider` - State management for themes
- `shared_preferences` - Persistent settings storage
- `sqflite` / `sqflite_common_ffi` - Database (mobile/desktop)
- `path_provider` - Cross-platform file paths

### E-book Functionality
- `epubx` - EPUB file processing and reading
- `file_picker` - File selection for book imports

### UI Enhancement
- `fl_chart` - Charts for reading statistics
- `page_flip` - Page turning animations
- `volume_controller` - Hardware volume button support
- `intl` - Internationalization support

## Development Notes

### Main Entry Point
- Desktop platform initialization occurs in `main.dart` with `sqfliteFfiInit()` for Windows/Linux/macOS
- `ThemeNotifier` provider manages app-wide theme state
- Debug logging utility available as `debugLog()` function

### Cross-Platform Considerations
- Database initialization differs between mobile and desktop platforms
- Desktop platforms require FFI initialization in main.dart
- Path handling varies between platforms using path_provider

### Database Versioning
- Current version: 4 (with notes and highlights tables addition)
- Migration system handles upgrades in DatabaseService._onUpgrade()
- Always increment _dbVersion when making schema changes

### Theme System
- Supports light/dark mode with Material 3 design
- Custom color schemes with seed colors
- Theme persistence via SharedPreferences
- Responsive to system theme changes

### Import Functionality
- Supports multiple book formats (EPUB, PDF, TXT)
- File validation and metadata extraction
- Error handling for unsupported formats

### Text Selection and Annotation Features
- Text highlighting with color support
- Note-taking functionality with text references
- Custom text selection toolbar
- Position-based highlight storage for accurate rendering