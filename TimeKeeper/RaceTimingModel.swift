import Foundation
import Combine
import AVFoundation

// MARK: - Time Input

/// Parsing/formatting for user-typed race times. Accepts "mm:ss", "mm:ss.fff",
/// "ss" or "ss.fff" (comma works as decimal separator; a leading "-" is allowed).
enum TimeInput {
    static func parse(_ text: String) -> Double? {
        var s = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        var sign = 1.0
        if s.hasPrefix("-") { sign = -1; s.removeFirst() }
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            guard let secs = Double(parts[0]), secs >= 0 else { return nil }
            return sign * secs
        case 2:
            guard let mins = Double(parts[0]), let secs = Double(parts[1]),
                  mins >= 0, secs >= 0, secs < 60 else { return nil }
            return sign * (mins * 60 + secs)
        default:
            return nil
        }
    }

    static func format(_ seconds: Double) -> String {
        let sign = seconds < 0 ? "-" : ""
        let totalMs = Int((abs(seconds) * 1000).rounded())
        return String(format: "%@%02d:%02d.%03d", sign, totalMs / 60000, (totalMs / 1000) % 60, totalMs % 1000)
    }
}

// MARK: - App Configuration
class AppConfig {
    static let shared = AppConfig()

    // Race configuration
    var maxLanes: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: "maxLanes")
            return value > 0 ? value : 4  // Default to 4 if not set
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "maxLanes")
        }
    }

    // Output directory helpers
    func getFreeRacesDirectory() -> URL {
        if let path = UserDefaults.standard.string(forKey: "freeRacesDirectory") {
            let url = URL(fileURLWithPath: path)
            // Ensure directory exists
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        // Default to Desktop/FreeRaces
        let defaultURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.appendingPathComponent("FreeRaces") ?? FileManager.default.temporaryDirectory.appendingPathComponent("FreeRaces")
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: defaultURL, withIntermediateDirectories: true)
        return defaultURL
    }

    func getEventRacesDirectory() -> URL {
        if let path = UserDefaults.standard.string(forKey: "eventRacesDirectory") {
            let url = URL(fileURLWithPath: path)
            // Ensure directory exists
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        // Default to Desktop/EventRaces
        let defaultURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.appendingPathComponent("EventRaces") ?? FileManager.default.temporaryDirectory.appendingPathComponent("EventRaces")
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: defaultURL, withIntermediateDirectories: true)
        return defaultURL
    }

    private init() {}
}

enum LaneStatus: String, Codable {
    case registered = "Registered"  // Default status before race
    case finished = "Finished"
    case dns = "DNS"  // Did Not Start
    case dnf = "DNF"  // Did Not Finish
    case dsq = "DSQ"  // Disqualified
}

// Free-form detection line for motion inspection (Phase A virtual finish line).
// Endpoints are normalized 0..1 in view space, same convention as
// PlayerViewModel.finishLineTopX/BottomX. Lane count is derived from
// SessionData.teamNames.count at inspection time.
struct DetectionLine: Codable, Equatable {
    var p1: CGPoint               // (x, y) normalized 0..1
    var p2: CGPoint               // (x, y) normalized 0..1
    var roiHalfWidthPx: Int       // perpendicular band, pixels at native video resolution

    init(p1: CGPoint, p2: CGPoint, roiHalfWidthPx: Int = 40) {
        self.p1 = p1
        self.p2 = p2
        self.roiHalfWidthPx = roiHalfWidthPx
    }
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

/// One recording of a race. A race can have several (e.g. a long-distance race
/// filmed boat by boat, or a clip restarted by the operator); they are placed on
/// one timeline by when each started.
struct VideoClip: Codable, Equatable {
    var path: String
    var relativeStart: Double  // seconds after the race's first clip started
    var duration: Double?
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
    var videoDuration: Double?  // Duration of the video file in seconds
    var raceDuration: Double?  // Duration of the race in seconds (manually adjustable)
    var detectionLine: DetectionLine?  // Free-form line for virtual-finish-line motion inspection (Phase A)
    var finishLineTopX: Double?     // Normalized X (0..1) for top endpoint of the photo finish overlay
    var finishLineBottomX: Double?  // Normalized X (0..1) for bottom endpoint of the photo finish overlay
    var isLongDistance: Bool?  // Long-distance race (>1000m): boats start one by one, each with its own start time
    var laneStartOffsets: [String: Double]?  // Team name -> seconds from race START to that boat's start (long distance only)
    var videoClips: [VideoClip]?  // All recordings of this race in order; videoFilePath/videoStartWallclock describe the first

    init() {
        self.raceName = "Race"
        self.teamNames = (1...AppConfig.shared.maxLanes).map { "Lane \($0)" }
        self.videoStartInRace = 0
        self.finishEvents = []
        self.notes = ""
        self.recordingStartupDelay = 0
        self.exportedImages = []
        self.selectedImagesForSending = Set<String>()
    }
}

extension SessionData {
    /// Crew's own time: finish on the race clock minus that boat's start offset.
    /// Equals tRace for normal (mass start) races.
    func netTime(for event: FinishEvent) -> Double {
        guard let offset = laneStartOffsets?[event.label] else { return event.tRace }
        return round((event.tRace - offset) * 1000) / 1000
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
    /// Set after every successful saveCurrentSession(), so views can clear
    /// their unsaved-changes state however the save was triggered.
    @Published private(set) var lastSessionSave: Date?

    private var timer: Timer?
    var outputDirectory: URL?

    var formattedElapsedTime: String {
        let minutes = Int(raceElapsedTime) / 60
        let seconds = Int(raceElapsedTime) % 60
        let milliseconds = Int((raceElapsedTime.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }

    var exportedImages: [String] {
        let filenames = sessionData?.exportedImages ?? []
        // Convert filenames back to full paths (in race-type specific directory)
        let outputDir: URL
        if sessionData?.eventId == nil {
            // Free Race
            outputDir = AppConfig.shared.getFreeRacesDirectory()
        } else {
            // Event Race
            outputDir = AppConfig.shared.getEventRacesDirectory()
        }
        return filenames.map { filename in
            outputDir.appendingPathComponent(filename).path
        }
    }

    var isLongDistance: Bool {
        sessionData?.isLongDistance ?? false
    }

    func laneStartOffset(for team: String) -> Double? {
        sessionData?.laneStartOffsets?[team]
    }

    func netTime(for event: FinishEvent) -> Double {
        sessionData?.netTime(for: event) ?? event.tRace
    }

    /// Live: the boat in this lane has just left the start.
    func recordLaneStart(_ team: String) {
        guard isRaceActive, let startTime = raceStartTime else { return }
        let offset = Date().timeIntervalSince(startTime)
        setLaneStartOffset(team, round(offset * 1000) / 1000)
    }

    /// Correct or clear (nil) a boat's start offset. Its finish stays put on the
    /// race clock, so its net time changes accordingly.
    func setLaneStartOffset(_ team: String, _ offset: Double?) {
        if sessionData?.laneStartOffsets == nil {
            sessionData?.laneStartOffsets = [:]
        }
        sessionData?.laneStartOffsets?[team] = offset
        print(">>> Lane start: \(team) -> \(offset.map { String(format: "%.3f", $0) } ?? "cleared")")
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
        sessionData?.laneStartOffsets = nil
        // Long distance: START is the first boat's start (lowest lane with a crew);
        // the rest are tapped as they leave.
        if isLongDistance, let firstTeam = sessionData?.teamNames.first(where: { !$0.isEmpty }) {
            sessionData?.laneStartOffsets = [firstTeam: 0]
        }

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
        // Round race time to 3 decimal places (milliseconds) when recording
        let roundedTime = round(time * 1000) / 1000
        let roundedVideoTime = videoTime.map { round($0 * 1000) / 1000 }

        let event = FinishEvent(tRace: roundedTime, tVideo: roundedVideoTime, label: lane, status: status)
        finishEvents.append(event)
        sessionData?.finishEvents.append(event)

        // Log the marker details
        let videoTimeStr = roundedVideoTime.map { String(format: "%02d:%02d.%03d", Int($0) / 60, Int($0) % 60, Int(round(($0.truncatingRemainder(dividingBy: 1)) * 1000))) } ?? "N/A"
        print(">>> Finish marker saved:")
        print("    Lane: \(lane)")
        print("    Status: \(status.rawValue)")
        print("    Original time: \(time) -> Rounded time: \(roundedTime)")
        print("    Race time: \(String(format: "%02d:%02d.%03d", Int(roundedTime) / 60, Int(roundedTime) % 60, Int(round((roundedTime.truncatingRemainder(dividingBy: 1)) * 1000))))")
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

    func initializeNewRace(name: String, teamNames: [String], eventId: Int? = nil, raceId: Int? = nil, originalRaceTitle: String? = nil, isLongDistance: Bool = false) {
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
        sessionData?.isLongDistance = isLongDistance ? true : nil
        isRaceInitialized = true
        print("Initialized new race: \(name) with \(teamNames.count) teams, event ID: \(eventId?.description ?? "none"), race ID: \(raceId?.description ?? "none")")
    }

    /// Recordings of this race in timeline order. Sessions from before multi-clip
    /// support (a single videoFilePath) yield one clip.
    var videoClips: [VideoClip] {
        if let clips = sessionData?.videoClips, !clips.isEmpty {
            return clips.sorted { $0.relativeStart < $1.relativeStart }
        }
        if let path = sessionData?.videoFilePath {
            return [VideoClip(path: path, relativeStart: 0, duration: sessionData?.videoDuration)]
        }
        return []
    }

    /// The clip covering a position on the combined video timeline (seconds after
    /// the first clip started), with the time inside that clip's own file.
    func clip(atVideoTime videoTime: Double) -> (clip: VideoClip, localTime: Double)? {
        for clip in videoClips {
            guard let duration = clip.duration else { continue }
            if videoTime >= clip.relativeStart && videoTime <= clip.relativeStart + duration {
                return (clip, videoTime - clip.relativeStart)
            }
        }
        return nil
    }

    /// A new recording began. The first clip anchors the video timeline; later
    /// clips are placed relative to it, so earlier recordings are kept.
    func beginVideoClip(url: URL, at date: Date) {
        if (sessionData?.videoClips ?? []).isEmpty || sessionData?.videoStartWallclock == nil {
            sessionData?.videoClips = []
            setVideoStartTime(date)
        }
        let relativeStart = date.timeIntervalSince(sessionData?.videoStartWallclock ?? date)
        sessionData?.videoClips?.append(VideoClip(path: url.path, relativeStart: round(relativeStart * 1000) / 1000))
        sessionData?.videoFilePath = videoClips.first?.path
        print("📹 Video clip \(sessionData?.videoClips?.count ?? 0) started at +\(String(format: "%.3f", relativeStart))s: \(url.lastPathComponent)")
    }

    func endVideoClip(url: URL, at date: Date) {
        setVideoStopTime(date)
        if let index = sessionData?.videoClips?.firstIndex(where: { $0.path == url.path }) {
            sessionData?.videoClips?[index].duration = Self.readDuration(of: url.path)
        }
        refreshVideoSpan()
    }

    /// Recording failed: drop its clip so the timeline doesn't show a gap-less hole.
    func discardVideoClip(url: URL) {
        sessionData?.videoClips?.removeAll { $0.path == url.path }
        sessionData?.videoFilePath = videoClips.first?.path
    }

    /// videoDuration covers all clips: from the first clip's start to the last one's end.
    private func refreshVideoSpan() {
        guard var clips = sessionData?.videoClips, !clips.isEmpty else { return }
        for i in clips.indices where clips[i].duration == nil {
            clips[i].duration = Self.readDuration(of: clips[i].path)
        }
        sessionData?.videoClips = clips
        let end = clips.compactMap { clip in clip.duration.map { clip.relativeStart + $0 } }.max()
        if let end {
            sessionData?.videoDuration = end
        }
    }

    private static func readDuration(of path: String) -> Double? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let duration = AVAsset(url: URL(fileURLWithPath: path)).duration
        guard duration.isValid && !duration.isIndefinite else { return nil }
        return CMTimeGetSeconds(duration)
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

    /// Sessions that were never saved with wallclock data (e.g. a race loaded from
    /// the race plan with only a video on disk) have no race start to hang timing
    /// edits on. Synthesize one: the video starts at the file's creation time and
    /// the race starts `videoStartInRace` seconds before that.
    func ensureTimingAnchor() {
        guard sessionData != nil, sessionData?.raceStartWallclock == nil else { return }

        var videoStart = Date()
        if let path = sessionData?.videoFilePath,
           let created = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.creationDateKey]).creationDate {
            videoStart = created
        }
        let raceStart = videoStart.addingTimeInterval(-(sessionData?.videoStartInRace ?? 0))

        sessionData?.raceStartWallclock = raceStart
        sessionData?.videoStartWallclock = videoStart
        if let videoDuration = sessionData?.videoDuration {
            sessionData?.videoStopWallclock = videoStart.addingTimeInterval(videoDuration)
        }
        raceStartTime = raceStart
        if let raceDuration = sessionData?.raceDuration {
            raceStopTime = raceStart.addingTimeInterval(raceDuration)
        }
        print("⏱️ Synthesized timing anchor: race start \(raceStart), video start \(videoStart)")
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
        // Store only the filename, not the full path (images are in same directory as JSON)
        let filename = URL(fileURLWithPath: imagePath).lastPathComponent
        sessionData?.exportedImages.append(filename)
        // Auto-select new images for sending by default
        sessionData?.selectedImagesForSending.insert(filename)
    }

    func clearExportedImages() {
        sessionData?.exportedImages.removeAll()
        sessionData?.selectedImagesForSending.removeAll()
    }

    func toggleImageSelection(_ imagePath: String) {
        let filename = URL(fileURLWithPath: imagePath).lastPathComponent
        if sessionData?.selectedImagesForSending.contains(filename) == true {
            sessionData?.selectedImagesForSending.remove(filename)
            print("🔄 Deselected image: \(filename)")
        } else {
            sessionData?.selectedImagesForSending.insert(filename)
            print("✅ Selected image: \(filename)")
        }
        print("📋 Total selected images: \(sessionData?.selectedImagesForSending.count ?? 0)")
    }

    func isImageSelected(_ imagePath: String) -> Bool {
        let filename = URL(fileURLWithPath: imagePath).lastPathComponent
        return sessionData?.selectedImagesForSending.contains(filename) ?? false
    }

    func getSelectedImages() -> [String] {
        let selectedFilenames = Array(sessionData?.selectedImagesForSending ?? Set<String>())
        // Convert filenames back to full paths (in race-type specific directory)
        let outputDir: URL
        if sessionData?.eventId == nil {
            // Free Race
            outputDir = AppConfig.shared.getFreeRacesDirectory()
        } else {
            // Event Race
            outputDir = AppConfig.shared.getEventRacesDirectory()
        }
        return selectedFilenames.map { filename in
            outputDir.appendingPathComponent(filename).path
        }
    }

    @discardableResult
    func saveSession(to url: URL) -> Bool {
        sessionData?.finishEvents = finishEvents
        sessionData?.recordingStartupDelay = recordingStartupDelay

        // Debug: Print what's being saved
        print("💾 Saving session with:")
        print("  - Exported images: \(sessionData?.exportedImages.count ?? 0)")
        if let images = sessionData?.exportedImages {
            for (i, imagePath) in images.enumerated() {
                print("    [\(i+1)] \(imagePath)")
            }
        }
        print("  - Selected images: \(sessionData?.selectedImagesForSending.count ?? 0)")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        guard let session = sessionData else {
            print("❌ No session data to save")
            return false
        }
        do {
            let data = try encoder.encode(session)
            try data.write(to: url)
            print("💾 Session saved successfully to: \(url.path)")
            return true
        } catch {
            print("❌ Failed to encode/save session to \(url.path): \(error)")
            return false
        }
    }

    func loadSession(from url: URL) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: url),
              let loadedSession = try? decoder.decode(SessionData.self, from: data) else {
            return
        }

        // Apply synchronously on the main thread: callers read sessionData
        // (videoFilePath, wallclocks) right after loading.
        let apply = {
            self.sessionData = loadedSession
            self.raceStartTime = loadedSession.raceStartWallclock
            // Don't inherit the previously loaded race's stop time
            self.raceStopTime = loadedSession.videoStopWallclock
            self.finishEvents = loadedSession.finishEvents
            self.recordingStartupDelay = loadedSession.recordingStartupDelay
            self.isRaceActive = false
            self.isRaceInitialized = true  // Mark race as initialized after loading

            // Set race elapsed time and stop time based on stored race duration
            if let raceDuration = loadedSession.raceDuration {
                // Use stored race duration (manually adjusted)
                self.raceElapsedTime = raceDuration
                if let raceStart = self.raceStartTime {
                    self.raceStopTime = raceStart.addingTimeInterval(raceDuration)
                }
                print("📊 Loaded race duration: \(raceDuration)s (manually set)")
            } else if let raceStart = self.raceStartTime {
                // Fallback to wallclock calculation
                if let raceStop = self.raceStopTime {
                    self.raceElapsedTime = raceStop.timeIntervalSince(raceStart)
                } else {
                    // For loaded sessions without stop time, use race duration from finish events
                    let maxFinishTime = loadedSession.finishEvents.map { $0.tRace }.max() ?? 0
                    if maxFinishTime > 0 {
                        self.raceElapsedTime = maxFinishTime
                    } else {
                        // Fallback: don't use current time for old sessions
                        self.raceElapsedTime = 0
                    }
                }
                print("📊 Calculated race elapsed time: \(self.raceElapsedTime)s (from wallclock)")
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    func saveCurrentSession() {
        // Determine the save directory based on race type
        let saveDirectory: URL
        if sessionData?.eventId == nil {
            // Free Race - use Free Races directory
            saveDirectory = AppConfig.shared.getFreeRacesDirectory()
            print("💾 Saving to Free Races directory")
        } else {
            // Event Race - use Event Races directory
            saveDirectory = AppConfig.shared.getEventRacesDirectory()
            print("💾 Saving to Event Races directory")
        }

        let raceName = sessionData?.raceName ?? "Race"
        let sessionFileName = "\(raceName).json"
        let sessionURL = saveDirectory.appendingPathComponent(sessionFileName)
        if saveSession(to: sessionURL) {
            lastSessionSave = Date()
        }
    }

    func readAndStoreVideoDuration(from videoPath: String) {
        // Several recordings: the video timeline spans all of them
        if (sessionData?.videoClips?.count ?? 0) > 1 {
            refreshVideoSpan()
            return
        }

        guard FileManager.default.fileExists(atPath: videoPath) else {
            print("⚠️ Video file not found: \(videoPath)")
            return
        }

        let videoURL = URL(fileURLWithPath: videoPath)
        let asset = AVAsset(url: videoURL)
        let duration = asset.duration

        guard duration.isValid && !duration.isIndefinite else {
            print("⚠️ Could not read valid duration from video: \(videoPath)")
            return
        }

        let durationSeconds = CMTimeGetSeconds(duration)
        sessionData?.videoDuration = durationSeconds

        print("📹 Video duration read: \(String(format: "%.3f", durationSeconds))s (\(formatDuration(durationSeconds)))")
        print("📝 Note: Video duration stored independently - race duration unchanged")
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, secs, millis)
    }
}