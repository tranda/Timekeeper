# TimeKeeper Roadmap

## Current Status
TimeKeeper is a functional race timing application with comprehensive keyboard shortcuts and video review capabilities. The core workflow (setup → timing → video review → marker placement → export) is complete and working well.

## Potential Next Steps

### Core Functionality Enhancements
- **Multi-camera support** - Record from multiple angles simultaneously
- **Audio integration** - Optional audio recording for start gun detection
- **Batch export** - Export all finish markers as images in one operation
- **CSV/Excel export** - Export timing results for external analysis

### User Experience Improvements
- **Session templates** - Save/load race configurations (lane names, settings)
- **Undo/redo system** - For marker placement corrections
- **Zoom controls** - Better video inspection at finish line
- **Playback speed controls** - Slow motion review capability

### Professional Features
- **Split timing** - Multiple checkpoints during races
- **False start detection** - Visual/audio cues for race officials
- **Photo finish overlay** - Grid lines and measurement tools
- **Backup/restore** - Automatic session backup and recovery

### Distribution & Polish
- **App Store preparation** - If considering broader distribution
- **Performance optimization** - For longer races and larger video files
- **Accessibility features** - VoiceOver support, larger text options
- **Localization** - Multi-language support

### Technical Debt
- **Unit tests** - Core timing logic validation
- **Error handling** - More robust camera/storage failure recovery
- **Memory optimization** - Better handling of large video files

## Priority Considerations
Items should be prioritized based on:
1. **User pain points** encountered during actual race timing
2. **Frequency of use** in typical racing scenarios
3. **Implementation complexity** vs. impact
4. **Distribution goals** (personal use vs. broader release)

## Recent Completion
- ✅ Comprehensive keyboard shortcuts system
- ✅ Context-aware UI behavior
- ✅ Help system and documentation
- ✅ Timeline navigation with precision controls
- ✅ Lane status management (DNS/DNF/DSQ)