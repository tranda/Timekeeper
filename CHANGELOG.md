# Changelog

All notable changes to TimeKeeper will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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