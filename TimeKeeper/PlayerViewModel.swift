import AVFoundation
import Combine

class PlayerViewModel: ObservableObject {
    @Published var player: AVPlayer
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    @Published var isSeekingOutsideVideo = false

    private var timeObserver: Any?
    private var statusObserver: AnyCancellable?
    private var rateObserver: AnyCancellable?

    var timingModel: RaceTimingModel?

    init() {
        self.player = AVPlayer()
        setupObservers()
    }

    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
    }

    private func setupObservers() {
        let interval = CMTime(seconds: 1.0/30.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }

        rateObserver = player.publisher(for: \.rate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                self?.isPlaying = rate != 0
            }
    }

    func loadVideo(url: URL) {
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        statusObserver = playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .readyToPlay {
                    self?.duration = playerItem.asset.duration.seconds
                }
            }

        player.replaceCurrentItem(with: playerItem)
        player.pause()
    }

    func seek(to time: Double, precise: Bool = false) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

        if precise {
            player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: cmTime)
        }
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    func seekToNextFrame() {
        guard let currentItem = player.currentItem else { return }

        let frameRate = currentItem.asset.tracks(withMediaType: .video).first?.nominalFrameRate ?? 30.0
        let frameDuration = 1.0 / Double(frameRate)
        let nextTime = currentTime + frameDuration

        if nextTime <= duration {
            seek(to: nextTime, precise: true)
        }
    }

    func seekToPreviousFrame() {
        guard let currentItem = player.currentItem else { return }

        let frameRate = currentItem.asset.tracks(withMediaType: .video).first?.nominalFrameRate ?? 30.0
        let frameDuration = 1.0 / Double(frameRate)
        let previousTime = max(0, currentTime - frameDuration)

        seek(to: previousTime, precise: true)
    }
}