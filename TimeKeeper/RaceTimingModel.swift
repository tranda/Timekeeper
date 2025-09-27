import Foundation
import Combine

// Configuration constant - change this to adjust the number of lanes
let MAX_LANES = 4

enum LaneStatus: String, Codable {
    case registered = "Registered"  // Default status before race
    case finished = "Finished"
    case dns = "DNS"  // Did Not Start
    case dnf = "DNF"  // Did Not Finish
    case dsq = "DSQ"  // Disqualified
}

struct FinishEvent: Identifiable, Codable {
    let id: String
    var tRace: Double  // Time in race (from race start) - make mutable for editing
    let tVideo: Double? // Time in video (from video start) - optional for backwards compatibility
    let label: String
    var status: LaneStatus  // Make mutable for editing

    init(tRace: Double, tVideo: Double? = nil, label: String = "Lane ?", status: LaneStatus = .finished) {
        self.id = UUID().uuidString
        self.tRace = tRace
        self.tVideo = tVideo
        self.label = label
        self.status = status
    }
}

struct SessionData: Codable {
    var raceName: String
    var teamNames: [String]
    var eventId: Int?  // ID of the event from API (nil for custom races)
    var raceId: Int?  // ID of the race from API (nil for custom races)
    var originalRaceTitle: String?  // Original race title from API (for discipline info)
    var raceStartWallclock: Date?
    var videoStartWallclock: Date?
    var videoStopWallclock: Date?
    var videoStartInRace: Double
    var finishEvents: [FinishEvent]
    var notes: String
    var recordingStartupDelay: Double  // Delay between record button and actual video start
    var exportedImages: [String]  // Array of exported image file paths
    var selectedImagesForSending: Set<String>  // Set of selected image paths for sending
    var videoFilePath: String?  // Path to the recorded video file for review mode

    init() {
        self.raceName = "Race"
        self.teamNames = (1...MAX_LANES).map { "Lane \($0)" }
        self.videoStartInRace = 0
        self.finishEvents = []
        self.notes = ""
        self.recordingStartupDelay = 0
        self.exportedImages = []
        self.selectedImagesForSending = Set<String>()
    }
}

class RaceTimingModel: ObservableObject {
    @Published var raceStartTime: Date?
    @Published var raceStopTime: Date?
    @Published var raceElapsedTime: Double = 0
    @Published var finishEvents: [FinishEvent] = []
    @Published var isRaceActive = false
    // Auto-start recording disabled - only manually record finish line
    // @Published var autoStartRecording = false
    @Published var sessionData: SessionData? = SessionData()
    @Published var isRaceInitialized = false
    @Published var recordingStartupDelay: Double = 0  // Actual delay between record click and video start

    private var timer: Timer?
    var outputDirectory: URL?

    var formattedElapsedTime: String {
        let minutes = Int(raceElapsedTime) / 60
        let seconds = Int(raceElapsedTime) % 60
        let milliseconds = Int((raceElapsedTime.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }

    func startRace() {
        raceStartTime = Date()
        // Don't create new SessionData here - it was already initialized with the race name
        if sessionData == nil {
            sessionData = SessionData()
        }
        sessionData?.raceStartWallclock = raceStartTime
        isRaceActive = true
        raceElapsedTime = 0
        finishEvents = []
        sessionData?.finishEvents = []

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            DispatchQueue.main.async {
                if let startTime = self.raceStartTime {
                    self.raceElapsedTime = Date().timeIntervalSince(startTime)
                }
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

    func recordFinishAtTime(_ time: Double, lane: String, videoTime: Double? = nil, status: LaneStatus = .finished) {
        let event = FinishEvent(tRace: time, tVideo: videoTime, label: lane, status: status)
        finishEvents.append(event)
        sessionData?.finishEvents.append(event)

        // Log the marker details
        let videoTimeStr = videoTime.map { String(format: "%02d:%02d.%03d", Int($0) / 60, Int($0) % 60, Int(($0.truncatingRemainder(dividingBy: 1)) * 1000)) } ?? "N/A"
        print(">>> Finish marker saved:")
        print("    Lane: \(lane)")
        print("    Status: \(status.rawValue)")
        print("    Race time: \(String(format: "%02d:%02d.%03d", Int(time) / 60, Int(time) % 60, Int((time.truncatingRemainder(dividingBy: 1)) * 1000)))")
        print("    Video time: \(videoTimeStr)")

        // Session will be saved manually via Save button
    }

    func recordLaneStatus(_ lane: String, status: LaneStatus) {
        // Remove any existing entry for this lane
        finishEvents.removeAll { $0.label == lane }
        sessionData?.finishEvents.removeAll { $0.label == lane }

        // Add the status marker at race time 0 (status-only markers don't have a finish time)
        let event = FinishEvent(tRace: 0, tVideo: nil, label: lane, status: status)
        finishEvents.append(event)
        sessionData?.finishEvents.append(event)

        print(">>> Lane status saved:")
        print("    Lane: \(lane)")
        print("    Status: \(status.rawValue)")

        // Session will be saved manually via Save button
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
        isRaceInitialized = false
        sessionData = SessionData()
    }

    func initializeNewRace(name: String, teamNames: [String], eventId: Int? = nil, raceId: Int? = nil, originalRaceTitle: String? = nil) {
        resetRace()
        // Ensure sessionData exists and set the race name, teams, event ID, and race ID
        if sessionData == nil {
            sessionData = SessionData()
        }
        sessionData?.raceName = name
        sessionData?.teamNames = teamNames
        sessionData?.eventId = eventId
        sessionData?.raceId = raceId
        sessionData?.originalRaceTitle = originalRaceTitle
        isRaceInitialized = true
        print("Initialized new race: \(name) with \(teamNames.count) teams, event ID: \(eventId?.description ?? "none"), race ID: \(raceId?.description ?? "none")")
    }

    func setVideoStartTime(_ date: Date) {
        sessionData?.videoStartWallclock = date
        updateVideoStartInRace()
    }

    func setVideoStopTime(_ date: Date) {
        sessionData?.videoStopWallclock = date
    }

    private func updateVideoStartInRace() {
        guard let raceStart = sessionData?.raceStartWallclock,
              let videoStart = sessionData?.videoStartWallclock else {
            sessionData?.videoStartInRace = 0
            return
        }

        sessionData?.videoStartInRace = videoStart.timeIntervalSince(raceStart)
    }

    func videoTimeForRaceTime(_ raceTime: Double) -> Double {
        let videoStartInRace = sessionData?.videoStartInRace ?? 0
        return max(0, raceTime - videoStartInRace)
    }

    func raceTimeForVideoTime(_ videoTime: Double) -> Double? {
        guard let videoStartInRace = sessionData?.videoStartInRace,
              videoStartInRace >= 0 else { return nil }
        return videoTime + videoStartInRace
    }

    func addExportedImage(_ imagePath: String) {
        sessionData?.exportedImages.append(imagePath)
        // Auto-select new images for sending by default
        sessionData?.selectedImagesForSending.insert(imagePath)
    }

    func clearExportedImages() {
        sessionData?.exportedImages.removeAll()
        sessionData?.selectedImagesForSending.removeAll()
    }

    func toggleImageSelection(_ imagePath: String) {
        if sessionData?.selectedImagesForSending.contains(imagePath) == true {
            sessionData?.selectedImagesForSending.remove(imagePath)
        } else {
            sessionData?.selectedImagesForSending.insert(imagePath)
        }
    }

    func isImageSelected(_ imagePath: String) -> Bool {
        return sessionData?.selectedImagesForSending.contains(imagePath) ?? false
    }

    func getSelectedImages() -> [String] {
        return Array(sessionData?.selectedImagesForSending ?? Set<String>())
    }

    func saveSession(to url: URL) {
        sessionData?.finishEvents = finishEvents
        sessionData?.recordingStartupDelay = recordingStartupDelay

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
        recordingStartupDelay = loadedSession.recordingStartupDelay
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

    func saveCurrentSession() {
        // Save to Desktop or the configured output directory
        let saveDirectory = outputDirectory ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let raceName = sessionData?.raceName ?? "Race"
        let sessionFileName = "\(raceName).json"
        let sessionURL = saveDirectory.appendingPathComponent(sessionFileName)
        saveSession(to: sessionURL)
        print("Session saved to: \(sessionURL.path)")
    }
}