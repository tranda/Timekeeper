import Foundation
import Combine

struct Event {
    let id: Int
    let name: String
    let location: String
    let year: Int
    let status: String
}

struct RacePlan {
    let eventId: String  // Changed from Int to String
    let eventName: String
    let raceCount: Int
    let races: [Race]
}

struct Race {
    let id: Int
    let raceNumber: Int
    let stage: String
    let disciplineId: Int
    let disciplineInfo: String
    let boatSize: String
    let raceTime: String
    let status: String
    let lanes: [Lane]
    let title: String
    let createdAt: String
    let updatedAt: String
}

struct Lane {
    let lane: Int
    let team: String
    let crewId: Int
    let time: String?
    let status: String?  // Changed from String to String? (optional)
    let position: Int?
}

class RacePlanService: ObservableObject {
    static let shared = RacePlanService()

    @Published var availableEvents: [Event] = []
    @Published var selectedEvent: Event?
    @Published var availableRacePlan: RacePlan?
    @Published var selectedRace: Race?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var shouldRefreshRaceData = false  // Triggers UI to refresh race data

    private var cancellables = Set<AnyCancellable>()
    private let racePlanCacheURL: URL

    private init() {
        // Create cache file URL in app support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("TimeKeeper")
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        racePlanCacheURL = appFolder.appendingPathComponent("race_plans.json")

        // Load cached race plans on init
        loadCachedRacePlans()

        // Load events on init
        fetchEvents()
    }

    func fetchRacePlans() {
        guard let apiKey = KeychainService.shared.getAPIKey() else {
            errorMessage = "API key not found. Please configure your API key."
            return
        }

        guard let selectedEvent = selectedEvent else {
            errorMessage = "No event selected. Please select an event first."
            return
        }

        guard let url = URL(string: "https://events.motion.rs/api/race-results/fetch-plans?event_id=\(selectedEvent.id)") else {
            errorMessage = "Invalid API endpoint URL"
            return
        }

        isLoading = true
        errorMessage = nil

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTaskPublisher(for: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Network error: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] dataResponse in
                    let data = dataResponse.data
                    let response = dataResponse.response

                    // Log response details
                    if let httpResponse = response as? HTTPURLResponse {
                        print("=== RACE PLAN API RESPONSE DETAILS ===")
                        print("Status Code: \(httpResponse.statusCode)")
                        print("Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
                        print("URL: \(httpResponse.url?.absoluteString ?? "unknown")")
                        print("=======================================")
                    }

                    // Log raw API response
                    if let rawString = String(data: data, encoding: .utf8) {
                        print("=== RAW RACE PLAN API RESPONSE ===")
                        print(rawString)
                        print("==================================")
                    }

                    do {
                        let decoder = JSONDecoder()
                        decoder.keyDecodingStrategy = .convertFromSnakeCase
                        let response = try decoder.decode(ApiResponse.self, from: data)

                        if response.success {
                            switch response.data {
                            case .racePlan(let racePlan):
                                self?.availableRacePlan = racePlan
                                self?.saveCachedRacePlans()
                                self?.errorMessage = nil

                                // If there's a selected race, trigger UI refresh
                                if self?.selectedRace != nil {
                                    self?.shouldRefreshRaceData = true
                                }
                            case .empty:
                                self?.availableRacePlan = nil
                                self?.errorMessage = "No race data found"
                            }
                        } else {
                            self?.availableRacePlan = nil
                            self?.errorMessage = response.message ?? "Unknown API error"
                        }

                    } catch {
                        // More detailed error for debugging
                        if let decodingError = error as? DecodingError {
                            switch decodingError {
                            case .typeMismatch(let type, let context):
                                self?.errorMessage = "Type mismatch for \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
                            case .valueNotFound(let type, let context):
                                self?.errorMessage = "Value not found for \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
                            case .keyNotFound(let key, let context):
                                self?.errorMessage = "Key '\(key.stringValue)' not found at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
                            case .dataCorrupted(let context):
                                self?.errorMessage = "Data corrupted at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
                            @unknown default:
                                self?.errorMessage = "Decoding error: \(error.localizedDescription)"
                            }
                        } else {
                            self?.errorMessage = "Failed to parse API response: \(error.localizedDescription)"
                        }
                    }
                }
            )
            .store(in: &cancellables)
    }

    func fetchEvents() {
        guard let url = URL(string: "https://events.motion.rs/api/events") else {
            errorMessage = "Invalid events endpoint URL"
            return
        }

        isLoading = true
        errorMessage = nil

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTaskPublisher(for: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = "Network error fetching events: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] dataResponse in
                    let data = dataResponse.data
                    let response = dataResponse.response

                    // Log response details
                    if let httpResponse = response as? HTTPURLResponse {
                        print("=== EVENTS API RESPONSE DETAILS ===")
                        print("Status Code: \(httpResponse.statusCode)")
                        print("Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
                        print("URL: \(httpResponse.url?.absoluteString ?? "unknown")")
                        print("===================================")
                    }

                    // Log raw API response
                    if let rawString = String(data: data, encoding: .utf8) {
                        print("=== RAW EVENTS API RESPONSE ===")
                        print(rawString)
                        print("===============================")
                    }

                    do {
                        let decoder = JSONDecoder()
                        decoder.keyDecodingStrategy = .convertFromSnakeCase
                        let events = try decoder.decode([Event].self, from: data)

                        self?.availableEvents = events
                        self?.errorMessage = nil

                        // Auto-select the last event
                        if let lastEvent = events.last {
                            self?.selectedEvent = lastEvent
                        }

                    } catch {
                        print("Events parsing error: \(error)")
                        self?.errorMessage = "Failed to parse events: \(error.localizedDescription)"
                    }
                }
            )
            .store(in: &cancellables)
    }

    func selectEvent(_ event: Event) {
        selectedEvent = event
        // Clear race plan when selecting a different event
        availableRacePlan = nil
        selectedRace = nil
    }

    func selectRace(_ race: Race) {
        selectedRace = race
    }

    func saveAPIKey(_ apiKey: String) -> Bool {
        return KeychainService.shared.saveAPIKey(apiKey)
    }

    func hasAPIKey() -> Bool {
        return KeychainService.shared.getAPIKey() != nil
    }

    func submitRaceResults(sessionData: SessionData, finishEvents: [FinishEvent], completion: @escaping (Result<String, Error>) -> Void) {
        guard let apiKey = KeychainService.shared.getAPIKey() else {
            completion(.failure(NSError(domain: "RacePlanService", code: 1, userInfo: [NSLocalizedDescriptionKey: "API key not found"])))
            return
        }

        guard let raceId = sessionData.raceId else {
            completion(.failure(NSError(domain: "RacePlanService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Race ID not found. Can only submit results for races loaded from race plans."])))
            return
        }

        guard let url = URL(string: "https://events.motion.rs/api/race-results/update-single") else {
            completion(.failure(NSError(domain: "RacePlanService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid API endpoint URL"])))
            return
        }

        // Build the request payload
        let requestData = buildSingleUpdatePayload(sessionData: sessionData, finishEvents: finishEvents, raceId: raceId)

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestData, options: .prettyPrinted)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData

            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async { [weak self] in
                    // Log response details
                    if let httpResponse = response as? HTTPURLResponse {
                        print("=== RESULTS SUBMISSION RESPONSE DETAILS ===")
                        print("Status Code: \(httpResponse.statusCode)")
                        print("Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
                        print("URL: \(httpResponse.url?.absoluteString ?? "unknown")")
                        print("===========================================")
                    }

                    // Log raw response from results submission
                    if let data = data, let rawString = String(data: data, encoding: .utf8) {
                        print("=== RAW RESULTS SUBMISSION RESPONSE ===")
                        print(rawString)
                        print("=======================================")
                    }

                    if let error = error {
                        completion(.failure(error))
                        return
                    }

                    if let httpResponse = response as? HTTPURLResponse {
                        if httpResponse.statusCode == 200 {
                            // Update internal race data after successful submission
                            self?.updateInternalRaceData(sessionData: sessionData, finishEvents: finishEvents)
                            completion(.success("Race results submitted successfully"))
                        } else {
                            let errorMsg = "Server returned status code: \(httpResponse.statusCode)"
                            completion(.failure(NSError(domain: "RacePlanService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                        }
                    }
                }
            }.resume()

        } catch {
            completion(.failure(error))
        }
    }

    private func buildSingleUpdatePayload(sessionData: SessionData, finishEvents: [FinishEvent], raceId: Int) -> [String: Any] {
        // Build lanes dictionary for the new API format
        var lanes: [String: [String: Any]] = [:]

        // Add all teams from session data
        for (index, teamName) in sessionData.teamNames.enumerated() {
            guard !teamName.isEmpty else { continue } // Skip empty lanes

            let laneNumber = String(index + 1)
            var laneData: [String: Any] = ["team": teamName]

            // Find finish event for this team
            if let finishEvent = finishEvents.first(where: { $0.label == teamName }) {
                switch finishEvent.status {
                case .finished:
                    // Convert seconds back to MM:SS.mmm format
                    let minutes = Int(finishEvent.tRace) / 60
                    let seconds = finishEvent.tRace.truncatingRemainder(dividingBy: 60)
                    laneData["time"] = String(format: "%d:%06.3f", minutes, seconds)
                case .dns:
                    laneData["time"] = "DNS"
                case .dnf:
                    laneData["time"] = "DNF"
                case .dsq:
                    laneData["time"] = "DSQ"
                default:
                    break // No time for registered status
                }
            }

            lanes[laneNumber] = laneData
        }

        // Build the new simplified payload format
        return [
            "race_id": raceId,
            "status": determineRaceStatus(finishEvents: finishEvents),
            "lanes": lanes
        ]
    }

    private func extractRaceNumber(from raceName: String) -> Int {
        // Try to extract race number from race name like "1 - Small Senior B Mixed 200m"
        let components = raceName.components(separatedBy: " - ")
        if let firstComponent = components.first,
           let raceNumber = Int(firstComponent.trimmingCharacters(in: .whitespaces)) {
            return raceNumber
        }
        return 1 // Default fallback
    }

    private func determineRaceStatus(finishEvents: [FinishEvent]) -> String {
        return finishEvents.isEmpty ? "SCHEDULED" : "FINISHED"
    }

    private func extractDisciplineInfo(from raceName: String) -> String {
        // Extract discipline info from race name - fallback to race name
        return raceName.contains(" - ") ? String(raceName.split(separator: " - ").last ?? "") : raceName
    }

    private func extractBoatSize(from raceName: String) -> String {
        if raceName.lowercased().contains("small") {
            return "Small boat"
        } else if raceName.lowercased().contains("big") {
            return "Big boat"
        }
        return "Small boat" // Default fallback
    }

    private func updateInternalRaceData(sessionData: SessionData, finishEvents: [FinishEvent]) {
        guard let raceId = sessionData.raceId,
              let racePlan = availableRacePlan else { return }

        // Find and update the race in the race plan
        var updatedRaces = racePlan.races
        guard let raceIndex = updatedRaces.firstIndex(where: { $0.id == raceId }) else { return }

        // Update lanes with the submitted results
        var updatedLanes = updatedRaces[raceIndex].lanes

        for (index, teamName) in sessionData.teamNames.enumerated() {
            guard !teamName.isEmpty else { continue }

            let laneNumber = index + 1

            // Find the lane in the existing data
            if let laneIndex = updatedLanes.firstIndex(where: { $0.lane == laneNumber }) {
                // Update existing lane
                var updatedLane = updatedLanes[laneIndex]

                // Find finish event for this team
                if let finishEvent = finishEvents.first(where: { $0.label == teamName }) {
                    switch finishEvent.status {
                    case .finished:
                        let minutes = Int(finishEvent.tRace) / 60
                        let seconds = finishEvent.tRace.truncatingRemainder(dividingBy: 60)
                        updatedLane = Lane(lane: updatedLane.lane, team: updatedLane.team, crewId: updatedLane.crewId,
                                         time: String(format: "%d:%06.3f", minutes, seconds), status: "FINISHED", position: updatedLane.position)
                    case .dns:
                        updatedLane = Lane(lane: updatedLane.lane, team: updatedLane.team, crewId: updatedLane.crewId,
                                         time: "DNS", status: "DNS", position: updatedLane.position)
                    case .dnf:
                        updatedLane = Lane(lane: updatedLane.lane, team: updatedLane.team, crewId: updatedLane.crewId,
                                         time: "DNF", status: "DNF", position: updatedLane.position)
                    case .dsq:
                        updatedLane = Lane(lane: updatedLane.lane, team: updatedLane.team, crewId: updatedLane.crewId,
                                         time: "DSQ", status: "DSQ", position: updatedLane.position)
                    default:
                        break
                    }
                    updatedLanes[laneIndex] = updatedLane
                }
            }
        }

        // Update the race with new lanes data
        let updatedRace = Race(id: updatedRaces[raceIndex].id, raceNumber: updatedRaces[raceIndex].raceNumber,
                              stage: updatedRaces[raceIndex].stage, disciplineId: updatedRaces[raceIndex].disciplineId,
                              disciplineInfo: updatedRaces[raceIndex].disciplineInfo, boatSize: updatedRaces[raceIndex].boatSize,
                              raceTime: updatedRaces[raceIndex].raceTime,
                              status: finishEvents.isEmpty ? updatedRaces[raceIndex].status : "FINISHED",
                              lanes: updatedLanes, title: updatedRaces[raceIndex].title,
                              createdAt: updatedRaces[raceIndex].createdAt, updatedAt: updatedRaces[raceIndex].updatedAt)

        updatedRaces[raceIndex] = updatedRace

        // Update the race plan
        let updatedRacePlan = RacePlan(eventId: racePlan.eventId, eventName: racePlan.eventName,
                                      raceCount: racePlan.raceCount, races: updatedRaces)
        availableRacePlan = updatedRacePlan

        // Save updated race plan to cache
        saveCachedRacePlans()

        print("✅ Internal race data updated for race ID \(raceId)")
    }

    func clearRacePlans() {
        availableRacePlan = nil
        selectedRace = nil
        errorMessage = nil

        // Remove cached file
        try? FileManager.default.removeItem(at: racePlanCacheURL)
    }

    private func saveCachedRacePlans() {
        guard let racePlan = availableRacePlan else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(racePlan)
            try data.write(to: racePlanCacheURL)
        } catch {
            print("Failed to cache race plans: \(error)")
        }
    }

    private func loadCachedRacePlans() {
        do {
            let data = try Data(contentsOf: racePlanCacheURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            availableRacePlan = try decoder.decode(RacePlan.self, from: data)
        } catch {
            // Cache file doesn't exist or is invalid - that's ok
            availableRacePlan = nil
        }
    }

    func submitRaceResultsWithImages(raceId: Int, sessionData: SessionData, finishEvents: [FinishEvent], imagePaths: [String], completion: @escaping (Result<String, Error>) -> Void) {
        guard let apiKey = KeychainService.shared.getAPIKey() else {
            completion(.failure(NSError(domain: "RacePlanService", code: 1, userInfo: [NSLocalizedDescriptionKey: "API key not found"])))
            return
        }

        guard let url = URL(string: "https://events.motion.rs/api/race-results/update-single") else {
            completion(.failure(NSError(domain: "RacePlanService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid API endpoint URL"])))
            return
        }

        // Create multipart form data request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add race_id field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"race_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(raceId)\r\n".data(using: .utf8)!)

        // Add status field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"status\"\r\n\r\n".data(using: .utf8)!)
        body.append("FINISHED\r\n".data(using: .utf8)!)

        // Add lanes data
        for (index, teamName) in sessionData.teamNames.enumerated() {
            guard !teamName.isEmpty else { continue }

            let laneIndex = index

            // Add team name
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"lanes[\(laneIndex)][team]\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(teamName)\r\n".data(using: .utf8)!)

            // Add race time if available
            if let finishEvent = finishEvents.first(where: { $0.label == teamName }) {
                let timeString: String
                switch finishEvent.status {
                case .finished:
                    let minutes = Int(finishEvent.tRace) / 60
                    let seconds = finishEvent.tRace.truncatingRemainder(dividingBy: 60)
                    timeString = String(format: "%02d:%06.3f", minutes, seconds)
                case .dns:
                    timeString = "DNS"
                case .dnf:
                    timeString = "DNF"
                case .dsq:
                    timeString = "DSQ"
                case .registered:
                    timeString = "" // No time for registered status
                }

                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"lanes[\(laneIndex)][time]\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(timeString)\r\n".data(using: .utf8)!)
            }
        }

        // Add image files
        print("📸 Processing \(imagePaths.count) image paths:")
        for (index, imagePath) in imagePaths.enumerated() {
            print("  [\(index + 1)] Path: \(imagePath)")

            let imageURL = URL(fileURLWithPath: imagePath)
            print("  [\(index + 1)] File exists: \(FileManager.default.fileExists(atPath: imagePath))")

            guard let imageData = try? Data(contentsOf: imageURL) else {
                print("  ❌ [\(index + 1)] ERROR: Could not read image at path: \(imagePath)")
                continue
            }

            let filename = imageURL.lastPathComponent
            let mimeType = getMimeType(for: imageURL.pathExtension)

            print("  ✅ [\(index + 1)] Image loaded: \(filename), size: \(imageData.count) bytes, type: \(mimeType)")

            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"images[]\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        }

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        print("=== SUBMITTING RACE RESULTS WITH IMAGES ===")
        print("Race ID: \(raceId)")
        print("Images: \(imagePaths.count)")
        print("Lanes: \(sessionData.teamNames.filter { !$0.isEmpty }.count)")
        print("Endpoint: \(url.absoluteString)")
        print("Request body size: \(body.count) bytes")
        print("Content-Type: multipart/form-data; boundary=\(boundary)")
        print("API Key: \(apiKey.prefix(10))...") // Show first 10 chars only for security
        print("Headers: X-API-Key = \(apiKey.isEmpty ? "EMPTY" : "SET")")
        print("==========================================")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { [weak self] in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    print("=== RACE RESULTS SUBMISSION RESPONSE ===")
                    print("Status Code: \(httpResponse.statusCode)")
                    print("Headers: \(httpResponse.allHeaderFields)")

                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        print("Response Body: \(responseString)")
                    }
                    print("========================================")

                    if httpResponse.statusCode == 200 {
                        // Update internal race data after successful submission
                        self?.updateInternalRaceData(sessionData: sessionData, finishEvents: finishEvents)
                        completion(.success("Race results and images submitted successfully"))
                    } else {
                        let errorMsg = "Server returned status code: \(httpResponse.statusCode)"
                        completion(.failure(NSError(domain: "RacePlanService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                    }
                }
            }
        }.resume()
    }

    private func getMimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        default:
            return "image/jpeg"
        }
    }
}

// Response models for API parsing
private struct ApiResponse: Codable {
    let success: Bool
    let data: ApiData
    let message: String?
}

private enum ApiData: Codable {
    case racePlan(RacePlan)
    case empty([String]) // For error case with empty array

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try to decode as array first (error case)
        if let emptyArray = try? container.decode([String].self) {
            self = .empty(emptyArray)
            return
        }

        // Try to decode as RacePlan (success case)
        if let racePlan = try? container.decode(RacePlan.self) {
            self = .racePlan(racePlan)
            return
        }

        throw DecodingError.typeMismatch(ApiData.self,
            DecodingError.Context(codingPath: decoder.codingPath,
            debugDescription: "Expected RacePlan or empty array"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .racePlan(let racePlan):
            try container.encode(racePlan)
        case .empty(let array):
            try container.encode(array)
        }
    }
}

extension Event: Codable, Identifiable {
    enum CodingKeys: String, CodingKey {
        case id, name, location, year, status
    }
}

extension RacePlan: Codable, Identifiable {
    var id: String { eventId }  // eventId is already a string

    enum CodingKeys: String, CodingKey {
        case eventId, eventName, raceCount, races
    }
}

extension Race: Codable, Identifiable {
    enum CodingKeys: String, CodingKey {
        case id, raceNumber, stage, disciplineId, disciplineInfo, boatSize, raceTime, status, lanes, title, createdAt, updatedAt
    }
}

extension Lane: Codable, Identifiable {
    var id: String { "\(lane)_\(team)" }

    enum CodingKeys: String, CodingKey {
        case lane, team, crewId, time, status, position
    }
}