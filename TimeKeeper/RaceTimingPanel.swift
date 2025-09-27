import SwiftUI
import Combine

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
    @State private var newTeamNames = (1...MAX_LANES).map { "Lane \($0)" }
    @State private var showResultsAlert = false
    @State private var resultsAlertTitle = ""
    @State private var resultsAlertMessage = ""
    @State private var resultsAlertIsSuccess = false

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

                        Spacer()
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal)

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
                // Refresh the race data to show updated results from race plan
                loadSelectedRaceData()
                // Reset the trigger
                racePlanService.shouldRefreshRaceData = false
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
                        ForEach(0..<MAX_LANES, id: \.self) { index in
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
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(40)
            .frame(width: 450)
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
                timingModel.saveCurrentSession()
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

            timingModel.saveCurrentSession()
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
    }

    private func loadSelectedRaceData() {
        guard let selectedRace = racePlanService.selectedRace else { return }

        // Set race name from selected race
        newRaceName = "\(selectedRace.raceNumber) - \(selectedRace.title)"

        // Clear existing team names and populate from race data
        newTeamNames = (1...MAX_LANES).map { _ in "" } // Start with empty strings instead of "Lane X"

        // Populate team names from race lanes
        for lane in selectedRace.lanes {
            if lane.lane >= 1 && lane.lane <= MAX_LANES {
                newTeamNames[lane.lane - 1] = lane.team
            }
        }

        // Initialize the race with the loaded data
        timingModel.initializeNewRace(name: newRaceName, teamNames: newTeamNames, eventId: racePlanService.selectedEvent?.id, raceId: selectedRace.id, originalRaceTitle: selectedRace.title)

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

        // Clear the recorded video and reset capture manager state
        captureManager.lastRecordedURL = nil
        captureManager.videoStartTime = nil
        captureManager.videoStopTime = nil
        playerViewModel.player.replaceCurrentItem(with: nil)
        playerViewModel.isSeekingOutsideVideo = false
    }

    // Helper function to parse time string like "00:58.120" to seconds
    private func parseTimeString(_ timeString: String) -> Double? {
        let components = timeString.split(separator: ":")
        guard components.count == 2 else { return nil }

        let minutes = Double(components[0]) ?? 0
        let seconds = Double(components[1]) ?? 0

        return minutes * 60 + seconds
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
                if url != nil {
                    print("Video saved for review")
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

        // TEMPORARILY DISABLED: Get selected images for upload
        // let selectedImages = timingModel.getSelectedImages()

        // Call the API to submit race results (without images for now)
        racePlanService.submitRaceResults(
            sessionData: sessionData,
            finishEvents: timingModel.finishEvents
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let message):
                    print("✅ SUCCESS: \(message)")
                    self.resultsAlertTitle = "Success"
                    self.resultsAlertMessage = "Race results submitted successfully!"
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
    }

    private func formatRaceTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, secs, millis)
    }

    private func calculatePosition(for event: FinishEvent, in events: [FinishEvent]) -> Int? {
        // Only calculate position for finished events
        let finishedEvents = events.filter { $0.status == .finished }
        let sortedEvents = finishedEvents.sorted { $0.tRace < $1.tRace }
        if let index = sortedEvents.firstIndex(where: { $0.id == event.id }) {
            return index + 1
        }
        return nil
    }

    private var exportedImagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("Exported Images (\(timingModel.getSelectedImages().count) selected)")
                .font(.headline)

            Text("Basic image selection functionality - checkboxes coming soon")
                .font(.caption)
                .foregroundColor(.secondary)
        }
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
                    .textFieldStyle(.plain)
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
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
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