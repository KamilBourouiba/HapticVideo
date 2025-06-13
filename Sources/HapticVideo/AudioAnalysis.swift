import Foundation
import AVFoundation
import Accelerate

public class AudioAnalysis {
    private let sampleRate: Double
    private let frameSize: Int
    
    public init(sampleRate: Double = 44100, frameSize: Int = 2048) {
        self.sampleRate = sampleRate
        self.frameSize = frameSize
    }
    
    public func analyzeAudio(from audioTrack: AVAssetTrack) async throws -> [String: [Float]] {
        let asset = audioTrack.asset
        let duration = try await asset.load(.duration).seconds
        let frameCount = Int(duration * sampleRate)
        
        // Création du buffer audio
        var audioBuffer = [Float](repeating: 0, count: frameCount)
        
        // Configuration de la FFT
        let log2n = vDSP_Length(log2(Float(frameSize)))
        let n = vDSP_Length(1 << log2n)
        let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        
        // Buffers pour la FFT
        var realIn = [Float](repeating: 0, count: Int(n))
        var imagIn = [Float](repeating: 0, count: Int(n))
        var realOut = [Float](repeating: 0, count: Int(n))
        var imagOut = [Float](repeating: 0, count: Int(n))
        
        // Configuration du split complex
        var splitComplex = DSPSplitComplex(realp: &realOut, imagp: &imagOut)
        
        // Conversion des données en format complexe
        let complexBuffer = zip(realIn, imagIn).map { DSPComplex(real: $0, imag: $1) }
        vDSP_ctoz(complexBuffer, 2, &splitComplex, 1, vDSP_Length(n/2))
        
        // Exécution de la FFT
        vDSP_fft_zrip(setup!, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
        
        // Calcul des magnitudes
        var magnitudes = [Float](repeating: 0, count: Int(n/2))
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(n/2))
        
        // Nettoyage
        vDSP_destroy_fftsetup(setup)
        
        // Calcul du RMS
        var rms = [Float](repeating: 0, count: frameCount)
        vDSP_rmsqv(audioBuffer, 1, &rms, vDSP_Length(frameCount))
        
        // Analyse spectrale
        var spectrum = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let startIdx = i * Int(n/2)
            let endIdx = min(startIdx + Int(n/2), magnitudes.count)
            let frameMagnitudes = magnitudes[startIdx..<endIdx]
            spectrum[i] = frameMagnitudes.reduce(0, +) / Float(frameMagnitudes.count)
        }
        
        return [
            "rms": rms,
            "spectrum": spectrum,
            "magnitudes": magnitudes
        ]
    }
    
    private func processFrame(_ frame: [Float], setup: FFTSetup) -> [Float] {
        let log2n = vDSP_Length(log2(Float(frameSize)))
        let n = vDSP_Length(1 << log2n)
        
        var realIn = [Float](repeating: 0, count: Int(n))
        var imagIn = [Float](repeating: 0, count: Int(n))
        var realOut = [Float](repeating: 0, count: Int(n))
        var imagOut = [Float](repeating: 0, count: Int(n))
        
        // Copie des données du frame
        realIn.replaceSubrange(0..<min(frame.count, Int(n)), with: frame)
        
        var splitComplex = DSPSplitComplex(realp: &realOut, imagp: &imagOut)
        
        // Conversion des données en format complexe
        let complexBuffer = zip(realIn, imagIn).map { DSPComplex(real: $0, imag: $1) }
        vDSP_ctoz(complexBuffer, 2, &splitComplex, 1, vDSP_Length(n/2))
        
        // FFT
        vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
        
        // Calcul des magnitudes
        var magnitudes = [Float](repeating: 0, count: Int(n/2))
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(n/2))
        
        return magnitudes
    }
    
    private func analyzeFrequencyBands(_ magnitudes: [Float]) -> [Float] {
        let numBands = 8
        var bands = [Float](repeating: 0, count: numBands)
        let bandSize = magnitudes.count / numBands
        
        for i in 0..<numBands {
            let startIdx = i * bandSize
            let endIdx = min(startIdx + bandSize, magnitudes.count)
            let bandMagnitudes = magnitudes[startIdx..<endIdx]
            bands[i] = bandMagnitudes.reduce(0, +) / Float(bandMagnitudes.count)
        }
        
        return bands
    }
    
    private func calculateSpectralCentroid(_ magnitudes: [Float]) -> Float {
        var weightedSum: Float = 0
        var totalMagnitude: Float = 0
        
        for (i, magnitude) in magnitudes.enumerated() {
            let frequency = Float(i) * Float(sampleRate) / Float(frameSize)
            weightedSum += frequency * magnitude
            totalMagnitude += magnitude
        }
        
        return totalMagnitude > 0 ? weightedSum / totalMagnitude : 0
    }
    
    private func calculateSpectralFlatness(_ magnitudes: [Float]) -> Float {
        let geometricMean = magnitudes.reduce(1.0) { $0 * $1 }
        let arithmeticMean = magnitudes.reduce(0.0, +) / Float(magnitudes.count)
        
        return arithmeticMean > 0 ? geometricMean / arithmeticMean : 0
    }
} 