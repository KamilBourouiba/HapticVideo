import Foundation
import Accelerate

struct AudioAnalysis {
    static func calculateRMS(_ data: UnsafeMutablePointer<Float>, frameCount: Int) -> [Float] {
        let hopLength = 512
        let nFrames = frameCount / hopLength
        var rms = [Float](repeating: 0, count: nFrames)
        
        for i in 0..<nFrames {
            let start = i * hopLength
            let end = min(start + hopLength, frameCount)
            let frameData = data + start
            let frameLength = end - start
            
            var sum: Float = 0
            vDSP_measqv(frameData, 1, &sum, vDSP_Length(frameLength))
            rms[i] = sqrt(sum / Float(frameLength))
        }
        
        return rms
    }
    
    static func calculateFrequencies(_ data: UnsafeMutablePointer<Float>, frameCount: Int) -> [Float] {
        let hopLength = 512
        let nFrames = frameCount / hopLength
        var frequencies = [Float](repeating: 0, count: nFrames)
        
        // Configuration de la FFT
        let log2n = vDSP_Length(log2(Float(hopLength)))
        let n = vDSP_Length(1 << log2n)
        let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        
        defer {
            vDSP_destroy_fftsetup(fftSetup)
        }
        
        for i in 0..<nFrames {
            let start = i * hopLength
            let end = min(start + hopLength, frameCount)
            let frameData = data + start
            let frameLength = end - start
            
            // Préparer les données pour la FFT
            var realIn = [Float](repeating: 0, count: Int(n))
            var imagIn = [Float](repeating: 0, count: Int(n))
            var realOut = [Float](repeating: 0, count: Int(n))
            var imagOut = [Float](repeating: 0, count: Int(n))
            
            // Copier les données
            for j in 0..<frameLength {
                realIn[j] = frameData[j]
            }
            
            // Appliquer la fenêtre de Hann
            var window = [Float](repeating: 0, count: Int(n))
            vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
            vDSP_vmul(realIn, 1, window, 1, &realIn, 1, vDSP_Length(n))
            
            // Créer la structure de données complexe
            var complex = DSPSplitComplex(realp: &realOut, imagp: &imagOut)
            
            // Effectuer la FFT
            vDSP_ctoz([DSPComplex](zip(realIn, imagIn)), 2, &complex, 1, vDSP_Length(n/2))
            vDSP_fft_zrip(fftSetup, &complex, 1, log2n, FFTDirection(kFFTDirection_Forward))
            
            // Calculer la magnitude
            var magnitudes = [Float](repeating: 0, count: Int(n/2))
            vDSP_zvmags(&complex, 1, &magnitudes, 1, vDSP_Length(n/2))
            
            // Trouver la fréquence dominante
            var maxMagnitude: Float = 0
            var maxIndex: vDSP_Length = 0
            vDSP_maxvi(magnitudes, 1, &maxMagnitude, &maxIndex, vDSP_Length(n/2))
            
            frequencies[i] = Float(maxIndex) * 22050.0 / Float(n)
        }
        
        return frequencies
    }
    
    static func calculateSpectralRolloff(_ data: UnsafeMutablePointer<Float>, frameCount: Int) -> [Float] {
        let hopLength = 512
        let nFrames = frameCount / hopLength
        var rolloff = [Float](repeating: 0, count: nFrames)
        
        // Configuration de la FFT
        let log2n = vDSP_Length(log2(Float(hopLength)))
        let n = vDSP_Length(1 << log2n)
        let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        
        defer {
            vDSP_destroy_fftsetup(fftSetup)
        }
        
        for i in 0..<nFrames {
            let start = i * hopLength
            let end = min(start + hopLength, frameCount)
            let frameData = data + start
            let frameLength = end - start
            
            // Préparer les données pour la FFT
            var realIn = [Float](repeating: 0, count: Int(n))
            var imagIn = [Float](repeating: 0, count: Int(n))
            var realOut = [Float](repeating: 0, count: Int(n))
            var imagOut = [Float](repeating: 0, count: Int(n))
            
            // Copier les données
            for j in 0..<frameLength {
                realIn[j] = frameData[j]
            }
            
            // Appliquer la fenêtre de Hann
            var window = [Float](repeating: 0, count: Int(n))
            vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
            vDSP_vmul(realIn, 1, window, 1, &realIn, 1, vDSP_Length(n))
            
            // Créer la structure de données complexe
            var complex = DSPSplitComplex(realp: &realOut, imagp: &imagOut)
            
            // Effectuer la FFT
            vDSP_ctoz([DSPComplex](zip(realIn, imagIn)), 2, &complex, 1, vDSP_Length(n/2))
            vDSP_fft_zrip(fftSetup, &complex, 1, log2n, FFTDirection(kFFTDirection_Forward))
            
            // Calculer la magnitude
            var magnitudes = [Float](repeating: 0, count: Int(n/2))
            vDSP_zvmags(&complex, 1, &magnitudes, 1, vDSP_Length(n/2))
            
            // Calculer le rolloff spectral
            let threshold: Float = 0.85
            var totalEnergy: Float = 0
            vDSP_sve(magnitudes, 1, &totalEnergy, vDSP_Length(n/2))
            
            var cumulativeEnergy: Float = 0
            var rolloffIndex = 0
            
            for j in 0..<Int(n/2) {
                cumulativeEnergy += magnitudes[j]
                if cumulativeEnergy >= threshold * totalEnergy {
                    rolloffIndex = j
                    break
                }
            }
            
            rolloff[i] = Float(rolloffIndex) / Float(n/2)
        }
        
        return rolloff
    }
    
    static func calculateSpectralBandwidth(_ data: UnsafeMutablePointer<Float>, frameCount: Int) -> [Float] {
        let hopLength = 512
        let nFrames = frameCount / hopLength
        var bandwidth = [Float](repeating: 0, count: nFrames)
        
        // Configuration de la FFT
        let log2n = vDSP_Length(log2(Float(hopLength)))
        let n = vDSP_Length(1 << log2n)
        let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        
        defer {
            vDSP_destroy_fftsetup(fftSetup)
        }
        
        for i in 0..<nFrames {
            let start = i * hopLength
            let end = min(start + hopLength, frameCount)
            let frameData = data + start
            let frameLength = end - start
            
            // Préparer les données pour la FFT
            var realIn = [Float](repeating: 0, count: Int(n))
            var imagIn = [Float](repeating: 0, count: Int(n))
            var realOut = [Float](repeating: 0, count: Int(n))
            var imagOut = [Float](repeating: 0, count: Int(n))
            
            // Copier les données
            for j in 0..<frameLength {
                realIn[j] = frameData[j]
            }
            
            // Appliquer la fenêtre de Hann
            var window = [Float](repeating: 0, count: Int(n))
            vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
            vDSP_vmul(realIn, 1, window, 1, &realIn, 1, vDSP_Length(n))
            
            // Créer la structure de données complexe
            var complex = DSPSplitComplex(realp: &realOut, imagp: &imagOut)
            
            // Effectuer la FFT
            vDSP_ctoz([DSPComplex](zip(realIn, imagIn)), 2, &complex, 1, vDSP_Length(n/2))
            vDSP_fft_zrip(fftSetup, &complex, 1, log2n, FFTDirection(kFFTDirection_Forward))
            
            // Calculer la magnitude
            var magnitudes = [Float](repeating: 0, count: Int(n/2))
            vDSP_zvmags(&complex, 1, &magnitudes, 1, vDSP_Length(n/2))
            
            // Calculer la bande passante spectrale
            var totalEnergy: Float = 0
            vDSP_sve(magnitudes, 1, &totalEnergy, vDSP_Length(n/2))
            
            if totalEnergy > 0 {
                var weightedSum: Float = 0
                for j in 0..<Int(n/2) {
                    let frequency = Float(j) * 22050.0 / Float(n)
                    weightedSum += frequency * magnitudes[j]
                }
                
                bandwidth[i] = weightedSum / totalEnergy
            }
        }
        
        return bandwidth
    }
    
    static func interpolate(_ data: [Float], targetCount: Int) -> [Float] {
        let sourceCount = data.count
        var result = [Float](repeating: 0, count: targetCount)
        
        for i in 0..<targetCount {
            let sourceIndex = Float(i) * Float(sourceCount - 1) / Float(targetCount - 1)
            let sourceIndexInt = Int(sourceIndex)
            let sourceIndexFrac = sourceIndex - Float(sourceIndexInt)
            
            if sourceIndexInt + 1 < sourceCount {
                result[i] = data[sourceIndexInt] * (1 - sourceIndexFrac) + data[sourceIndexInt + 1] * sourceIndexFrac
            } else {
                result[i] = data[sourceIndexInt]
            }
        }
        
        return result
    }
    
    static func smoothData(_ data: [Float]) -> [Float] {
        let windowSize = 11
        let halfWindow = windowSize / 2
        var result = [Float](repeating: 0, count: data.count)
        
        for i in 0..<data.count {
            var sum: Float = 0
            var count = 0
            
            for j in max(0, i - halfWindow)...min(data.count - 1, i + halfWindow) {
                sum += data[j]
                count += 1
            }
            
            result[i] = sum / Float(count)
        }
        
        return result
    }
    
    static func calculateIntensityThreshold(_ data: [Float]) -> Float {
        var mean: Float = 0
        var stdDev: Float = 0
        
        // Calculer la moyenne
        vDSP_meanv(data, 1, &mean, vDSP_Length(data.count))
        
        // Calculer l'écart-type
        var squaredDifferences = [Float](repeating: 0, count: data.count)
        for i in 0..<data.count {
            squaredDifferences[i] = pow(data[i] - mean, 2)
        }
        vDSP_meanv(squaredDifferences, 1, &stdDev, vDSP_Length(data.count))
        stdDev = sqrt(stdDev)
        
        return mean + 0.5 * stdDev
    }
} 