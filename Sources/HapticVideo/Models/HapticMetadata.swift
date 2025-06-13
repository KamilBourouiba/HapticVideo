import Foundation

public struct HapticMetadata: Codable {
    public let version: Int
    public let fps: Int
    public let duration: Double
    public let totalFrames: Int
    
    public init(version: Int = 3, fps: Int, duration: Double, totalFrames: Int) {
        self.version = version
        self.fps = fps
        self.duration = duration
        self.totalFrames = totalFrames
    }
} 