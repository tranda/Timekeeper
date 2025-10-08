import AVFoundation
import AppKit

class CaptureManager: NSObject, ObservableObject {
    @Published var availableDevices: [AVCaptureDevice] = []
    @Published var selectedDevice: AVCaptureDevice?
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

        // Listen for camera switch notifications from Settings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCameraSwitchRequest(_:)),
            name: NSNotification.Name("CameraSwitchRequested"),
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

        // Since iPhone cameras don't provide portrait formats, use HD landscape and rotate
        // Use 1080p if available for best quality
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
            print("Using HD 1920x1080 preset - will rotate to portrait")
        } else if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
            print("Using HD 1280x720 preset - will rotate to portrait")
        } else {
            session.sessionPreset = .high
            print("Using high preset - will rotate to portrait")
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

        let outputFolder = folder ?? outputDirectory ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory

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