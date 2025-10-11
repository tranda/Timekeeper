import AVFoundation
import AppKit

struct VideoQuality: Equatable, Hashable {
    let preset: AVCaptureSession.Preset?
    let format: AVCaptureDevice.Format?
    let displayName: String
    let dimensions: String
    let frameRate: String

    // Unique identifier combining display name and frame rate
    var uniqueID: String {
        return "\(displayName) @ \(frameRate)"
    }

    // Standard presets
    static let standardPresets: [VideoQuality] = [
        VideoQuality(preset: .hd4K3840x2160, format: nil, displayName: "4K UHD", dimensions: "3840×2160", frameRate: "30fps"),
        VideoQuality(preset: .hd1920x1080, format: nil, displayName: "HD 1080p", dimensions: "1920×1080", frameRate: "30fps"),
        VideoQuality(preset: .hd1280x720, format: nil, displayName: "HD 720p", dimensions: "1280×720", frameRate: "30fps"),
        VideoQuality(preset: .high, format: nil, displayName: "High", dimensions: "Device dependent", frameRate: "30fps"),
        VideoQuality(preset: .medium, format: nil, displayName: "Medium", dimensions: "Device dependent", frameRate: "30fps"),
        VideoQuality(preset: .low, format: nil, displayName: "Low", dimensions: "Device dependent", frameRate: "30fps")
    ]

    // Create from device format
    static func fromFormat(_ format: AVCaptureDevice.Format, preferredFrameRate: Double = 30.0) -> VideoQuality {
        let description = format.formatDescription
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)

        // Use the exact preferred frame rate instead of finding the "best"
        let actualFrameRate = preferredFrameRate
        let frameRateString = "\(Int(actualFrameRate))fps"

        let displayName: String
        switch (width, height) {
        case (3840, 2160):
            displayName = "4K UHD"
        case (1920, 1080):
            displayName = "HD 1080p"
        case (1920, 1440):
            displayName = "HD 1080p+"  // iPhone specific format
        case (1280, 720):
            displayName = "HD 720p"
        case (640, 480):
            displayName = "SD 480p"
        default:
            displayName = "Custom"
        }

        return VideoQuality(
            preset: nil,
            format: format,
            displayName: displayName,
            dimensions: "\(width)×\(height)",
            frameRate: frameRateString
        )
    }

    static func == (lhs: VideoQuality, rhs: VideoQuality) -> Bool {
        if let lhsPreset = lhs.preset, let rhsPreset = rhs.preset {
            return lhsPreset.rawValue == rhsPreset.rawValue && lhs.frameRate == rhs.frameRate
        }
        return lhs.displayName == rhs.displayName && lhs.dimensions == rhs.dimensions && lhs.frameRate == rhs.frameRate
    }

    func hash(into hasher: inout Hasher) {
        if let preset = preset {
            hasher.combine(preset.rawValue)
        } else {
            hasher.combine(displayName)
            hasher.combine(dimensions)
        }
        hasher.combine(frameRate)
    }
}

class CaptureManager: NSObject, ObservableObject {
    @Published var availableDevices: [AVCaptureDevice] = []
    @Published var selectedDevice: AVCaptureDevice?
    @Published var availableQualities: [VideoQuality] = []
    @Published var selectedQuality: VideoQuality = VideoQuality.standardPresets[1] // Default to HD 1080p
    @Published var isRecording = false
    @Published var outputDirectory: URL? {
        didSet {
            // Save to UserDefaults whenever the output directory changes
            if let url = outputDirectory {
                UserDefaults.standard.set(url.path, forKey: "outputDirectory")
                print("💾 Saved output directory: \(url.path)")
            }
        }
    }
    @Published var lastRecordedURL: URL?
    @Published var isSessionRunning = false
    @Published var captureSession: AVCaptureSession?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var currentDeviceInput: AVCaptureDeviceInput?
    private var stopRecordingCompletion: ((URL?) -> Void)?

    // Add a serial queue for session operations
    private let sessionQueue = DispatchQueue(label: "com.timekeeper.sessionQueue")

    @Published var videoStartTime: Date?
    @Published var videoStopTime: Date?
    var timingModel: RaceTimingModel?
    private var recordButtonClickTime: Date?  // Track when record button was clicked


    override init() {
        super.init()

        // Load saved output directory from UserDefaults
        if let savedPath = UserDefaults.standard.string(forKey: "outputDirectory") {
            let savedURL = URL(fileURLWithPath: savedPath)
            // Verify the directory still exists
            if FileManager.default.fileExists(atPath: savedPath) {
                outputDirectory = savedURL
                print("📂 Loaded saved output directory: \(savedPath)")
            } else {
                print("⚠️ Saved output directory no longer exists: \(savedPath)")
                // Fallback to Desktop
                outputDirectory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            }
        } else {
            // Default to Desktop
            outputDirectory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            print("📂 Using default output directory: Desktop")
        }

        // Don't refresh devices here - let ContentView do it after setup
        // But we can load the saved camera device ID for later use
        loadSavedCameraDevice()
        // Video quality will be loaded when device formats are detected

        // Listen for camera switch notifications from Settings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCameraSwitchRequest(_:)),
            name: NSNotification.Name("CameraSwitchRequested"),
            object: nil
        )

        // Listen for video quality change notifications from Settings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVideoQualityChange(_:)),
            name: NSNotification.Name("VideoQualityChanged"),
            object: nil
        )
    }

    private func loadSavedCameraDevice() {
        // Load and auto-select the saved camera device when devices are available
        if let savedDeviceID = UserDefaults.standard.string(forKey: "selectedCameraDevice") {
            print("📹 Saved camera device ID: \(savedDeviceID)")
            // Will be applied when refreshDevices() is called
        }
    }


    func saveVideoQuality(_ quality: VideoQuality) {
        selectedQuality = quality
        UserDefaults.standard.set(quality.uniqueID, forKey: "selectedVideoQuality")
        print("💾 Saved video quality: \(quality.uniqueID)")
    }

    func detectAvailableQualities(for device: AVCaptureDevice) {
        print("=== DEVICE FORMAT ANALYSIS ===")
        print("Device: \(device.localizedName)")
        print("Device type: \(device.deviceType.rawValue)")
        print("Available formats: \(device.formats.count)")

        // Log all available formats to understand device capabilities
        for (index, format) in device.formats.enumerated() {
            let description = format.formatDescription
            let dimensions = CMVideoFormatDescriptionGetDimensions(description)
            let mediaSubType = CMFormatDescriptionGetMediaSubType(description)

            let codecString = String(format: "%c%c%c%c",
                (mediaSubType >> 24) & 0xff,
                (mediaSubType >> 16) & 0xff,
                (mediaSubType >> 8) & 0xff,
                mediaSubType & 0xff)

            print("Format \(index): \(dimensions.width)x\(dimensions.height) (\(codecString))")

            // Check supported frame rates for this format
            let frameRateRanges = format.videoSupportedFrameRateRanges
            for range in frameRateRanges {
                print("  Frame rates: \(range.minFrameRate)-\(range.maxFrameRate) fps")
            }
        }
        print("===============================")

        var qualities: [VideoQuality] = []

        // Group formats by resolution and frame rate combinations
        var formatsByResolutionAndFrameRate: [String: AVCaptureDevice.Format] = [:]

        for format in device.formats {
            let description = format.formatDescription
            let dimensions = CMVideoFormatDescriptionGetDimensions(description)

            // Get all common frame rates supported by this format
            let frameRateRanges = format.videoSupportedFrameRateRanges
            let commonFrameRates: [Double] = [30.0, 60.0] // Common frame rates we want to support

            for targetFrameRate in commonFrameRates {
                // Check if this format supports the target frame rate
                if let range = frameRateRanges.first(where: { range in
                    targetFrameRate >= range.minFrameRate && targetFrameRate <= range.maxFrameRate
                }) {
                    let key = "\(dimensions.width)x\(dimensions.height)@\(Int(targetFrameRate))"

                    // Only store this format if we don't have one yet, OR if this one is better
                    // Better = maxFrameRate is closer to our target (prefer 60fps format for 60fps target)
                    if let existingFormat = formatsByResolutionAndFrameRate[key],
                       let existingRange = existingFormat.videoSupportedFrameRateRanges.first {
                        // Prefer format whose max frame rate matches our target
                        if abs(range.maxFrameRate - targetFrameRate) < abs(existingRange.maxFrameRate - targetFrameRate) {
                            formatsByResolutionAndFrameRate[key] = format
                        }
                    } else {
                        formatsByResolutionAndFrameRate[key] = format
                    }
                }
            }
        }

        // Create VideoQuality objects from each resolution/frame rate combination
        let sortedKeys = formatsByResolutionAndFrameRate.keys.sorted { key1, key2 in
            // Extract resolution for sorting
            let components1 = key1.split(separator: "@")
            let components2 = key2.split(separator: "@")

            if let res1 = components1.first, let res2 = components2.first {
                let dim1 = res1.split(separator: "x")
                let dim2 = res2.split(separator: "x")

                if dim1.count == 2, dim2.count == 2,
                   let w1 = Int(dim1[0]), let h1 = Int(dim1[1]),
                   let w2 = Int(dim2[0]), let h2 = Int(dim2[1]) {
                    let area1 = w1 * h1
                    let area2 = w2 * h2

                    // Sort by area first, then by frame rate
                    if area1 != area2 {
                        return area1 > area2
                    } else {
                        // Same resolution, sort by frame rate (higher first)
                        if let fps1 = Int(components1.last ?? "0"),
                           let fps2 = Int(components2.last ?? "0") {
                            return fps1 > fps2
                        }
                    }
                }
            }
            return false
        }

        for key in sortedKeys {
            if let format = formatsByResolutionAndFrameRate[key] {
                let components = key.split(separator: "@")
                if let frameRateStr = components.last, let frameRate = Double(frameRateStr) {
                    let quality = VideoQuality.fromFormat(format, preferredFrameRate: frameRate)
                    qualities.append(quality)
                    print("✅ Available quality: \(quality.displayName) (\(quality.dimensions)) @ \(quality.frameRate)")
                }
            }
        }

        DispatchQueue.main.async {
            self.availableQualities = qualities

            // Try to match saved quality preference first
            let savedQualityID = UserDefaults.standard.string(forKey: "selectedVideoQuality")
            var qualityChanged = false

            if let savedID = savedQualityID,
               let matchingQuality = qualities.first(where: { $0.uniqueID == savedID }) {
                self.selectedQuality = matchingQuality
                qualityChanged = true
                print("🔄 Restored saved quality preference: \(matchingQuality.uniqueID)")
            } else if let currentQualityID = self.selectedQuality.uniqueID as String?,
                      let matchingQuality = qualities.first(where: { $0.uniqueID == currentQualityID }) {
                self.selectedQuality = matchingQuality
                qualityChanged = true
                print("🔄 Updated to device-specific format for: \(matchingQuality.uniqueID)")
            } else if let bestQuality = qualities.first {
                self.selectedQuality = bestQuality
                qualityChanged = true
                print("🔄 Switched to best available quality: \(bestQuality.uniqueID)")
            }

            // Reconfigure session with the new format-based quality
            if qualityChanged, let device = self.selectedDevice {
                self.sessionQueue.async { [weak self] in
                    self?.configureSession(device: device) { success in
                        if success {
                            print("✅ Reconfigured session with format-based quality")
                            self?.startSessionIfNeeded()
                        } else {
                            print("❌ Failed to reconfigure session with format-based quality")
                        }
                    }
                }
            }

            // Notify SettingsView about available qualities
            NotificationCenter.default.post(
                name: NSNotification.Name("AvailableQualitiesUpdated"),
                object: qualities
            )
        }
    }

    private func positionString(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .front: return "Front"
        case .back: return "Back"
        case .unspecified: return "Unspecified"
        @unknown default: return "Unknown"
        }
    }

    func refreshDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .externalUnknown
            ],
            mediaType: .video,
            position: .unspecified
        )

        let devices = Array(discoverySession.devices)
        print("=== CAMERA DEVICE DISCOVERY DEBUG ===")
        print("Total devices found: \(devices.count)")
        for device in devices {
            print("  - Name: \(device.localizedName)")
            print("    ID: \(device.uniqueID)")
            print("    Position: \(device.position.rawValue) (\(positionString(device.position)))")
            print("    Connected: \(device.isConnected)")
            print("    ---")
        }
        print("======================================")

        // Sort devices to prefer back camera - do this before dispatching
        let sortedDevices = devices.sorted { device1, device2 in
            // Back camera (position = 1) comes first
            if device1.position == .back && device2.position != .back {
                return true
            }
            if device1.position != .back && device2.position == .back {
                return false
            }
            // Otherwise maintain original order
            return false
        }

        DispatchQueue.main.async { [weak self] in
            self?.availableDevices = sortedDevices

            print("=== CAMERA AUTO-SELECTION DEBUG ===")
            let savedDeviceID = UserDefaults.standard.string(forKey: "selectedCameraDevice")
            print("Saved device ID: \(savedDeviceID ?? "None")")

            // Auto-select saved device if available, otherwise select first available device
            if let savedDeviceID = savedDeviceID,
               let savedDevice = sortedDevices.first(where: { $0.uniqueID == savedDeviceID }) {
                print("✅ Found saved camera: \(savedDevice.localizedName)")
                print("📹 Auto-selecting saved camera...")
                self?.selectDevice(savedDevice)
            } else if let firstDevice = sortedDevices.first {
                print("⚠️ No saved camera found, using first available")
                print("📹 Auto-selecting first camera: \(firstDevice.localizedName)")
                self?.selectDevice(firstDevice)
                // Save this as the default
                UserDefaults.standard.set(firstDevice.uniqueID, forKey: "selectedCameraDevice")
                print("💾 Saved device ID: \(firstDevice.uniqueID)")
            } else {
                print("❌ No cameras available to select")
            }
            print("===================================")
        }
    }

    func selectDevice(_ device: AVCaptureDevice) {
        print("Selecting device: \(device.localizedName) - ID: \(device.uniqueID)")

        // Set selectedDevice on main queue, avoiding deadlock if already on main queue
        if Thread.isMainThread {
            selectedDevice = device
            print("📱 Device set as selectedDevice: \(device.localizedName) (main thread)")
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.selectedDevice = device
                print("📱 Device set as selectedDevice: \(device.localizedName) (sync to main)")
            }
        }

        // Use the serial queue for session configuration
        sessionQueue.async { [weak self] in
            print("🔧 Starting session configuration on session queue...")
            self?.configureSession(device: device) { success in
                if success {
                    print("Successfully configured session for: \(device.localizedName)")
                    // Detect available qualities for this device
                    self?.detectAvailableQualities(for: device)
                    self?.startSessionIfNeeded()
                } else {
                    print("Failed to configure session for: \(device.localizedName)")
                }
            }
        }
    }

    func pickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Output Directory"

        if panel.runModal() == .OK {
            outputDirectory = panel.url
        }
    }

    func configureSession(device: AVCaptureDevice, completion: @escaping (Bool) -> Void) {
        print("🔧 ConfigureSession called with device: \(device.localizedName)")

        print("=== SESSION CONFIGURATION DEBUG ===")
        print("🔧 Configuring session with device: \(device.localizedName)")
        print("🔧 Device ID: \(device.uniqueID)")
        print("🔧 Device connected: \(device.isConnected)")

        // Create session if needed - do this synchronously to avoid race conditions
        if captureSession == nil {
            let newSession = AVCaptureSession()
            DispatchQueue.main.sync {
                self.captureSession = newSession
                self.objectWillChange.send()
            }
        }

        guard let session = captureSession else {
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }

        session.beginConfiguration()

        if let currentInput = currentDeviceInput {
            session.removeInput(currentInput)
            currentDeviceInput = nil
        }

        if let currentOutput = movieFileOutput {
            session.removeOutput(currentOutput)
            movieFileOutput = nil
        }

        // Configure video quality - use format if available, otherwise preset
        // NOTE: Continuity Camera devices don't support setting activeFormat directly
        // Check if this is a Continuity Camera device (external type)
        let isContinuityCameraDevice = device.deviceType == .externalUnknown

        if let format = selectedQuality.format, !isContinuityCameraDevice {
            // Use direct format selection for best quality control (only for non-Continuity Camera devices)
            // Set both format AND frame rate together before adding to session
            do {
                try device.lockForConfiguration()

                // Set the format first
                device.activeFormat = format

                // Set frame rate immediately after format, while device is still locked
                if let frameRate = Double(selectedQuality.frameRate.replacingOccurrences(of: "fps", with: "")) {
                    let frameDuration = CMTimeMake(value: 1, timescale: Int32(frameRate))
                    device.activeVideoMinFrameDuration = frameDuration
                    device.activeVideoMaxFrameDuration = frameDuration
                }

                device.unlockForConfiguration()
                print("✅ Set device format: \(selectedQuality.displayName) (\(selectedQuality.dimensions)) @ \(selectedQuality.frameRate)")
            } catch {
                print("❌ Failed to set format and frame rate: \(error)")
                // Fallback to preset mode
                session.sessionPreset = .high
                print("Fallback to high preset")
            }
        } else {
            // For Continuity Camera or preset-based quality, use session presets
            // Continuity Camera doesn't support activeFormat, so we must use presets
            if isContinuityCameraDevice {
                print("⚠️ Continuity Camera detected - using preset mode (activeFormat not supported)")
            }

            if let preset = selectedQuality.preset {
                // Use preset-based configuration
                if session.canSetSessionPreset(preset) {
                    session.sessionPreset = preset
                    print("✅ Using preset: \(selectedQuality.displayName) (\(selectedQuality.dimensions))")
                } else {
                    // Fallback to the best available preset
                    var fallbackPreset: AVCaptureSession.Preset = .high
                    for quality in VideoQuality.standardPresets {
                        if let qualityPreset = quality.preset, session.canSetSessionPreset(qualityPreset) {
                            fallbackPreset = qualityPreset
                            break
                        }
                    }
                    session.sessionPreset = fallbackPreset
                    print("❌ Selected preset not available, using fallback: \(fallbackPreset.rawValue)")
                }
            } else {
                // No preset available, use high quality preset as fallback
                session.sessionPreset = .high
                print("⚠️ Using .high preset as fallback for Continuity Camera")
            }
        }

        do {
            print("🔧 Creating device input...")
            let deviceInput = try AVCaptureDeviceInput(device: device)
            print("✅ Device input created successfully")

            if session.canAddInput(deviceInput) {
                print("✅ Can add device input to session")
                session.addInput(deviceInput)
                currentDeviceInput = deviceInput
                print("✅ Device input added to session")
            } else {
                print("❌ Cannot add device input to session")
                session.commitConfiguration()
                print("================================")
                completion(false)
                return
            }

            print("🔧 Creating movie output...")
            let movieOutput = AVCaptureMovieFileOutput()
            movieOutput.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 1)
            print("✅ Movie output created")

            if session.canAddOutput(movieOutput) {
                print("✅ Can add movie output to session")
                session.addOutput(movieOutput)
                movieFileOutput = movieOutput
                print("✅ Movie output added to session")

                if let connection = movieOutput.connection(with: .video) {
                    // Check current dimensions
                    let formatDescription = device.activeFormat.formatDescription
                    let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
                    print("Active format dimensions: \(dimensions.width) x \(dimensions.height)")

                    // Keep natural landscape orientation
                    // Don't force portrait - record in the sensor's natural orientation
                    print("Using natural landscape orientation for recording")

                    // Enable mirroring only for front-facing cameras
                    // Back cameras should not be mirrored
                    if device.position == .front {
                        connection.isVideoMirrored = true
                    } else {
                        connection.isVideoMirrored = false
                    }

                    // Video stabilization is only available on iOS
                    #if os(iOS)
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .auto
                    }
                    #endif
                }
            } else {
                print("❌ Cannot add movie output to session")
                session.commitConfiguration()
                print("================================")
                completion(false)
                return
            }

            session.commitConfiguration()
            print("✅ Session configuration completed successfully")
            print("================================")

            DispatchQueue.main.async {
                completion(true)
            }

        } catch {
            print("Error configuring session: \(error)")
            session.commitConfiguration()
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }

    func startSessionIfNeeded() {
        guard let session = captureSession else { return }

        // Use the session queue to avoid concurrent modifications
        sessionQueue.async { [weak self] in
            if !session.isRunning {
                session.startRunning()
                DispatchQueue.main.async { [weak self] in
                    self?.isSessionRunning = true
                    self?.objectWillChange.send()
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.isSessionRunning = true
                }
            }
        }
    }

    func stopSession() {
        guard let session = captureSession else { return }

        sessionQueue.async { [weak self] in
            if session.isRunning {
                session.stopRunning()
                DispatchQueue.main.async { [weak self] in
                    self?.isSessionRunning = false
                }
            }
        }
    }

    func startRecording(to folder: URL? = nil, completion: @escaping (Bool) -> Void) {
        guard let movieOutput = movieFileOutput,
              !isRecording else {
            completion(false)
            return
        }

        // Determine output folder based on race type if folder not explicitly provided
        let outputFolder: URL
        if let explicitFolder = folder {
            outputFolder = explicitFolder
        } else if let eventId = timingModel?.sessionData?.eventId {
            // Event Race - use Event Races directory
            outputFolder = AppConfig.shared.getEventRacesDirectory()
            print("📹 Recording to Event Races directory")
        } else if timingModel?.sessionData != nil {
            // Free Race - use Free Races directory
            outputFolder = AppConfig.shared.getFreeRacesDirectory()
            print("📹 Recording to Free Races directory")
        } else {
            // Fallback to legacy outputDirectory or Desktop
            outputFolder = outputDirectory ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            print("📹 Recording to fallback directory (no race initialized)")
        }

        // Use race name from timing model if available
        let raceName = timingModel?.sessionData?.raceName ?? "Race"
        print("Starting recording with race name: '\(raceName)'")
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "\(raceName)_\(timestamp).mov"
        let fileURL = outputFolder.appendingPathComponent(fileName)
        print("Recording to file: \(fileName)")

        // Keep natural landscape orientation for recording
        // The sensor records in landscape by default

        // Record the start time when we initiate recording
        let recordingInitiatedTime = Date()
        self.recordButtonClickTime = recordingInitiatedTime
        print("RECORD button clicked at: \(recordingInitiatedTime)")

        movieOutput.startRecording(to: fileURL, recordingDelegate: self)

        DispatchQueue.main.async {
            self.isRecording = true
            // Set video start time immediately when we initiate recording
            self.videoStartTime = recordingInitiatedTime
            self.timingModel?.setVideoStartTime(recordingInitiatedTime)
            completion(true)
        }
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard let movieOutput = movieFileOutput,
              isRecording else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        // Store the completion handler to call it when recording actually stops
        self.stopRecordingCompletion = completion

        // Stop recording on a background queue
        DispatchQueue.global(qos: .userInitiated).async {
            movieOutput.stopRecording()
        }

        DispatchQueue.main.async {
            self.isRecording = false
        }
    }

    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.refreshDevices()
                    }
                }
            }
        case .denied, .restricted:
            print("Camera access denied or restricted")
        case .authorized:
            break
        @unknown default:
            break
        }
    }

    @objc private func handleCameraSwitchRequest(_ notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice else {
            print("⚠️ Invalid camera switch notification - no device provided")
            return
        }

        print("🔄 Settings requested camera switch to: \(device.localizedName)")
        selectDevice(device)
    }

    @objc private func handleVideoQualityChange(_ notification: Notification) {
        guard let quality = notification.object as? VideoQuality else {
            print("⚠️ Invalid video quality change notification - no quality provided")
            return
        }

        print("🔄 Settings requested quality change to: \(quality.displayName)")
        saveVideoQuality(quality)

        // Reconfigure the session with the new quality if we have an active device
        if let device = selectedDevice {
            sessionQueue.async { [weak self] in
                self?.configureSession(device: device) { success in
                    if success {
                        print("Successfully reconfigured session with new quality: \(quality.displayName)")
                    } else {
                        print("Failed to reconfigure session with new quality: \(quality.displayName)")
                    }
                }
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension CaptureManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        let actualStartTime = Date()
        print("Recording started: \(fileURL.lastPathComponent)")

        // Calculate and log the delay
        if let clickTime = self.recordButtonClickTime {
            let delay = actualStartTime.timeIntervalSince(clickTime)
            print(">>> Recording startup delay: \(String(format: "%.3f", delay)) seconds (\(Int(delay * 1000))ms)")

            // Don't use this delay for compensation - it's not accurate
            DispatchQueue.main.async {
                self.timingModel?.recordingStartupDelay = 0
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("Recording error: \(error)")
                self.lastRecordedURL = nil
                self.stopRecordingCompletion?(nil)
            } else {
                print("Recording finished: \(outputFileURL.lastPathComponent)")
                self.lastRecordedURL = outputFileURL
                self.videoStopTime = Date()
                self.timingModel?.setVideoStopTime(self.videoStopTime!)

                let outputFolder = self.outputDirectory ?? outputFileURL.deletingLastPathComponent()
                // Session will be saved manually via Save button
                // let raceName = self.timingModel?.sessionData?.raceName ?? "Race"
                // let sessionFileName = "\(raceName).json"
                // let sessionURL = outputFolder.appendingPathComponent(sessionFileName)
                // self.timingModel?.saveSession(to: sessionURL)

                self.stopRecordingCompletion?(outputFileURL)
            }
            self.stopRecordingCompletion = nil
        }
    }
}