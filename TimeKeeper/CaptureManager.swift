import AVFoundation
import AppKit

class CaptureManager: NSObject, ObservableObject {
    @Published var availableDevices: [AVCaptureDevice] = []
    @Published var selectedDevice: AVCaptureDevice?
    @Published var isRecording = false
    @Published var outputDirectory: URL? = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    @Published var lastRecordedURL: URL?
    @Published var isSessionRunning = false
    @Published var captureSession: AVCaptureSession?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var currentDeviceInput: AVCaptureDeviceInput?
    private var stopRecordingCompletion: ((URL?) -> Void)?

    // Add a serial queue for session operations
    private let sessionQueue = DispatchQueue(label: "com.timekeeper.sessionQueue")

    var videoStartTime: Date?
    var videoStopTime: Date?
    var timingModel: RaceTimingModel?
    private var recordButtonClickTime: Date?  // Track when record button was clicked


    override init() {
        super.init()
        // Don't refresh devices here - let ContentView do it after setup
    }

    func refreshDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )

        let devices = Array(discoverySession.devices)
        print("Found devices:")
        for device in devices {
            print("  - \(device.localizedName): \(device.uniqueID) [Position: \(device.position.rawValue)]")
        }

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
        }
    }

    func selectDevice(_ device: AVCaptureDevice) {
        print("Selecting device: \(device.localizedName) - ID: \(device.uniqueID)")
        DispatchQueue.main.async { [weak self] in
            self?.selectedDevice = device
        }

        // Use the serial queue for session configuration
        sessionQueue.async { [weak self] in
            self?.configureSession { success in
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

    func configureSession(completion: @escaping (Bool) -> Void) {
        guard let device = selectedDevice else {
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }

        print("Configuring session with device: \(device.localizedName)")

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
            let deviceInput = try AVCaptureDeviceInput(device: device)

            if session.canAddInput(deviceInput) {
                session.addInput(deviceInput)
                currentDeviceInput = deviceInput
            } else {
                session.commitConfiguration()
                completion(false)
                return
            }

            let movieOutput = AVCaptureMovieFileOutput()
            movieOutput.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 1)

            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
                movieFileOutput = movieOutput

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
            }

                session.commitConfiguration()

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
                let raceName = self.timingModel?.sessionData?.raceName ?? "Race"
                let sessionFileName = "\(raceName).json"
                let sessionURL = outputFolder.appendingPathComponent(sessionFileName)
                self.timingModel?.saveSession(to: sessionURL)

                self.stopRecordingCompletion?(outputFileURL)
            }
            self.stopRecordingCompletion = nil
        }
    }
}