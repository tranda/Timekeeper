import AVFoundation
import AppKit

class CaptureManager: NSObject, ObservableObject {
    @Published var availableDevices: [AVCaptureDevice] = []
    @Published var selectedDevice: AVCaptureDevice?
    @Published var isRecording = false
    @Published var outputDirectory: URL?
    @Published var lastRecordedURL: URL?
    @Published var isSessionRunning = false
    @Published var captureSession: AVCaptureSession?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var currentDeviceInput: AVCaptureDeviceInput?
    private var stopRecordingCompletion: ((URL?) -> Void)?

    var videoStartTime: Date?
    var videoStopTime: Date?
    var timingModel: RaceTimingModel?


    override init() {
        super.init()
        refreshDevices()
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
            print("  - \(device.localizedName): \(device.uniqueID)")
        }
        DispatchQueue.main.async {
            self.availableDevices = devices
        }
    }

    func selectDevice(_ device: AVCaptureDevice) {
        print("Selecting device: \(device.localizedName) - ID: \(device.uniqueID)")
        DispatchQueue.main.async {
            self.selectedDevice = device
        }
        configureSession { success in
            if success {
                print("Successfully configured session for: \(device.localizedName)")
                self.startSessionIfNeeded()
            } else {
                print("Failed to configure session for: \(device.localizedName)")
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
            completion(false)
            return
        }

        print("Configuring session with device: \(device.localizedName)")

        if captureSession == nil {
            let newSession = AVCaptureSession()
            captureSession = newSession
            // Notify UI that session is available
            DispatchQueue.main.async {
                self.captureSession = newSession
                self.objectWillChange.send()
            }
        }

        guard let session = captureSession else {
            completion(false)
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

        session.sessionPreset = .high

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
                    // Video stabilization is only available on iOS
                    #if os(iOS)
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .auto
                    }
                    #endif
                }
            }

            session.commitConfiguration()
            completion(true)

        } catch {
            print("Error configuring session: \(error)")
            session.commitConfiguration()
            completion(false)
        }
    }

    func startSessionIfNeeded() {
        guard let session = captureSession else { return }

        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = true
                    self.objectWillChange.send()
                }
            }
        } else {
            DispatchQueue.main.async {
                self.isSessionRunning = true
            }
        }
    }

    func stopSession() {
        guard let session = captureSession else { return }

        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.stopRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = false
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

        let outputFolder = folder ?? outputDirectory ?? FileManager.default.temporaryDirectory
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "TimeKeeper_\(timestamp).mov"
        let fileURL = outputFolder.appendingPathComponent(fileName)

        movieOutput.startRecording(to: fileURL, recordingDelegate: self)

        DispatchQueue.main.async {
            self.isRecording = true
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
        print("Recording started: \(fileURL.lastPathComponent)")
        DispatchQueue.main.async {
            self.videoStartTime = Date()
            self.timingModel?.setVideoStartTime(self.videoStartTime!)
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
                let sessionURL = outputFolder.appendingPathComponent("session.json")
                self.timingModel?.saveSession(to: sessionURL)

                self.stopRecordingCompletion?(outputFileURL)
            }
            self.stopRecordingCompletion = nil
        }
    }
}