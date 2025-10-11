# Changelog

All notable changes to TimeKeeper will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.3] - 2025-01-11

### Added
- **Separate Output Folders for Race Types**: Automatic file organization by race type
  - Free Races folder: Default to Desktop/FreeRaces for all custom races
  - Event Races folder: Default to Desktop/EventRaces for all API-connected races
  - Both folders configurable in Preferences with custom locations
  - Automatic directory creation when needed
  - Clean separation prevents file mixing between race types

### Improved
- **Automatic Storage Routing**: Session data automatically saved to correct folder
  - Free Races (no eventId) save to Free Races directory
  - Event Races (with eventId) save to Event Races directory
  - No manual intervention required for folder selection
- **Easy Migration**: Existing race files can be copied to new folders and work immediately

## [0.7.2] - 2025-01-11

### Improved
- **UX Enhancement**: NEW RACE button now properly disabled when event with race plan is loaded
  - Prevents accidental creation of manual races when races are predefined in race plan
  - Button appears dimmed (50% opacity) when disabled to provide clear visual feedback
  - Races from loaded events must be selected from the Race dropdown, not created manually

## [0.7.1] - 2025-01-11

### Improved
- **Lane Number Display**: Enhanced lane selection dialogs to show lane numbers
  - Timeline marker selection now displays "Lane X: [Team Name]" format
  - New Race dialog lane setup shows clear lane numbering
  - Improved usability when identifying lanes during race timing

### Fixed
- **Unsaved Changes Protection**: Comprehensive confirmation dialogs for all navigation actions
  - Event picker now checks for unsaved changes before switching events
  - Race picker already had confirmation via reactive system
  - NEW RACE button confirmation implemented
  - Video recording via keyboard shortcuts now properly marks data as unsaved
  - Prevents accidental data loss when navigating between events and races

## [0.6.2] - 2025-01-08

### Added
- **Image Selection UI**: Complete interface for selecting exported images to send to server
  - Individual checkboxes for each exported image with filename and timestamp
  - Latest exported image automatically selected by default
  - "Send Selected" button with server upload functionality
  - Scrollable list showing most recent images first

### Fixed
- **Unified Zoom/Pan for Photo Finish**: Photo finish overlay now zooms and pans together with video
  - Fixed finish line overlay positioning to move with video transforms
  - Eliminated overlay drift when zooming or panning video
  - Maintained relative position accuracy during all zoom/pan operations
  - Enhanced visual consistency between UI display and exported coordinates

### Improved
- **Visual Consistency**: Changed finish line color to yellow in both UI and exported images
- **Content Clipping**: Enabled proper clipping for zoomed video content within frame bounds
- **Code Cleanup**: Removed deprecated finish line overlay code and debug elements

## [0.6.1] - 2025-01-07

### Fixed
- **Perfect Export Coordinate Alignment**: Fixed Y coordinate calculation to match UI positioning exactly
- **16:9 Video Display**: Removed letterboxing for 1920×1080 videos in 16:9 container for perfect fit
- **Edge Positioning**: Updated finish line to position at absolute top/bottom edges for precise measurement
- **Simplified Export Logic**: Removed 90% height scaling and margin calculations for direct coordinate mapping
- **Clean Interface**: Removed debug elements for production-ready appearance

## [0.6.0] - 2025-01-07

### Added
- **Unified Zoom and Pan System**: Video and photo finish overlay now zoom/pan together as single unit
- **Intuitive Gesture Controls**: Pinch-to-zoom and drag-to-pan with natural responsiveness
- **Precise Finish Line Control**: 1px width line with exact mouse following for accurate measurement
- **Smart Angle Preservation**: Line dragging maintains angle while following mouse movement
- **Improved Export Alignment**: Fixed coordinate calculation between UI and exported images

### Fixed
- Photo finish overlay coordinates now properly align with exported images
- Pinch zoom responsiveness improved, especially when starting from 1x zoom
- Finish line dragging follows mouse pointer exactly while preserving set angles
- Pan gesture state tracking prevents position jumping when starting new drags

## [0.5.1] - 2025-01-26

### Added
- **Photo Finish Analysis Tools**: Enhanced video inspection for precise race timing
  - Angled finish line overlay with adjustable positioning for camera perspective
  - Draggable handles for precise finish line placement
  - Support for non-perpendicular camera angles
  - "F" key toggle for finish line overlay
  - Integration with existing export system (⌘+E)

### Improved
- Optimized finish line proportions (80% of video frame height with 10% margins)
- Removed unnecessary UI overlays for cleaner interface
- Enhanced handle positioning for better usability
- Race time display integration with existing timing model

### Fixed
- Reserved keyword conflict in Swift code (`extension` variable renamed)
- Proper optional handling for race time conversion methods

## [0.5.0] - 2025-01-26

### Added
- **Video Zoom and Pan Controls**: Comprehensive zoom controls with vertical slider (1x-5x)
  - Visual tick marks and current zoom level display
  - Pan controls with directional arrows for navigating zoomed video
  - Touch gesture support (pinch-to-zoom, drag-to-pan)
  - Keyboard shortcuts (⌘++, ⌘+-, ⌘+0)
  - Continuous panning on button hold with time-based jump prevention
  - Zoom/pan reset functionality for detailed race analysis

### Fixed
- Pan button jumping when holding - prevented single click during long press operations

## [0.4.0] - 2025-01-26

### Added
- **Race Plan API Integration**: Complete platform connection with secure API access
  - Event selection dropdown with public events API
  - Secure API key storage using macOS Keychain
  - Race plan loading with event-based fetching
  - Single-race update API endpoint integration
  - Internal race data updates after submission
  - Auto-refresh of results table when race plans load
  - Event ID storage in session data

### Improved
- Enhanced error handling and user feedback for network operations
- Reactive UI updates and auto-refresh capabilities

## [0.3.0] - 2025-01-26

### Added
- **Comprehensive Keyboard Shortcuts System**
  - Race setup: ENTER to start race
  - During race: SPACE to record, ESC to stop
  - Video review: M for lane selection, arrow keys for navigation
  - Timeline navigation: ←/→ (±10ms), ⇧+←/→ (±1ms), ⌘+←/→ (±100ms)
  - Export: ⌘+E for current frame, ⌘+S to save session
  - Dynamic help display showing relevant shortcuts per race state

### Improved
- Updated help system with contextual keyboard shortcuts
- Enhanced user workflow efficiency with quick access controls

## [0.2.0] - 2025-01-26

### Added
- **Lane Status Management**: Complete DNS/DNF/DSQ support
  - Lane status tracking (Did Not Start, Did Not Finish, Disqualified)
  - Visual status indicators in results table and timeline
  - Status-based result filtering and display

### Improved
- Enhanced lane selection dialog filtering (non-empty lanes only)
- Improved timeline marker positioning and design
- Better visual distinction between different lane statuses

## [0.1.0] - 2025-01-26

### Added
- **Core Race Timing Features**
  - Video synchronization with race timing
  - Lane selection and finish time recording
  - Timeline visualization with precise time markers
  - Session data persistence and loading
- **Initial Release**: Basic TimeKeeper functionality
  - Camera selection and video recording
  - Basic video playback and review
  - Frame export capabilities
  - macOS native application with SwiftUI interface

### Features
- H.264 video recording from any connected camera
- AVPlayer-based video scrubbing and playback
- JPEG still frame export with zero-tolerance precision
- User-selectable output directory per session
- Developer-signed distribution for macOS 13 (Ventura)

---

## Project Information

**Target Platform**: macOS 13 (Ventura) and later
**Distribution**: Developer-signed (non–App Store)
**Video Format**: H.264 .mov (no audio)
**Export Format**: JPEG still frames via AVAssetImageGenerator
**UI Framework**: SwiftUI with minimal chrome design