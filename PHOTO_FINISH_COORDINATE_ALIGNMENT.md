# Photo Finish Export Coordinate Alignment

## Current Status (2025-01-27)

### 🔧 UI Layout Changes Made
1. **Live camera preview**: Restored to original proportional sizing (90% width, 16:9 aspect ratio)
2. **Recorded video player**: Modified to use 90% height container with full width
3. **Green debug quad**: Updated to use `videoHeight - 10` positioning
4. **Export system**: Added `uiHeightScale` parameter (not yet implemented)

### ❌ Critical Issues - ALIGNMENT STILL BROKEN

**MAIN PROBLEM**: Coordinate mismatch between UI and exported image persists despite all attempts to fix it.

1. **UI vs Export Misalignment**:
   - Finish line handles appear in different positions in UI vs exported image
   - Green debug quad position differs significantly between UI and export
   - All coordinate transformations attempted so far have failed to resolve this

2. **Root Cause Analysis Needed**:
   - Complex nested layout with multiple geometry containers causing confusion
   - VideoPlayer aspect ratio behavior vs UI container sizing mismatch
   - Coordinate system transformations not properly accounting for all UI offsets

3. **Current State**:
   - **BROKEN** - UI overlay and exported image coordinates do not align
   - Multiple layout changes made but core issue remains unresolved
   - Export functionality works but coordinates are wrong

### 🔧 Next Steps to Complete

1. **Update Export System**:
   ```swift
   // In FrameExporter.swift - exportJPEGWithFinishLine method
   // Apply UI height scaling to coordinate transformation:

   // Current (line ~172-173):
   let lineTopX = Double(width) * topX
   let lineBottomX = Double(width) * bottomX

   // Needs to become:
   let effectiveHeight = Double(height) * uiHeightScale  // Account for 90% UI container
   let yOffset = (Double(height) - effectiveHeight) / 2  // Center the content
   let lineTopY = yOffset + (effectiveHeight * 0.1)     // 10% margin from top of effective area
   let lineBottomY = yOffset + (effectiveHeight * 0.9)  // 10% margin from bottom of effective area
   ```

2. **Update Export Call**:
   ```swift
   // In RaceTimelineView.swift - exportCurrentFrame method
   // Pass the UI scaling factor:

   exporter.exportFrameWithFinishLine(
       from: videoURL,
       at: videoTime,
       to: outputURL,
       topX: playerViewModel.finishLineTopX,
       bottomX: playerViewModel.finishLineBottomX,
       videoSize: videoSize,
       uiHeightScale: 0.9,  // <- Add this line
       zeroTolerance: true
   )
   ```

3. **Update Debug Quad Export**:
   ```swift
   // In FrameExporter.swift - update green quad positioning to match UI
   // Current (line ~198-199):
   context.fill(CGRect(x: 10, y: 10, width: 20, height: 20))

   // Should become:
   let debugQuadY = yOffset + (effectiveHeight - 30)  // 10px from bottom of effective area
   context.fill(CGRect(x: 10, y: debugQuadY, width: 20, height: 20))
   ```

### 📁 Key Files
- `/TimeKeeper/FrameExporter.swift` - Export system with coordinate transformation
- `/TimeKeeper/ContentView.swift` - UI layout with 90% height container
- `/TimeKeeper/RaceTimelineView.swift` - Export function caller

### 🎯 Goal
Perfect alignment between UI photo finish overlay and exported image coordinates, with green debug quad appearing in identical positions in both UI and exported image.

### 📝 Notes
- UI container uses 90% height (`geometry.size.height * 0.9`) with vertical centering
- Video content is positioned within this scaled container
- Export system currently uses full image dimensions without accounting for UI scaling
- All coordinate transformations need to account for the UI's 90% height constraint

## Testing
After implementing changes, verify:
1. Green debug quad appears in same position in UI and exported image
2. Finish line handles align correctly between UI and export
3. Photo finish overlay matches exactly between video review and exported photos