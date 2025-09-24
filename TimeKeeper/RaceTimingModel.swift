import Foundation
import Combine

struct FinishEvent: Identifiable, Codable {
    let id: String
    let tRace: Double
    let label: String

    init(tRace: Double, label: String = "Lane ?") {
        self.id = UUID().uuidString
        self.tRace = tRace
        self.label = label
    }
}

struct SessionData: Codable {
    var raceStartWallclock: Date?
    var videoStartWallclock: Date?
    var videoStopWallclock: Date?
    var raceStartInVideoSeconds: Double
    var finishEvents: [FinishEvent]
    var notes: String

    init() {
        self.raceStartInVideoSeconds = 0
        self.finishEvents = []
        self.notes = ""
    }
}

class RaceTimingModel: ObservableObject {
    @Published var raceStartTime: Date?
    @Published var raceStopTime: Date?
    @Published var raceElapsedTime: Double = 0
    @Published var finishEvents: [FinishEvent] = []
    @Published var isRaceActive = false
    @Published var autoStartRecording = false
    @Published var sessionData: SessionData? = SessionData()

    private var timer: Timer?

    var formattedElapsedTime: String {
        let minutes = Int(raceElapsedTime) / 60
        let seconds = Int(raceElapsedTime) % 60
        let milliseconds = Int((raceElapsedTime.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }

    func startRace() {
        raceStartTime = Date()
        sessionData = SessionData()
        sessionData?.raceStartWallclock = raceStartTime
        isRaceActive = true
        raceElapsedTime = 0
        finishEvents = []
        sessionData?.finishEvents = []

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            if let startTime = self.raceStartTime {
                self.raceElapsedTime = Date().timeIntervalSince(startTime)
            }
        }
    }

    func recordFinish(lane: String = "Lane ?") {
        guard isRaceActive, let startTime = raceStartTime else { return }

        let elapsedTime = Date().timeIntervalSince(startTime)
        let event = FinishEvent(tRace: elapsedTime, label: lane)
        finishEvents.append(event)
        sessionData?.finishEvents.append(event)
    }

    func recordFinishAtTime(_ time: Double, lane: String) {
        let event = FinishEvent(tRace: time, label: lane)
        finishEvents.append(event)
        sessionData?.finishEvents.append(event)
    }

    func stopRace() {
        timer?.invalidate()
        timer = nil
        isRaceActive = false
        raceStopTime = Date()
        if let startTime = raceStartTime {
            raceElapsedTime = raceStopTime!.timeIntervalSince(startTime)
        }
    }

    func resetRace() {
        timer?.invalidate()
        timer = nil
        raceStartTime = nil
        raceStopTime = nil
        raceElapsedTime = 0
        finishEvents = []
        isRaceActive = false
        sessionData = SessionData()
    }

    func setVideoStartTime(_ date: Date) {
        sessionData?.videoStartWallclock = date
        updateRaceStartInVideo()
    }

    func setVideoStopTime(_ date: Date) {
        sessionData?.videoStopWallclock = date
    }

    private func updateRaceStartInVideo() {
        guard let raceStart = sessionData?.raceStartWallclock,
              let videoStart = sessionData?.videoStartWallclock else {
            sessionData?.raceStartInVideoSeconds = 0
            return
        }

        sessionData?.raceStartInVideoSeconds = raceStart.timeIntervalSince(videoStart)
    }

    func videoTimeForRaceTime(_ raceTime: Double) -> Double {
        let raceStartInVideo = sessionData?.raceStartInVideoSeconds ?? 0
        return max(0, raceStartInVideo) + raceTime
    }

    func raceTimeForVideoTime(_ videoTime: Double) -> Double? {
        guard let raceStartInVideo = sessionData?.raceStartInVideoSeconds,
              raceStartInVideo >= 0 else { return nil }
        return videoTime - raceStartInVideo
    }

    func saveSession(to url: URL) {
        sessionData?.finishEvents = finishEvents

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        if let session = sessionData,
           let data = try? encoder.encode(session) {
            try? data.write(to: url)
        }
    }

    func loadSession(from url: URL) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: url),
              let loadedSession = try? decoder.decode(SessionData.self, from: data) else {
            return
        }

        sessionData = loadedSession
        raceStartTime = loadedSession.raceStartWallclock
        finishEvents = loadedSession.finishEvents
        isRaceActive = false

        if let raceStart = raceStartTime {
            // Calculate elapsed time based on stop time if race was stopped
            if let raceStop = raceStopTime {
                raceElapsedTime = raceStop.timeIntervalSince(raceStart)
            } else {
                raceElapsedTime = Date().timeIntervalSince(raceStart)
            }
        }
    }
}