import SwiftUI
import AVKit

struct RaceTimelineView: View {
    @ObservedObject var timingModel: RaceTimingModel
    @ObservedObject var captureManager: CaptureManager
    @ObservedObject var playerViewModel: PlayerViewModel

    @State private var currentRaceTime: Double = 0
    @State private var isDragging = false
    @State private var showLaneInput = false
    @State private var selectedLane = "1"

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
                            let videoStartPercent = videoStartInRace / raceEndTime
                            let videoEndPercent = videoEndInRace / raceEndTime
                            let startX = geometry.size.width * videoStartPercent
                            let width = geometry.size.width * (videoEndPercent - videoStartPercent)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: width, height: 36)
                                .offset(x: startX, y: 2)
                        }
                    }

                    // Finish markers
                    GeometryReader { geometry in
                        ForEach(timingModel.finishEvents) { event in
                            let position = event.tRace / raceEndTime
                            let xPosition = geometry.size.width * position

                            VStack(spacing: 2) {
                                Rectangle()
                                    .fill(Color.green)
                                    .frame(width: 2, height: 40)
                                Text(event.label)
                                    .font(.system(size: 9))
                                    .foregroundColor(.green)
                            }
                            .offset(x: xPosition - 1)
                        }
                    }
                }
                .frame(height: 40)

                // Scrubber
                Slider(
                    value: $currentRaceTime,
                    in: 0...raceEndTime,
                    onEditingChanged: { editing in
                        isDragging = editing
                        if !editing {
                            seekToRaceTime()
                        }
                    }
                )
                .onChange(of: currentRaceTime) { _ in
                    // Seek video in real-time while dragging
                    seekToRaceTime()
                }

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
                Button("Add Finish Here") {
                    // Show lane selection dialog
                    showLaneInput = true
                }
                .buttonStyle(.bordered)

                if !timingModel.finishEvents.isEmpty {
                    Menu("Jump to Finish") {
                        ForEach(timingModel.finishEvents) { event in
                            Button("\(event.label): \(formatTime(event.tRace))") {
                                currentRaceTime = event.tRace
                                seekToRaceTime()
                            }
                        }
                    }
                    .buttonStyle(.bordered)
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

                Picker("Lane", selection: $selectedLane) {
                    ForEach(["1", "2", "3", "4", "5", "6", "7", "8"], id: \.self) { lane in
                        Text("Lane \(lane)").tag(lane)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                HStack(spacing: 20) {
                    Button("Cancel") {
                        showLaneInput = false
                    }
                    .keyboardShortcut(.escape)

                    Button("Save Finish") {
                        timingModel.recordFinishAtTime(currentRaceTime, lane: "Lane \(selectedLane)")
                        showLaneInput = false
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(30)
            .frame(width: 400)
        }
    }

    private func seekToRaceTime() {
        if isVideoAvailable {
            let videoTime = currentRaceTime - videoStartInRace
            playerViewModel.seek(to: videoTime, precise: true)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, secs, millis)
    }
}