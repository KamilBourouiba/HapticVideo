import Foundation

public struct HapticEvent: Codable {
    public let time: Double
    public let intensity: Double
    public let sharpness: Double
    public let type: HapticType
    
    public init(time: Double, intensity: Double, sharpness: Double, type: HapticType) {
        self.time = time
        self.intensity = intensity
        self.sharpness = sharpness
        self.type = type
    }
}

public enum HapticType: String, Codable {
    case heavy
    case medium
    case light
    case soft
} 