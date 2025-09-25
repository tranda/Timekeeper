import SwiftUI
import AVKit

struct RaceTimelineView: View {
    @ObservedObject var timingModel: RaceTimingModel
    @ObservedObject var captureManager: CaptureManager
    @ObservedObject var playerViewModel: PlayerViewModel
    @Binding var triggerLaneSelection: Bool

    @State private var currentRaceTime: Double = 0
    @State private var isDragging = false
    @State private var showLaneInput = false
    @State private var selectedLane = "1"
    @State private var showOverwriteConfirmation = false
    @State private var laneToOverwrite: String? = nil
    @State private var showExportSuccess = false
    @State private var isExporting = false

    var raceEndTime: Double {
        guard let raceStart = timingModel.raceStartTime else { return 0 }
        // Use stop time if race was stopped, otherwise current time
        if let raceStop = timingModel.raceStopTime {
            return raceStop.timeIntervalSince(raceStart)
        }
        return Date().timeIntervalSince(raceStart)
    }

    var videoStartInRace: Double {
        guard let videoStart = captureManager.videoStartTime,
              let raceStart = timingModel.raceStartTime else { return 0 }
        return max(0, videoStart.timeIntervalSince(raceStart))
    }

    var videoEndInRace: Double {
        guard let videoStop = captureManager.videoStopTime,
              let raceStart = timingModel.raceStartTime else { return raceEndTime }
        return videoStop.timeIntervalSince(raceStart)
    }

    var isVideoAvailable: Bool {
        return currentRaceTime >= videoStartInRace && currentRaceTime <= videoEndInRace && captureManager.lastRecordedURL != nil
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

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: width, height: 36)
                                .offset(x: startX, y: 2)
                                .allowsHitTesting(false)  // Don't interfere with interactions
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
                Button("Set Marker") {
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
                .buttonStyle(.bordered)

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
        let fileName = "\(raceName)-\(timeString).jpg"

        // Save to Desktop
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let outputURL = desktopURL.appendingPathComponent(fileName)

        exporter.exportFrame(from: videoURL, at: videoTime, to: outputURL, zeroTolerance: true) { success in
            DispatchQueue.main.async {
                self.isExporting = false
                self.showExportSuccess = success
            }
        }
    }
}