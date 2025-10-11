# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Status

A minimal time-keeping utility for recording from any connected camera (incl. iPhone via Continuity Camera), scrubbing the resulting clip, and exporting an exact still frame (JPEG) at the finish line.

Target: macOS 13 (Ventura)

Distribution: developer-signed (non–App Store)

Capture: H.264 .mov by default, no audio

Playback: AVPlayer for scrubbing

Export: JPEG still via AVAssetImageGenerator (supports zero-tolerance precise extraction)

UI: minimal SwiftUI chrome; device picker, record/stop, scrubber, export button

Storage: user-choosable output directory per session (fallback: temp)

## Versioning Instructions

**IMPORTANT**: Follow this versioning scheme strictly:

When user says:
- **"increase version"** → increase 3rd digit (patch version)
- **"increase minor version"** → increase 2nd digit, set 3rd digit to 0
- **"increase major version"** → increase 1st digit, set 2nd and 3rd digits to 0
- **When any digit reaches 9**: continue with 10, 11, 12... (no limit)

Format: `MAJOR.MINOR.PATCH` (e.g., 0.5.0)

Examples:
- "increase version": 0.7.0 → 0.7.1
- "increase minor version": 0.7.5 → 0.8.0
- "increase major version": 0.9.3 → 1.0.0
- Beyond 9: 0.5.9 → 0.5.10 → 0.5.11...

Current version: 0.7.4

## Deployment Instructions

**IMPORTANT**: When user says **"deploy"**, perform these steps:

1. **Build Release version**:
   ```bash
   xcodebuild -project TimeKeeper.xcodeproj -scheme TimeKeeper -configuration Release clean build
   ```

2. **Deploy to Desktop** (replace old version if exists):
   ```bash
   rm -rf ~/Desktop/TimeKeeper.app
   cp -R /Users/zorantrandafilovic/Library/Developer/Xcode/DerivedData/TimeKeeper-dggblasvfdpwjuazmiprpyuzepwz/Build/Products/Release/TimeKeeper.app ~/Desktop/TimeKeeper.app
   ```

3. **Confirm deployment**: Inform user that TimeKeeper.app has been deployed to Desktop

**Note**: "deploy" means build Release configuration and place on Desktop, replacing any existing version