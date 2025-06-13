import Foundation
import AVKit
import Combine

public class HapticVideoViewModel: ObservableObject {
    @Published public var player: AVPlayer?
    @Published public var hapticFileName: String?
    @Published public var videoFileName: String?
    @Published public var isReadyToPlay: Bool = false
    @Published public var hapticMultiplier: Double = 1.0
    
    private var hapticEvents: [HapticEvent] = []
    private var timeObserver: Any?
    private var nextHapticEventIndex: Int = 0
    private var cancellables = Set<AnyCancellable>()
    
    public init() {}
    
    public func loadHapticFile(url: URL) {
        hapticFileName = url.lastPathComponent
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let hapticData = try decoder.decode(HapticData.self, from: data)
            hapticEvents = hapticData.events
            checkReadyState()
        } catch {
            hapticFileName = nil
            hapticEvents = []
        }
    }
    
    public func loadVideo(url: URL) {
        videoFileName = url.lastPathComponent
        player = AVPlayer(url: url)
        setupTimeObserver()
        checkReadyState()
    }
    
    private func checkReadyState() {
        isReadyToPlay = !hapticEvents.isEmpty && player != nil
    }
    
    private func setupTimeObserver() {
        if let player = player, let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        guard let player = player else { return }
        nextHapticEventIndex = 0
        let observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.01, preferredTimescale: 600), queue: .main) { [weak self] _ in
            guard let self = self else { return }
            let currentTime = player.currentTime().seconds
            let lookahead = 0.02
            while self.nextHapticEventIndex < self.hapticEvents.count,
                  self.hapticEvents[self.nextHapticEventIndex].time <= currentTime + lookahead {
                let event = self.hapticEvents[self.nextHapticEventIndex]
                self.playHapticEvent(event)
                self.nextHapticEventIndex += 1
            }
        }
        self.timeObserver = observer
    }
    
    public func startPlayback() {
        player?.play()
    }
    
    public func pausePlayback() {
        player?.pause()
    }
    
    public func stopPlayback() {
        player?.pause()
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
    
    public func adjustHapticIntensity(_ multiplier: Double) {
        hapticMultiplier = max(0.0, min(2.0, multiplier))
    }
    
    private func playHapticEvent(_ event: HapticEvent) {
        // À implémenter : jouer l'événement haptique avec CoreHaptics
    }
} 