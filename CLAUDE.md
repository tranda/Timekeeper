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