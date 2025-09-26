# Continue Tomorrow

## Current Issue to Fix

**Problem**: Local data update inconsistency when switching between races after submitting results.

**Details**:
- When results are submitted to server for Race A, the internal race data is updated correctly
- However, when user switches to Race B and then back to Race A, the results table may not reflect the previously submitted data
- This suggests the internal data update mechanism (`updateInternalRaceData`) may have issues with:
  1. Finding the correct race in the race plan array
  2. Properly updating the lane data structure
  3. Triggering UI refresh after internal data changes

**Current Implementation**:
- Results submission calls `updateInternalRaceData()` on success
- This method updates `availableRacePlan` with new lane times/statuses
- Race selection triggers `loadSelectedRaceData()` which imports lane data into timing model

**Suspected Issues**:
1. Race ID matching might not be working correctly in `updateInternalRaceData`
2. Lane data might not be persisting correctly in the updated race plan
3. UI refresh might not be triggered when switching back to an updated race

**Next Steps**:
1. Debug the `updateInternalRaceData` method - add logging to verify:
   - Race is found correctly by ID
   - Lane data is updated properly
   - Updated race plan is saved correctly
2. Test race switching scenario:
   - Submit results for Race A
   - Switch to Race B
   - Switch back to Race A
   - Verify results table shows submitted data
3. Consider adding explicit race plan refresh or cache invalidation

## Recent Completed Work

✅ Event selection dropdown with public events API
✅ Secure API key storage using Keychain
✅ Race plan loading with event-based fetching
✅ Single-race update API endpoint integration
✅ Internal race data updates after submission
✅ Auto-refresh of results table when race plans load
✅ Event ID storage in session data
✅ Build fixes and error handling

## Architecture Status

The app now has a complete race plan integration with:
- Event management and selection
- Race plan fetching and caching
- Result submission with internal data sync
- Reactive UI updates and auto-refresh

Main remaining issue is the data consistency when switching between races after updates.