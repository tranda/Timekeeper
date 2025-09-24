# TimeKeeper

A macOS application for precision race timing with synchronized video recording, designed for rowing, sailing, and other water sports competitions.

## Features

### Race Timing
- **START/STOP Control**: Large, easy-to-use buttons for race control
- **Precise Timing**: Millisecond-accurate elapsed time display
- **Finish Recording**: Mark finish times for individual lanes/boats
- **Lane Assignment**: Popup dialog for assigning lanes to finish times

### Video Integration
- **Synchronized Recording**: Video recording automatically synced with race timing
- **Camera Support**: Works with built-in cameras, external cameras, and iPhone Continuity Camera
- **Vertical Video Optimized**: UI optimized for portrait orientation (9:16 aspect ratio)
- **Live Preview**: Always-visible camera preview during recording and playback

### Video Review
- **Race Timeline**: Visual timeline showing race duration and video availability
- **Frame-Accurate Scrubbing**: Precise video navigation synchronized with race time
- **Finish Markers**: Visual markers on timeline for all recorded finishes
- **Dual Display**: Live camera preview and recorded video shown simultaneously

### Data Export
- **JSON Session Files**: Race data exported in structured JSON format
- **Frame Export**: Export individual frames as JPEG images
- **Database Ready**: Structured data format for easy database integration

## Requirements

- macOS 13.0 or later
- Camera access permission
- File system access for video storage

## Installation

1. Clone the repository
2. Open `TimeKeeper.xcodeproj` in Xcode
3. Build and run the project

## Usage

1. **Setup**:
   - Select camera from dropdown menu
   - Choose output folder for recordings

2. **During Race**:
   - Click START to begin race timing
   - Video recording can be started automatically or manually
   - Click STOP to end the race

3. **Review**:
   - Use timeline to scrub through race video
   - Click "Add Finish Here" to mark finish times
   - Assign lanes to each finish time

4. **Export**:
   - Session data automatically saved as JSON
   - Use "Export Frame" to save specific moments

## Technical Details

- Built with SwiftUI for macOS
- AVFoundation for video capture and playback
- Responsive design adapts to window size
- H.264 video encoding without audio

## File Structure

- `TimeKeeperApp.swift` - Main application entry point
- `ContentView.swift` - Main UI layout and coordination
- `RaceTimingModel.swift` - Race timing logic and data management
- `RaceTimingPanel.swift` - Race control UI components
- `RaceTimelineView.swift` - Timeline visualization and controls
- `CaptureManager.swift` - Video capture handling
- `PlayerViewModel.swift` - Video playback control
- `VideoPreviewView.swift` - Live camera preview
- `FrameExporter.swift` - Frame extraction utilities

## License

[Add your license here]

## Author

Zoran Trandafilovic