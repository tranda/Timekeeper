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

- **NEVER change the 1st digit** (major version) until explicitly instructed by the user
- **Increase 2nd digit** (minor version) for new features or significant improvements
- **Increase 3rd digit** (patch version) for bug fixes, small improvements, or routine updates

Format: `MAJOR.MINOR.PATCH` (e.g., 0.5.0)

Examples:
- Bug fix: 0.5.0 → 0.5.1
- New feature: 0.5.1 → 0.6.0
- Major rewrite: 0.6.0 → 1.0.0 (only when user explicitly requests major version increase)

Current version: 0.5.1