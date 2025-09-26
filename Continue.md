# TimeKeeper Development Roadmap

## Current Status
TimeKeeper now has comprehensive lane status management with DNS/DNF/DSQ support, results table in the left panel, and clean timeline display showing only finished events with actual times.

## Development Roadmap

### Phase 1: User Experience Enhancement
1. **Implement keyboard shortcuts for faster race timing operations**
   - Quick lane selection shortcuts
   - Rapid status changes (DNS/DNF/DSQ)
   - Timeline navigation shortcuts
   - Fast marker placement
   - Export shortcuts

### Phase 2: Platform Connection Setup
2. **Review existing platform API endpoints and authentication methods**
   - Document available API endpoints
   - Understand authentication flow
   - Map data structures between TimeKeeper and platform

3. **Add network layer to TimeKeeper for API communication**
   - Create networking service classes
   - Implement authentication handling
   - Add error handling and retry logic
   - Set up configuration for different environments

4. **Implement race plan download from platform**
   - Download heat sheets and lane assignments
   - Import competitor information
   - Sync race schedules and event details
   - Handle race plan updates

5. **Add competitor database integration**
   - Store competitor names, times, rankings
   - Link timing data to competitor profiles
   - Handle competitor search and selection
   - Manage competitor photo/info display

### Phase 3: Real-time Integration
6. **Implement real-time results upload and synchronization**
   - Upload finish times as they're recorded
   - Sync status changes (DNS/DNF/DSQ) in real-time
   - Handle conflict resolution for concurrent updates
   - Implement offline mode with sync when reconnected

7. **Add multi-race event handling**
   - Support for heats, semifinals, finals structure
   - Automatic advancement based on times/positions
   - Heat progression rules and qualifying times
   - Session management for multi-day events

### Phase 4: Live Operations & Broadcasting
8. **Implement live results broadcasting to displays/websites**
   - Real-time results streaming
   - Integration with display systems
   - WebSocket connections for live updates
   - Mobile-friendly results viewing

9. **Add competition-wide leaderboards and standings display**
   - Overall competition rankings
   - Category/division leaderboards
   - Team scoring and standings
   - Historical performance tracking

10. **Implement automated heat progression and advancement rules**
    - Configurable advancement criteria
    - Automatic heat sheet generation for next rounds
    - Time standards and qualifying procedures
    - Seeding algorithms for elimination rounds

## Technical Architecture Notes
- Network layer should be built with URLSession and Combine for reactive programming
- Consider implementing Core Data for local competitor database caching
- Use WebSocket for real-time updates where needed
- Implement proper error handling and user feedback for network operations
- Consider offline-first approach with sync capabilities

## Integration Points
- Existing platform API (already built)
- Race timing data (current TimeKeeper format)
- Video synchronization (current implementation)
- Session data (JSON format, current implementation)

## Next Immediate Task
Start with **Phase 2: Platform Connection Setup** - Review existing platform API endpoints and authentication methods.