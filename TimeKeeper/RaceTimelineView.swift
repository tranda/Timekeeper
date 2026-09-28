import SwiftUI
import AVKit

struct RaceTimelineView: View {
    @ObservedObject var timingModel: RaceTimingModel
    @ObservedObject var captureManager: CaptureManager
    @ObservedObject var playerViewModel: PlayerViewModel
    @Binding var triggerLaneSelection: Bool
    /// Existing race opened read-only: scrubbing/navigation only, no editing
    var isViewOnly: Bool = false
    var onDataChanged: () -> Void = {}

    @State private var currentRaceTime: Double = 0
    @State private var isDragging = false
    @State private var isDraggingVideoTiming = false
    @State private var isHoveringVideoBar = false
    @State private var showLaneInput = false
    @State private var selectedLane = "1"
    @State private var showOverwriteConfirmation = false
    @State private var laneToOverwrite: String? = nil
    @State private var showExportSuccess = false
    @State private var isExporting = false

    var raceEndTime: Double {
        // First try to use stored race duration if available
        if let raceDuration = timingModel.sessionData?.raceDuration {
            return raceDuration
        }

        // Fallback to wallclock calculation
        if let raceStart = timingModel.raceStartTime {
            // Use stop time if race was stopped, current time while it's running
            if let raceStop = timingModel.raceStopTime {
                return raceStop.timeIntervalSince(raceStart)
            }
            if timingModel.isRaceActive {
                return Date().timeIntervalSince(raceStart)
            }
        }

        // Stopped race without a duration or stop time (e.g. race loaded from the
        // plan with only a video on disk, whose race start may be a synthesized
        // anchor from yesterday): size the timeline to cover finishes and the
        // video so markers and the video bar stay positionable.
        let latestFinish = timingModel.finishEvents.map { $0.tRace }.max() ?? 0
        let videoEnd = timingModel.sessionData?.videoDuration.map { videoStartInRace + $0 } ?? 0
        let fallback = max(latestFinish + 5, videoEnd)
        return fallback > 0 ? fallback : 60
    }

    var videoStartInRace: Double {
        // Use videoStartInRace from session data if available (for manual timing)
        // (also when there is no wallclock data to derive it from)
        if let videoStartInRace = timingModel.sessionData?.videoStartInRace,
           videoStartInRace > 0 || captureManager.videoStartTime == nil || timingModel.raceStartTime == nil {
            let result = videoStartInRace  // Positive because video started after race began
            return result
        }

        // Fallback to wallclock calculation
        guard let videoStart = captureManager.videoStartTime,
              let raceStart = timingModel.raceStartTime else {
            return 0
        }
        let result = videoStart.timeIntervalSince(raceStart)  // Allow negative values
        return result
    }

    var videoEndInRace: Double {
        // First try to use stored video duration if available
        if let videoDuration = timingModel.sessionData?.videoDuration {
            let result = videoStartInRace + videoDuration
            return result
        }

        // Fallback to wallclock calculation
        guard let videoStop = captureManager.videoStopTime,
              let raceStart = timingModel.raceStartTime else {
            return raceEndTime
        }
        let result = videoStop.timeIntervalSince(raceStart)
        return result
    }

    var isVideoAvailable: Bool {
        let available = currentRaceTime >= videoStartInRace && currentRaceTime <= videoEndInRace && captureManager.lastRecordedURL != nil
        return available
    }

    var body: some View {
        VStack(spacing: 20) {
            // Timeline Header
            HStack {
                Text("Race Timeline")
                    .font(.headline)

                Spacer()

                if isVideoAvailable {
                    Label("Video Available", systemImage: "video.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    Label("No Video", systemImage: "video.slash")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
            }

            // Timing Adjustment Controls (visible but locked in view-only)
            timingAdjustmentSection
                .disabled(isViewOnly)
                // Fresh fields per race, so a draft/focus from the previous race
                // can't linger (or be committed into this one)
                .id(timingModel.sessionData?.raceName ?? "")

            // Motion-energy bar graph aligned to race-time space (above the timeline).
            // Only renders if a sweep has been run.
            if !playerViewModel.motionSweepRows.isEmpty {
                MotionEnergyGraph(
                    rows: playerViewModel.motionSweepRows,
                    crossings: playerViewModel.motionCrossings,
                    raceEndTime: raceEndTime,
                    videoStartInRace: videoStartInRace,
                    currentRaceTime: currentRaceTime,
                    onSeekRaceTime: { raceTime in
                        currentRaceTime = max(0, min(raceEndTime, raceTime))
                        seekToRaceTime()
                    }
                )
                .frame(height: 42)
            }

            // Main Timeline Slider
            VStack(spacing: 10) {
                // Timeline with markers
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 40)

                    // Video available region
                    if captureManager.lastRecordedURL != nil {
                        GeometryReader { geometry in
                            // Blue ribbon uses race timeline coordinates
                            let videoStartPercent = videoStartInRace / raceEndTime
                            let videoEndPercent = videoEndInRace / raceEndTime

                            // Calculate positions - note that videoEndPercent can be > 1.0
                            let startX = geometry.size.width * videoStartPercent
                            let width = geometry.size.width * (videoEndPercent - videoStartPercent)

                            DraggableVideoBar(
                                width: width,
                                startX: startX,
                                isHovering: $isHoveringVideoBar,
                                isDragging: $isDraggingVideoTiming,
                                geometry: geometry,
                                raceEndTime: raceEndTime,
                                videoStartInRace: videoStartInRace,
                                currentRaceTime: currentRaceTime,
                                isVideoAvailable: isVideoAvailable,
                                playerViewModel: playerViewModel,
                                updateVideoStartInRace: updateVideoStartInRace,
                                onDragCompleted: {
                                    print("🎬 Video timing drag completed - data ready for manual save")
                                    onDataChanged()
                                }
                            )
                            .allowsHitTesting(!isViewOnly)
                        }
                    }

                    // Finish markers
                    GeometryReader { geometry in
                        ForEach(timingModel.finishEvents.filter { $0.status == .finished }) { event in
                            ZStack(alignment: .topLeading) {
                                // Color for finished events (green)
                                let markerColor = Color.green

                                // Vertical line - this is the exact position
                                Rectangle()
                                    .fill(markerColor)
                                    .frame(width: 2, height: 40)
                                    .shadow(color: markerColor.opacity(0.3), radius: 2, x: 0, y: 0)

                                // Triangle pointer at top
                                Path { path in
                                    path.move(to: CGPoint(x: 1, y: 0))
                                    path.addLine(to: CGPoint(x: -4, y: -6))
                                    path.addLine(to: CGPoint(x: 6, y: -6))
                                    path.closeSubpath()
                                }
                                .fill(markerColor)
                                .frame(width: 10, height: 6)
                                .offset(x: -4, y: -6)

                                // Lane label below
                                Text(event.label)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(markerColor)
                                    )
                                    .offset(x: -20, y: 44)
                            }
                            .offset(x: calculateMarkerPosition(event: event, geometry: geometry))
                        }
                    }
                }
                .frame(height: 40)

                // Custom precise scrubber
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)
                            .frame(maxWidth: .infinity)

                        // Progress
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * (currentRaceTime / raceEndTime), height: 4)

                        // Thumb
                        Circle()
                            .fill(Color.white)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                            .offset(x: geometry.size.width * (currentRaceTime / raceEndTime) - 8)
                    }
                    .frame(height: 16)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let newTime = (value.location.x / geometry.size.width) * raceEndTime
                                currentRaceTime = max(0, min(raceEndTime, newTime))
                                seekToRaceTime()
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
                }
                .frame(height: 16)

                // Time display
                HStack {
                    Text("Race Time:")
                        .font(.system(size: 14))
                    Text(formatTime(currentRaceTime))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.primary)

                    Spacer()

                    if isVideoAvailable {
                        Text("Video Time:")
                            .font(.system(size: 14))
                        Text(formatTime(currentRaceTime - videoStartInRace))
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.blue)
                    }

                    Spacer()

                    Text("Total: \(formatTime(raceEndTime))")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }

            // Video loading is handled by ContentView's video player

            // Status indicator for current position
            HStack {
                Spacer()
                if !isVideoAvailable {
                    Label(
                        currentRaceTime < videoStartInRace ? "Before Recording" :
                        currentRaceTime > videoEndInRace ? "After Recording" :
                        "No Video",
                        systemImage: "video.slash"
                    )
                    .foregroundColor(.gray)
                    .font(.caption)
                } else {
                    Label("Video Ready", systemImage: "video.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
                Spacer()
            }
            .padding(.vertical, 5)


            // Quick Actions
            HStack(spacing: 20) {
                if !isViewOnly {
                Button("Set Marker (M)") {
                    // Simply use the current slider position (currentRaceTime)
                    // This is what the user has positioned on the timeline
                    let videoTime = isVideoAvailable ? (currentRaceTime - videoStartInRace) : nil
                    print(">>> Adding marker:")
                    print("    Race time: \(formatTime(currentRaceTime))")
                    if let vt = videoTime {
                        print("    Video time: \(formatTime(vt)) (this will be stored)")
                    } else {
                        print("    Video time: N/A (outside video range)")
                    }
                    print("    Video starts at: \(formatTime(videoStartInRace)) in race")
                    print("    Is video available: \(isVideoAvailable)")

                    // Show lane selection dialog
                    showLaneInput = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                }

                if !timingModel.finishEvents.isEmpty {
                    Menu("Jump to marker") {
                        ForEach(timingModel.finishEvents.filter { $0.status == .finished }) { event in
                            Button("\(event.label): \(formatTime(event.tRace))") {
                                currentRaceTime = event.tRace
                                seekToRaceTime()
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                // Export Image button in the center
                if isVideoAvailable && captureManager.lastRecordedURL != nil && !isViewOnly {
                    Button("EXPORT IMAGE") {
                        exportCurrentFrame()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()

                if isVideoAvailable {
                    Button(playerViewModel.isPlaying ? "Pause" : "Play") {
                        playerViewModel.togglePlayPause()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .sheet(isPresented: $showLaneInput) {
            VStack(spacing: 20) {
                Text("Mark Finish at \(formatTime(currentRaceTime))")
                    .font(.headline)

                Text("Select Lane/Boat")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    // Filter to only non-empty lanes
                    let nonEmptyLanes = timingModel.sessionData?.teamNames.enumerated().compactMap { index, name in
                        // Show lane if it has any name (including default "Lane X"), but not if empty
                        (!name.isEmpty) ? (index: index, name: name) : nil
                    } ?? []

                    if nonEmptyLanes.isEmpty {
                        Text("No lanes configured")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(nonEmptyLanes, id: \.index) { item in
                            Button(action: {
                                selectedLane = String(item.index + 1)
                            }) {
                                HStack {
                                    Text("Lane \(item.index + 1):")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .frame(width: 60, alignment: .leading)
                                    Text(item.name)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if selectedLane == String(item.index + 1) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(selectedLane == String(item.index + 1) ? Color.accentColor.opacity(0.1) : Color.clear)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: 250)

                HStack(spacing: 20) {
                    Button("Cancel") {
                        showLaneInput = false
                    }
                    .keyboardShortcut(.escape)

                    Button("Save Marker") {
                        let laneIndex = Int(selectedLane) ?? 1
                        let laneName = timingModel.sessionData?.teamNames[safe: laneIndex - 1] ?? "Lane \(selectedLane)"
                        // Calculate video time only if we're within video range
                        let videoTime = isVideoAvailable ? (currentRaceTime - videoStartInRace) : nil

                        // Check if this lane already has a finish time
                        if timingModel.finishEvents.contains(where: { $0.label == laneName }) {
                            laneToOverwrite = laneName
                            showLaneInput = false  // Close the input sheet first
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                showOverwriteConfirmation = true  // Then show confirmation
                            }
                        } else {
                            timingModel.recordFinishAtTime(currentRaceTime, lane: laneName, videoTime: videoTime)
                            onDataChanged()  // Notify parent of changes
                            showLaneInput = false
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
                if let lane = laneToOverwrite {
                    // Remove the existing finish event for this lane
                    timingModel.finishEvents.removeAll { $0.label == lane }
                    // Calculate video time only if we're within video range
                    let videoTime = isVideoAvailable ? (currentRaceTime - videoStartInRace) : nil
                    // Add the new finish time
                    timingModel.recordFinishAtTime(currentRaceTime, lane: lane, videoTime: videoTime)
                    onDataChanged()  // Notify parent of changes
                    showLaneInput = false
                    laneToOverwrite = nil
                }
            }
        } message: {
            if let lane = laneToOverwrite {
                Text("\(lane) already has a recorded time. Do you want to overwrite it?")
            }
        }
        .alert("Export Complete", isPresented: $showExportSuccess) {
            Button("OK") { }
        } message: {
            Text("Image exported successfully to output folder")
        }
        .onChange(of: triggerLaneSelection) { newValue in
            if newValue {
                showLaneInput = true
                triggerLaneSelection = false // Reset the trigger
            }
        }
        // Keep currentRaceTime in sync with the AVPlayer's playhead. Arrow-key
        // frame-stepping in ContentView only updates playerViewModel.currentTime;
        // without this observer the timeline's race-time readout (and the
        // "Mark Finish at HH:MM:SS.mmm" button label / recorded finish time)
        // stay stuck at the last slider value while the displayed frame moves.
        // Skip the sync while the user is actively dragging the timeline slider
        // so we don't fight the drag's own writes.
        // Put the play marker on the video's first frame when the timeline
        // opens or a different race/video is loaded.
        .onAppear { moveToVideoStart() }
        .onChange(of: loadedVideoIdentity) { _ in moveToVideoStart() }
        .onChange(of: playerViewModel.currentTime) { videoTime in
            if isDragging { return }
            let synced = max(0, min(raceEndTime, videoTime + videoStartInRace))
            if abs(synced - currentRaceTime) > 0.0005 {
                currentRaceTime = synced
            }
        }
    }

    /// Changes whenever a different race or video file is loaded.
    private var loadedVideoIdentity: String {
        "\(timingModel.sessionData?.raceName ?? "")|\(captureManager.lastRecordedURL?.path ?? "")"
    }

    private func moveToVideoStart() {
        guard captureManager.lastRecordedURL != nil else { return }
        // Video starting before the race start (negative offset) → race time 0
        currentRaceTime = min(max(0, videoStartInRace), raceEndTime)
        seekToRaceTime()
    }

    private func seekToRaceTime() {
        if isVideoAvailable {
            let videoTime = currentRaceTime - videoStartInRace
            playerViewModel.isSeekingOutsideVideo = false
            playerViewModel.seek(to: videoTime, precise: true)
        } else {
            // We're outside the video range
            playerViewModel.isSeekingOutsideVideo = true
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, secs, millis)
    }

    private func markerColorForStatus(_ status: LaneStatus) -> Color {
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

    private func calculateMarkerPosition(event: FinishEvent, geometry: GeometryProxy) -> CGFloat {
        // The geometry width represents the full race timeline (0 to raceEndTime)
        // This should match the custom scrubber width exactly
        let raceTimelineWidth = geometry.size.width

        // Position marker based on race time
        let position = event.tRace / raceEndTime
        let xPosition = raceTimelineWidth * position

        return xPosition
    }

    private func exportCurrentFrame() {
        guard let videoURL = captureManager.lastRecordedURL else { return }

        isExporting = true

        let exporter = FrameExporter()
        let videoTime = currentRaceTime - videoStartInRace

        // Format filename with race name and time
        let raceName = timingModel.sessionData?.raceName ?? "Race"
        let timeString = formatTime(currentRaceTime).replacingOccurrences(of: ":", with: "-")

        // Check if photo finish overlay is active
        if playerViewModel.showPhotoFinishOverlay {
            let fileName = "\(raceName)-photo_finish-\(timeString).jpg"

            // Save to race-type specific directory
            let outputDirectory: URL
            if timingModel.sessionData?.eventId == nil {
                // Free Race - use Free Races directory
                outputDirectory = AppConfig.shared.getFreeRacesDirectory()
            } else {
                // Event Race - use Event Races directory
                outputDirectory = AppConfig.shared.getEventRacesDirectory()
            }
            let outputURL = outputDirectory.appendingPathComponent(fileName)

            // Get actual video dimensions
            guard let currentItem = playerViewModel.player.currentItem,
                  let videoTrack = currentItem.asset.tracks(withMediaType: .video).first else {
                print("Failed to get video track for export")
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.showExportSuccess = false
                }
                return
            }

            let videoSize = videoTrack.naturalSize

            // Debug logging for UI context
            print("=== UI EXPORT CONTEXT ===")
            print("Video track natural size: \(videoSize)")
            print("finishLineTopX: \(playerViewModel.finishLineTopX)")
            print("finishLineBottomX: \(playerViewModel.finishLineBottomX)")
            print("========================")

            // Export with finish line overlay
            exporter.exportFrameWithFinishLine(
                from: videoURL,
                at: videoTime,
                to: outputURL,
                topX: playerViewModel.finishLineTopX,
                bottomX: playerViewModel.finishLineBottomX,
                videoSize: videoSize,
                uiHeightScale: 0.9,
                zeroTolerance: true
            ) { success in
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.showExportSuccess = success
                    if success {
                        self.timingModel.addExportedImage(outputURL.path)
                    }
                }
            }
        } else {
            let fileName = "\(raceName)-\(timeString).jpg"

            // Save to race-type specific directory
            let outputDirectory: URL
            if timingModel.sessionData?.eventId == nil {
                // Free Race - use Free Races directory
                outputDirectory = AppConfig.shared.getFreeRacesDirectory()
            } else {
                // Event Race - use Event Races directory
                outputDirectory = AppConfig.shared.getEventRacesDirectory()
            }
            let outputURL = outputDirectory.appendingPathComponent(fileName)

            // Standard export without overlay
            exporter.exportFrame(from: videoURL, at: videoTime, to: outputURL, zeroTolerance: true) { success in
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.showExportSuccess = success
                    if success {
                        self.timingModel.addExportedImage(outputURL.path)
                    }
                }
            }
        }
    }

    // MARK: - Timing Adjustment Section

    private var timingAdjustmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Timing Adjustment")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("Drag blue bar to adjust video timing")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Race Duration")
                        .font(.caption)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        TimeEntryField(value: currentRaceDurationForInput) { duration in
                            guard duration > 0 else { return false }
                            updateRaceDuration(duration)
                            return true
                        }
                        .frame(width: 80)

                        Text("(e.g., 01:30.250)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Video Start in Race")
                        .font(.caption)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        TimeEntryField(value: videoStartInRace) { start in
                            updateVideoStartInRace(start)
                            return true
                        }
                        .frame(width: 80)

                        Text("(or drag blue bar)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Video Duration")
                        .font(.caption)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        if let videoDuration = timingModel.sessionData?.videoDuration {
                            Text(formatTime(videoDuration))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.green)
                                .frame(width: 80, alignment: .leading)

                            Text("(from file)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("--:--.---")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)

                            Text("(not loaded)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }

    private var currentRaceDurationForInput: Double? {
        if let raceDuration = timingModel.sessionData?.raceDuration {
            return raceDuration
        }
        if let raceStart = timingModel.sessionData?.raceStartWallclock,
           let raceStop = timingModel.raceStopTime {
            return raceStop.timeIntervalSince(raceStart)
        }
        if let maxFinishTime = timingModel.finishEvents.map({ $0.tRace }).max(), maxFinishTime > 0 {
            // Use max finish time + buffer as race duration
            return maxFinishTime + 10
        }
        return nil
    }

    private func updateRaceDuration(_ duration: Double) {
        guard timingModel.sessionData != nil else { return }
        timingModel.ensureTimingAnchor()

        // Update ONLY race timing - do NOT touch video timing
        timingModel.sessionData?.raceDuration = duration
        timingModel.raceElapsedTime = duration
        if let raceStart = timingModel.sessionData?.raceStartWallclock ?? timingModel.raceStartTime {
            timingModel.raceStopTime = raceStart.addingTimeInterval(duration)
        }
        print("🎯 Updated race duration to \(TimeInput.format(duration)) - stored in session data")
        onDataChanged()
    }

    private func updateVideoStartInRace(_ newVideoStartInRace: Double) {
        guard timingModel.sessionData != nil else { return }

        // Update videoStartInRace in session data
        timingModel.sessionData?.videoStartInRace = newVideoStartInRace
        timingModel.ensureTimingAnchor()

        // Update wallclock timing (race start stays fixed, video start moves)
        if let raceStart = timingModel.sessionData?.raceStartWallclock ?? timingModel.raceStartTime {
            let newVideoStartWallclock = raceStart.addingTimeInterval(newVideoStartInRace)
            captureManager.videoStartTime = newVideoStartWallclock
            timingModel.sessionData?.videoStartWallclock = newVideoStartWallclock

            if let videoDuration = timingModel.sessionData?.videoDuration {
                let newVideoStop = newVideoStartWallclock.addingTimeInterval(videoDuration)
                captureManager.videoStopTime = newVideoStop
                timingModel.sessionData?.videoStopWallclock = newVideoStop
            }

            // Drags log once, on release (DraggableVideoBar.onEnded)
            if !isDraggingVideoTiming {
                print("🎬 Updated video start in race to \(formatTime(newVideoStartInRace))")
            }
        }
    }
}

/// Text field for a race time (mm:ss.fff). Keeps its own draft while the user
/// types and only commits on Return / focus loss, so partial input like "01:"
/// isn't reformatted away mid-edit. `onCommit` returns false to reject a value.
struct TimeEntryField: View {
    let value: Double?
    let onCommit: (Double) -> Bool

    @State private var draft = ""
    @State private var isInvalid = false
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("mm:ss.fff", text: $draft)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            .focused($isFocused)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.red, lineWidth: isInvalid ? 1.5 : 0)
            )
            .help(isInvalid ? "Couldn't read that time — use mm:ss.fff or seconds" : "Press Return to apply")
            .onAppear { resetDraft() }
            .onChange(of: value) { _ in
                if !isFocused { resetDraft() }
            }
            .onChange(of: isFocused) { focused in
                if !focused { commit() }
            }
            .onSubmit { commit() }
    }

    private func resetDraft() {
        draft = value.map(TimeInput.format) ?? ""
        isInvalid = false
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == value.map(TimeInput.format) {
            resetDraft()
            return
        }
        if let parsed = TimeInput.parse(trimmed), onCommit(parsed) {
            draft = TimeInput.format(parsed)
            isInvalid = false
        } else {
            isInvalid = true
            print("⚠️ Invalid time input: '\(draft)'")
        }
    }
}

struct DraggableVideoBar: View {
    let width: CGFloat
    let startX: CGFloat
    @Binding var isHovering: Bool
    @Binding var isDragging: Bool
    let geometry: GeometryProxy
    let raceEndTime: Double
    let videoStartInRace: Double
    let currentRaceTime: Double
    let isVideoAvailable: Bool
    let playerViewModel: PlayerViewModel
    let updateVideoStartInRace: (Double) -> Void
    let onDragCompleted: () -> Void

    @State private var dragStartVideoStartInRace: Double = 0
    @State private var dragStartRaceEndTime: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.blue.opacity(isHovering || isDragging ? 0.5 : 0.3))
            .overlay(
                // Add visual indicator that this is draggable
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.blue.opacity(isHovering || isDragging ? 0.8 : 0.6), lineWidth: isHovering || isDragging ? 2 : 1)
            )
            .overlay(
                // Add drag handle in the center
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.blue.opacity(isHovering || isDragging ? 1.0 : 0.8))
                            .frame(width: 2, height: isHovering || isDragging ? 16 : 12)
                    }
                }
            )
            .frame(width: width, height: 36)
            .offset(x: startX, y: 2)
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .onHover { hovering in
                isHovering = hovering
            }
            .help("Drag to adjust video timing")
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging {
                            // Store the initial video start position when drag begins
                            dragStartVideoStartInRace = videoStartInRace
                            dragStartRaceEndTime = raceEndTime
                            isDragging = true
                        }

                        // Calculate new video start time based on absolute drag distance
                        let dragDeltaX = value.translation.width
                        // Scale by the timeline length at drag start, so a length
                        // change mid-drag can't make the bar run away
                        let dragDeltaTime = (dragDeltaX / geometry.size.width) * dragStartRaceEndTime

                        let newVideoStartInRace = dragStartVideoStartInRace + dragDeltaTime
                        updateVideoStartInRace(newVideoStartInRace)

                        // Update video preview in real-time if positioned on timeline
                        if isVideoAvailable && currentRaceTime >= newVideoStartInRace {
                            let videoTime = currentRaceTime - newVideoStartInRace
                            if videoTime >= 0 {
                                playerViewModel.seek(to: videoTime, precise: true)
                                playerViewModel.isSeekingOutsideVideo = false
                            }
                        } else {
                            playerViewModel.isSeekingOutsideVideo = true
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        print("🎬 Video timing adjustment completed - final position: \(String(format: "%.3f", videoStartInRace))s")
                        onDragCompleted()
                    }
            )
    }
}
// MARK: - Motion Energy Graph
//
// Bar-graph strip rendered above the main timeline. Each bar represents the motion
// energy at one sampled frame from the most-recent sweep. Bars are positioned in
// race-time space (so they align horizontally with the existing video ribbon and
// finish markers). Detected crossings are marked with red triangles. Click anywhere
// in the graph to seek to that race time.
struct MotionEnergyGraph: View {
    let rows: [SweepRow]
    let crossings: [CrossingEvent]
    let raceEndTime: Double
    let videoStartInRace: Double
    let currentRaceTime: Double
    let onSeekRaceTime: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("Motion Energy")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                Text("\(rows.count) samples · \(crossings.count) crossings")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }

            GeometryReader { geo in
                let maxEnergy = max(1, rows.map { $0.motionEnergy }.max() ?? 1)
                let plotHeight: CGFloat = 28
                ZStack(alignment: .topLeading) {
                    // Background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.12))
                        .frame(height: plotHeight)

                    // Bars
                    ForEach(0..<rows.count, id: \.self) { i in
                        let row = rows[i]
                        let raceT = row.time + videoStartInRace
                        let xFrac = max(0, min(1, raceT / raceEndTime))
                        let h = CGFloat(row.motionEnergy) / CGFloat(maxEnergy) * plotHeight
                        Rectangle()
                            .fill(barColor(energy: row.motionEnergy, max: maxEnergy))
                            .frame(width: max(1, geo.size.width / CGFloat(max(1, rows.count)) - 0.5),
                                   height: h)
                            .position(x: CGFloat(xFrac) * geo.size.width,
                                      y: plotHeight - h / 2)
                    }

                    // Crossing markers (red triangles below each peak)
                    ForEach(0..<crossings.count, id: \.self) { i in
                        let raceT = crossings[i].time + videoStartInRace
                        let xFrac = max(0, min(1, raceT / raceEndTime))
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: 0))
                            p.addLine(to: CGPoint(x: -5, y: -7))
                            p.addLine(to: CGPoint(x: 5, y: -7))
                            p.closeSubpath()
                        }
                        .fill(Color.red)
                        .frame(width: 10, height: 7)
                        .position(x: CGFloat(xFrac) * geo.size.width,
                                  y: plotHeight + 4)
                    }

                    // Current playhead
                    let phFrac = max(0, min(1, currentRaceTime / raceEndTime))
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 1.5, height: plotHeight)
                        .position(x: CGFloat(phFrac) * geo.size.width, y: plotHeight / 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let f = max(0, min(1, value.location.x / geo.size.width))
                            onSeekRaceTime(Double(f) * raceEndTime)
                        }
                )
            }
        }
    }

    private func barColor(energy: Int, max: Int) -> Color {
        let frac = Double(energy) / Double(Swift.max(1, max))
        if frac < 0.05 { return Color.gray.opacity(0.4) }
        if frac < 0.33 { return Color.cyan.opacity(0.85) }
        if frac < 0.66 { return Color.yellow.opacity(0.9) }
        return Color.red.opacity(0.95)
    }
}
