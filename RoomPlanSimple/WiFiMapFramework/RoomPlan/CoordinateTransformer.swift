import Foundation
import simd

/// Handles coordinate system transformations between RoomPlan and WiFiMap coordinate systems
public class CoordinateTransformer {
    
    // MARK: - Properties
    
    private var roomPlanOrigin: Point3D = Point3D.zero
    private var roomPlanScale: Double = 1.0
    private var rotationMatrix: simd_float3x3 = matrix_identity_float3x3
    private var isConfigured: Bool = false
    
    // MARK: - Configuration
    
    /// Configure the coordinate transformation parameters
    /// - Parameters:
    ///   - origin: The origin point in the target coordinate system
    ///   - scale: Scale factor to apply
    ///   - rotation: Rotation matrix for coordinate system alignment
    public func configure(
        origin: Point3D,
        scale: Double = 1.0,
        rotation: simd_float3x3 = matrix_identity_float3x3
    ) {
        self.roomPlanOrigin = origin
        self.roomPlanScale = scale
        self.rotationMatrix = rotation
        self.isConfigured = true
    }
    
    /// Auto-configure transformation based on room model bounds
    /// - Parameter roomModel: The parsed room model
    public func autoConfigure(from roomModel: RoomModel) {
        // Set origin to room bounds minimum (bottom-left-front corner)
        self.roomPlanOrigin = roomModel.bounds.min
        
        // Auto-scale based on room size (normalize to reasonable units)
        let roomSize = roomModel.bounds.size
        let maxDimension = max(roomSize.x, max(roomSize.y, roomSize.z))
        
        // If room seems too small or too large, apply scaling
        if maxDimension < 1.0 {
            // Room seems to be in millimeters or other small units
            self.roomPlanScale = 0.001
        } else if maxDimension > 100.0 {
            // Room seems to be in centimeters or other large units
            self.roomPlanScale = 0.01
        } else {
            // Room is in reasonable units (meters)
            self.roomPlanScale = 1.0
        }
        
        // Default to no rotation
        self.rotationMatrix = matrix_identity_float3x3
        self.isConfigured = true
    }
    
    // MARK: - Point Transformation
    
    /// Transform a point from RoomPlan coordinate system to WiFiMap coordinate system
    /// - Parameter roomPlanPoint: Point in RoomPlan coordinates
    /// - Returns: Transformed point in WiFiMap coordinates
    public func transformPoint(_ roomPlanPoint: Point3D) -> Point3D {
        guard isConfigured else {
            // If not configured, return point as-is
            return roomPlanPoint
        }
        
        // Apply scale first
        var scaledPoint = Point3D(
            x: roomPlanPoint.x * roomPlanScale,
            y: roomPlanPoint.y * roomPlanScale,
            z: roomPlanPoint.z * roomPlanScale
        )
        
        // Apply rotation
        let simdPoint = simd_float3(
            Float(scaledPoint.x),
            Float(scaledPoint.y),
            Float(scaledPoint.z)
        )
        let rotatedPoint = rotationMatrix * simdPoint
        
        // Apply translation (origin offset)
        return Point3D(
            x: Double(rotatedPoint.x) + roomPlanOrigin.x,
            y: Double(rotatedPoint.y) + roomPlanOrigin.y,
            z: Double(rotatedPoint.z) + roomPlanOrigin.z
        )
    }
    
    /// Transform multiple points efficiently
    /// - Parameter points: Array of points in RoomPlan coordinates
    /// - Returns: Array of transformed points in WiFiMap coordinates
    public func transformPoints(_ points: [Point3D]) -> [Point3D] {
        return points.map(transformPoint)
    }
    
    // MARK: - Vector Transformation
    
    /// Transform a vector from RoomPlan coordinate system to WiFiMap coordinate system
    /// Note: Vectors don't get translation, only rotation and scale
    /// - Parameter roomPlanVector: Vector in RoomPlan coordinates
    /// - Returns: Transformed vector in WiFiMap coordinates
    public func transformVector(_ roomPlanVector: Vector3D) -> Vector3D {
        guard isConfigured else {
            return roomPlanVector
        }
        
        // Apply scale
        var scaledVector = Vector3D(
            x: roomPlanVector.x * roomPlanScale,
            y: roomPlanVector.y * roomPlanScale,
            z: roomPlanVector.z * roomPlanScale
        )
        
        // Apply rotation
        let simdVector = simd_float3(
            Float(scaledVector.x),
            Float(scaledVector.y),
            Float(scaledVector.z)
        )
        let rotatedVector = rotationMatrix * simdVector
        
        return Vector3D(
            x: Double(rotatedVector.x),
            y: Double(rotatedVector.y),
            z: Double(rotatedVector.z)
        )
    }
    
    // MARK: - Bounding Box Transformation
    
    /// Transform a bounding box from RoomPlan to WiFiMap coordinates
    /// - Parameter roomPlanBounds: Bounding box in RoomPlan coordinates
    /// - Returns: Transformed bounding box in WiFiMap coordinates
    public func transformBoundingBox(_ roomPlanBounds: BoundingBox) -> BoundingBox {
        // Transform the corner points
        let transformedMin = transformPoint(roomPlanBounds.min)
        let transformedMax = transformPoint(roomPlanBounds.max)
        
        // After rotation, min/max might be swapped, so recalculate
        let finalMin = Point3D(
            x: min(transformedMin.x, transformedMax.x),
            y: min(transformedMin.y, transformedMax.y),
            z: min(transformedMin.z, transformedMax.z)
        )
        
        let finalMax = Point3D(
            x: max(transformedMin.x, transformedMax.x),
            y: max(transformedMin.y, transformedMax.y),
            z: max(transformedMin.z, transformedMax.z)
        )
        
        return BoundingBox(min: finalMin, max: finalMax)
    }
    
    // MARK: - Inverse Transformation
    
    /// Transform a point from WiFiMap coordinate system back to RoomPlan coordinate system
    /// - Parameter wifiMapPoint: Point in WiFiMap coordinates
    /// - Returns: Point in RoomPlan coordinates
    public func inverseTransformPoint(_ wifiMapPoint: Point3D) -> Point3D {
        guard isConfigured else {
            return wifiMapPoint
        }
        
        // Remove translation
        var translatedPoint = Point3D(
            x: wifiMapPoint.x - roomPlanOrigin.x,
            y: wifiMapPoint.y - roomPlanOrigin.y,
            z: wifiMapPoint.z - roomPlanOrigin.z
        )
        
        // Apply inverse rotation
        let simdPoint = simd_float3(
            Float(translatedPoint.x),
            Float(translatedPoint.y),
            Float(translatedPoint.z)
        )
        let inverseRotation = rotationMatrix.transpose
        let rotatedPoint = inverseRotation * simdPoint
        
        // Apply inverse scale
        return Point3D(
            x: Double(rotatedPoint.x) / roomPlanScale,
            y: Double(rotatedPoint.y) / roomPlanScale,
            z: Double(rotatedPoint.z) / roomPlanScale
        )
    }
    
    // MARK: - Coordinate System Analysis
    
    /// Analyze and detect the coordinate system characteristics of a room model
    /// - Parameter roomModel: The room model to analyze
    /// - Returns: Detected coordinate system information
    public func analyzeCoordinateSystem(of roomModel: RoomModel) -> CoordinateSystemInfo {
        let bounds = roomModel.bounds
        let size = bounds.size
        
        // Detect likely units based on typical room sizes
        let units = detectUnits(from: size)
        
        // Detect orientation based on furniture alignment
        let orientation = detectOrientation(from: roomModel)
        
        // Check for coordinate system consistency
        let consistency = checkConsistency(roomModel: roomModel)
        
        return CoordinateSystemInfo(
            detectedUnits: units,
            orientation: orientation,
            consistency: consistency,
            recommendedScale: calculateRecommendedScale(for: units),
            requiresTransformation: units != .meters || orientation != .standard
        )
    }
    
    private func detectUnits(from size: Vector3D) -> CoordinateUnits {
        let maxDimension = max(size.x, max(size.y, size.z))
        let minDimension = min(size.x, min(size.y, size.z))
        
        // Typical room dimensions
        if maxDimension < 0.1 && minDimension > 0.001 {
            return .millimeters
        } else if maxDimension < 10.0 && minDimension > 0.1 {
            return .centimeters
        } else if maxDimension < 1000.0 && minDimension > 1.0 {
            return .meters
        } else {
            return .unknown
        }
    }
    
    private func detectOrientation(from roomModel: RoomModel) -> CoordinateOrientation {
        // For now, assume standard orientation
        // TODO: Implement furniture-based orientation detection
        return .standard
    }
    
    private func checkConsistency(roomModel: RoomModel) -> ConsistencyLevel {
        var issues = 0
        
        // Check for reasonable room bounds
        let size = roomModel.bounds.size
        if size.x <= 0 || size.y <= 0 || size.z <= 0 {
            issues += 1
        }
        
        // Check for reasonable furniture sizes relative to room
        for furniture in roomModel.furniture {
            let furnitureSize = furniture.bounds.size
            if furnitureSize.x > size.x || furnitureSize.y > size.y || furnitureSize.z > size.z {
                issues += 1
            }
        }
        
        // Check wall consistency
        if roomModel.walls.isEmpty && roomModel.bounds.volume > 0 {
            issues += 1
        }
        
        switch issues {
        case 0:
            return .high
        case 1...2:
            return .medium
        default:
            return .low
        }
    }
    
    private func calculateRecommendedScale(for units: CoordinateUnits) -> Double {
        switch units {
        case .millimeters:
            return 0.001  // mm to m
        case .centimeters:
            return 0.01   // cm to m
        case .meters:
            return 1.0    // m to m
        case .unknown:
            return 1.0    // No scaling for unknown units
        }
    }
}

// MARK: - Supporting Types

public struct CoordinateSystemInfo {
    public let detectedUnits: CoordinateUnits
    public let orientation: CoordinateOrientation
    public let consistency: ConsistencyLevel
    public let recommendedScale: Double
    public let requiresTransformation: Bool
    
    public var isReliable: Bool {
        return consistency != .low && detectedUnits != .unknown
    }
}

public enum CoordinateUnits {
    case millimeters
    case centimeters
    case meters
    case unknown
    
    public var description: String {
        switch self {
        case .millimeters: return "mm"
        case .centimeters: return "cm"
        case .meters: return "m"
        case .unknown: return "unknown"
        }
    }
}

public enum CoordinateOrientation {
    case standard    // X-right, Y-forward, Z-up
    case rotated90   // 90° rotation around Z
    case rotated180  // 180° rotation around Z
    case rotated270  // 270° rotation around Z
    case flipped     // Y-axis flipped
    case custom      // Non-standard orientation
}

public enum ConsistencyLevel {
    case high    // No detected issues
    case medium  // Minor issues detected
    case low     // Major issues detected
}

// MARK: - Transformation Utilities

extension CoordinateTransformer {
    
    /// Create a rotation matrix for aligning coordinate systems
    /// - Parameter orientation: The detected orientation to correct
    /// - Returns: Rotation matrix for correction
    public static func createRotationMatrix(for orientation: CoordinateOrientation) -> simd_float3x3 {
        switch orientation {
        case .standard:
            return matrix_identity_float3x3
            
        case .rotated90:
            return simd_float3x3(
                simd_float3(0, -1, 0),
                simd_float3(1,  0, 0),
                simd_float3(0,  0, 1)
            )
            
        case .rotated180:
            return simd_float3x3(
                simd_float3(-1,  0, 0),
                simd_float3( 0, -1, 0),
                simd_float3( 0,  0, 1)
            )
            
        case .rotated270:
            return simd_float3x3(
                simd_float3( 0, 1, 0),
                simd_float3(-1, 0, 0),
                simd_float3( 0, 0, 1)
            )
            
        case .flipped:
            return simd_float3x3(
                simd_float3(1,  0, 0),
                simd_float3(0, -1, 0),
                simd_float3(0,  0, 1)
            )
            
        case .custom:
            // Return identity for now, would need specific transformation
            return matrix_identity_float3x3
        }
    }
    
    /// Automatically configure transformation based on detected coordinate system
    /// - Parameter roomModel: The room model to configure for
    public func autoConfigureFromAnalysis(_ roomModel: RoomModel) {
        let analysis = analyzeCoordinateSystem(of: roomModel)
        
        // Set origin to room minimum bounds
        let origin = roomModel.bounds.min
        
        // Apply recommended scale
        let scale = analysis.recommendedScale
        
        // Create rotation matrix for orientation correction
        let rotation = Self.createRotationMatrix(for: analysis.orientation)
        
        configure(origin: origin, scale: scale, rotation: rotation)
    }
}