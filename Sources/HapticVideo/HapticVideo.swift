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

public struct HapticEvent: Codable {
    public let time: Double
    public let intensity: Float
    public let frequency: Float
    
    public init(time: Double, intensity: Float, frequency: Float) {
        self.time = time
        self.intensity = intensity
        self.frequency = frequency
    }
}

public struct HapticData: Codable {
    public let events: [HapticEvent]
    public let duration: Double
    
    public init(events: [HapticEvent], duration: Double) {
        self.events = events
        self.duration = duration
    }
}

public struct HapticVideoError: Error {
    case audioTrackNotFound
    case analysisFailed
    case invalidData
}

public struct HapticVideoEvent: Codable, Identifiable {
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

public struct HapticVideoMetadata: Codable {
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

public struct HapticVideoData: Codable {
    public let metadata: HapticVideoMetadata
    public let events: [HapticVideoEvent]
    
    public init(metadata: HapticVideoMetadata, events: [HapticVideoEvent]) {
        self.metadata = metadata
        self.events = events
    }
}

public class HapticVideoPlayer: ObservableObject {
    @Published public var isPlaying = false
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0
    @Published public var isAnalyzing = false
    @Published public var progress: Double = 0
    @Published public var error: String?
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var engine: CHHapticEngine?
    private var playerPattern: CHHapticPattern?
    private var playerPatternPlayer: CHHapticPatternPlayer?
    private var hapticData: HapticData?
    
    public init() {
        setupHapticEngine()
    }
    
    private func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            error = "Haptics non supportés sur cet appareil"
            return
        }
        
        do {
            engine = try CHHapticEngine()
            try engine?.start()
            
            engine?.resetHandler = { [weak self] in
                self?.setupHapticEngine()
            }
            
            engine?.stoppedHandler = { [weak self] reason in
                self?.error = "Moteur haptique arrêté: \(reason)"
            }
        } catch {
            self.error = "Erreur lors de l'initialisation du moteur haptique: \(error.localizedDescription)"
        }
    }
    
    public func loadVideo(from url: URL) {
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        self.playerItem = playerItem
        self.player = AVPlayer(playerItem: playerItem)
        
        // Obtenir la durée de la vidéo
        let duration = CMTimeGetSeconds(asset.duration)
        self.duration = duration
        
        // Configurer l'observateur de temps
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = CMTimeGetSeconds(time)
            self?.updateHapticFeedback()
        }
        
        // Analyser la vidéo pour les données haptiques
        analyzeVideo(asset)
    }
    
    private func analyzeVideo(_ asset: AVAsset) {
        isAnalyzing = true
        progress = 0
        
        // Obtenir la piste audio
        let audioTracks = asset.tracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            error = "Aucune piste audio trouvée"
            isAnalyzing = false
            return
        }
        
        // Analyser l'audio pour générer les données haptiques
        let analyzer = AudioAnalysis()
        
        Task {
            do {
                let analysis = try await analyzer.analyzeAudio(from: audioTrack)
                let events = generateHapticEvents(from: analysis)
                hapticData = HapticData(events: events, duration: duration)
                isAnalyzing = false
                progress = 1.0
            } catch {
                self.error = "Erreur lors de l'analyse: \(error.localizedDescription)"
                isAnalyzing = false
            }
        }
    }
    
    private func generateHapticEvents(from analysis: [String: [Float]]) -> [HapticEvent] {
        var events: [HapticEvent] = []
        let rms = analysis["rms"] ?? []
        let spectrum = analysis["spectrum"] ?? []
        
        for i in 0..<min(rms.count, spectrum.count) {
            let time = Double(i) * 0.1 // 100ms par frame
            let intensity = rms[i]
            let frequency = spectrum[i]
            
            if intensity > 0.1 { // Seuil d'intensité
                events.append(HapticEvent(time: time, intensity: intensity, frequency: frequency))
            }
        }
        
        return events
    }
    
    private func updateHapticFeedback() {
        guard let hapticData = hapticData,
              let engine = engine,
              engine.isRunning else { return }
        
        // Trouver les événements haptiques pour le temps actuel
        let currentEvents = hapticData.events.filter { abs($0.time - currentTime) < 0.1 }
        
        for event in currentEvents {
            do {
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: event.frequency)
                
                let hapticEvent = CHHapticEvent(eventType: .hapticTransient,
                                              parameters: [intensity, sharpness],
                                              relativeTime: 0)
                
                let pattern = try CHHapticPattern(events: [hapticEvent], parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: 0)
            } catch {
                self.error = "Erreur lors de la lecture haptique: \(error.localizedDescription)"
            }
        }
    }
    
    public func play() {
        player?.play()
        isPlaying = true
    }
    
    public func pause() {
        player?.pause()
        isPlaying = false
    }
    
    public func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime)
    }
    
    deinit {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        engine?.stop()
    }
}

public struct HapticVideoView: View {
    @StateObject private var player = HapticVideoPlayer()
    @State private var isFilePickerPresented = false
    
    public init() {}
    
    public var body: some View {
        VStack {
            if player.isAnalyzing {
                ProgressView("Analyse en cours...", value: player.progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding()
            } else if let error = player.error {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            } else {
                if let player = player.player {
                    VideoPlayer(player: player)
                        .frame(height: 300)
                }
                
                HStack {
                    Button(action: { player.seek(to: max(0, player.currentTime - 10)) }) {
                        Image(systemName: "gobackward.10")
                    }
                    
                    Button(action: { player.isPlaying ? player.pause() : player.play() }) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    }
                    
                    Button(action: { player.seek(to: min(player.duration, player.currentTime + 10)) }) {
                        Image(systemName: "goforward.10")
                    }
                }
                .padding()
                
                Slider(value: $player.currentTime, in: 0...player.duration) { editing in
                    if !editing {
                        player.seek(to: player.currentTime)
                    }
                }
                .padding()
            }
            
            Button(action: { isFilePickerPresented = true }) {
                Text("Sélectionner une vidéo")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .fileImporter(
                isPresented: $isFilePickerPresented,
                allowedContentTypes: [.movie],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        player.loadVideo(from: url)
                    }
                case .failure(let error):
                    player.error = error.localizedDescription
                }
            }
        }
        .padding()
    }
}

public class VideoHaptic {
    private let videoURL: URL
    private let fps: Int
    
    public init(target: String, fps: Int = 60) {
        self.videoURL = URL(fileURLWithPath: target)
        self.fps = fps
    }
    
    public func generateHapticData() async throws -> HapticVideoData {
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        guard let audioTrack = audioTrack else {
            throw HapticVideoError.audioTrackNotFound
        }
        
        let audioFeatures = try await analyzeAudioFeatures(from: audioTrack, duration: duration)
        let events = generateHapticEvents(from: audioFeatures, duration: duration)
        
        return HapticVideoData(
            metadata: HapticVideoMetadata(
                version: 3,
                fps: fps,
                duration: duration,
                totalFrames: Int(duration * Double(fps))
            ),
            events: events
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
    
    private func generateHapticEvents(from features: [String: [Float]], duration: Double) -> [HapticVideoEvent] {
        var events: [HapticVideoEvent] = []
        let frameCount = features["rms"]?.count ?? 0
        let frameDuration = duration / Double(frameCount)
        
        for i in 0..<frameCount {
            let time = Double(i) * frameDuration
            let rms = features["rms"]?[i] ?? 0
            let magnitude = features["magnitudes"]?[i] ?? 0
            
            let intensity = min(max(Float(rms) * 2.0, 0.0), 1.0)
            let sharpness = min(max(Float(magnitude) * 0.5, 0.0), 1.0)
            
            if intensity > 0.1 {
                events.append(HapticVideoEvent(
                    time: time,
                    intensity: Double(intensity),
                    sharpness: Double(sharpness),
                    type: "impact"
                ))
            }
        }
        
        return events
    }
} 