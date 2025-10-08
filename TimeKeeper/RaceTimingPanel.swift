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

    // Manual timing setup for sessions without wallclock data
    @State private var manualRaceDuration = ""
    @State private var manualVideoStart = ""

    // Save/confirmation system for race changes
    @State private var showSaveConfirmation = false
    @State private var pendingRaceChange: String? = nil
    @State private var hasUnsavedChanges = false

    var body: some View {
        VStack(spacing: 20) {
            // New Race button at the top (visible but disabled during race)
            Button(action: {
                // Set default race name with current date/time
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM d HH-mm"
                newRaceName = "Race \(dateFormatter.string(from: Date()))"
                showNewRaceSheet = true
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(timingModel.isRaceActive ? Color.blue.opacity(0.5) : Color.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    Text("NEW RACE")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(timingModel.isRaceActive)
            .padding(.horizontal)

            // Event Selection Section
            if !racePlanService.availableEvents.isEmpty {
                VStack(spacing: 8) {
                    HStack {
                        Text("Event:")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)

                        Picker("", selection: Binding(
                            get: { racePlanService.selectedEvent?.id ?? 0 },
                            set: { eventId in
                                if let event = racePlanService.availableEvents.first(where: { $0.id == eventId }) {
                                    racePlanService.selectEvent(event)
                                    // Auto-load race plans for the new event
                                    if racePlanService.hasAPIKey() {
                                        racePlanService.fetchRacePlans()
                                    }
                                }
                            }
                        )) {
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
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            // Race Plan Selection Section (only show if race plan is available)
            if let racePlan = racePlanService.availableRacePlan, !racePlan.races.isEmpty {
                VStack(spacing: 8) {
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
                                Text("\(race.raceNumber) - \(formatRaceTitle(race.title)) (\(race.stage))")
                                    .font(.system(size: 16, weight: .medium))
                                    .tag(race.id)
                            }
                        }
                        .frame(width: 400)
                        .disabled(timingModel.isRaceActive)

                        Button(action: {
                            isReviewMode.toggle()

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

                        if isReviewMode {
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
                .padding(.vertical, 8)
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
                .padding(.vertical, 12)

                if let errorMessage = racePlanService.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
            }

            // Main controls in horizontal layout
            HStack(alignment: .top, spacing: 30) {
                // START/STOP Section
                VStack(spacing: 15) {
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

                // VIDEO RECORDING Section
                VStack(spacing: 15) {
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

            Divider()

            // Manual Timing Setup for sessions without wallclock data
            if shouldShowManualTimingSetup {
                manualTimingSetupSection
                Divider()
            }


            // Race Results Table
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Race Results")
                        .font(.headline)

                    if isReviewMode {
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
                        LazyVStack(spacing: 2) {
                            ForEach(Array(timingModel.sessionData?.teamNames.enumerated() ?? [].enumerated()), id: \.offset) { index, teamName in
                                raceResultRow(index: index, teamName: teamName)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
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
            VStack(spacing: 12) {
                // Exported Images Selection
                if timingModel.isRaceInitialized && !(timingModel.sessionData?.exportedImages.isEmpty ?? true) {
                    exportedImagesSection
                }

                // Send Results button (only show if race is initialized)
                if timingModel.isRaceInitialized {
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
                    .padding(.horizontal)
                }
            }

            Spacer()
        }
        .padding(20)
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
                        ForEach(0..<AppConfig.shared.maxLanes, id: \.self) { index in
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

                HStack(spacing: 20) {
                    Button("Cancel") {
                        showNewRaceSheet = false
                    }
                    .keyboardShortcut(.escape)

                    Button("Start New Race") {
                        timingModel.initializeNewRace(name: newRaceName, teamNames: newTeamNames, eventId: racePlanService.selectedEvent?.id)
                        // Clear the recorded video and reset capture manager state
                        captureManager.lastRecordedURL = nil
                        captureManager.videoStartTime = nil
                        captureManager.videoStopTime = nil
                        playerViewModel.player.replaceCurrentItem(with: nil)
                        playerViewModel.isSeekingOutsideVideo = false
                        showNewRaceSheet = false
                        hasUnsavedChanges = false  // Reset unsaved changes after new race
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
            }
        } message: {
            Text("You have unsaved changes to the current race. What would you like to do?")
        }
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

            Group {
                if isReviewMode {
                    EditableTimeField(
                        time: finishEvent?.tRace,
                        onTimeChange: { newTime in
                            if let event = finishEvent {
                                updateFinishEventTime(event: event, newTime: newTime)
                            } else {
                                // Create a new finish event for this lane
                                createFinishEventForLane(teamName: teamName, time: newTime)
                            }
                        }
                    )
                    .frame(width: 100, alignment: .leading)
                } else {
                    // In live mode, show read-only time display
                    if let event = finishEvent, event.status == .finished {
                        Text(formatRaceTime(event.tRace))
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

            positionText(for: finishEvent, position: position)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(index % 2 == 0 ? Color.clear : Color.gray.opacity(0.05))
    }

    @ViewBuilder
    private func statusMenu(for teamName: String, finishEvent: FinishEvent?) -> some View {
        Menu {
            Button("Registered") {
                timingModel.recordLaneStatus(teamName, status: .registered)
            }

            Button("Finished") {
                // Do nothing - times are set via timeline
            }
            .disabled(true)

            Divider()

            Button("DNS - Did Not Start") {
                timingModel.recordLaneStatus(teamName, status: .dns)
            }

            Button("DNF - Did Not Finish") {
                timingModel.recordLaneStatus(teamName, status: .dnf)
            }

            Button("DSQ - Disqualified") {
                timingModel.recordLaneStatus(teamName, status: .dsq)
            }

            Divider()

            Button("Clear") {
                timingModel.finishEvents.removeAll { $0.label == teamName }
                timingModel.sessionData?.finishEvents.removeAll { $0.label == teamName }
                // Session will be saved manually via Save button
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

            // Session will be saved manually via Save button
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

        // Load video into player
        playerViewModel.loadVideo(url: videoURL)

        print("📺 Video loaded successfully for review mode with timing sync")
    }

    private func findLatestVideoForRace(raceName: String) -> URL? {
        // Search common video locations
        var searchPaths: [URL] = []

        // Add standard directories
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            searchPaths.append(desktop)
        }
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            searchPaths.append(documents)
        }

        // Add configured output directory
        if let outputDir = timingModel.outputDirectory {
            searchPaths.append(outputDir)
            print("🔍 Searching configured output directory: \(outputDir.path)")
        }

        // Add capture manager output directory (might be different)
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

    private func loadSelectedRaceData() {
        guard let selectedRace = racePlanService.selectedRace else { return }

        // Auto-exit review mode when changing races
        isReviewMode = false

        // Set race name from selected race
        newRaceName = "\(selectedRace.raceNumber) - \(selectedRace.title)"

        // Clear existing team names and populate from race data
        newTeamNames = (1...AppConfig.shared.maxLanes).map { _ in "" } // Start with empty strings instead of "Lane X"

        // Populate team names from race lanes
        for lane in selectedRace.lanes {
            if lane.lane >= 1 && lane.lane <= AppConfig.shared.maxLanes {
                newTeamNames[lane.lane - 1] = lane.team
            }
        }

        // Initialize the race with the loaded data
        timingModel.initializeNewRace(name: newRaceName, teamNames: newTeamNames, eventId: racePlanService.selectedEvent?.id, raceId: selectedRace.id, originalRaceTitle: selectedRace.title)

        // Clear current video player and look for compatible video with new race name
        playerViewModel.player.replaceCurrentItem(with: nil)
        captureManager.lastRecordedURL = nil

        // Try to auto-find video for the new race
        if let autoFoundVideo = findLatestVideoForRace(raceName: newRaceName) {
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
        loadExistingSessionForRace(raceName: newRaceName)

        // Only clear video state if no existing session was found
        if timingModel.sessionData?.videoFilePath == nil {
            captureManager.lastRecordedURL = nil
            captureManager.videoStartTime = nil
            captureManager.videoStopTime = nil
            playerViewModel.player.replaceCurrentItem(with: nil)
            playerViewModel.isSeekingOutsideVideo = false
        }
    }

    // Helper function to parse time string like "00:58.120" to seconds
    private func parseTimeString(_ timeString: String) -> Double? {
        let components = timeString.split(separator: ":")
        guard components.count == 2 else { return nil }

        let minutes = Double(components[0]) ?? 0
        let seconds = Double(components[1]) ?? 0

        return minutes * 60 + seconds
    }

    // Load existing session data for a race if JSON file exists
    private func loadExistingSessionForRace(raceName: String) {
        // Search for JSON session files in the output directory
        let outputDirectory = captureManager.outputDirectory ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory

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
        timingModel.stopRace()

        // Always stop video recording when stopping race
        if captureManager.isRecording {
            captureManager.stopRecording { url in
                print("Stopped video recording with race")
                // Video URL will be available for review
                if let videoURL = url {
                    print("Video saved for review: \(videoURL.path)")
                    // Save video path to session data for review mode
                    timingModel.sessionData?.videoFilePath = videoURL.path
                    // Session will be saved manually via Save button
                }
            }
        }
    }

    private func handleRecordPress() {
        if captureManager.isRecording {
            captureManager.stopRecording { _ in
                print("Stopped video recording")
            }
        } else {
            // Use the output directory (defaults to Desktop)
            captureManager.startRecording(to: captureManager.outputDirectory) { success in
                if success {
                    print("Started video recording")
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

    private func calculatePosition(for event: FinishEvent, in events: [FinishEvent]) -> Int? {
        // Only calculate position for finished events
        let finishedEvents = events.filter { $0.status == .finished }
        let sortedEvents = finishedEvents.sorted { $0.tRace < $1.tRace }

        guard let targetEvent = sortedEvents.first(where: { $0.id == event.id }) else {
            return nil
        }

        // Times are already rounded when recorded, so no need to round again for comparison
        let targetTime = targetEvent.tRace

        // Find position by counting crews with better (faster) times
        // Crews with identical times share the same position
        let betterTimes = sortedEvents.filter { $0.tRace < targetTime }
        let position = betterTimes.count + 1

        print("🏁 Position calculation for \(targetEvent.label):")
        print("   Time: \(targetTime)")
        print("   Teams with better times: \(betterTimes.count)")
        print("   Calculated position: \(position)")

        return position
    }

    private var exportedImagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(timingModel.exportedImages.reversed(), id: \.self) { imagePath in
                            HStack(spacing: 8) {
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
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 100)
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

            Text("This session is missing timing synchronization data. Enter the race duration and when video recording started relative to race start.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Race Duration (mm:ss)")
                        .font(.caption)
                        .fontWeight(.medium)

                    TextField("01:30", text: $manualRaceDuration)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Video Start Delay (mm:ss)")
                        .font(.caption)
                        .fontWeight(.medium)

                    TextField("00:50", text: $manualVideoStart)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                Button("Apply Timing") {
                    guard let raceDuration = parseTimeString(manualRaceDuration),
                          let videoStartDelay = parseTimeString(manualVideoStart) else {
                        print("Failed to parse manual timing values")
                        return
                    }

                    // Create synthetic wallclock times based on manual input
                    // Video started before race, race starts at videoStartDelay seconds into video
                    let now = Date()
                    let raceStartTime = now
                    let videoStartTime_wallclock = raceStartTime.addingTimeInterval(-videoStartDelay)
                    let raceStopTime = raceStartTime.addingTimeInterval(raceDuration)

                    // Calculate video stop time using actual video duration if available
                    var videoStopTime = videoStartTime_wallclock.addingTimeInterval(videoStartDelay + raceDuration)

                    // If we have a video file, use its actual duration
                    if let videoFilePath = timingModel.sessionData?.videoFilePath,
                       FileManager.default.fileExists(atPath: videoFilePath) {
                        let videoURL = URL(fileURLWithPath: videoFilePath)
                        if let actualVideoDuration = getVideoDuration(from: videoURL) {
                            videoStopTime = videoStartTime_wallclock.addingTimeInterval(actualVideoDuration)
                            print("📹 Using actual video duration: \(actualVideoDuration)s")
                        }
                    }

                    // Update the session data
                    timingModel.sessionData?.raceStartWallclock = raceStartTime
                    timingModel.sessionData?.videoStartWallclock = videoStartTime_wallclock
                    timingModel.sessionData?.videoStopWallclock = videoStopTime
                    timingModel.sessionData?.videoStartInRace = videoStartDelay

                    // Update the timing model
                    timingModel.raceStartTime = raceStartTime
                    timingModel.raceStopTime = raceStopTime

                    // Update the capture manager for timeline
                    captureManager.videoStartTime = videoStartTime_wallclock
                    captureManager.videoStopTime = videoStopTime

                    // Save the updated session
                    // Session will be saved manually via Save button

                    print("✅ Applied manual timing:")
                    print("   Race duration: \(raceDuration)s")
                    print("   Video start delay: \(videoStartDelay)s")
                    print("   Race start (wallclock): \(raceStartTime)")
                    print("   Video start (wallclock): \(videoStartTime_wallclock)")
                    print("   Video stop (wallclock): \(videoStopTime)")

                    // Clear the input fields
                    manualRaceDuration = ""
                    manualVideoStart = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(manualRaceDuration.isEmpty || manualVideoStart.isEmpty)

                Spacer()
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

        // Get actual video duration from file if available
        if let videoFilePath = sessionData.videoFilePath,
           FileManager.default.fileExists(atPath: videoFilePath) {
            let videoURL = URL(fileURLWithPath: videoFilePath)
            if let actualVideoDuration = getVideoDuration(from: videoURL) {
                // Calculate race duration based on video duration and when race started
                if sessionData.videoStartInRace > 0 {
                    let raceDuration = actualVideoDuration - sessionData.videoStartInRace
                    manualRaceDuration = formatTimeForInput(raceDuration)
                    print("📝 Auto-populated race duration from video: \(manualRaceDuration)")
                } else {
                    // Fallback: use full video duration as race duration
                    manualRaceDuration = formatTimeForInput(actualVideoDuration)
                    print("📝 Auto-populated full video duration: \(manualRaceDuration)")
                }
            }
        } else {
            // Fallback: Calculate race duration from wallclock times
            if let raceStart = sessionData.raceStartWallclock,
               let raceStop = sessionData.videoStopWallclock {
                let raceDuration = raceStop.timeIntervalSince(raceStart)
                manualRaceDuration = formatTimeForInput(raceDuration)
                print("📝 Auto-populated race duration from wallclock: \(manualRaceDuration)")
            }
        }

        // Use existing videoStartInRace if available
        if sessionData.videoStartInRace > 0 {
            manualVideoStart = formatTimeForInput(sessionData.videoStartInRace)
            print("📝 Auto-populated video start delay: \(manualVideoStart)")
        } else if let raceStart = sessionData.raceStartWallclock,
                  let videoStart = sessionData.videoStartWallclock {
            // Calculate from wallclock difference
            let videoStartDelaySeconds = raceStart.timeIntervalSince(videoStart)
            if videoStartDelaySeconds > 0 {
                manualVideoStart = formatTimeForInput(videoStartDelaySeconds)
                print("📝 Auto-populated video start delay from wallclock: \(manualVideoStart)")
            }
        }
    }

    private func formatTimeForInput(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func getVideoDuration(from url: URL) -> Double? {
        let asset = AVAsset(url: url)
        let duration = asset.duration
        guard duration.isValid && !duration.isIndefinite else { return nil }
        return CMTimeGetSeconds(duration)
    }

    // MARK: - Save/Confirmation System

    private func saveCurrentRaceData() {
        print("💾 Saving current race data...")
        timingModel.saveCurrentSession()
        hasUnsavedChanges = false
    }

    private func confirmRaceChange() {
        guard let newRaceName = pendingRaceChange else { return }
        print("🔄 Confirming race change to: \(newRaceName)")

        // Perform the actual race change
        loadSelectedRaceData()

        // Clear pending change
        pendingRaceChange = nil
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
        hasUnsavedChanges = true
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