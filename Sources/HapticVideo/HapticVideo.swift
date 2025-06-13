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
    public let intensity: Double
    public let sharpness: Double
    public let type: String
}

public struct HapticData: Codable {
    public let metadata: Metadata
    public let hapticEvents: [HapticEvent]
    
    public struct Metadata: Codable {
        public let version: Int
        public let fps: Int
        public let duration: Double
        public let totalFrames: Int
    }
}

public class HapticVideoPlayer: ObservableObject {
    private let player: AVPlayer
    private let hapticEngine: CHHapticEngine?
    private var hapticData: HapticData?
    private var timeObserver: Any?
    private var isAnalyzing = false
    
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

public class HAPTICKAnalyzer {
    private let fps: Int
    private let audioEngine: AudioEngine
    private let mixer: Mixer
    
    public init(fps: Int = 60) {
        self.fps = fps
        self.audioEngine = AudioEngine()
        self.mixer = Mixer()
        audioEngine.output = mixer
    }
    
    public func hapticVideo(_ videoURL: URL) async throws -> URL {
        // Créer un fichier temporaire pour l'audio
        let tempAudioURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        
        // Extraire l'audio de la vidéo
        try await extractAudio(from: videoURL, to: tempAudioURL)
        
        // Analyser l'audio
        let audioFeatures = try await analyzeAudio(tempAudioURL)
        
        // Générer les événements haptiques
        let hapticData = generateHapticData(from: audioFeatures, videoDuration: audioFeatures.duration)
        
        // Sauvegarder en JSON
        let jsonURL = videoURL.deletingPathExtension().appendingPathExtension("json")
        try saveHapticData(hapticData, to: jsonURL)
        
        // Nettoyer
        try? FileManager.default.removeItem(at: tempAudioURL)
        
        return jsonURL
    }
    
    private func extractAudio(from videoURL: URL, to audioURL: URL) async throws {
        let command = "-i \(videoURL.path) -vn -acodec pcm_s16le -ar 22050 -ac 1 \(audioURL.path)"
        try await FFmpegKit.execute(command)
    }
    
    private func analyzeAudio(_ audioURL: URL) async throws -> AudioFeatures {
        let file = try AVAudioFile(forReading: audioURL)
        let format = file.processingFormat
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))
        try file.read(into: buffer!)
        
        // Convertir en AudioKit format
        let audioData = buffer!.floatChannelData?[0]
        let frameCount = Int(buffer!.frameLength)
        
        // Analyser les caractéristiques audio
        let rms = AudioAnalysis.calculateRMS(audioData!, frameCount: frameCount)
        let frequencies = AudioAnalysis.calculateFrequencies(audioData!, frameCount: frameCount)
        let spectralRolloff = AudioAnalysis.calculateSpectralRolloff(audioData!, frameCount: frameCount)
        let spectralBandwidth = AudioAnalysis.calculateSpectralBandwidth(audioData!, frameCount: frameCount)
        
        return AudioFeatures(
            rms: rms,
            frequencies: frequencies,
            spectralRolloff: spectralRolloff,
            spectralBandwidth: spectralBandwidth,
            duration: Double(file.duration)
        )
    }
    
    private func generateHapticData(from features: AudioFeatures, videoDuration: Double) -> [String: Any] {
        let nFrames = Int(videoDuration * Double(fps))
        var hapticEvents: [HapticEvent] = []
        
        // Interpoler les données pour correspondre au nombre de frames
        let rmsInterp = AudioAnalysis.interpolate(features.rms, targetCount: nFrames)
        let freqsInterp = AudioAnalysis.interpolate(features.frequencies, targetCount: nFrames)
        let rolloffInterp = AudioAnalysis.interpolate(features.spectralRolloff, targetCount: nFrames)
        let bandwidthInterp = AudioAnalysis.interpolate(features.spectralBandwidth, targetCount: nFrames)
        
        // Lisser les données
        let rmsSmooth = AudioAnalysis.smoothData(rmsInterp)
        let freqsSmooth = AudioAnalysis.smoothData(freqsInterp)
        let rolloffSmooth = AudioAnalysis.smoothData(rolloffInterp)
        let bandwidthSmooth = AudioAnalysis.smoothData(bandwidthInterp)
        
        // Calculer le seuil d'intensité
        let intensityThreshold = AudioAnalysis.calculateIntensityThreshold(rmsSmooth)
        
        // Générer les événements haptiques
        for i in 0..<nFrames {
            let t = Double(i) / Double(fps)
            let intensity = min(rmsSmooth[i] * 2, 1.0)
            let sharpness = freqsSmooth[i] / (freqsSmooth.max() ?? 1.0)
            
            let frameFeatures = AudioFeatures(
                rms: [rmsSmooth[i]],
                frequencies: [freqsSmooth[i]],
                spectralRolloff: [rolloffSmooth[i]],
                spectralBandwidth: [bandwidthSmooth[i]],
                duration: 0
            )
            
            let hapticType = determineHapticType(frameFeatures)
            
            if intensity > intensityThreshold && i % 2 == 0 {
                hapticEvents.append(HapticEvent(
                    time: t,
                    intensity: intensity,
                    sharpness: sharpness,
                    type: hapticType
                ))
            }
        }
        
        let metadata = HapticMetadata(
            fps: fps,
            duration: videoDuration,
            totalFrames: nFrames
        )
        
        return [
            "metadata": metadata,
            "haptic_events": hapticEvents
        ]
    }
    
    private func saveHapticData(_ data: [String: Any], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url)
    }
    
    private func determineHapticType(_ features: AudioFeatures) -> HapticType {
        if features.rms[0] > 0.7 && features.spectralBandwidth[0] > 0.6 {
            return .heavy
        } else if features.rms[0] > 0.4 && features.spectralRolloff[0] > 0.5 {
            return .medium
        } else if features.rms[0] > 0.2 {
            return .light
        } else {
            return .soft
        }
    }
}

struct AudioFeatures {
    let rms: [Float]
    let frequencies: [Float]
    let spectralRolloff: [Float]
    let spectralBandwidth: [Float]
    let duration: Double
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