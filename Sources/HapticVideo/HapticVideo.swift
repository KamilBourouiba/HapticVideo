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

public struct HapticEvent {
    public let time: TimeInterval
    public let intensity: Float
    public let frequency: Float
    
    public init(time: TimeInterval, intensity: Float, frequency: Float) {
        self.time = time
        self.intensity = intensity
        self.frequency = frequency
    }
}

public struct HapticData {
    public let events: [HapticEvent]
    public let duration: TimeInterval
    
    public init(events: [HapticEvent], duration: TimeInterval) {
        self.events = events
        self.duration = duration
    }
}

public enum HapticVideoError: Error {
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
    private var engine: CHHapticEngine?
    public var hapticPlayer: CHHapticPatternPlayer?
    public var videoPlayer: AVPlayer?
    @Published public var currentHapticData: HapticData?
    @Published public var isPlaying = false
    @Published public var isAnalyzing = false
    @Published public var progress: Double = 0
    @Published public var duration: Double = 0
    @Published public var currentTime: Double = 0
    @Published public var error: String?
    private var timer: Timer?
    private var startTime: TimeInterval = 0
    
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
                self?.isPlaying = false
                self?.error = "Moteur haptique arrêté: \(reason)"
            }
        } catch {
            self.error = "Erreur lors de l'initialisation du moteur haptique: \(error.localizedDescription)"
        }
    }
    
    public func play(hapticData: HapticData, videoURL: URL? = nil) {
        guard let engine = engine else {
            error = "Moteur haptique non initialisé"
            return
        }
        
        currentHapticData = hapticData
        
        do {
            let pattern = try createPattern(from: hapticData)
            hapticPlayer = try engine.makePlayer(with: pattern)
            try hapticPlayer?.start(atTime: CHHapticTimeImmediate)
            
            if let videoURL = videoURL {
                let playerItem = AVPlayerItem(url: videoURL)
                videoPlayer = AVPlayer(playerItem: playerItem)
                videoPlayer?.play()
            }
            
            isPlaying = true
            startTime = Date().timeIntervalSince1970
            duration = hapticData.duration
            
            startProgressTimer()
        } catch {
            self.error = "Erreur lors de la lecture haptique: \(error.localizedDescription)"
        }
    }
    
    public func resume() {
        guard let hapticData = currentHapticData else {
            error = "Aucune donnée haptique disponible"
            return
        }
        
        do {
            let pattern = try createPattern(from: hapticData)
            hapticPlayer = try engine?.makePlayer(with: pattern)
            try hapticPlayer?.start(atTime: CHHapticTimeImmediate)
            
            videoPlayer?.play()
            isPlaying = true
            startTime = Date().timeIntervalSince1970 - currentTime
            startProgressTimer()
        } catch {
            self.error = "Erreur lors de la reprise de la lecture: \(error.localizedDescription)"
        }
    }
    
    public func pause() {
        do {
            try hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
            videoPlayer?.pause()
            isPlaying = false
            timer?.invalidate()
            timer = nil
        } catch {
            self.error = "Erreur lors de la mise en pause: \(error.localizedDescription)"
        }
    }
    
    public func stop() {
        do {
            try hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
            videoPlayer?.pause()
            isPlaying = false
            timer?.invalidate()
            timer = nil
            progress = 0
            currentTime = 0
        } catch {
            self.error = "Erreur lors de l'arrêt de la lecture: \(error.localizedDescription)"
        }
    }
    
    public func seek(to time: Double) {
        currentTime = time
        progress = time / duration
        
        if let videoPlayer = videoPlayer {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            videoPlayer.seek(to: cmTime)
        }
        
        if let hapticPlayer = hapticPlayer, let hapticData = currentHapticData {
            do {
                try hapticPlayer.stop(atTime: CHHapticTimeImmediate)
                let pattern = try createPattern(from: HapticData(
                    events: hapticData.events.filter { $0.time >= time },
                    duration: duration - time
                ))
                try hapticPlayer.start(atTime: CHHapticTimeImmediate)
            } catch {
                self.error = "Erreur lors du changement de position: \(error.localizedDescription)"
            }
        }
    }
    
    private func startProgressTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            let currentTime = Date().timeIntervalSince1970 - self.startTime
            self.currentTime = currentTime
            self.progress = min(currentTime / self.duration, 1.0)
            
            if self.progress >= 1.0 {
                self.stop()
            }
        }
    }
    
    private func createPattern(from hapticData: HapticData) throws -> CHHapticPattern {
        var events = [CHHapticEvent]()
        
        for event in hapticData.events {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(event.intensity))
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(event.frequency))
            
            let hapticEvent = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensity, sharpness],
                relativeTime: TimeInterval(event.time)
            )
            
            events.append(hapticEvent)
        }
        
        return try CHHapticPattern(events: events, parameters: [])
    }
}

public class VideoHaptic {
    @available(iOS 15.0, *)
    public static func generateHapticData(from videoURL: URL) async throws -> HapticData {
        let asset = AVAsset(url: videoURL)
        
        // Obtenir la durée de la vidéo
        let duration = try await asset.load(.duration).seconds
        
        // Obtenir la piste audio
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw HapticVideoError.audioTrackNotFound
        }
        
        // Analyser l'audio
        let analyzer = AudioAnalysis()
        let audioFeatures = try await analyzer.analyzeAudio(from: audioTrack)
        let hapticEvents = generateHapticEvents(from: audioFeatures, duration: duration)
        
        return HapticData(events: hapticEvents, duration: duration)
    }
    
    public static func generateHapticDataLegacy(from videoURL: URL) async throws -> HapticData {
        let asset = AVAsset(url: videoURL)
        
        // Obtenir la durée de la vidéo
        let duration = CMTimeGetSeconds(asset.duration)
        
        // Obtenir la piste audio
        let audioTracks = asset.tracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw HapticVideoError.audioTrackNotFound
        }
        
        // Analyser l'audio
        let analyzer = AudioAnalysis()
        let audioFeatures = try await analyzer.analyzeAudio(from: audioTrack)
        let hapticEvents = generateHapticEvents(from: audioFeatures, duration: duration)
        
        return HapticData(events: hapticEvents, duration: duration)
    }
    
    private static func generateHapticEvents(from features: [String: [Float]], duration: TimeInterval) -> [HapticEvent] {
        var events: [HapticEvent] = []
        let frameCount = features["rms"]?.count ?? 0
        let frameDuration = duration / TimeInterval(frameCount)
        
        for i in 0..<frameCount {
            let time = TimeInterval(i) * frameDuration
            let rms = features["rms"]?[i] ?? 0
            let magnitude = features["magnitudes"]?[i] ?? 0
            
            let intensity = min(max(rms * 2.0, 0.0), 1.0)
            let sharpness = min(max(magnitude * 0.5, 0.0), 1.0)
            
            if intensity > 0.1 {
                events.append(HapticEvent(
                    time: time,
                    intensity: intensity,
                    frequency: sharpness
                ))
            }
        }
        
        return events
    }
}

public struct HapticVideoPlayerView: View {
    @ObservedObject var player: HapticVideoPlayer
    @State private var isDragging = false
    
    public init(player: HapticVideoPlayer) {
        self.player = player
    }
    
    public var body: some View {
        VStack {
            if let error = player.error {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            } else {
                if let player = player.videoPlayer {
                    VideoPlayer(player: player)
                        .frame(height: 300)
                }
                
                HStack {
                    Text(formatTime(player.currentTime))
                    Slider(
                        value: Binding(
                            get: { player.progress },
                            set: { newValue in
                                if !isDragging {
                                    player.seek(to: newValue * player.duration)
                                }
                            }
                        ),
                        in: 0...1
                    )
                    .onChange(of: player.progress) { newValue in
                        if isDragging {
                            player.seek(to: newValue * player.duration)
                        }
                    }
                    Text(formatTime(player.duration))
                }
                .padding()
                
                HStack {
                    Button(action: {
                        if player.isPlaying {
                            player.pause()
                        } else {
                            if let hapticData = player.currentHapticData {
                                player.play(hapticData: hapticData)
                            }
                        }
                    }) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                    }
                }
                .padding()
            }
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
                if let player = player.videoPlayer {
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