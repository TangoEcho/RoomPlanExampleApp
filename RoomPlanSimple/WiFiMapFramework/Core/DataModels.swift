import Foundation
import simd

// MARK: - Spatial Data Structures
// Using simd_float3 for all 3D coordinates for performance and consistency with ARKit/SceneKit

public typealias Point3D = simd_float3
public typealias Vector3D = simd_float3

// MARK: - Extensions for simd_float3

extension simd_float3 {
    /// Calculate distance to another point
    public func distance(to other: simd_float3) -> Float {
        return simd_distance(self, other)
    }
    
    /// Calculate midpoint to another point
    public func midpoint(to other: simd_float3) -> simd_float3 {
        return (self + other) * 0.5
    }
    
    /// Move point by a vector offset
    public func moved(by offset: simd_float3) -> simd_float3 {
        return self + offset
    }
    
    /// Vector magnitude (length)
    public var magnitude: Float {
        return simd_length(self)
    }
    
    /// Normalized vector (unit vector)
    public var normalized: simd_float3 {
        let mag = magnitude
        guard mag > 0 else { return .zero }
        return self / mag
    }
    
    /// Dot product with another vector
    public func dot(_ other: simd_float3) -> Float {
        return simd_dot(self, other)
    }
    
    /// Cross product with another vector
    public func cross(_ other: simd_float3) -> simd_float3 {
        return simd_cross(self, other)
    }
    
    /// Angle between vectors in radians
    public func angleFrom(_ other: simd_float3) -> Float {
        let dotProduct = dot(other)
        let magnitudes = magnitude * other.magnitude
        guard magnitudes > 0 else { return 0 }
        let cosAngle = max(-1, min(1, dotProduct / magnitudes))
        return acos(cosAngle)
    }
    
    /// Scale vector by a factor
    public func scaled(by factor: Float) -> simd_float3 {
        return self * factor
    }
}

/// Represents an axis-aligned bounding box
public struct BoundingBox: Codable, Hashable, Equatable {
    public let min: Point3D
    public let max: Point3D
    
    public init(min: Point3D, max: Point3D) {
        self.min = simd_float3(
            Swift.min(min.x, max.x),
            Swift.min(min.y, max.y),
            Swift.min(min.z, max.z)
        )
        self.max = simd_float3(
            Swift.max(min.x, max.x),
            Swift.max(min.y, max.y),
            Swift.max(min.z, max.z)
        )
    }
    
    /// Center point of the bounding box
    public var center: Point3D {
        return (min + max) * 0.5
    }
    
    /// Size of the bounding box
    public var size: Vector3D {
        return max - min
    }
    
    /// Volume of the bounding box
    public var volume: Float {
        let s = size
        return s.x * s.y * s.z
    }
    
    /// Check if a point is contained within the box
    public func contains(_ point: Point3D) -> Bool {
        return point.x >= min.x && point.x <= max.x &&
               point.y >= min.y && point.y <= max.y &&
               point.z >= min.z && point.z <= max.z
    }
    
    /// Check if this box intersects with another box
    public func intersects(_ other: BoundingBox) -> Bool {
        return min.x <= other.max.x && max.x >= other.min.x &&
               min.y <= other.max.y && max.y >= other.min.y &&
               min.z <= other.max.z && max.z >= other.min.z
    }
    
    /// Expand the box to include a point
    public func expanded(to point: Point3D) -> BoundingBox {
        return BoundingBox(
            min: simd_float3(
                Swift.min(min.x, point.x),
                Swift.min(min.y, point.y),
                Swift.min(min.z, point.z)
            ),
            max: simd_float3(
                Swift.max(max.x, point.x),
                Swift.max(max.y, point.y),
                Swift.max(max.z, point.z)
            )
        )
    }
    
    /// Expand the box by a margin
    public func expanded(by margin: Float) -> BoundingBox {
        let marginVec = simd_float3(margin, margin, margin)
        return BoundingBox(
            min: min - marginVec,
            max: max + marginVec
        )
    }
}

// MARK: - Room Model Structures

/// Complete model of a scanned room
public struct RoomModel: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let bounds: BoundingBox
    public let walls: [WallElement]
    public let furniture: [FurnitureItem]
    public let openings: [Opening]
    public let floor: FloorPlan
    
    public init(
        id: UUID,
        name: String,
        bounds: BoundingBox,
        walls: [WallElement],
        furniture: [FurnitureItem],
        openings: [Opening],
        floor: FloorPlan
    ) {
        self.id = id
        self.name = name
        self.bounds = bounds
        self.walls = walls
        self.furniture = furniture
        self.openings = openings
        self.floor = floor
    }
    
    /// Find placement surfaces of a specific accessibility level
    public func findSurfaces(ofType accessibility: SurfaceAccessibility) -> [PlacementSurface] {
        return furniture.flatMap(\.surfaces).filter { $0.accessibility == accessibility }
    }
    
    /// Calculate total room volume
    public func calculateVolume() -> Float {
        return bounds.volume
    }
    
    /// Get obstacles between two points (simplified line-of-sight check)
    public func getObstaclesBetween(_ from: Point3D, _ to: Point3D) -> [Obstacle] {
        var obstacles: [Obstacle] = []
        
        // Check wall intersections
        for wall in walls {
            if lineIntersectsWall(from: from, to: to, wall: wall) {
                obstacles.append(.wall(wall))
            }
        }
        
        // Check furniture intersections
        for furnitureItem in furniture {
            if lineIntersectsBounds(from: from, to: to, bounds: furnitureItem.bounds) {
                obstacles.append(.furniture(furnitureItem))
            }
        }
        
        return obstacles
    }
    
    private func lineIntersectsWall(from: Point3D, to: Point3D, wall: WallElement) -> Bool {
        // Simplified 2D line intersection check
        return linesIntersect2D(
            p1: Point2D(x: from.x, y: from.y),
            p2: Point2D(x: to.x, y: to.y),
            p3: Point2D(x: wall.startPoint.x, y: wall.startPoint.y),
            p4: Point2D(x: wall.endPoint.x, y: wall.endPoint.y)
        )
    }
    
    private func lineIntersectsBounds(from: Point3D, to: Point3D, bounds: BoundingBox) -> Bool {
        // Simple bounding box intersection check
        // This is a simplified implementation - proper ray-box intersection would be more accurate
        return bounds.contains(from) || bounds.contains(to) || 
               bounds.intersects(BoundingBox(min: from, max: to))
    }
    
    private func linesIntersect2D(p1: Point2D, p2: Point2D, p3: Point2D, p4: Point2D) -> Bool {
        let denom = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
        if abs(denom) < Float(1e-10) { return false }
        
        let t = ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / denom
        let u = -((p1.x - p2.x) * (p1.y - p3.y) - (p1.y - p2.y) * (p1.x - p3.x)) / denom
        
        return t >= 0 && t <= 1 && u >= 0 && u <= 1
    }
}

/// Represents a wall element in the room
public struct WallElement: Codable, Identifiable, Hashable {
    public let id: UUID
    public let startPoint: Point3D
    public let endPoint: Point3D
    public let height: Float
    public let thickness: Float
    public let material: WallMaterial
    
    public init(
        id: UUID,
        startPoint: Point3D,
        endPoint: Point3D,
        height: Float,
        thickness: Float,
        material: WallMaterial
    ) {
        self.id = id
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.height = height
        self.thickness = thickness
        self.material = material
    }
    
    /// Calculate wall length
    public var length: Float {
        return startPoint.distance(to: endPoint)
    }
    
    /// Get wall direction vector
    public var direction: Vector3D {
        return (endPoint - startPoint).normalized
    }
    
    /// Get wall normal vector (perpendicular, pointing right when facing along direction)
    public var normal: Vector3D {
        let wallDirection = direction
        return simd_float3(-wallDirection.y, wallDirection.x, 0).normalized
    }
    
    /// Calculate RF attenuation factor for a given frequency
    public func attenuationFactor(at frequency: Float) -> Float {
        return material.rfAttenuation(frequency: frequency)
    }
}

/// Materials that walls can be made of
public enum WallMaterial: String, Codable, CaseIterable {
    case drywall = "drywall"
    case concrete = "concrete"
    case brick = "brick"
    case wood = "wood"
    case glass = "glass"
    case metal = "metal"
    
    /// Get RF attenuation for this material at a specific frequency
    public func rfAttenuation(frequency: Float) -> Float {
        // Attenuation in dB - these are approximate values
        switch self {
        case .drywall:
            return frequency < 3000 ? 3.0 : 4.0
        case .concrete:
            return frequency < 3000 ? 15.0 : 20.0
        case .brick:
            return frequency < 3000 ? 10.0 : 13.0
        case .wood:
            return frequency < 3000 ? 2.0 : 3.0
        case .glass:
            return frequency < 3000 ? 2.0 : 3.0
        case .metal:
            return frequency < 3000 ? 25.0 : 30.0
        }
    }
}

/// Represents a piece of furniture in the room
public struct FurnitureItem: Codable, Identifiable, Hashable {
    public let id: UUID
    public let type: FurnitureType
    public let bounds: BoundingBox
    public let surfaces: [PlacementSurface]
    public let confidence: Float
    
    public init(
        id: UUID,
        type: FurnitureType,
        bounds: BoundingBox,
        surfaces: [PlacementSurface],
        confidence: Float
    ) {
        self.id = id
        self.type = type
        self.bounds = bounds
        self.surfaces = surfaces
        self.confidence = confidence
    }
    
    /// Whether this furniture is suitable for WiFi equipment placement
    public var isPlacementCandidate: Bool {
        switch type {
        case .table, .desk, .dresser, .shelf, .cabinet, .counter, .nightstand:
            return true
        case .sofa, .chair, .bed, .stool:
            return false
        }
    }
    
    /// Calculate surface area of the furniture
    public func surfaceArea() -> Float {
        return bounds.size.x * bounds.size.y
    }
}

/// Types of furniture that can be detected
public enum FurnitureType: String, Codable, CaseIterable {
    case table = "table"
    case desk = "desk"
    case dresser = "dresser"
    case shelf = "shelf"
    case cabinet = "cabinet"
    case counter = "counter"
    case nightstand = "nightstand"
    case sofa = "sofa"
    case chair = "chair"
    case bed = "bed"
    case stool = "stool"
}

/// Represents a surface suitable for equipment placement
public struct PlacementSurface: Codable, Identifiable, Hashable {
    public let id: UUID
    public let center: Point3D
    public let normal: Vector3D
    public let area: Float
    public let accessibility: SurfaceAccessibility
    public let powerProximity: Float?
    
    public init(
        id: UUID,
        center: Point3D,
        normal: Vector3D,
        area: Float,
        accessibility: SurfaceAccessibility,
        powerProximity: Float?
    ) {
        self.id = id
        self.center = center
        self.normal = normal
        self.area = area
        self.accessibility = accessibility
        self.powerProximity = powerProximity
    }
    
    /// Check if surface can accommodate a device of given dimensions
    public func isViableForDevice(_ deviceDimensions: Vector3D) -> Bool {
        let requiredArea = deviceDimensions.x * deviceDimensions.y
        return area >= requiredArea * 1.2 // 20% margin
    }
}

/// Accessibility levels for placement surfaces
public enum SurfaceAccessibility: String, Codable, CaseIterable {
    case excellent = "excellent"
    case good = "good"
    case poor = "poor"
    
    public var description: String {
        switch self {
        case .excellent: return "Excellent access, highly visible"
        case .good: return "Good access, reasonably visible"
        case .poor: return "Poor access, hard to reach"
        }
    }
}

/// Represents room openings (doors, windows, etc.)
public struct Opening: Codable, Identifiable, Hashable {
    public let id: UUID
    public let type: OpeningType
    public let bounds: BoundingBox
    public let isPassable: Bool
    
    public init(id: UUID, type: OpeningType, bounds: BoundingBox, isPassable: Bool) {
        self.id = id
        self.type = type
        self.bounds = bounds
        self.isPassable = isPassable
    }
    
    public enum OpeningType: String, Codable, CaseIterable {
        case door = "door"
        case window = "window"
        case opening = "opening"
    }
}

/// Represents the floor plan of the room
public struct FloorPlan: Codable, Hashable {
    public let bounds: BoundingBox
    public let area: Float
    
    public init(bounds: BoundingBox, area: Float) {
        self.bounds = bounds
        self.area = area
    }
}

/// Represents obstacles that can affect RF propagation
public enum Obstacle {
    case wall(WallElement)
    case furniture(FurnitureItem)
    case opening(Opening)
    
    /// Get RF attenuation caused by this obstacle
    public func rfAttenuation(frequency: Float) -> Float {
        switch self {
        case .wall(let wall):
            return wall.material.rfAttenuation(frequency: frequency)
        case .furniture(let furniture):
            // Simplified furniture attenuation based on type
            switch furniture.type {
            case .cabinet, .dresser:
                return 5.0 // Metal/wood furniture
            case .shelf:
                return 2.0 // Open furniture
            default:
                return 1.0 // Minimal attenuation
            }
        case .opening:
            return 0.0 // Openings don't attenuate
        }
    }
}

// MARK: - Helper Types

/// 2D point for simplified calculations
public struct Point2D {
    let x: Float
    let y: Float
    
    init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

// MARK: - WiFi Data Structures

/// Represents a WiFi measurement at a specific location
public struct WiFiMeasurement: Codable, Identifiable {
    public let id: UUID
    public let location: Point3D
    public let timestamp: Date
    public let bands: [BandMeasurement]
    public let deviceId: String
    
    public init(
        id: UUID,
        location: Point3D,
        timestamp: Date,
        bands: [BandMeasurement],
        deviceId: String
    ) {
        self.id = id
        self.location = location
        self.timestamp = timestamp
        self.bands = bands
        self.deviceId = deviceId
    }
    
    /// Get signal quality based on strongest band
    public func signalQuality() -> SignalQuality {
        let maxRSSI = bands.map(\.rssi).max() ?? -100.0
        return SignalQuality.fromRSSI(Float(maxRSSI))
    }
    
    /// Calculate average RSSI across all bands
    public func averageRSSI() -> Float {
        guard !bands.isEmpty else { return -100.0 }
        return Float(bands.reduce(0.0) { $0 + $1.rssi } / Double(bands.count))
    }
}

/// Measurement data for a specific frequency band
public struct BandMeasurement: Codable {
    public let frequency: Double        // MHz
    public let rssi: Double            // dBm
    public let snr: Double?            // dB
    public let channelWidth: Int       // MHz
    public let txRate: Double?         // Mbps
    public let rxRate: Double?         // Mbps
    
    public init(
        frequency: Double,
        rssi: Double,
        snr: Double?,
        channelWidth: Int,
        txRate: Double?,
        rxRate: Double?
    ) {
        self.frequency = frequency
        self.rssi = rssi
        self.snr = snr
        self.channelWidth = channelWidth
        self.txRate = txRate
        self.rxRate = rxRate
    }
}

/// WiFi signal quality levels
public enum SignalQuality: String, Codable, CaseIterable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    case unusable = "unusable"
    
    public static func fromRSSI(_ rssi: Float) -> SignalQuality {
        switch rssi {
        case -50...:
            return .excellent
        case -60..<(-50):
            return .good
        case -70..<(-60):
            return .fair
        case -80..<(-70):
            return .poor
        default:
            return .unusable
        }
    }
    
    public var description: String {
        switch self {
        case .excellent: return "Excellent signal strength"
        case .good: return "Good signal strength"
        case .fair: return "Fair signal strength"
        case .poor: return "Poor signal strength"
        case .unusable: return "Signal too weak"
        }
    }
}

/// Network configuration information
public struct NetworkConfiguration: Codable {
    public let routerLocation: Point3D
    public let routerSpec: DeviceSpec
    public let ssid: String
    public let securityType: SecurityType
    public let channels: [ChannelConfig]
    public let existingExtenders: [ExtenderInfo]
    
    public init(
        routerLocation: Point3D,
        routerSpec: DeviceSpec,
        ssid: String,
        securityType: SecurityType,
        channels: [ChannelConfig],
        existingExtenders: [ExtenderInfo]
    ) {
        self.routerLocation = routerLocation
        self.routerSpec = routerSpec
        self.ssid = ssid
        self.securityType = securityType
        self.channels = channels
        self.existingExtenders = existingExtenders
    }
    
    /// Get supported frequency bands
    public func supportedBands() -> [FrequencyBand] {
        return routerSpec.supportedStandards.flatMap { $0.supportedBands }
    }
}

/// Device specifications
public struct DeviceSpec: Codable {
    public let model: String
    public let manufacturer: String
    public let antennaGain: [Float]        // dBi per band
    public let txPower: [Float]            // dBm per band
    public let supportedStandards: [WiFiStandard]
    public let dimensions: Vector3D
    public let powerRequirement: Float     // Watts
    
    public init(
        model: String,
        manufacturer: String,
        antennaGain: [Float],
        txPower: [Float],
        supportedStandards: [WiFiStandard],
        dimensions: Vector3D,
        powerRequirement: Float
    ) {
        self.model = model
        self.manufacturer = manufacturer
        self.antennaGain = antennaGain
        self.txPower = txPower
        self.supportedStandards = supportedStandards
        self.dimensions = dimensions
        self.powerRequirement = powerRequirement
    }
}

/// WiFi standards and their capabilities
public enum WiFiStandard: String, Codable, CaseIterable {
    case wifi4 = "802.11n"
    case wifi5 = "802.11ac"
    case wifi6 = "802.11ax"
    case wifi6e = "802.11ax-6GHz"
    case wifi7 = "802.11be"
    
    public var supportedBands: [FrequencyBand] {
        switch self {
        case .wifi4:
            return [.band2_4GHz, .band5GHz]
        case .wifi5:
            return [.band5GHz]
        case .wifi6:
            return [.band2_4GHz, .band5GHz]
        case .wifi6e:
            return [.band2_4GHz, .band5GHz, .band6GHz]
        case .wifi7:
            return [.band2_4GHz, .band5GHz, .band6GHz]
        }
    }
}

/// Frequency bands
public enum FrequencyBand: Float, Codable, CaseIterable {
    case band2_4GHz = 2400
    case band5GHz = 5000
    case band6GHz = 6000
    
    public static func fromFrequency(_ frequency: Float) -> FrequencyBand {
        switch frequency {
        case 2400...2500:
            return .band2_4GHz
        case 5000...6000:
            return .band5GHz
        case 6000...7200:
            return .band6GHz
        default:
            return .band5GHz // Default fallback
        }
    }
}

/// Security types
public enum SecurityType: String, Codable, CaseIterable {
    case open = "open"
    case wep = "wep"
    case wpa = "wpa"
    case wpa2 = "wpa2"
    case wpa3 = "wpa3"
}

/// Channel configuration
public struct ChannelConfig: Codable {
    public let band: FrequencyBand
    public let channel: Int
    public let width: Int               // MHz
    public let power: Float            // dBm
    
    public init(band: FrequencyBand, channel: Int, width: Int, power: Float) {
        self.band = band
        self.channel = channel
        self.width = width
        self.power = power
    }
}

/// Existing extender information
public struct ExtenderInfo: Codable, Identifiable {
    public let id: UUID
    public let location: Point3D
    public let deviceSpec: DeviceSpec
    public let status: ExtenderStatus
    
    public init(id: UUID, location: Point3D, deviceSpec: DeviceSpec, status: ExtenderStatus) {
        self.id = id
        self.location = location
        self.deviceSpec = deviceSpec
        self.status = status
    }
    
    public enum ExtenderStatus: String, Codable {
        case active = "active"
        case inactive = "inactive"
        case error = "error"
    }
}