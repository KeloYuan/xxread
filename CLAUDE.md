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
   - `bookmark_dao.dart` - Bookmark data access operations with full CRUD functionality
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
- `bookmarks` - Stores user bookmarks with notes and page references
- `reading_stats` - Tracks daily reading statistics and reading time
- `highlights` - Stores text highlights with positions and color coding
- `notes` - Stores user notes with text references and timestamps

#### Database Schema Updates
- **Version 4**: Added highlights and notes tables for annotation features
- **Bookmark enhancements**: Full CRUD operations with note support
- **Cross-references**: Proper foreign key relationships between books, bookmarks, highlights, and notes

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

### Common UI Patterns and Solutions

#### Control Bar Animation Issues
When working with animated control bars in reading interfaces:
- **Problem**: Control bars appearing in wrong position or lacking animation
- **Solution**: Use AnimatedPositioned with bottom positioning and AnimatedOpacity for fade effects
- **Code Pattern**:
  ```dart
  AnimatedPositioned(
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeInOut,
    bottom: _showControls ? 0 : -200,
    left: 0,
    right: 0,
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: _showControls ? 1.0 : 0.0,
      child: Container(...)
    )
  )
  ```

#### Text Pagination with UI Overlays
When implementing text pagination that needs to account for UI elements:
- **Problem**: Text being covered by control bars or other UI elements
- **Solution**: Reserve space in pagination calculations
- **Implementation**: Subtract UI element height from available space before calculating characters per page
- **Key**: Always reserve space even when UI elements are hidden to maintain consistent pagination

#### Animation Conflicts
- **Problem**: Multiple animation systems conflicting (AnimationController vs implicit animations)
- **Solution**: Choose one approach consistently - prefer implicit animations (AnimatedPositioned, AnimatedOpacity) for simpler implementations
- **Avoid**: Mixing SingleTickerProviderStateMixin with implicit animations unless absolutely necessary

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

### Reading Interface Enhancements
- **Enhanced Control Bar System**: Slide-in/slide-out animated control bar at bottom of screen
  - Smooth AnimatedPositioned transitions (300ms duration)
  - AnimatedOpacity for fade effects (250ms duration)
  - Proper Stack layout with title bar at top, control bar at bottom
- **Smart Text Pagination**: Intelligent text flow management
  - Control bar space reservation (140px) to prevent text overlap
  - Dynamic character-per-page calculation based on available display area
  - Responsive layout adaptation for different screen sizes
- **Bookmark Management**: Full bookmark functionality with database persistence
  - Quick bookmark addition/removal from control bar
  - Bookmark navigation and management
  - Note support for bookmarks
- **Search and Navigation**: Enhanced text search with multi-result navigation
  - Search across entire book content
  - Result highlighting and navigation
  - Case-insensitive search support
- **Sharing Capabilities**: Multiple content sharing formats
  - Current page content sharing
  - Selected text sharing
  - Reading progress sharing

### Animation System
- **Implicit Animations**: Uses Flutter's AnimatedPositioned and AnimatedOpacity
  - Avoids complex AnimationController management
  - Smooth, consistent animations across UI elements
  - Proper curve animations (Curves.easeInOut) for natural motion
- **Performance Optimized**: Minimal animation overhead
  - State-based animation triggers
  - Efficient widget rebuilding strategies