//
//  HapticVideo.swift
//  HapticVideo
//
//  Created by Bourouiba Mohamed Kamil
//  Copyright © 2024 Bourouiba Mohamed Kamil. Tous droits réservés.
//

import Foundation
import AVFoundation
import Accelerate
import SwiftUI
import AVKit
import CoreHaptics

public struct HapticEvent: Codable, Identifiable {
    public let id = UUID()
    public let time: Double
    public let intensity: Double
    public let sharpness: Double
    public let type: String
    
    public init(time: Double, intensity: Double, sharpness: Double, type: String) {
        self.time = time
        self.intensity = intensity
        self.sharpness = sharpness
        self.type = type
    }
}

public struct HapticData: Codable {
    public let metadata: Metadata
    public let hapticEvents: [HapticEvent]
    
    public struct Metadata: Codable {
        public let version: Int
        public let fps: Int
        public let duration: Double
        public let totalFrames: Int
        
        public init(version: Int, fps: Int, duration: Double, totalFrames: Int) {
            self.version = version
            self.fps = fps
            self.duration = duration
            self.totalFrames = totalFrames
        }
    }
    
    public init(metadata: Metadata, hapticEvents: [HapticEvent]) {
        self.metadata = metadata
        self.hapticEvents = hapticEvents
    }
}

public class HapticVideoPlayer: ObservableObject {
    private let player: AVPlayer
    private let hapticEngine: CHHapticEngine?
    private var hapticData: HapticData?
    private var timeObserver: Any?
    private var isAnalyzing = false
    private var hapticPlayers: [CHHapticPatternPlayer] = []
    
    @Published public var isPlaying = false
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0
    @Published public var analysisProgress: Double = 0
    @Published public var error: String?
    
    public init() {
        self.player = AVPlayer()
        self.hapticEngine = try? CHHapticEngine()
        try? self.hapticEngine?.start()
        
        // Configuration de l'observateur de temps
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
            self?.updateHapticFeedback()
        }
        
        // Configuration des notifications pour la gestion de la mémoire
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    deinit {
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        NotificationCenter.default.removeObserver(self)
        stopHapticEngine()
    }
    
    private func stopHapticEngine() {
        hapticEngine?.stop()
        hapticPlayers.removeAll()
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            pause()
            stopHapticEngine()
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                try? hapticEngine?.start()
                play()
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            pause()
            stopHapticEngine()
        default:
            break
        }
    }
    
    public func loadVideo(url: URL) {
        isAnalyzing = true
        analysisProgress = 0
        
        Task {
            do {
                // Analyse de la vidéo
                let hapticGenerator = VideoHaptic(target: url.path)
                let data = try await hapticGenerator.generateHapticData()
                
                DispatchQueue.main.async {
                    self.hapticData = data
                    self.duration = data.metadata.duration
                    self.player.replaceCurrentItem(with: AVPlayerItem(url: url))
                    self.isAnalyzing = false
                    self.analysisProgress = 1.0
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    self.isAnalyzing = false
                }
            }
        }
    }
    
    public func play() {
        player.play()
        isPlaying = true
    }
    
    public func pause() {
        player.pause()
        isPlaying = false
    }
    
    public func seek(to time: Double) {
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }
    
    private func updateHapticFeedback() {
        guard let hapticData = hapticData,
              let engine = hapticEngine,
              isPlaying else { return }
        
        // Nettoyage des anciens joueurs haptiques
        hapticPlayers.removeAll { player in
            do {
                try player.stop(atTime: 0)
                return true
            } catch {
                return false
            }
        }
        
        // Trouver les événements haptiques proches du temps actuel
        let currentEvents = hapticData.hapticEvents.filter { abs($0.time - currentTime) < 0.1 }
        
        for event in currentEvents {
            do {
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(event.intensity))
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(event.sharpness))
                
                let hapticEvent = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensity, sharpness],
                    relativeTime: 0
                )
                
                let pattern = try CHHapticPattern(events: [hapticEvent], parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: 0)
                hapticPlayers.append(player)
            } catch {
                print("Erreur haptique: \(error.localizedDescription)")
            }
        }
    }
}

public struct HapticVideoView: View {
    @StateObject private var player = HapticVideoPlayer()
    @State private var showFilePicker = false
    
    public init() {}
    
    public var body: some View {
        VStack {
            if player.isAnalyzing {
                VStack {
                    ProgressView("Analyse en cours...", value: player.analysisProgress, total: 1.0)
                        .progressViewStyle(.linear)
                    Text("\(Int(player.analysisProgress * 100))%")
                }
                .padding()
            } else if let error = player.error {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            } else {
                // Lecteur vidéo
                VideoPlayer(player: player.player)
                    .frame(height: 300)
                
                // Contrôles
                HStack {
                    Button(action: { player.isPlaying ? player.pause() : player.play() }) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                    }
                    
                    Slider(value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ), in: 0...player.duration)
                    
                    Text(String(format: "%.1f / %.1f", player.currentTime, player.duration))
                        .font(.caption)
                }
                .padding()
            }
            
            // Bouton de sélection de fichier
            Button("Sélectionner une vidéo") {
                showFilePicker = true
            }
            .buttonStyle(.bordered)
            .padding()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    player.loadVideo(url: url)
                }
            case .failure(let error):
                player.error = error.localizedDescription
            }
        }
    }
}

public class VideoHaptic {
    private let videoURL: URL
    private let fps: Int
    
    public init(target: String, fps: Int = 60) {
        self.videoURL = URL(fileURLWithPath: target)
        self.fps = fps
    }
    
    public func generateHapticData() async throws -> HapticData {
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        guard let audioTrack = audioTrack else {
            throw NSError(domain: "HapticVideo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Aucune piste audio trouvée"])
        }
        
        let audioFeatures = try await analyzeAudioFeatures(from: audioTrack, duration: duration)
        let hapticEvents = generateHapticEvents(from: audioFeatures, duration: duration)
        
        return HapticData(
            metadata: .init(
                version: 3,
                fps: fps,
                duration: duration,
                totalFrames: Int(duration * Double(fps))
            ),
            hapticEvents: hapticEvents
        )
    }
    
    private func analyzeAudioFeatures(from audioTrack: AVAssetTrack, duration: Double) async throws -> [String: [Float]] {
        let sampleRate: Double = 44100
        let frameCount = Int(duration * sampleRate)
        
        // Création d'un buffer pour l'audio
        var audioBuffer = [Float](repeating: 0, count: frameCount)
        
        // Analyse RMS avec vDSP
        var rms = [Float](repeating: 0, count: frameCount)
        vDSP_rmsqv(audioBuffer, 1, &rms, 1, vDSP_Length(frameCount))
        
        // Analyse spectrale avec vDSP
        var spectrum = [Float](repeating: 0, count: frameCount)
        var magnitudes = [Float](repeating: 0, count: frameCount)
        
        // Configuration de la FFT
        let log2n = vDSP_Length(log2(Float(frameCount)))
        let n = vDSP_Length(1 << log2n)
        let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        
        // Analyse spectrale
        var realIn = [Float](repeating: 0, count: Int(n))
        var imagIn = [Float](repeating: 0, count: Int(n))
        var realOut = [Float](repeating: 0, count: Int(n))
        var imagOut = [Float](repeating: 0, count: Int(n))
        
        var splitComplex = DSPSplitComplex(realp: &realOut, imagp: &imagOut)
        
        // Conversion en format split complex
        audioBuffer.withUnsafeBytes { ptr in
            vDSP_ctoz(ptr.baseAddress!.assumingMemoryBound(to: DSPComplex.self), 2, &splitComplex, 1, n/2)
        }
        
        // Exécution de la FFT
        vDSP_fft_zrip(setup!, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
        
        // Calcul des magnitudes
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, n/2)
        
        // Nettoyage
        vDSP_destroy_fftsetup(setup)
        
        return [
            "rms": rms,
            "spectrum": spectrum,
            "magnitudes": magnitudes
        ]
    }
    
    private func generateHapticEvents(from features: [String: [Float]], duration: Double) -> [HapticEvent] {
        let frameCount = Int(duration * Double(fps))
        var events: [HapticEvent] = []
        
        for i in 0..<frameCount {
            let time = Double(i) / Double(fps)
            let rms = features["rms"]?[i] ?? 0
            let magnitude = features["magnitudes"]?[i] ?? 0
            
            // Calcul de l'intensité et de la netteté
            let intensity = min(max(Double(rms) * 2, 0), 1)
            let sharpness = min(max(Double(magnitude), 0), 1)
            
            // Détermination du type de retour haptique
            let type = determineHapticType(intensity: intensity, sharpness: sharpness)
            
            // Ajout de l'événement si l'intensité est significative
            if intensity > 0.3 {
                events.append(HapticEvent(
                    time: time,
                    intensity: intensity,
                    sharpness: sharpness,
                    type: type
                ))
            }
        }
        
        return events
    }
    
    private func determineHapticType(intensity: Double, sharpness: Double) -> String {
        if intensity > 0.7 && sharpness > 0.6 {
            return "heavy"
        } else if intensity > 0.4 && sharpness > 0.5 {
            return "medium"
        } else if intensity > 0.2 {
            return "light"
        } else {
            return "soft"
        }
    }
} 