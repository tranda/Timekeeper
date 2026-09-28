import SwiftUI

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundColor(configuration.isOn ? .blue : .secondary)
                .onTapGesture {
                    configuration.isOn.toggle()
                }

            configuration.label
        }
    }
}
import Combine
import AppKit
import AVFoundation

struct RaceTimingPanel: View {
    @ObservedObject var timingModel: RaceTimingModel
    @ObservedObject var captureManager: CaptureManager
    @ObservedObject var playerViewModel: PlayerViewModel
    @Binding var isReviewMode: Bool
    @Binding var isViewOnly: Bool
    @Binding var onTimelineDataChanged: () -> Void
    @Binding var stopRaceAction: () -> Void
    @StateObject private var racePlanService = RacePlanService.shared
    @State private var showLaneInput = false
    @State private var selectedLane = "1"
    @State private var manualTimeEntry: Double?
    @State private var showOverwriteConfirmation = false
    @State private var laneToOverwrite: String? = nil
    @State private var showNewRaceSheet = false
    @State private var newRaceName = ""
    @State private var newTeamNames = (1...AppConfig.shared.maxLanes).map { "Lane \($0)" }
    @State private var showResultsAlert = false
    @State private var resultsAlertTitle = ""
    @State private var resultsAlertMessage = ""
    @State private var resultsAlertIsSuccess = false
    @State private var showRefreshConfirm = false
    @State private var showResetConfirm = false
    @State private var showRerunConfirm = false
    @State private var newRaceIsLongDistance = false
    @State private var laneStartToOverwrite: String? = nil
    @State private var startIntervalRevision = 0  // bumps when the per-event start interval is edited
    // Set by REFRESH: the local session whose timing/video data should survive
    // the reload from server (consumed by the next loadSelectedRaceData()).
    @State private var pendingRefreshSnapshot: SessionData? = nil

    // Manual timing setup for sessions without wallclock data
    @State private var manualRaceDuration = ""
    @State private var manualTimingError: String?
    @State private var manualVideoStart = ""

    // Save/confirmation system for race changes
    @State private var showSaveConfirmation = false
    @State private var pendingRaceChange: String? = nil
    @State private var hasUnsavedChanges = false
    @State private var pendingNewRace = false
    @State private var pendingEventId: Int? = nil

    // Free Races management
    @State private var availableFreeRaces: [String] = []  // List of race names from saved JSON files
    @State private var selectedFreeRaceName: String = ""

    var body: some View {
        VStack(spacing: 12) {
            // New Race button at the top (visible but disabled during race or when event has race plan)
            Button(action: {
                print("🔵 NEW RACE clicked - hasUnsavedChanges = \(hasUnsavedChanges)")
                // Check for unsaved changes before starting new race
                if hasUnsavedChanges {
                    print("🔵 Showing confirmation dialog")
                    pendingNewRace = true
                    showSaveConfirmation = true
                } else {
                    print("🔵 No unsaved changes, opening new race sheet")
                    // No unsaved changes, proceed directly
                    openNewRaceSheet()
                }
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill((timingModel.isRaceActive || hasLoadedEventWithRacePlan) ? Color.blue.opacity(0.5) : Color.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    Text("NEW RACE")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(timingModel.isRaceActive || hasLoadedEventWithRacePlan)
            .padding(.horizontal)

            // Event Selection Section
            if !racePlanService.availableEvents.isEmpty {
                VStack(spacing: 4) {
                    HStack {
                        Text("Event:")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)

                        Picker("", selection: Binding(
                            get: { racePlanService.selectedEvent?.id ?? -1 },
                            set: { eventId in
                                // Check for unsaved changes before switching events
                                if hasUnsavedChanges {
                                    // Show confirmation dialog and store pending event ID
                                    pendingEventId = eventId
                                    showSaveConfirmation = true
                                } else {
                                    // No unsaved changes, switch event directly
                                    if eventId == -1 {
                                        // Free Races mode - clear race plans and reset race data
                                        racePlanService.clearRacePlans()
                                        racePlanService.selectedEvent = nil
                                        timingModel.resetRace()
                                        // Scan for available free races
                                        scanForFreeRaces()
                                    } else if let event = racePlanService.availableEvents.first(where: { $0.id == eventId }) {
                                        racePlanService.selectEvent(event)
                                        // Reset race data when switching to an event
                                        timingModel.resetRace()
                                        // Auto-load race plans for the new event
                                        if racePlanService.hasAPIKey() {
                                            racePlanService.fetchRacePlans()
                                        }
                                    }
                                }
                            }
                        )) {
                            // Free Races option at the top
                            Text("Free Races")
                                .font(.system(size: 18, weight: .bold))
                                .tag(-1)

                            Divider()

                            ForEach(racePlanService.availableEvents) { event in
                                Text("\(event.name) \(String(event.year)) - \(event.location)")
                                    .tag(event.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.system(size: 18, weight: .bold))
                        .disabled(timingModel.isRaceActive)

                        Spacer()
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            // Free Races Control Section (show when in Free Races mode)
            // Also shown when no free race has been saved to disk yet but one is
            // running/recorded in memory — otherwise the very first free race has
            // no REVIEW / LOAD VIDEO / SAVE affordance at all (only the ⌘S shortcut),
            // and the recording can't be saved without discovering that shortcut.
            if racePlanService.selectedEvent == nil && (timingModel.isRaceInitialized || !availableFreeRaces.isEmpty) {
                VStack(spacing: 4) {
                    HStack {
                        // Nothing saved yet -> nothing to pick from; the buttons below still apply.
                        if !availableFreeRaces.isEmpty {
                        Text("Race:")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)

                        Picker("", selection: $selectedFreeRaceName) {
                            ForEach(availableFreeRaces, id: \.self) { raceName in
                                Text(raceName)
                                    .font(.system(size: 16, weight: .medium))
                                    .tag(raceName)
                            }
                        }
                        .frame(width: 400)
                        .disabled(timingModel.isRaceActive)
                        .onChange(of: selectedFreeRaceName) { newRaceName in
                            if !newRaceName.isEmpty && newRaceName != timingModel.sessionData?.raceName {
                                // Check for unsaved changes before switching
                                if hasUnsavedChanges {
                                    pendingRaceChange = newRaceName
                                    showSaveConfirmation = true
                                } else {
                                    loadFreeRace(raceName: newRaceName)
                                }
                            }
                        }
                        }

                        // Only show Review/Save buttons if a race is actually initialized
                        if timingModel.isRaceInitialized {
                        reviewModeButtons

                        if isReviewMode && !isViewOnly {
                            Button(action: {
                                showVideoFileSelector()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder.badge.plus")
                                        .font(.caption)
                                    Text("LOAD VIDEO")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(height: 35)
                                .padding(.horizontal, 12)
                                .background(Color.blue)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .help("Load a video file from disk for review")
                        }
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal)

                // Prominent Save Button for Free Races (only show if race is initialized)
                if timingModel.isRaceInitialized {
                Button(action: {
                    saveCurrentRaceData()
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(hasUnsavedChanges ? Color.orange : Color.green)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .shadow(color: hasUnsavedChanges ? Color.orange.opacity(0.3) : Color.green.opacity(0.3), radius: 4, x: 0, y: 2)

                        HStack(spacing: 8) {
                            Image(systemName: hasUnsavedChanges ? "externaldrive.badge.plus" : "externaldrive.badge.checkmark")
                                .font(.title2)
                            Text("SAVE")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .help(hasUnsavedChanges ? "Save current race data (unsaved changes detected)" : "All changes saved")
                .scaleEffect(hasUnsavedChanges ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: hasUnsavedChanges)
                .padding(.horizontal)
                .padding(.vertical, 6)
                }
            }

            // Race Plan Selection Section (only show if race plan is available)
            if let racePlan = racePlanService.availableRacePlan, !racePlan.races.isEmpty {
                VStack(spacing: 4) {
                    // Race Selection
                    HStack {
                        Text("Race:")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)

                        Picker("", selection: Binding(
                            get: { racePlanService.selectedRace?.id ?? 0 },
                            set: { raceId in
                                if let race = racePlan.races.first(where: { $0.id == raceId }) {
                                    racePlanService.selectRace(race)
                                    // Auto-load race when selected
                                    if !timingModel.isRaceActive {
                                        loadSelectedRaceData()
                                    }
                                }
                            }
                        )) {
                            Text("Select Race")
                                .font(.system(size: 16, weight: .medium))
                                .tag(0)
                            ForEach(racePlan.races) { race in
                                Text(raceDropdownLabel(for: race))
                                    .font(.system(size: 16, weight: .medium))
                                    .tag(race.id)
                            }
                        }
                        .frame(width: 400)
                        .disabled(timingModel.isRaceActive)

                        reviewModeButtons

                        Button(action: {
                            showRefreshConfirm = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .bold))
                                Text("REFRESH")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(height: 35)
                            .padding(.horizontal, 10)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(timingModel.isRaceActive)
                        .help("Reload lanes and results from the server, keeping this race's timing sync, video and finish line")

                        Button(action: {
                            showResetConfirm = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .bold))
                                Text("RESET")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(height: 35)
                            .padding(.horizontal, 10)
                            .background(Color.red)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(timingModel.isRaceActive)
                        .help("Move this race's saved session to the Trash and start over from server data")

                        if isReviewMode && !isViewOnly {
                            Button(action: {
                                showVideoFileSelector()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder.badge.plus")
                                        .font(.caption)
                                    Text("LOAD VIDEO")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(height: 35)
                                .padding(.horizontal, 12)
                                .background(Color.blue)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .help("Load a video file from disk for review")
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal)

                // Prominent Save Button
                Button(action: {
                    saveCurrentRaceData()
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(hasUnsavedChanges ? Color.orange : Color.green)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .shadow(color: hasUnsavedChanges ? Color.orange.opacity(0.3) : Color.green.opacity(0.3), radius: 4, x: 0, y: 2)

                        HStack(spacing: 8) {
                            Image(systemName: hasUnsavedChanges ? "externaldrive.badge.plus" : "externaldrive.badge.checkmark")
                                .font(.title2)
                            Text("SAVE")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .help(hasUnsavedChanges ? "Save current race data (unsaved changes detected)" : "All changes saved")
                .scaleEffect(hasUnsavedChanges ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: hasUnsavedChanges)
                .padding(.horizontal)
                .padding(.vertical, 6)

                if let errorMessage = racePlanService.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
            }

            // Main controls in horizontal layout
            HStack(alignment: .top, spacing: 20) {
                // START/STOP Section
                VStack(spacing: 8) {
                    if !timingModel.isRaceActive {
                        Button(action: handleStartPress) {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 100, height: 100)

                                Text("START")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!timingModel.isRaceInitialized || (timingModel.raceStartTime != nil && !timingModel.isRaceActive) || isReviewMode)
                        .opacity((timingModel.isRaceInitialized && (timingModel.raceStartTime == nil || timingModel.isRaceActive) && !isReviewMode) ? 1.0 : 0.5)
                    } else {
                        Button(action: handleStopPress) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 100, height: 100)

                                Text("STOP")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isReviewMode)
                        .opacity(isReviewMode ? 0.5 : 1.0)
                    }

                    Text(timingModel.formattedElapsedTime)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .frame(minWidth: 120)

                    if canRerunRace {
                        Button(action: { showRerunConfirm = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 12, weight: .bold))
                                Text("RE-RUN")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(height: 30)
                            .padding(.horizontal, 12)
                            .background(Color.purple)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .help("Run and record this race again (previous run's session goes to the Trash)")
                    }

                    if timingModel.isRaceActive {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 12, height: 12)
                            Text("RACE ACTIVE")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.green)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // Center Hint Section
                centeredActionHint
                    .frame(maxWidth: .infinity)

                // VIDEO RECORDING Section
                VStack(spacing: 8) {
                    Button(action: handleRecordPress) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(captureManager.isRecording ? Color.red : Color.green)
                                .frame(width: 100, height: 100)

                            VStack {
                                Image(systemName: captureManager.isRecording ? "stop.circle" : "video.circle")
                                    .font(.system(size: 30))
                                Text(captureManager.isRecording ? "STOP" : "RECORD")
                                    .font(.system(size: 14, weight: .bold))
                                Text("VIDEO")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(captureManager.selectedDevice == nil || (!timingModel.isRaceInitialized || (timingModel.raceStartTime != nil && !timingModel.isRaceActive)) || isReviewMode)
                    .opacity((captureManager.selectedDevice != nil && timingModel.isRaceInitialized && (timingModel.raceStartTime == nil || timingModel.isRaceActive) && !isReviewMode) ? 1.0 : 0.5)

                    HStack {
                        if captureManager.isRecording {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                            Text("REC")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red)
                        } else {
                            Text("NOT REC")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    if timingModel.finishEvents.count > 0 {
                        Text("\(timingModel.finishEvents.count) finishes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if timingModel.isLongDistance && timingModel.isRaceInitialized && !isReviewMode {
                laneStartsSection
            }

            Divider()

            // Manual Timing Setup for sessions without wallclock data
            if shouldShowManualTimingSetup && !isViewOnly {
                manualTimingSetupSection
                Divider()
            }


            // Race Results Table
            VStack(alignment: .leading, spacing: 6) {
                // Race plan details — shown when an API-loaded race is selected
                if let race = racePlanService.selectedRace {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Race \(race.raceNumber) — \(race.disciplineInfo)")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        HStack(spacing: 6) {
                            if !race.stage.isEmpty {
                                Text(race.stage)
                            }
                            if !race.boatSize.isEmpty {
                                Text("•")
                                Text(race.boatSize)
                            }
                            if let competition = race.competition, !competition.isEmpty {
                                Text("•")
                                Text(competition)
                                    .fontWeight(.medium)
                            }
                            if !race.raceTime.isEmpty {
                                Text("•")
                                Text(race.raceTime)
                            }
                            if !race.status.isEmpty {
                                Text("•")
                                Text(race.status)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(6)
                }

                HStack {
                    Text("Race Results")
                        .font(.headline)

                    if timingModel.isLongDistance {
                        Text("LONG DISTANCE · staggered start")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.teal)
                            .cornerRadius(4)
                    }

                    if isReviewMode && isViewOnly {
                        Text("(VIEW ONLY - press EDIT to change)")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                    } else if isReviewMode {
                        Text("(REVIEW MODE - Times Editable)")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .fontWeight(.medium)
                    }

                    Spacer()
                }

                if timingModel.isRaceInitialized {
                    // Table Header
                    HStack(spacing: 0) {
                        Text("Lane")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(width: 50, alignment: .leading)

                        Text("Team")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(width: 120, alignment: .leading)

                        if timingModel.isLongDistance {
                            Text("Start")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(width: 100, alignment: .leading)
                        }

                        Text("Time")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(width: 100, alignment: .leading)

                        Text("Status")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(width: 120, alignment: .leading)

                        Text("Pos")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(width: 40, alignment: .leading)

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.gray.opacity(0.1))

                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(timingModel.sessionData?.teamNames.enumerated() ?? [].enumerated()), id: \.offset) { index, teamName in
                                raceResultRow(index: index, teamName: teamName)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .background(Color.gray.opacity(0.02))
                    .cornerRadius(5)
                } else {
                    Text("Click 'New Race' to initialize")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }
            }
            .frame(maxWidth: .infinity)

            // Bottom section with images and send button - scrollable if needed
            VStack(spacing: 8) {
                // Exported Images Selection
                if timingModel.isRaceInitialized && !(timingModel.sessionData?.exportedImages.isEmpty ?? true) {
                    exportedImagesSection
                        .disabled(isViewOnly)
                }

                // Send Results button (only show if race is initialized and has an event)
                if timingModel.isRaceInitialized && racePlanService.selectedEvent != nil {
                    Button(action: sendRaceResults) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.green)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                            Text("SEND RESULTS")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isViewOnly)
                    .opacity(isViewOnly ? 0.5 : 1.0)
                    .help(isViewOnly ? "Press EDIT to send results" : "Send results to the server")
                    .padding(.horizontal)
                }
            }

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .sheet(isPresented: $showLaneInput) {
            VStack(spacing: 20) {
                Text("Enter Lane/Boat")
                    .font(.headline)

                VStack(spacing: 8) {
                    ForEach(Array(timingModel.sessionData?.teamNames.enumerated() ?? [].enumerated()), id: \.offset) { index, name in
                        Button(action: {
                            selectedLane = String(index + 1)
                        }) {
                            HStack {
                                Text("Lane \(index + 1):")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                Text(name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if selectedLane == String(index + 1) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedLane == String(index + 1) ? Color.accentColor.opacity(0.1) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 250)

                HStack {
                    Button("Cancel") {
                        showLaneInput = false
                        manualTimeEntry = nil
                    }
                    .keyboardShortcut(.escape)

                    Button("Save Marker") {
                        if let manualTime = manualTimeEntry {
                            let laneIndex = Int(selectedLane) ?? 1
                            let laneName = timingModel.sessionData?.teamNames[safe: laneIndex - 1] ?? "Lane \(selectedLane)"
                            // Check if this lane already has a finish time
                            if timingModel.finishEvents.contains(where: { $0.label == laneName }) {
                                laneToOverwrite = laneName
                                showLaneInput = false  // Close the input sheet first
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    showOverwriteConfirmation = true  // Then show confirmation
                                }
                            } else {
                                // Recording from video scrubbing
                                let raceTime = timingModel.raceTimeForVideoTime(manualTime) ?? manualTime
                                timingModel.recordFinishAtTime(raceTime, lane: laneName)
                                showLaneInput = false
                                manualTimeEntry = nil
                            }
                        }
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(30)
            .frame(width: 400)
        }
        .alert("Overwrite Lane Time?", isPresented: $showOverwriteConfirmation) {
            Button("Cancel", role: .cancel) {
                laneToOverwrite = nil
            }
            Button("Overwrite", role: .destructive) {
                if let lane = laneToOverwrite, let manualTime = manualTimeEntry {
                    // Remove the existing finish event for this lane
                    timingModel.finishEvents.removeAll { $0.label == lane }
                    // Add the new finish time
                    let raceTime = timingModel.raceTimeForVideoTime(manualTime) ?? manualTime
                    timingModel.recordFinishAtTime(raceTime, lane: lane)
                    showLaneInput = false
                    manualTimeEntry = nil
                    laneToOverwrite = nil
                }
            }
        } message: {
            if let lane = laneToOverwrite {
                Text("\(lane) already has a recorded time. Do you want to overwrite it?")
            }
        }
        .alert(resultsAlertTitle, isPresented: $showResultsAlert) {
            Button("OK") { }
        } message: {
            Text(resultsAlertMessage)
        }
        .onReceive(timingModel.$lastSessionSave.dropFirst()) { _ in
            // Any successful save (SAVE button, Cmd+S, auto-save) clears the flag
            hasUnsavedChanges = false
        }
        .onReceive(racePlanService.$shouldRefreshRaceData) { shouldRefresh in
            if shouldRefresh && racePlanService.selectedRace != nil {
                // Check for unsaved changes before switching races
                checkForUnsavedChanges {
                    // Refresh the race data to show updated results from race plan
                    loadSelectedRaceData()
                    // Reset the trigger
                    racePlanService.shouldRefreshRaceData = false
                }

                // If we showed a confirmation dialog, reset the trigger will happen in confirmRaceChange()
                if !showSaveConfirmation {
                    racePlanService.shouldRefreshRaceData = false
                }
            }
        }
        .alert("Refresh from server?", isPresented: $showRefreshConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Refresh") { refreshCurrentRaceFromServer() }
        } message: {
            Text("Lanes, seeds and results for this race are replaced with the server's. Timing sync, video, finish line and exported photos are kept. Local times that haven't been sent will be replaced.")
        }
        .alert("Run this race again?", isPresented: $showRerunConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Re-run", role: .destructive) { rerunCurrentRace() }
        } message: {
            Text("The previous run's times and timing are cleared and its session file is moved to the Trash. Lanes, crews and the finish-line position are kept. Previous videos and photos stay in the race folder. Results already sent to the server stay there until you send the new ones.")
        }
        .alert("Reset this race?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) { resetCurrentRaceFromServer() }
        } message: {
            Text("This race's saved session (times, timing sync, finish line, photo list) is moved to the Trash and the race is reloaded from the server. The video and photo files stay in the race folder.")
        }
        .sheet(isPresented: $showNewRaceSheet) {
            VStack(spacing: 20) {
                Text("Setup New Race")
                    .font(.title2)
                    .bold()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Race Name:")
                        .font(.headline)
                    TextField("Enter race name", text: $newRaceName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Team/Lane Names:")
                        .font(.headline)

                    VStack(spacing: 8) {
                        ForEach(0..<min(AppConfig.shared.maxLanes, newTeamNames.count), id: \.self) { index in
                            HStack {
                                Text("Lane \(index + 1):")
                                    .frame(width: 60, alignment: .trailing)
                                TextField("Lane \(index + 1)", text: $newTeamNames[index])
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 200)
                            }
                        }
                    }
                }

                Toggle("Long distance (staggered start)", isOn: $newRaceIsLongDistance)
                    .help("Boats start one by one; each lane gets its own start time and its result is finish − start")

                HStack(spacing: 20) {
                    Button("Cancel") {
                        showNewRaceSheet = false
                    }
                    .keyboardShortcut(.escape)

                    Button("Start New Race") {
                        // Exit review mode when starting a new race
                        isReviewMode = false

                        timingModel.initializeNewRace(name: newRaceName, teamNames: newTeamNames, eventId: racePlanService.selectedEvent?.id, isLongDistance: newRaceIsLongDistance)
                        // Clear the recorded video and reset capture manager state
                        captureManager.lastRecordedURL = nil
                        captureManager.videoStartTime = nil
                        captureManager.videoStopTime = nil
                        playerViewModel.player.replaceCurrentItem(with: nil)
                        playerViewModel.isSeekingOutsideVideo = false
                        showNewRaceSheet = false
                        print("🟢 Resetting hasUnsavedChanges to false after starting new race")
                        hasUnsavedChanges = false  // Reset unsaved changes after new race

                        // If in Free Races mode, update the list
                        if racePlanService.selectedEvent == nil {
                            scanForFreeRaces()
                            selectedFreeRaceName = newRaceName
                        }
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(40)
            .frame(width: 450)
        }
        .alert("Unsaved Changes", isPresented: $showSaveConfirmation) {
            Button("Save and Switch") {
                saveCurrentRaceData()
                confirmRaceChange()
            }
            .keyboardShortcut(.return)

            Button("Discard and Switch") {
                confirmRaceChange()
            }
            .keyboardShortcut(.escape)

            Button("Cancel") {
                pendingRaceChange = nil
                pendingNewRace = false
                pendingEventId = nil
            }
        } message: {
            Text("You have unsaved changes to the current race. What would you like to do?")
        }
        .onAppear {
            // Set up the callback for timeline data changes
            onTimelineDataChanged = markAsUnsaved
            // ESC (handled in ContentView) stops the race through the same path
            stopRaceAction = handleStopPress

            // Auto-initialize on first appear
            if racePlanService.selectedEvent == nil {
                // In Free Races mode - scan and auto-load first race
                scanForFreeRaces()

                // Auto-load the first free race if available
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // Only auto-load if still in Free Races mode and no race initialized
                    if self.racePlanService.selectedEvent == nil,
                       !self.availableFreeRaces.isEmpty,
                       let firstRace = self.availableFreeRaces.first,
                       !self.timingModel.isRaceInitialized {
                        print("🚀 Auto-loading first free race: \(firstRace)")
                        self.loadFreeRace(raceName: firstRace)
                    }
                }
            } else if let selectedEvent = racePlanService.selectedEvent {
                // In Event mode - fetch race plans if we have an API key
                if racePlanService.hasAPIKey() {
                    print("🚀 Auto-fetching race plans for selected event: \(selectedEvent.name)")
                    racePlanService.fetchRacePlans()
                }
            }
        }
    }

    // MARK: - Computed Properties

    // Check if we have a loaded event with race plan (races are predefined)
    private var hasLoadedEventWithRacePlan: Bool {
        return racePlanService.selectedEvent != nil &&
               racePlanService.availableRacePlan != nil &&
               !(racePlanService.availableRacePlan?.races.isEmpty ?? true)
    }

    // MARK: - Centered Action Hint

    @ViewBuilder
    private var centeredActionHint: some View {
        let hintData = getCenteredHint()

        VStack(spacing: 8) {
            // Icon
            Image(systemName: hintData.icon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(hintData.color)

            // Message
            VStack(spacing: 4) {
                Text(hintData.primaryMessage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(hintData.color)
                    .multilineTextAlignment(.center)

                if let secondaryMessage = hintData.secondaryMessage {
                    Text(secondaryMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let tertiaryMessage = hintData.tertiaryMessage {
                    Text(tertiaryMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: 160)
        .padding(.vertical, 10)
        .transition(.opacity.combined(with: .scale))
        .animation(.easeInOut(duration: 0.3), value: hintData.primaryMessage)
    }

    private func getCenteredHint() -> (primaryMessage: String, secondaryMessage: String?, tertiaryMessage: String?, icon: String, color: Color) {
        // Review mode
        if isReviewMode && isViewOnly {
            return ("VIEW ONLY", "EDIT to change", nil, "eye.fill", Color.blue)
        }
        if isReviewMode {
            return ("REVIEW MODE", "M to mark", nil, "film.fill", Color.purple)
        }

        // Race completed (not active, has started)
        if !timingModel.isRaceActive && timingModel.raceStartTime != nil {
            return ("RACE COMPLETE", "Review mode", nil, "checkmark.circle.fill", Color.green)
        }

        // Race active
        if timingModel.isRaceActive {
            if timingModel.isLongDistance, let next = nextStartCountdown {
                let when = next.remaining > 0 ? "in \(formatCountdown(next.remaining))" : "due now"
                return ("PRESS \(next.lane)", "start \(next.team) \(when)", "⎋ ESC — stop race", "flag.fill", next.remaining > 0 ? Color.green : Color.orange)
            }
            if captureManager.isRecording {
                return ("⎵ SPACE", "stop recording", "⎋ ESC — stop race", "record.circle.fill", Color.red)
            } else {
                return ("⎵ SPACE", "record video", "⎋ ESC — stop race", "video.badge.plus", Color.orange)
            }
        }

        // Race initialized but not started
        if timingModel.isRaceInitialized && timingModel.raceStartTime == nil {
            return ("⏎ ENTER", "start race", nil, "play.circle.fill", Color.blue)
        }

        // No race initialized
        return ("Click NEW RACE", "to begin", nil, "flag.checkered", Color.gray)
    }

    @ViewBuilder
    private func raceResultRow(index: Int, teamName: String) -> some View {
        let laneNumber = index + 1
        let finishEvent = timingModel.finishEvents.first { $0.label == teamName }
        let position = finishEvent != nil ? calculatePosition(for: finishEvent!, in: timingModel.finishEvents) : nil

        HStack(spacing: 0) {
            Text("\(laneNumber)")
                .font(.system(size: 14))
                .frame(width: 50, alignment: .leading)

            Text(teamName)
                .font(.system(size: 14))
                .frame(width: 120, alignment: .leading)

            if timingModel.isLongDistance {
                laneStartCell(teamName: teamName)
            }

            Group {
                // Time column shows the crew's own (net) time; finish markers are
                // stored on the race clock, so add the boat's start offset back.
                let startOffset = timingModel.laneStartOffset(for: teamName) ?? 0
                if isReviewMode && !isViewOnly {
                    EditableTimeField(
                        time: finishEvent.map { timingModel.netTime(for: $0) },
                        onTimeChange: { newTime in
                            if let event = finishEvent {
                                updateFinishEventTime(event: event, newTime: newTime + startOffset)
                            } else {
                                // Create a new finish event for this lane
                                createFinishEventForLane(teamName: teamName, time: newTime + startOffset)
                            }
                        }
                    )
                    .frame(width: 100, alignment: .leading)
                } else {
                    // In live mode, show read-only time display
                    if let event = finishEvent, event.status == .finished {
                        Text(formatRaceTime(timingModel.netTime(for: event)))
                            .font(.system(size: 14, design: .monospaced))
                            .frame(width: 100, alignment: .leading)
                    } else {
                        Text("--:--")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .leading)
                    }
                }
            }

            statusMenu(for: teamName, finishEvent: finishEvent)
                .disabled(isViewOnly)

            positionText(for: finishEvent, position: position)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(index % 2 == 0 ? Color.clear : Color.gray.opacity(0.05))
    }

    @ViewBuilder
    private func statusMenu(for teamName: String, finishEvent: FinishEvent?) -> some View {
        // No team assigned to this lane → don't show a status (and don't pretend a
        // non-existent crew is "Registered"). Render a dash placeholder instead.
        if teamName.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("—")
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
        } else {
        Menu {
            Button("Registered") {
                timingModel.recordLaneStatus(teamName, status: .registered)
                markAsUnsaved()
            }

            Button("Finished") {
                // Do nothing - times are set via timeline
            }
            .disabled(true)

            Divider()

            Button("DNS - Did Not Start") {
                timingModel.recordLaneStatus(teamName, status: .dns)
                markAsUnsaved()
            }

            Button("DNF - Did Not Finish") {
                timingModel.recordLaneStatus(teamName, status: .dnf)
                markAsUnsaved()
            }

            Button("DSQ - Disqualified") {
                timingModel.recordLaneStatus(teamName, status: .dsq)
                markAsUnsaved()
            }

            Divider()

            Button("Clear") {
                timingModel.finishEvents.removeAll { $0.label == teamName }
                timingModel.sessionData?.finishEvents.removeAll { $0.label == teamName }
                markAsUnsaved()
            }
        } label: {
            HStack(spacing: 4) {
                if let event = finishEvent {
                    Text(event.status.rawValue)
                        .foregroundColor(textColorForStatus(event.status))
                } else {
                    Text("Registered")
                        .foregroundColor(textColorForStatus(.registered))
                }
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .frame(width: 110, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 120, alignment: .leading)
        }
    }

    @ViewBuilder
    private func positionText(for finishEvent: FinishEvent?, position: Int?) -> some View {
        if let event = finishEvent, event.status == .finished {
            Text(position != nil ? "\(position!)" : "-")
                .font(.system(size: 14))
                .fontWeight(position == 1 ? .bold : .regular)
                .foregroundColor(position == 1 ? .yellow : .primary)
                .frame(width: 40, alignment: .leading)
        } else {
            Text("-")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)
        }
    }

    private func updateFinishEventTime(event: FinishEvent, newTime: Double) {
        // Update the finish event with new time and set status to finished
        print("🔄 Attempting to update finish event for \(event.label): \(event.tRace) -> \(newTime)")

        if let index = timingModel.finishEvents.firstIndex(where: { $0.id == event.id }) {
            let oldTime = timingModel.finishEvents[index].tRace
            let oldStatus = timingModel.finishEvents[index].status

            timingModel.finishEvents[index].tRace = newTime
            timingModel.finishEvents[index].status = .finished

            // Also update session data
            if let sessionIndex = timingModel.sessionData?.finishEvents.firstIndex(where: { $0.id == event.id }) {
                timingModel.sessionData?.finishEvents[sessionIndex].tRace = newTime
                timingModel.sessionData?.finishEvents[sessionIndex].status = .finished
                print("📝 Updated existing finish event for \(event.label): time \(oldTime) -> \(newTime), status \(oldStatus) -> finished")
            } else {
                print("⚠️ Could not find event in session data to update")
            }

            // Log all current times after update
            print("📊 ALL CURRENT TIMES AFTER UPDATE:")
            for (i, finishEvent) in timingModel.finishEvents.enumerated() {
                let rounded = round(finishEvent.tRace * 1000) / 1000
                print("   \(i+1). \(finishEvent.label): \(finishEvent.tRace) (rounded: \(rounded)) - \(finishEvent.status.rawValue)")
            }

            // Mark as unsaved
            markAsUnsaved()
        } else {
            print("⚠️ Could not find finish event with ID \(event.id) to update")
        }
    }

    private func createFinishEventForLane(teamName: String, time: Double) {
        // Remove any existing status-only entry for this lane first
        timingModel.finishEvents.removeAll { $0.label == teamName }
        timingModel.sessionData?.finishEvents.removeAll { $0.label == teamName }

        // Create a new finish event for this lane
        print("🆕 Creating new finish event for \(teamName) with time \(time)")
        timingModel.recordFinishAtTime(time, lane: teamName, videoTime: nil, status: .finished)

        // Log all current times after creation
        print("📊 ALL CURRENT TIMES AFTER CREATION:")
        for (i, finishEvent) in timingModel.finishEvents.enumerated() {
            let rounded = round(finishEvent.tRace * 1000) / 1000
            print("   \(i+1). \(finishEvent.label): \(finishEvent.tRace) (rounded: \(rounded)) - \(finishEvent.status.rawValue)")
        }

        // Mark as unsaved
        markAsUnsaved()
    }

    /// LIVE/REVIEW toggle, plus EDIT while an existing race is open read-only.
    @ViewBuilder
    private var reviewModeButtons: some View {
        if isReviewMode && isViewOnly {
            Button(action: {
                isViewOnly = false
                print("✏️ EDIT pressed - editing unlocked")
            }) {
                Text("EDIT")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 80, height: 35)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .help("Unlock editing of times, markers, timing and finish line")
        }

        Button(action: {
            isReviewMode.toggle()
            isViewOnly = false

            // When entering review mode, load the video if available
            if isReviewMode {
                loadVideoForReview()
            }
        }) {
            Text(isReviewMode ? "LIVE" : "REVIEW")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 80, height: 35)
                .background(isReviewMode ? Color.orange : Color.green)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help(isReviewMode ? "Switch to live race mode" : "Switch to review mode for editing times")
    }

    /// An existing race (one with a recorded video) opens in review, read-only.
    private func openInViewModeIfRecorded() {
        guard captureManager.lastRecordedURL != nil, !timingModel.isRaceActive else { return }
        isReviewMode = true
        isViewOnly = true
        print("👁️ Opened existing race read-only (press EDIT to change)")
    }

    private func loadVideoForReview() {
        // First, check if we have a video file path in session data
        if let videoPath = timingModel.sessionData?.videoFilePath,
           FileManager.default.fileExists(atPath: videoPath) {

            loadVideoFromPath(videoPath)
            return
        }

        // If no stored path or file doesn't exist, try to find video automatically by race name
        if let raceName = timingModel.sessionData?.raceName {
            if let autoFoundVideo = findLatestVideoForRace(raceName: raceName) {
                print("🔍 Auto-found video for race '\(raceName)': \(autoFoundVideo.path)")
                loadVideoFromPath(autoFoundVideo.path)

                // Save the auto-found path for future use
                timingModel.sessionData?.videoFilePath = autoFoundVideo.path
                // Session will be saved manually via Save button
                return
            }
        }

        print("ℹ️ No video available for review mode")
    }

    private func loadVideoFromPath(_ videoPath: String) {
        let videoURL = URL(fileURLWithPath: videoPath)

        print("🎥 Loading video for review mode: \(videoPath)")

        // Read and store video duration automatically
        timingModel.readAndStoreVideoDuration(from: videoPath)

        // Set the video URL in capture manager for consistency
        captureManager.lastRecordedURL = videoURL

        // Restore video timing data from session for proper sync
        if let sessionData = timingModel.sessionData {
            captureManager.videoStartTime = sessionData.videoStartWallclock
            captureManager.videoStopTime = sessionData.videoStopWallclock

            // Ensure race start time is set for timeline calculations
            if timingModel.raceStartTime == nil {
                timingModel.raceStartTime = sessionData.raceStartWallclock
            }

            // For review mode, set race stop time based on video stop time or latest finish event
            if timingModel.raceStopTime == nil {
                if let videoStop = sessionData.videoStopWallclock {
                    timingModel.raceStopTime = videoStop
                } else if let latestFinish = sessionData.finishEvents.max(by: { $0.tRace < $1.tRace }) {
                    // Use latest finish time + some buffer
                    if let raceStart = timingModel.raceStartTime {
                        timingModel.raceStopTime = raceStart.addingTimeInterval(latestFinish.tRace + 30)
                    }
                }
            }

            print("📅 Timeline timing setup:")
            print("  - Race start: \(timingModel.raceStartTime?.description ?? "nil")")
            print("  - Race stop: \(timingModel.raceStopTime?.description ?? "nil")")
            print("  - Video start: \(captureManager.videoStartTime?.description ?? "nil")")
            print("  - Video stop: \(captureManager.videoStopTime?.description ?? "nil")")
        }

        // Load video into player: every recording of the race on one timeline
        let clips = timingModel.videoClips
        if clips.count > 1 && clips.contains(where: { $0.path == videoPath }) {
            playerViewModel.loadVideo(clips: clips.map { (url: URL(fileURLWithPath: $0.path), start: $0.relativeStart) })
        } else {
            playerViewModel.loadVideo(url: videoURL)
        }

        print("📺 Video loaded successfully for review mode with timing sync")
    }

    private func findLatestVideoForRace(raceName: String) -> URL? {
        // Search common video locations
        var searchPaths: [URL] = []

        // PRIORITY: Add race-type specific directories first
        if racePlanService.selectedEvent == nil {
            // Free Races mode - search Free Races directory first
            let freeRacesDir = AppConfig.shared.getFreeRacesDirectory()
            searchPaths.append(freeRacesDir)
            print("🔍 Searching Free Races directory: \(freeRacesDir.path)")
        } else {
            // Event mode - search Event Races directory first
            let eventRacesDir = AppConfig.shared.getEventRacesDirectory()
            searchPaths.append(eventRacesDir)
            print("🔍 Searching Event Races directory: \(eventRacesDir.path)")
        }

        // Add standard directories as fallback
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            searchPaths.append(desktop)
        }
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            searchPaths.append(documents)
        }

        // Add configured output directory (legacy)
        if let outputDir = timingModel.outputDirectory {
            searchPaths.append(outputDir)
            print("🔍 Searching configured output directory: \(outputDir.path)")
        }

        // Add capture manager output directory (legacy)
        if let captureOutputDir = captureManager.outputDirectory {
            searchPaths.append(captureOutputDir)
            print("🔍 Searching capture output directory: \(captureOutputDir.path)")
        }

        // Remove duplicates
        searchPaths = Array(Set(searchPaths))

        var foundVideos: [(URL, Date)] = []

        print("🔍 Searching for videos matching race name: '\(raceName)'")

        for searchPath in searchPaths {
            print("🔍 Searching: \(searchPath.path)")
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: searchPath,
                    includingPropertiesForKeys: [.creationDateKey],
                    options: []
                )

                let movFiles = contents.filter { $0.pathExtension.lowercased() == "mov" }
                print("   Found \(movFiles.count) .mov files")

                for fileURL in movFiles {
                    let fileName = fileURL.deletingPathExtension().lastPathComponent
                    print("   Checking: \(fileName)")
                    if fileName.contains(raceName) {
                        // Get creation date for sorting
                        let resourceValues = try? fileURL.resourceValues(forKeys: [.creationDateKey])
                        if let creationDate = resourceValues?.creationDate {
                            foundVideos.append((fileURL, creationDate))
                            print("   ✅ Match found: \(fileName) (created: \(creationDate))")
                        }
                    }
                }
            } catch {
                print("⚠️ Could not search directory \(searchPath.path): \(error)")
            }
        }

        // Return the latest video (most recent creation date)
        return foundVideos.sorted { $0.1 > $1.1 }.first?.0
    }

    private func showVideoFileSelector() {
        let panel = NSOpenPanel()
        panel.title = "Select Video File for Review"
        panel.allowedContentTypes = [.movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                DispatchQueue.main.async {
                    self.loadSelectedVideo(url: url)
                }
            }
        }
    }

    private func loadSelectedVideo(url: URL) {
        print("🎥 Loading selected video: \(url.path)")

        // A manually chosen file replaces the race's recordings
        timingModel.sessionData?.videoClips = nil

        // Read and store video duration automatically
        timingModel.readAndStoreVideoDuration(from: url.path)

        // Set the video URL in capture manager for consistency
        captureManager.lastRecordedURL = url

        // Check if we have existing wallclock timing data from session (backward compatibility)
        if let sessionData = timingModel.sessionData,
           let videoStartWallclock = sessionData.videoStartWallclock,
           let videoStopWallclock = sessionData.videoStopWallclock {

            // Use existing timing data from session (old sessions)
            captureManager.videoStartTime = videoStartWallclock
            captureManager.videoStopTime = videoStopWallclock
            print("📅 Using existing wallclock data from session: start=\(videoStartWallclock), stop=\(videoStopWallclock)")

        } else {
            // For new videos without timing data, create fresh timing
            captureManager.videoStartTime = Date()
            captureManager.videoStopTime = nil  // Will be calculated from video duration
            print("📅 New video load - using current time as reference")
        }

        // Load video into player
        playerViewModel.loadVideo(url: url)

        // Save the path to session data for future reference
        timingModel.sessionData?.videoFilePath = url.path
        // Session will be saved manually via Save button

        print("📺 Selected video loaded successfully for review mode")
    }

    /// Reload lanes/seeds/results for the selected race from the server while
    /// keeping the locally owned session data (timing sync, video, finish line,
    /// exported photos). The session file is rewritten once the reload finishes.
    private func refreshCurrentRaceFromServer() {
        guard let selectedRace = racePlanService.selectedRace else { return }
        if let current = timingModel.sessionData, current.raceId == selectedRace.id {
            pendingRefreshSnapshot = current
        } else {
            pendingRefreshSnapshot = nil
        }
        hasUnsavedChanges = false  // already confirmed in the Refresh dialog
        reloadSelectedRaceFromServer()
    }

    /// Discard the locally recorded session for the currently selected race and
    /// reload fresh data from the server (lanes, seeds, results). The session
    /// file goes to the Trash so a mis-click can be undone.
    private func resetCurrentRaceFromServer() {
        guard let selectedRace = racePlanService.selectedRace else { return }
        let raceName = "\(selectedRace.raceNumber) - \(selectedRace.title)"
        let sessionURL = AppConfig.shared.getEventRacesDirectory()
            .appendingPathComponent("\(raceName).json")
        moveSessionFileToTrash(sessionURL)
        pendingRefreshSnapshot = nil
        hasUnsavedChanges = false
        isReviewMode = false
        timingModel.resetRace()
        reloadSelectedRaceFromServer()
    }

    /// A loaded race that has already been run or recorded (and isn't running now).
    private var canRerunRace: Bool {
        timingModel.isRaceInitialized && !timingModel.isRaceActive && !captureManager.isRecording &&
            (timingModel.raceStartTime != nil || captureManager.lastRecordedURL != nil)
    }

    /// Clear the previous run of the current race so it can be started and
    /// recorded again. Keeps lanes/crews and the finish-line position.
    private func rerunCurrentRace() {
        guard let previous = timingModel.sessionData else { return }
        let raceName = previous.raceName

        let directory = previous.eventId == nil
            ? AppConfig.shared.getFreeRacesDirectory()
            : AppConfig.shared.getEventRacesDirectory()
        moveSessionFileToTrash(directory.appendingPathComponent("\(raceName).json"))

        timingModel.initializeNewRace(
            name: raceName,
            teamNames: previous.teamNames,
            eventId: previous.eventId,
            raceId: previous.raceId,
            originalRaceTitle: previous.originalRaceTitle,
            isLongDistance: previous.isLongDistance ?? false
        )
        timingModel.sessionData?.finishLineTopX = previous.finishLineTopX
        timingModel.sessionData?.finishLineBottomX = previous.finishLineBottomX
        timingModel.sessionData?.detectionLine = previous.detectionLine

        captureManager.lastRecordedURL = nil
        captureManager.videoStartTime = nil
        captureManager.videoStopTime = nil
        playerViewModel.player.replaceCurrentItem(with: nil)
        playerViewModel.isSeekingOutsideVideo = false

        isReviewMode = false
        isViewOnly = false
        hasUnsavedChanges = false
        print("🔁 RE-RUN: cleared previous run of '\(raceName)' - ready to start again")
    }

    private func reloadSelectedRaceFromServer() {
        // Re-fetch the plan; the $shouldRefreshRaceData hook reloads this race
        // from fresh server data once it arrives. Fall back to a local reload
        // from the cached plan when there's no API key configured.
        if racePlanService.hasAPIKey() {
            racePlanService.fetchRacePlans()
        } else {
            loadSelectedRaceData()
        }
    }

    private func moveSessionFileToTrash(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            print("🗑️ Moved session file to Trash: \(url.lastPathComponent)")
        } catch {
            print("❌ Could not move session file to Trash: \(error)")
        }
    }

    /// Re-apply the locally owned parts of a session after the race was rebuilt
    /// from server data, then persist the merged result.
    private func restoreLocalSessionData(from saved: SessionData) {
        guard timingModel.sessionData != nil else { return }

        timingModel.sessionData?.raceStartWallclock = saved.raceStartWallclock
        timingModel.sessionData?.videoStartWallclock = saved.videoStartWallclock
        timingModel.sessionData?.videoStopWallclock = saved.videoStopWallclock
        timingModel.sessionData?.videoStartInRace = saved.videoStartInRace
        timingModel.sessionData?.raceDuration = saved.raceDuration
        timingModel.sessionData?.recordingStartupDelay = saved.recordingStartupDelay
        timingModel.sessionData?.notes = saved.notes
        timingModel.sessionData?.exportedImages = saved.exportedImages
        timingModel.sessionData?.selectedImagesForSending = saved.selectedImagesForSending
        timingModel.sessionData?.detectionLine = saved.detectionLine
        timingModel.sessionData?.finishLineTopX = saved.finishLineTopX
        timingModel.sessionData?.finishLineBottomX = saved.finishLineBottomX
        timingModel.sessionData?.videoClips = saved.videoClips
        timingModel.recordingStartupDelay = saved.recordingStartupDelay

        // Server times are net (finish − boat's start); finish markers live on the
        // race clock, so shift them back by each boat's restored start offset.
        if let offsets = saved.laneStartOffsets {
            timingModel.sessionData?.laneStartOffsets = offsets
            for i in timingModel.finishEvents.indices where timingModel.finishEvents[i].status == .finished {
                let offset = offsets[timingModel.finishEvents[i].label] ?? 0
                timingModel.finishEvents[i].tRace += offset
            }
            timingModel.sessionData?.finishEvents = timingModel.finishEvents
        }

        timingModel.raceStartTime = saved.raceStartWallclock
        if let raceStart = saved.raceStartWallclock {
            if let raceDuration = saved.raceDuration {
                timingModel.raceStopTime = raceStart.addingTimeInterval(raceDuration)
                timingModel.raceElapsedTime = raceDuration
            } else {
                timingModel.raceStopTime = saved.videoStopWallclock
            }
        }

        if let videoPath = saved.videoFilePath, FileManager.default.fileExists(atPath: videoPath) {
            timingModel.sessionData?.videoFilePath = videoPath
            loadVideoFromPath(videoPath)
        } else {
            captureManager.videoStartTime = saved.videoStartWallclock
            captureManager.videoStopTime = saved.videoStopWallclock
        }

        // Replace the old session file (kept in the Trash) with the merged one
        let sessionURL = AppConfig.shared.getEventRacesDirectory()
            .appendingPathComponent("\(timingModel.sessionData?.raceName ?? "Race").json")
        moveSessionFileToTrash(sessionURL)
        saveCurrentRaceData()
        print("🔄 Refreshed race from server, kept local timing/video data")
    }

    private func loadSelectedRaceData() {
        guard let selectedRace = racePlanService.selectedRace else { return }

        // REFRESH in progress: rebuild from server data, then restore local timing
        let refreshSnapshot = pendingRefreshSnapshot
        pendingRefreshSnapshot = nil

        // Auto-exit review mode when changing races
        isReviewMode = false

        // Set race name from selected race
        newRaceName = "\(selectedRace.raceNumber) - \(selectedRace.title)"

        // Clear existing team names and populate from race data
        // Long-distance races (>1000m) start boat by boat and may put more crews
        // on the water than there are lanes, so keep every lane from the plan.
        let isLongDistance = (distanceMeters(from: selectedRace.title) ?? 0) > 1000
        let highestLane = selectedRace.lanes.map(\.lane).max() ?? 0
        let laneCount = isLongDistance ? max(AppConfig.shared.maxLanes, highestLane) : AppConfig.shared.maxLanes
        newTeamNames = (1...laneCount).map { _ in "" } // Start with empty strings instead of "Lane X"

        // Populate team names from race lanes
        for lane in selectedRace.lanes {
            if lane.lane >= 1 && lane.lane <= laneCount {
                newTeamNames[lane.lane - 1] = lane.team
            }
        }

        // Initialize the race with the loaded data
        timingModel.initializeNewRace(name: newRaceName, teamNames: newTeamNames, eventId: racePlanService.selectedEvent?.id, raceId: selectedRace.id, originalRaceTitle: selectedRace.title, isLongDistance: isLongDistance)

        // Clear current video player and look for compatible video with new race name
        playerViewModel.player.replaceCurrentItem(with: nil)
        captureManager.lastRecordedURL = nil

        // Session files and videos are matched by "<num> - <title>" only, so a
        // Races folder left over from a previous event can hold a same-named
        // race belonging to a different event. Don't let it override this one.
        let sessionURL = AppConfig.shared.getEventRacesDirectory()
            .appendingPathComponent("\(newRaceName).json")
        let isForeignSession = sessionBelongsToOtherRace(sessionURL, raceId: selectedRace.id)

        // Try to auto-find video for the new race
        if isForeignSession {
            print("⚠️ '\(newRaceName)' in Races folder belongs to another race (not id \(selectedRace.id)) — ignoring its session and video")
        } else if let autoFoundVideo = findLatestVideoForRace(raceName: newRaceName) {
            print("🔍 Auto-found video for new race '\(newRaceName)': \(autoFoundVideo.path)")
            loadVideoFromPath(autoFoundVideo.path)
            timingModel.sessionData?.videoFilePath = autoFoundVideo.path
        } else {
            print("📹 No video found for race '\(newRaceName)'")
        }

        // Import any existing finish times and statuses from the API data
        for lane in selectedRace.lanes {
            // Handle different lane statuses
            if let status = lane.status {
                switch status {
                case "FINISHED":
                    if let timeString = lane.time,
                       let raceTime = parseTimeString(timeString) {
                        // Add the existing finish time to the timing model
                        timingModel.recordFinishAtTime(raceTime, lane: lane.team)
                    }
                case "DNF":
                    timingModel.recordLaneStatus(lane.team, status: .dnf)
                case "DSQ":
                    timingModel.recordLaneStatus(lane.team, status: .dsq)
                case "DNS":
                    timingModel.recordLaneStatus(lane.team, status: .dns)
                default:
                    // For other statuses like "SCHEDULED", keep as registered
                    break
                }
            }
        }

        // Check for existing session JSON file for this race
        if let refreshSnapshot, refreshSnapshot.raceId == selectedRace.id {
            restoreLocalSessionData(from: refreshSnapshot)
        } else if !isForeignSession {
            loadExistingSessionForRace(raceName: newRaceName)
        }
        // The race distance decides the start mode, also for sessions saved before it existed
        timingModel.sessionData?.isLongDistance = isLongDistance ? true : nil

        // Only clear video state if no existing session was found
        if timingModel.sessionData?.videoFilePath == nil {
            captureManager.lastRecordedURL = nil
            captureManager.videoStartTime = nil
            captureManager.videoStopTime = nil
            playerViewModel.player.replaceCurrentItem(with: nil)
            playerViewModel.isSeekingOutsideVideo = false
        }

        openInViewModeIfRecorded()
    }

    /// Race distance from a plan title like "SmallSenior A Mixed 1500m".
    private func distanceMeters(from title: String) -> Int? {
        guard let match = title.range(of: #"(\d+)\s*m\s*$"#, options: .regularExpression) else { return nil }
        return Int(title[match].filter(\.isNumber))
    }

    // Helper function to parse time string like "00:58.120" to seconds
    private func parseTimeString(_ timeString: String) -> Double? {
        let components = timeString.split(separator: ":")
        guard components.count == 2 else { return nil }

        let minutes = Double(components[0]) ?? 0
        let seconds = Double(components[1]) ?? 0

        return minutes * 60 + seconds
    }

    /// True when a session file exists at `url` but was recorded for a different
    /// server race id (e.g. race #1 of a previous event with the same title).
    /// Files without a raceId (older or manual sessions) are never treated as foreign.
    private func sessionBelongsToOtherRace(_ url: URL, raceId: Int) -> Bool {
        struct SessionRaceId: Decodable { let raceId: Int? }
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(SessionRaceId.self, from: data),
              let storedId = stored.raceId else { return false }
        return storedId != raceId
    }

    // Load existing session data for a race if JSON file exists
    private func loadExistingSessionForRace(raceName: String) {
        // Search for JSON session files in the Event Races directory
        let outputDirectory = AppConfig.shared.getEventRacesDirectory()

        let sessionFileName = "\(raceName).json"
        let sessionURL = outputDirectory.appendingPathComponent(sessionFileName)

        print("Looking for existing session file: \(sessionURL.path)")

        if FileManager.default.fileExists(atPath: sessionURL.path) {
            print("Found existing session file, loading...")
            timingModel.loadSession(from: sessionURL)

            // If session has video file path, try to load the video
            if let videoFilePath = timingModel.sessionData?.videoFilePath,
               FileManager.default.fileExists(atPath: videoFilePath) {
                print("Loading existing video from session: \(videoFilePath)")
                loadVideoFromPath(videoFilePath)
            } else {
                // Try to find and auto-load video for this race
                if let autoFoundVideo = findLatestVideoForRace(raceName: raceName) {
                    print("Auto-loading video for existing session: \(autoFoundVideo.path)")
                    loadVideoFromPath(autoFoundVideo.path)
                }
            }

            // Set up video timing data if we have wallclock times
            if let videoStart = timingModel.sessionData?.videoStartWallclock,
               let raceStart = timingModel.sessionData?.raceStartWallclock {
                print("Setting up video timing from loaded session data")
                captureManager.videoStartTime = videoStart

                if let videoStop = timingModel.sessionData?.videoStopWallclock {
                    captureManager.videoStopTime = videoStop
                }

                // Make sure race timing model has the race start time set
                timingModel.raceStartTime = raceStart
                if let videoStop = timingModel.sessionData?.videoStopWallclock {
                    timingModel.raceStopTime = videoStop
                }

                print("Video timeline data set up immediately for loaded session")
            }
        } else {
            print("No existing session file found for race: \(raceName)")
        }
    }

    // Helper function to format race titles by adding spaces between words
    /// Label shown for each entry in the Race picker.
    /// Format: "<num> - <title> (<stage>) — <competition>" with competition omitted when nil/empty.
    private func raceDropdownLabel(for race: Race) -> String {
        let base = "\(race.raceNumber) - \(formatRaceTitle(race.title)) (\(race.stage))"
        if let competition = race.competition, !competition.isEmpty {
            return "\(base) — \(competition)"
        }
        return base
    }

    private func formatRaceTitle(_ title: String) -> String {
        return title
            .replacingOccurrences(of: "Small", with: "Small ")
            .replacingOccurrences(of: "Premier", with: "Premier ")
            .replacingOccurrences(of: "Senior", with: "Senior ")
            .replacingOccurrences(of: "Mixed", with: "Mixed ")
            .replacingOccurrences(of: "Women", with: "Women ")
            .replacingOccurrences(of: "Men", with: "Men ")
            .replacingOccurrences(of: "200m", with: "200m")
            .replacingOccurrences(of: "500m", with: "500m")
            // Clean up any double spaces
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private func handleStartPress() {
        timingModel.startRace()
        // Auto-start recording disabled - only manually record finish line
    }

    private func handleStopPress() {
        print("🟠 handleStopPress() called")
        timingModel.stopRace()

        // Always stop video recording when stopping race
        if captureManager.isRecording {
            print("🟠 Stopping recording...")
            captureManager.stopRecording { url in
                print("🟠 Recording stopped callback fired")
                // Video URL will be available for review
                if let videoURL = url {
                    print("🟠 Video saved for review: \(videoURL.path)")
                    // Save video path to session data for review mode (the
                    // first clip when the race has several recordings)
                    timingModel.sessionData?.videoFilePath = timingModel.videoClips.first?.path ?? videoURL.path
                }

                // Auto-switch to Review mode after stopping race
                DispatchQueue.main.async {
                    print("🎬 Auto-switching to Review mode after race stop")
                    self.isReviewMode = true
                    self.loadVideoForReview()
                    self.autoSaveSession(reason: "race stopped")
                }
            }
        } else {
            // No recording was active, still switch to review mode
            print("🎬 Auto-switching to Review mode after race stop (no recording)")
            isReviewMode = true
            loadVideoForReview()
            autoSaveSession(reason: "race stopped")
        }
    }

    private func handleRecordPress() {
        print("🟡 handleRecordPress() called")
        if captureManager.isRecording {
            print("🟡 Stopping recording...")
            captureManager.stopRecording { _ in
                print("🟡 Recording stopped, calling markAsUnsaved()")
                // Mark as unsaved when recording stops (video data saved)
                self.markAsUnsaved()
            }
        } else {
            print("🟡 Starting recording...")
            // Pass nil so CaptureManager picks Event/Free Races folder based on session type
            // (matches where the JSON session and exported images go).
            captureManager.startRecording(to: nil) { success in
                if success {
                    print("🟡 Recording started successfully, calling markAsUnsaved()")
                    // Mark as unsaved when recording starts
                    self.markAsUnsaved()
                } else {
                    print("🟡 Recording failed to start")
                }
            }
        }
    }

    private func sendRaceResults() {
        guard let sessionData = timingModel.sessionData else {
            print("No session data to send")
            return
        }

        guard let raceId = sessionData.raceId else {
            resultsAlertTitle = "Error"
            resultsAlertMessage = "No race ID found. Cannot submit results."
            resultsAlertIsSuccess = false
            showResultsAlert = true
            return
        }

        // Get selected images for upload
        let selectedImages = timingModel.getSelectedImages()

        // Call the appropriate API based on whether images are selected
        if selectedImages.isEmpty {
            // No images selected - use the simple results endpoint
            racePlanService.submitRaceResults(
                sessionData: sessionData,
                finishEvents: timingModel.finishEvents
            ) { result in
                self.handleResultsResponse(result: result)
            }
        } else {
            // Images selected - use the results + images endpoint
            racePlanService.submitRaceResultsWithImages(
                raceId: raceId,
                sessionData: sessionData,
                finishEvents: timingModel.finishEvents,
                imagePaths: selectedImages
            ) { result in
                self.handleResultsResponse(result: result)
            }
        }
    }

    private func handleResultsResponse(result: Result<String, Error>) {
        DispatchQueue.main.async {
            // Keep the local session whether or not the upload succeeded
            self.autoSaveSession(reason: "results sent")

            switch result {
            case .success(let message):
                print("✅ SUCCESS: \(message)")
                self.resultsAlertTitle = "Success"
                let selectedImages = self.timingModel.getSelectedImages()
                if selectedImages.isEmpty {
                    self.resultsAlertMessage = "Race results submitted successfully!"
                } else {
                    self.resultsAlertMessage = "Race results and \(selectedImages.count) image(s) submitted successfully!"
                }
                self.resultsAlertIsSuccess = true
                self.showResultsAlert = true

            case .failure(let error):
                print("❌ ERROR: \(error.localizedDescription)")
                self.resultsAlertTitle = "Error"
                self.resultsAlertMessage = "Failed to submit race results:\n\(error.localizedDescription)"
                self.resultsAlertIsSuccess = false
                self.showResultsAlert = true
            }
        }
    }

    private func formatRaceTime(_ seconds: Double) -> String {
        // Round milliseconds to handle floating-point precision issues
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int(round((seconds.truncatingRemainder(dividingBy: 1)) * 1000))
        return String(format: "%02d:%02d.%03d", minutes, secs, millis)
    }

    // MARK: - Long distance (staggered start)

    /// Lanes that have a crew, in lane order.
    private var crewLanes: [(lane: Int, team: String)] {
        (timingModel.sessionData?.teamNames ?? []).enumerated()
            .filter { !$0.element.isEmpty }
            .map { (lane: $0.offset + 1, team: $0.element) }
    }

    /// First crew (by lane) whose boat hasn't been started yet.
    private var nextLaneToStart: (lane: Int, team: String)? {
        crewLanes.first { timingModel.laneStartOffset(for: $0.team) == nil }
    }

    /// Seconds between boats in a long-distance start. Stored per event
    /// (Free Races share one value); only drives the countdown - starts are tapped.
    private var startIntervalKey: String {
        "longDistanceStartInterval." + (timingModel.sessionData?.eventId.map(String.init) ?? "free")
    }

    private var startInterval: Binding<Int> {
        Binding(
            get: {
                _ = startIntervalRevision
                let stored = UserDefaults.standard.integer(forKey: startIntervalKey)
                return stored > 0 ? stored : 30
            },
            set: { newValue in
                UserDefaults.standard.set(max(1, newValue), forKey: startIntervalKey)
                startIntervalRevision += 1
            }
        )
    }

    /// Planned start of a crew (seconds after START): its place in lane order × interval.
    private func plannedStart(forLane lane: Int) -> Double? {
        guard let order = crewLanes.firstIndex(where: { $0.lane == lane }) else { return nil }
        return Double(order * startInterval.wrappedValue)
    }

    /// Countdown to the next boat's planned start; negative once it is due.
    private var nextStartCountdown: (lane: Int, team: String, remaining: Double)? {
        guard timingModel.isRaceActive, let next = nextLaneToStart,
              let planned = plannedStart(forLane: next.lane) else { return nil }
        return (next.lane, next.team, planned - timingModel.raceElapsedTime)
    }

    private func formatCountdown(_ seconds: Double) -> String {
        let total = Int(abs(seconds).rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Live: start a lane's boat now; asks before overwriting an existing start.
    private func startLane(number: Int) {
        guard timingModel.isRaceActive, timingModel.isLongDistance,
              let crew = crewLanes.first(where: { $0.lane == number }) else { return }
        if timingModel.laneStartOffset(for: crew.team) != nil {
            laneStartToOverwrite = crew.team
        } else {
            timingModel.recordLaneStart(crew.team)
            markAsUnsaved()
        }
    }

    private var laneStartsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Lane Starts — tap (or press the lane number) as each boat leaves")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Interval")
                    .font(.caption)
                TextField("", value: startInterval, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 44)
                    .multilineTextAlignment(.trailing)
                Stepper("", value: startInterval, in: 1...600, step: 5)
                    .labelsHidden()
                Text("s")
                    .font(.caption)
            }
            // Locked during the race so the field can't keep keyboard focus and
            // swallow the lane-number start keys.
            .disabled(timingModel.isRaceActive)
            .help("Seconds between boats for this event; drives the countdown to the next start")

            if let countdown = nextStartCountdown {
                let isDue = countdown.remaining <= 0
                Text(isDue
                     ? "Lane \(countdown.lane) · \(countdown.team) — due, \(formatCountdown(countdown.remaining)) late"
                     : "Next: lane \(countdown.lane) · \(countdown.team) in \(formatCountdown(countdown.remaining))")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(isDue ? .orange : .primary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                ForEach(crewLanes, id: \.lane) { crew in
                    let offset = timingModel.laneStartOffset(for: crew.team)
                    Button(action: { startLane(number: crew.lane) }) {
                        VStack(spacing: 2) {
                            Text("\(crew.lane)")
                                .font(.system(size: 20, weight: .bold))
                            Text(crew.team)
                                .font(.system(size: 11))
                                .lineLimit(1)
                            Text(offset.map { "+" + formatRaceTime($0) }
                                 ?? plannedStart(forLane: crew.lane).map { "due +" + formatCountdown($0) }
                                 ?? "not started")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundColor(offset != nil ? .white : .primary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(offset != nil ? Color.green : Color.gray.opacity(0.15))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(!timingModel.isRaceActive)
                }
            }
        }
        .alert("Restart this boat?", isPresented: Binding(
            get: { laneStartToOverwrite != nil },
            set: { if !$0 { laneStartToOverwrite = nil } }
        )) {
            Button("Set start to now", role: .destructive) {
                if let team = laneStartToOverwrite {
                    timingModel.recordLaneStart(team)
                    markAsUnsaved()
                }
                laneStartToOverwrite = nil
            }
            Button("Cancel", role: .cancel) { laneStartToOverwrite = nil }
        } message: {
            Text("\(laneStartToOverwrite ?? "") already has a start time.")
        }
    }

    /// Results table: the boat's start (seconds after race START), editable in review.
    @ViewBuilder
    private func laneStartCell(teamName: String) -> some View {
        let offset = timingModel.laneStartOffset(for: teamName)
        if isReviewMode && !isViewOnly && !teamName.isEmpty {
            EditableTimeField(
                time: offset,
                onTimeChange: { newOffset in
                    timingModel.setLaneStartOffset(teamName, newOffset)
                    markAsUnsaved()
                    onTimelineDataChanged()
                }
            )
            .frame(width: 100, alignment: .leading)
        } else if let offset {
            Text("+" + formatRaceTime(offset))
                .font(.system(size: 14, design: .monospaced))
                .frame(width: 100, alignment: .leading)
        } else {
            Text("--:--")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
        }
    }

    private func calculatePosition(for event: FinishEvent, in events: [FinishEvent]) -> Int? {
        // Only calculate position for finished events
        let finishedEvents = events.filter { $0.status == .finished }
        let sortedEvents = finishedEvents.sorted { timingModel.netTime(for: $0) < timingModel.netTime(for: $1) }

        guard let targetEvent = sortedEvents.first(where: { $0.id == event.id }) else {
            return nil
        }

        // Times are already rounded when recorded, so no need to round again for comparison
        let targetTime = timingModel.netTime(for: targetEvent)

        // Find position by counting crews with better (faster) times
        // Crews with identical times share the same position
        let betterTimes = sortedEvents.filter { timingModel.netTime(for: $0) < targetTime }
        let position = betterTimes.count + 1

        return position
    }

    private var exportedImagesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()

            Text("Exported Images (\(timingModel.getSelectedImages().count) selected)")
                .font(.subheadline)
                .fontWeight(.medium)

            if timingModel.exportedImages.isEmpty {
                Text("No images exported yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 40)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(timingModel.exportedImages.reversed(), id: \.self) { imagePath in
                            HStack(spacing: 6) {
                                Toggle("", isOn: Binding(
                                    get: { timingModel.isImageSelected(imagePath) },
                                    set: { _ in timingModel.toggleImageSelection(imagePath) }
                                ))
                                .toggleStyle(CheckboxToggleStyle())

                                Text(URL(fileURLWithPath: imagePath).lastPathComponent)
                                    .font(.caption)
                                    .lineLimit(1)

                                Spacer()

                                Text(formatImageDate(imagePath))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                        }
                    }
                }
                .frame(maxHeight: 80)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(4)
            }
        }
    }

    private func formatImageDate(_ imagePath: String) -> String {
        let url = URL(fileURLWithPath: imagePath)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let creationDate = attributes[.creationDate] as? Date {
                let formatter = DateFormatter()
                formatter.timeStyle = .medium
                return formatter.string(from: creationDate)
            }
        } catch {
            // Ignore error, fall back to default
        }
        return ""
    }


    private func textColorForStatus(_ status: LaneStatus) -> Color {
        switch status {
        case .registered:
            return .blue
        case .finished:
            return .green
        case .dns:
            return .gray
        case .dnf:
            return .orange
        case .dsq:
            return .red
        }
    }

    // MARK: - Manual Timing Setup

    private var shouldShowManualTimingSetup: Bool {
        // Show if we have a loaded session but no wallclock timing data
        guard let sessionData = timingModel.sessionData,
              timingModel.isRaceInitialized else { return false }

        // Check if we're missing critical wallclock timing data
        return sessionData.raceStartWallclock == nil ||
               sessionData.videoStartWallclock == nil
    }


    private var manualTimingSetupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Manual Timing Setup")
                    .font(.headline)

                Text("(Missing wallclock data)")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fontWeight(.medium)

                Spacer()
            }

            Text("This session is missing timing synchronization data. Enter the race duration and how far into the race the video recording started (tip: scrub to a finish frame; video start = finish race time − video time).")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Race Duration (mm:ss.fff)")
                        .font(.caption)
                        .fontWeight(.medium)

                    TextField("01:30.000", text: $manualRaceDuration)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Video Start in Race (mm:ss.fff)")
                        .font(.caption)
                        .fontWeight(.medium)

                    TextField("00:41.500", text: $manualVideoStart)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                Button("Apply Timing") {
                    guard let raceDuration = TimeInput.parse(manualRaceDuration), raceDuration > 0,
                          let videoStartInRace = TimeInput.parse(manualVideoStart) else {
                        manualTimingError = "Couldn't read the times — use mm:ss.fff (e.g. 01:05.250) or seconds (e.g. 65.25)."
                        print("Failed to parse manual timing values: duration='\(manualRaceDuration)' videoStart='\(manualVideoStart)'")
                        return
                    }
                    manualTimingError = nil

                    // videoStartInRace = seconds from race start to video start
                    // (positive: recording began after the gun). Anchor wallclocks
                    // on the video file's creation time when available.
                    timingModel.sessionData?.raceStartWallclock = nil
                    timingModel.sessionData?.videoStartInRace = videoStartInRace
                    timingModel.sessionData?.raceDuration = raceDuration
                    timingModel.ensureTimingAnchor()

                    timingModel.raceElapsedTime = raceDuration
                    captureManager.videoStartTime = timingModel.sessionData?.videoStartWallclock
                    captureManager.videoStopTime = timingModel.sessionData?.videoStopWallclock
                    markAsUnsaved()

                    print("✅ Applied manual timing:")
                    print("   Race duration: \(raceDuration)s")
                    print("   Video start in race: \(videoStartInRace)s")
                    print("   Race start (wallclock): \(timingModel.sessionData?.raceStartWallclock?.description ?? "nil")")
                    print("   Video start (wallclock): \(timingModel.sessionData?.videoStartWallclock?.description ?? "nil")")

                    // Clear the input fields
                    manualRaceDuration = ""
                    manualVideoStart = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(manualRaceDuration.isEmpty || manualVideoStart.isEmpty)

                Spacer()
            }

            if let manualTimingError {
                Text(manualTimingError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .onAppear {
            // Auto-populate fields if we have timing data
            populateManualTimingFields()
        }
    }

    private func populateManualTimingFields() {
        // Only populate if fields are empty and we have session data
        guard manualRaceDuration.isEmpty && manualVideoStart.isEmpty,
              let sessionData = timingModel.sessionData else { return }

        if let raceDuration = sessionData.raceDuration {
            manualRaceDuration = TimeInput.format(raceDuration)
        } else if let latestFinish = sessionData.finishEvents.map({ $0.tRace }).max(), latestFinish > 0 {
            manualRaceDuration = TimeInput.format((latestFinish + 5).rounded(.up))
        }

        if sessionData.videoStartInRace != 0 {
            manualVideoStart = TimeInput.format(sessionData.videoStartInRace)
        }
    }

    // MARK: - Save/Confirmation System

    /// Save without user action at key moments (race stop, results sent) so a
    /// race's session can't be lost by forgetting SAVE.
    private func autoSaveSession(reason: String) {
        guard timingModel.isRaceInitialized else { return }
        print("💾 Auto-saving session (\(reason))")
        saveCurrentRaceData()
    }

    private func saveCurrentRaceData() {
        print("💾 Saving current race data...")
        timingModel.saveCurrentSession()
        hasUnsavedChanges = false

        // Rescan for free races after saving (the file now exists on disk)
        if racePlanService.selectedEvent == nil {
            scanForFreeRaces()
        }
    }

    private func confirmRaceChange() {
        // Check if this is a new race, event change, or race change
        if pendingNewRace {
            print("🆕 Confirming new race creation")
            openNewRaceSheet()
            pendingNewRace = false
        } else if let eventId = pendingEventId {
            print("🔄 Confirming event change to ID: \(eventId)")
            // Perform the actual event change
            if eventId == -1 {
                // Free Races mode - clear race plans and reset race data
                racePlanService.clearRacePlans()
                racePlanService.selectedEvent = nil
                timingModel.resetRace()
                // Scan for available free races
                scanForFreeRaces()
            } else if let event = racePlanService.availableEvents.first(where: { $0.id == eventId }) {
                racePlanService.selectEvent(event)
                // Auto-load race plans for the new event
                if racePlanService.hasAPIKey() {
                    racePlanService.fetchRacePlans()
                }
            }
            pendingEventId = nil
        } else if let newRaceName = pendingRaceChange {
            print("🔄 Confirming race change to: \(newRaceName)")
            // Perform the actual race change
            if racePlanService.selectedEvent == nil {
                // Free race - load from file
                loadFreeRace(raceName: newRaceName)
            } else {
                // Event race - load from race plan
                loadSelectedRaceData()
            }
            pendingRaceChange = nil
        }

        hasUnsavedChanges = false
    }

    private func checkForUnsavedChanges(before action: @escaping () -> Void) {
        if hasUnsavedChanges {
            // Store the action to perform after confirmation
            pendingRaceChange = racePlanService.selectedRace?.title ?? "Unknown Race"
            showSaveConfirmation = true
        } else {
            // No unsaved changes, proceed directly
            action()
        }
    }

    private func markAsUnsaved() {
        print("🔴 markAsUnsaved() called - setting hasUnsavedChanges = true")
        DispatchQueue.main.async {
            self.hasUnsavedChanges = true
            print("🔴 hasUnsavedChanges is now: \(self.hasUnsavedChanges)")
        }
    }

    private func openNewRaceSheet() {
        // Set default race name with current date/time
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d HH-mm"
        newRaceName = "Race \(dateFormatter.string(from: Date()))"

        // Update newTeamNames array to match current maxLanes setting
        newTeamNames = (1...AppConfig.shared.maxLanes).map { "Lane \($0)" }
        newRaceIsLongDistance = false

        showNewRaceSheet = true
    }

    // MARK: - Free Races Management

    private func scanForFreeRaces() {
        let outputDirectory = AppConfig.shared.getFreeRacesDirectory()

        print("🔍 scanForFreeRaces() called")
        print("🔍 Free Races directory: \(outputDirectory.path)")

        do {
            let contents = try FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: [.creationDateKey], options: [])

            print("🔍 Total files in directory: \(contents.count)")

            // Filter for .json files and extract race names
            let jsonFiles = contents.filter { $0.pathExtension.lowercased() == "json" }
            print("🔍 JSON files found: \(jsonFiles.count)")
            for jsonFile in jsonFiles {
                print("  - \(jsonFile.lastPathComponent)")
            }
            let raceNames = jsonFiles.map { $0.deletingPathExtension().lastPathComponent }

            // Sort by most recent first
            let sortedFiles = jsonFiles.sorted { file1, file2 in
                let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2
            }

            availableFreeRaces = sortedFiles.map { $0.deletingPathExtension().lastPathComponent }

            print("📋 Found \(availableFreeRaces.count) free races: \(availableFreeRaces)")

            // Set current race name if we have one
            if let currentRaceName = timingModel.sessionData?.raceName, !currentRaceName.isEmpty {
                selectedFreeRaceName = currentRaceName
                print("🔍 Set selectedFreeRaceName to current race: \(currentRaceName)")
            } else if let firstRace = availableFreeRaces.first {
                selectedFreeRaceName = firstRace
                print("🔍 Set selectedFreeRaceName to first race: \(firstRace)")
            }
        } catch {
            print("⚠️ Error scanning for free races: \(error)")
            availableFreeRaces = []
        }
    }

    private func loadFreeRace(raceName: String) {
        let outputDirectory = AppConfig.shared.getFreeRacesDirectory()
        let sessionURL = outputDirectory.appendingPathComponent("\(raceName).json")

        print("📂 loadFreeRace() called for: \(raceName)")
        print("📂 Free Races session URL: \(sessionURL.path)")

        guard FileManager.default.fileExists(atPath: sessionURL.path) else {
            print("⚠️ Race file not found: \(sessionURL.path)")
            return
        }

        print("📂 Loading free race: \(raceName)")

        // Auto-exit review mode when changing races
        isReviewMode = false

        // Load the session
        timingModel.loadSession(from: sessionURL)

        print("📂 After loading session:")
        print("   - isRaceInitialized: \(timingModel.isRaceInitialized)")
        print("   - sessionData exists: \(timingModel.sessionData != nil)")
        print("   - race name: \(timingModel.sessionData?.raceName ?? "nil")")
        print("   - team names count: \(timingModel.sessionData?.teamNames.count ?? 0)")
        print("   - finish events count: \(timingModel.finishEvents.count)")

        // Load video if available
        if let videoFilePath = timingModel.sessionData?.videoFilePath,
           FileManager.default.fileExists(atPath: videoFilePath) {
            print("🎥 Loading video from session: \(videoFilePath)")
            loadVideoFromPath(videoFilePath)
        } else {
            // Try to find video by race name
            if let autoFoundVideo = findLatestVideoForRace(raceName: raceName) {
                print("🎥 Auto-found video: \(autoFoundVideo.path)")
                loadVideoFromPath(autoFoundVideo.path)
                timingModel.sessionData?.videoFilePath = autoFoundVideo.path
            } else {
                print("📹 No video found for race")
            }
        }

        // Update selected race name
        selectedFreeRaceName = raceName

        // Clear unsaved changes flag
        hasUnsavedChanges = false

        openInViewModeIfRecorded()

        print("✅ Free race loaded: \(raceName)")
        print("✅ Final isRaceInitialized: \(timingModel.isRaceInitialized)")
    }

}

struct EditableTimeField: View {
    let time: Double?
    let onTimeChange: (Double) -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $editText)
                    .font(.system(size: 14, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        saveTime()
                    }
                    .onExitCommand {
                        cancelEdit()
                    }
                    .onChange(of: isTextFieldFocused) { focused in
                        // Save when field loses focus
                        if !focused && isEditing {
                            saveTime()
                        }
                    }
                    .allowsHitTesting(true)
                    .onAppear {
                        // Ensure proper text selection on edit start
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let textField = NSApp.keyWindow?.firstResponder as? NSTextField {
                                textField.selectText(nil)
                            }
                        }
                    }
            } else {
                let displayText: String = {
                    if let timeValue = time {
                        return formatRaceTimeHelper(timeValue)
                    } else {
                        return "--:--.---"
                    }
                }()

                Text(displayText)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(time != nil ? .primary : .secondary)
                    .onTapGesture {
                        startEditing()
                    }
                    .help("Tap to edit time")
            }
        }
    }

    private func startEditing() {
        if let timeValue = time {
            editText = formatRaceTimeHelper(timeValue)
        } else {
            editText = ""
        }
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTextFieldFocused = true
        }
    }

    private func cancelEdit() {
        isEditing = false
        editText = ""
        isTextFieldFocused = false
    }

    private func saveTime() {
        if let newTime = parseTimeString(editText) {
            print("🕒 Saving time: \(editText) -> \(newTime) seconds")
            onTimeChange(newTime)
        } else {
            print("⚠️ Could not parse time: '\(editText)'")
        }
        isEditing = false
        editText = ""
        isTextFieldFocused = false
    }

    private func formatRaceTimeHelper(_ seconds: Double) -> String {
        // Round milliseconds to handle floating-point precision issues
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int(round((seconds.truncatingRemainder(dividingBy: 1)) * 1000))
        return String(format: "%02d:%02d.%03d", minutes, secs, millis)
    }

    private func parseTimeString(_ timeString: String) -> Double? {
        // Handle formats like "mm:ss.fff" or "ss.fff"
        let trimmed = timeString.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            print("⚠️ Empty time string")
            return nil
        }

        if trimmed.contains(":") {
            // Format: mm:ss.fff
            let components = trimmed.split(separator: ":")
            guard components.count == 2 else {
                print("⚠️ Invalid time format with colon: '\(trimmed)' - expected mm:ss.fff")
                return nil
            }

            let minutes = Double(components[0]) ?? 0
            let seconds = Double(components[1]) ?? 0
            let result = minutes * 60 + seconds

            print("🕒 Parsed time '\(trimmed)' as \(minutes) min + \(seconds) sec = \(result) total seconds")
            return result
        } else {
            // Format: ss.fff (just seconds)
            if let result = Double(trimmed) {
                print("🕒 Parsed time '\(trimmed)' as \(result) seconds")
                return result
            } else {
                print("⚠️ Could not parse '\(trimmed)' as number")
                return nil
            }
        }
    }

}

// Safe array access extension
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}