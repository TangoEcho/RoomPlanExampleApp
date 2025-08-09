import Foundation
import simd

// MARK: - Standardized Coordinate System
// All 3D coordinates use simd_float3 for performance and consistency with ARKit/SceneKit

// Re-export types for convenience
public typealias Point3D = simd_float3
public typealias Vector3D = simd_float3

// MARK: - WiFi Frequency Band Support

enum WiFiFrequencyBand: Float {
    case band2_4GHz = 2437  // Channel 6 center frequency
    case band5GHz = 5200    // Channel 40 center frequency  
    case band6GHz = 6525    // 6GHz band center
    
    /// Create from frequency string
    static func from(_ frequencyString: String) -> WiFiFrequencyBand {
        if frequencyString.contains("2.4") || frequencyString.contains("2G") {
            return .band2_4GHz
        } else if frequencyString.contains("5") || frequencyString.contains("5G") {
            return .band5GHz
        } else if frequencyString.contains("6") || frequencyString.contains("6G") {
            return .band6GHz
        } else {
            return .band5GHz // Default to 5GHz
        }
    }
    
    /// Get display name
    var displayName: String {
        switch self {
        case .band2_4GHz: return "2.4 GHz"
        case .band5GHz: return "5 GHz"
        case .band6GHz: return "6 GHz"
        }
    }
}

// MARK: - Environment Type Support

enum IndoorEnvironment {
    case residential
    case office
    case commercial
    case industrial
    
    /// Convert from RoomType
    static func from(roomType: RoomType) -> IndoorEnvironment {
        switch roomType {
        case .kitchen, .livingRoom, .bedroom, .bathroom, .diningRoom, .hallway, .closet, .laundryRoom:
            return .residential
        case .office:
            return .office
        case .garage:
            return .industrial
        case .unknown:
            return .residential // Default
        }
    }
}

// MARK: - WiFiMeasurement Extensions

extension WiFiMeasurement {
    /// Convert to multi-band measurement format for advanced RF modeling
    func toAdvancedMeasurement(floor: Int = 0) -> AdvancedWiFiMeasurement {
        return AdvancedWiFiMeasurement(
            location: location,
            timestamp: timestamp,
            signalStrength: Float(signalStrength),
            frequency: WiFiFrequencyBand.from(frequency),
            speed: Float(speed),
            floor: floor,
            roomType: roomType
        )
    }
}

struct AdvancedWiFiMeasurement {
    let location: simd_float3
    let timestamp: Date
    let signalStrength: Float  // dBm
    let frequency: WiFiFrequencyBand
    let speed: Float  // Mbps
    let floor: Int
    let roomType: RoomType?
}

// MARK: - Network Device Extensions

extension NetworkDeviceManager.NetworkDevice {
    /// Convert to transmitter model for RF calculations
    func toTransmitter(floor: Int = 0) -> RFTransmitter {
        return RFTransmitter(
            position: position,
            type: type == .router ? .router : .extender,
            transmitPower: type == .router ? 20.0 : 17.0, // dBm
            antennaGain: type == .router ? 5.0 : 3.0,     // dBi
            floor: floor
        )
    }
}

struct RFTransmitter {
    let position: simd_float3
    let type: TransmitterType
    let transmitPower: Float  // dBm
    let antennaGain: Float    // dBi
    let floor: Int
    
    enum TransmitterType {
        case router
        case extender
        case accessPoint
    }
}

// MARK: - Room Model Conversion

extension RoomAnalyzer.IdentifiedRoom {
    /// Convert to WiFiMap RoomModel format
    func toWiFiMapRoomModel() -> WiFiMapRoomModel {
        return WiFiMapRoomModel(
            bounds: BoundingBox(
                min: simd_float3(
                    Float(bounds.min.x),
                    Float(bounds.min.y), 
                    Float(bounds.min.z)
                ),
                max: simd_float3(
                    Float(bounds.max.x),
                    Float(bounds.max.y),
                    Float(bounds.max.z)
                )
            ),
            walls: wallPoints.enumerated().compactMap { (index, point) in
                guard index < wallPoints.count - 1 else { return nil }
                let nextPoint = wallPoints[index + 1]
                return WiFiMapWall(
                    start: simd_float3(point.x, 0, point.y),
                    end: simd_float3(nextPoint.x, 0, nextPoint.y),
                    height: 2.5, // Standard ceiling height
                    material: .drywall // Default material
                )
            },
            furniture: [], // Will be populated from furniture analysis
            floor: 0 // Current floor
        )
    }
}

struct WiFiMapRoomModel {
    let bounds: BoundingBox
    let walls: [WiFiMapWall]
    let furniture: [WiFiMapFurniture]
    let floor: Int
}

struct WiFiMapWall {
    let start: simd_float3
    let end: simd_float3
    let height: Float
    let material: WallMaterial
    
    enum WallMaterial {
        case drywall
        case concrete
        case brick
        case glass
        case wood
        
        func attenuation(for band: WiFiFrequencyBand) -> Float {
            switch (self, band) {
            case (.drywall, .band2_4GHz): return 3.0
            case (.drywall, .band5GHz): return 4.0
            case (.drywall, .band6GHz): return 5.0
            case (.concrete, .band2_4GHz): return 10.0
            case (.concrete, .band5GHz): return 12.0
            case (.concrete, .band6GHz): return 15.0
            case (.brick, .band2_4GHz): return 6.0
            case (.brick, .band5GHz): return 8.0
            case (.brick, .band6GHz): return 10.0
            case (.glass, .band2_4GHz): return 2.0
            case (.glass, .band5GHz): return 3.0
            case (.glass, .band6GHz): return 4.0
            case (.wood, .band2_4GHz): return 4.0
            case (.wood, .band5GHz): return 5.0
            case (.wood, .band6GHz): return 6.0
            }
        }
    }
}

struct WiFiMapFurniture {
    let position: simd_float3
    let dimensions: simd_float3
    let category: String
    let confidence: Float
}

// MARK: - BoundingBox Helper

struct BoundingBox {
    let min: simd_float3
    let max: simd_float3
    
    var center: simd_float3 {
        return (min + max) * 0.5
    }
    
    var size: simd_float3 {
        return max - min
    }
    
    func contains(_ point: simd_float3) -> Bool {
        return point.x >= min.x && point.x <= max.x &&
               point.y >= min.y && point.y <= max.y &&
               point.z >= min.z && point.z <= max.z
    }
}