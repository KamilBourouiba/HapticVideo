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
    public let time: TimeInterval
    public let intensity: Float
    public let frequency: Float
    
    public init(time: TimeInterval, intensity: Float, frequency: Float) {
        self.time = time
        self.intensity = intensity
        self.frequency = frequency
    }
}

public struct HapticData: Codable {
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
    @Published public var player: AVPlayer?
    @Published public var isPlaying = false
    @Published public var videoURL: URL?
    @Published public var currentHapticData: HapticData?
    @Published public var isAnalyzing: Bool = false
    @Published public var progress: Double = 0
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 1
    @Published public var error: String? = nil
    private var engine: CHHapticEngine?
    private var hapticPlayer: CHHapticPatternPlayer?
    private var timer: Timer?
    private var startTime: TimeInterval = 0
    
    public init() {
        setupHapticEngine()
    }
    
    private func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("Erreur lors de l'initialisation du moteur haptique: \(error)")
        }
    }
    
    public func loadVideo(url: URL) {
        self.player = AVPlayer(url: url)
        self.videoURL = url
    }
    
    public func loadHapticData(_ data: HapticData) {
        self.currentHapticData = data
    }
    
    public func play() {
        player?.play()
        playHaptics()
        isPlaying = true
    }
    
    public func pause() {
        player?.pause()
        stopHaptics()
        isPlaying = false
    }
    
    public func stop() {
        player?.pause()
        player?.seek(to: .zero)
        stopHaptics()
        isPlaying = false
    }
    
    private func playHaptics() {
        guard let engine = engine, let hapticData = currentHapticData else { return }
        do {
            let pattern = try createPattern(from: hapticData)
            hapticPlayer = try engine.makePlayer(with: pattern)
            try hapticPlayer?.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Erreur lors de la lecture haptique: \(error)")
        }
    }
    
    private func stopHaptics() {
        do {
            try hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
        } catch {
            // Ignorer l'erreur
        }
    }
    
    private func createPattern(from hapticData: HapticData) throws -> CHHapticPattern {
        var events = [CHHapticEvent]()
        for event in hapticData.events {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: event.frequency)
            let hapticEvent = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensity, sharpness],
                relativeTime: event.time
            )
            events.append(hapticEvent)
        }
        return try CHHapticPattern(events: events, parameters: [])
    }
    
    public func seek(to time: Double) {
        currentTime = time
        if let player = player {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            player.seek(to: cmTime)
        }
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
    @State private var showingPicker = false
    @State private var showingHapticPicker = false
    
    public init(player: HapticVideoPlayer) {
        self.player = player
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            if let avPlayer = player.player {
                FullScreenVideoPlayer(player: avPlayer)
            } else {
                VStack {
                    Image(systemName: "video.slash")
                        .resizable()
                        .frame(width: 80, height: 60)
                        .foregroundColor(.gray)
                    Text("Aucune vidéo sélectionnée")
                        .foregroundColor(.gray)
                }
                .frame(height: 300)
            }
            HStack(spacing: 30) {
                Button(action: { player.stop() }) {
                    Image(systemName: "stop.fill").font(.largeTitle)
                }
                Button(action: {
                    if player.isPlaying {
                        player.pause()
                    } else {
                        player.play()
                    }
                }) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.largeTitle)
                }
            }
            Button("Sélectionner une vidéo") {
                showingPicker = true
            }
            .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.movie]) { result in
                switch result {
                case .success(let url):
                    player.loadVideo(url: url)
                case .failure:
                    break
                }
            }
            Button("Sélectionner un fichier haptique") {
                showingHapticPicker = true
            }
            .fileImporter(isPresented: $showingHapticPicker, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    if let data = try? Data(contentsOf: url),
                       let hapticData = try? JSONDecoder().decode(HapticData.self, from: data) {
                        player.loadHapticData(hapticData)
                    }
                case .failure:
                    break
                }
            }
        }
        .padding()
    }
}

public struct FullScreenVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    
    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        return controller
    }
    public func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
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
                    
                    Button(action: { 
                        if player.isPlaying {
                            player.pause()
                        } else {
                            player.play()
                        }
                    }) {
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
                        player.loadVideo(url: url)
                    }
                case .failure(let error):
                    player.error = error.localizedDescription
                }
            }
        }
        .padding()
    }
} 