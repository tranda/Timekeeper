import SwiftUI
import AVKit

struct RaceTimelineView: View {
    @ObservedObject var timingModel: RaceTimingModel
    @ObservedObject var captureManager: CaptureManager
    @ObservedObject var playerViewModel: PlayerViewModel
    @Binding var triggerLaneSelection: Bool

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
        guard let raceStart = timingModel.raceStartTime else { return 0 }
        // Use stop time if race was stopped, otherwise current time
        if let raceStop = timingModel.raceStopTime {
            return raceStop.timeIntervalSince(raceStart)
        }
        return Date().timeIntervalSince(raceStart)
    }

    var videoStartInRace: Double {
        // Use videoStartInRace from session data if available (for manual timing)
        if let videoStartInRace = timingModel.sessionData?.videoStartInRace,
           videoStartInRace > 0 {
            let result = videoStartInRace  // Positive because video started after race began
            print("🐛 Timeline: videoStartInRace = \(result) (using videoStartInRace: \(videoStartInRace))")
            return result
        }

        // Fallback to wallclock calculation
        guard let videoStart = captureManager.videoStartTime,
              let raceStart = timingModel.raceStartTime else {
            print("🐛 Timeline: Missing timing data - videoStart: \(captureManager.videoStartTime?.description ?? "nil"), raceStart: \(timingModel.raceStartTime?.description ?? "nil")")
            return 0
        }
        let result = videoStart.timeIntervalSince(raceStart)  // Allow negative values
        print("🐛 Timeline: videoStartInRace = \(result) (videoStart: \(videoStart), raceStart: \(raceStart))")
        return result
    }

    var videoEndInRace: Double {
        // First try to use stored video duration if available
        if let videoDuration = timingModel.sessionData?.videoDuration {
            let result = videoStartInRace + videoDuration
            print("🐛 Timeline: videoEndInRace = \(result) (using stored duration: \(videoDuration)s)")
            return result
        }

        // Fallback to wallclock calculation
        guard let videoStop = captureManager.videoStopTime,
              let raceStart = timingModel.raceStartTime else {
            print("🐛 Timeline: Missing end timing data - videoStop: \(captureManager.videoStopTime?.description ?? "nil"), raceStart: \(timingModel.raceStartTime?.description ?? "nil")")
            return raceEndTime
        }
        let result = videoStop.timeIntervalSince(raceStart)
        print("🐛 Timeline: videoEndInRace = \(result) (fallback: videoStop - raceStart)")
        return result
    }

    var isVideoAvailable: Bool {
        let available = currentRaceTime >= videoStartInRace && currentRaceTime <= videoEndInRace && captureManager.lastRecordedURL != nil
        print("🐛 Timeline: isVideoAvailable = \(available) (currentRaceTime: \(currentRaceTime), videoStart: \(videoStartInRace), videoEnd: \(videoEndInRace), hasURL: \(captureManager.lastRecordedURL != nil))")
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

            // Timing Adjustment Controls
            timingAdjustmentSection

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
                                }
                            )
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
                if isVideoAvailable && captureManager.lastRecordedURL != nil {
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
            Text("Image exported successfully to Desktop")
        }
        .onChange(of: triggerLaneSelection) { newValue in
            if newValue {
                showLaneInput = true
                triggerLaneSelection = false // Reset the trigger
            }
        }
    }

    private func seekToRaceTime() {
        if isVideoAvailable {
            let videoTime = currentRaceTime - videoStartInRace
            print("Seeking - Race time: \(formatTime(currentRaceTime)), Video offset: \(formatTime(videoStartInRace)), Seeking to: \(formatTime(videoTime))")
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

        // Debug log for troubleshooting - log the most recent marker
        if event.id == timingModel.finishEvents.last?.id {
            print(">>> Marker position calculation:")
            print("    Label: \(event.label)")
            print("    Race time: \(formatTime(event.tRace))")
            print("    Race end: \(formatTime(raceEndTime))")
            print("    Video end in race: \(formatTime(videoEndInRace))")
            print("    Video extends beyond race: \(videoEndInRace > raceEndTime)")
            print("    Position %: \(position * 100)%")
            print("    Geometry width: \(geometry.size.width)px")
            print("    X position: \(xPosition)px")
            if let vt = event.tVideo {
                print("    Video time: \(formatTime(vt))")
            }
        }

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

            // Save to Desktop
            let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let outputURL = desktopURL.appendingPathComponent(fileName)

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

            // Save to Desktop
            let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            let outputURL = desktopURL.appendingPathComponent(fileName)

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
                        TextField("mm:ss", text: Binding(
                            get: {
                                // First try to use stored race duration
                                if let raceDuration = timingModel.sessionData?.raceDuration {
                                    return formatTimeForInput(raceDuration)
                                }

                                // Fallback to calculated duration from wallclock times
                                if let sessionData = timingModel.sessionData,
                                   let raceStart = sessionData.raceStartWallclock,
                                   let raceStop = timingModel.raceStopTime {
                                    let duration = raceStop.timeIntervalSince(raceStart)
                                    return formatTimeForInput(duration)
                                } else if let maxFinishTime = timingModel.finishEvents.map({ $0.tRace }).max(), maxFinishTime > 0 {
                                    // Use max finish time + buffer as race duration
                                    return formatTimeForInput(maxFinishTime + 10)
                                }
                                return ""
                            },
                            set: { newValue in
                                if let duration = parseTimeString(newValue) {
                                    updateRaceDuration(duration)
                                }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                        Text("(e.g., 01:30)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Video Start in Race")
                        .font(.caption)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        Text(formatTime(videoStartInRace))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.blue)
                            .frame(width: 80, alignment: .leading)

                        Text("(drag blue bar)")
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

    private func formatTimeForInput(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func parseTimeString(_ timeString: String) -> Double? {
        let components = timeString.split(separator: ":")
        guard components.count == 2 else { return nil }

        let minutes = Double(components[0]) ?? 0
        let seconds = Double(components[1]) ?? 0

        return minutes * 60 + seconds
    }

    private func updateRaceDuration(_ duration: Double) {
        guard let sessionData = timingModel.sessionData else { return }

        // Update ONLY race timing - do NOT touch video timing
        if let raceStart = sessionData.raceStartWallclock ?? timingModel.raceStartTime {
            let newRaceStop = raceStart.addingTimeInterval(duration)
            timingModel.raceStopTime = newRaceStop
            // Removed: timingModel.sessionData?.videoStopWallclock = newRaceStop

            // Also update race elapsed time
            timingModel.raceElapsedTime = duration

            // Store race duration in session data for persistence
            timingModel.sessionData?.raceDuration = duration

            print("🎯 Updated race duration to \(formatTimeForInput(duration)) - stored in session data")
        }
    }

    private func updateVideoStartInRace(_ newVideoStartInRace: Double) {
        guard let sessionData = timingModel.sessionData else { return }

        // Update videoStartInRace in session data
        timingModel.sessionData?.videoStartInRace = newVideoStartInRace

        // Update wallclock timing if we have race start time
        if let raceStart = sessionData.raceStartWallclock ?? timingModel.raceStartTime {
            let newVideoStartWallclock = raceStart.addingTimeInterval(newVideoStartInRace)
            captureManager.videoStartTime = newVideoStartWallclock
            timingModel.sessionData?.videoStartWallclock = newVideoStartWallclock

            print("🎬 Updated video start in race to \(formatTime(newVideoStartInRace))")
            print("   New video start wallclock: \(newVideoStartWallclock)")
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
                            isDragging = true
                        }

                        // Calculate new video start time based on absolute drag distance
                        let dragDeltaX = value.translation.width
                        let dragDeltaTime = (dragDeltaX / geometry.size.width) * raceEndTime

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