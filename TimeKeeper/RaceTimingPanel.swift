import SwiftUI

struct RaceTimingPanel: View {
    @ObservedObject var timingModel: RaceTimingModel
    @ObservedObject var captureManager: CaptureManager
    @ObservedObject var playerViewModel: PlayerViewModel
    @State private var showResetConfirmation = false
    @State private var showLaneInput = false
    @State private var selectedLane = "1"
    @State private var manualTimeEntry: Double?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 20) {
                // Main controls in horizontal layout with equal distribution
                HStack(alignment: .top, spacing: 0) {
                // START/STOP Section
                VStack(spacing: 15) {
                    if !timingModel.isRaceActive {
                        Button(action: handleStartPress) {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: min(100, geometry.size.width * 0.12), height: min(100, geometry.size.width * 0.12))

                                Text("START")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: handleStopPress) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: min(100, geometry.size.width * 0.12), height: min(100, geometry.size.width * 0.12))

                                Text("STOP")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
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

                Divider()
                    .frame(height: 150)
                    .padding(.horizontal)

                // VIDEO RECORDING Section
                VStack(spacing: 15) {
                    Button(action: handleRecordPress) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(captureManager.isRecording ? Color.red : Color.green)
                                .frame(width: min(100, geometry.size.width * 0.12), height: min(100, geometry.size.width * 0.12))

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
                    .disabled(captureManager.selectedDevice == nil)

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

                Divider()
                    .frame(height: 150)
                    .padding(.horizontal)

                // OPTIONS Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Options")
                        .font(.headline)

                    Toggle("Auto-start video", isOn: $timingModel.autoStartRecording)
                        .toggleStyle(.checkbox)

                    Button("Reset") {
                        showResetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(!timingModel.isRaceActive && timingModel.finishEvents.isEmpty)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Finish Events")
                    .font(.headline)

                if timingModel.finishEvents.isEmpty {
                    Text("No finishes recorded")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(timingModel.finishEvents) { event in
                                HStack {
                                    Text(formatRaceTime(event.tRace))
                                        .font(.system(size: 14, design: .monospaced))
                                        .frame(width: 100, alignment: .leading)

                                    Text(event.label)
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)

                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(5)
                }
            }
            .frame(maxWidth: .infinity)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
        .sheet(isPresented: $showLaneInput) {
            VStack(spacing: 20) {
                Text("Enter Lane/Boat")
                    .font(.headline)

                Picker("Lane", selection: $selectedLane) {
                    ForEach(["1", "2", "3", "4", "5", "6", "7", "8"], id: \.self) { lane in
                        Text("Lane \(lane)").tag(lane)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                HStack {
                    Button("Cancel") {
                        showLaneInput = false
                        manualTimeEntry = nil
                    }
                    .keyboardShortcut(.escape)

                    Button("Save Finish") {
                        if let manualTime = manualTimeEntry {
                            // Recording from video scrubbing
                            let raceTime = timingModel.raceTimeForVideoTime(manualTime) ?? manualTime
                            timingModel.recordFinishAtTime(raceTime, lane: "Lane \(selectedLane)")
                        }
                        showLaneInput = false
                        manualTimeEntry = nil
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(30)
            .frame(width: 400)
        }
        .alert("Reset Race Data?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                timingModel.resetRace()
            }
        } message: {
            Text("This will clear all race timing data and finish events.")
        }
    }

    private func handleStartPress() {
        timingModel.startRace()

        if timingModel.autoStartRecording && !captureManager.isRecording {
            // Ensure output directory is set
            if captureManager.outputDirectory == nil {
                captureManager.outputDirectory = FileManager.default.temporaryDirectory
            }

            captureManager.startRecording(to: captureManager.outputDirectory) { success in
                if success {
                    print("Auto-started recording with race timer")
                }
            }
        }
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
            // Ensure output directory is set
            if captureManager.outputDirectory == nil {
                captureManager.outputDirectory = FileManager.default.temporaryDirectory
            }

            captureManager.startRecording(to: captureManager.outputDirectory) { success in
                if success {
                    print("Started video recording")
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
}