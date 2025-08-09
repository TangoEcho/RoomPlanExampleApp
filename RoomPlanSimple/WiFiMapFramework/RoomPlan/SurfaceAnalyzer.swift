import Foundation
import ModelIO
import SceneKit

/// Analyzes furniture objects to extract viable placement surfaces for WiFi equipment
public class SurfaceAnalyzer {
    
    // MARK: - Properties
    
    private let minSurfaceArea: Double = 0.01 // 10cm x 10cm minimum
    private let maxSurfaceArea: Double = 4.0  // 2m x 2m maximum
    private let minDeviceSpace: Double = 0.15 // 15cm x 15cm for typical extender
    
    // MARK: - Public Interface
    
    /// Extract placement surfaces from a furniture mesh
    /// - Parameters:
    ///   - mesh: The MDLMesh representing the furniture
    ///   - furnitureType: The detected furniture type
    ///   - bounds: The furniture's bounding box
    /// - Returns: Array of viable placement surfaces
    public func extractPlacementSurfaces(
        from mesh: MDLMesh,
        furnitureType: FurnitureType,
        bounds: BoundingBox
    ) -> [PlacementSurface] {
        
        switch furnitureType {
        case .table, .desk, .counter:
            return extractHorizontalTopSurfaces(from: mesh, bounds: bounds, furnitureType: furnitureType)
            
        case .dresser, .cabinet, .nightstand:
            return extractTopSurfacesWithHeightCheck(from: mesh, bounds: bounds, furnitureType: furnitureType)
            
        case .shelf:
            return extractShelfSurfaces(from: mesh, bounds: bounds)
            
        case .sofa, .chair, .bed, .stool:
            return [] // Not suitable for placement
        }
    }
    
    // MARK: - Surface Extraction Methods
    
    private func extractHorizontalTopSurfaces(
        from mesh: MDLMesh,
        bounds: BoundingBox,
        furnitureType: FurnitureType
    ) -> [PlacementSurface] {
        
        // For tables, desks, and counters, the top surface is the primary placement area
        let topSurfaceZ = bounds.max.z
        let surfaceCenter = Point3D(
            x: bounds.center.x,
            y: bounds.center.y,
            z: topSurfaceZ
        )
        
        let surfaceArea = bounds.size.x * bounds.size.y
        
        // Validate surface is large enough
        guard surfaceArea >= minSurfaceArea else { return [] }
        
        // Check if there's enough clear space (accounting for typical furniture edge design)
        let effectiveArea = calculateEffectivePlacementArea(
            totalArea: surfaceArea,
            bounds: bounds,
            furnitureType: furnitureType
        )
        
        guard effectiveArea >= minDeviceSpace * minDeviceSpace else { return [] }
        
        let accessibility = evaluateAccessibility(
            furnitureType: furnitureType,
            height: topSurfaceZ,
            bounds: bounds
        )
        
        let surface = PlacementSurface(
            id: UUID(),
            center: surfaceCenter,
            normal: Vector3D(x: 0, y: 0, z: 1), // Pointing up
            area: effectiveArea,
            accessibility: accessibility,
            powerProximity: nil // Will be calculated later
        )
        
        return [surface]
    }
    
    private func extractTopSurfacesWithHeightCheck(
        from mesh: MDLMesh,
        bounds: BoundingBox,
        furnitureType: FurnitureType
    ) -> [PlacementSurface] {
        
        let height = bounds.size.z
        
        // Only use top surface if furniture is not too tall (accessibility)
        // and not too short (visibility and cable management)
        guard height >= 0.5 && height <= 1.8 else { return [] }
        
        return extractHorizontalTopSurfaces(from: mesh, bounds: bounds, furnitureType: furnitureType)
    }
    
    private func extractShelfSurfaces(from mesh: MDLMesh, bounds: BoundingBox) -> [PlacementSurface] {
        var surfaces: [PlacementSurface] = []
        
        // Analyze mesh to find horizontal shelf levels
        let shelfLevels = detectShelfLevels(from: mesh, bounds: bounds)
        
        for (index, shelfZ) in shelfLevels.enumerated() {
            // Skip very high or very low shelves
            guard shelfZ >= 0.3 && shelfZ <= 2.2 else { continue }
            
            let surfaceCenter = Point3D(
                x: bounds.center.x,
                y: bounds.center.y,
                z: shelfZ
            )
            
            // Estimate shelf depth (typical shelf is not full furniture depth)
            let shelfDepth = min(bounds.size.y, 0.4) // Max 40cm depth
            let shelfArea = bounds.size.x * shelfDepth
            
            guard shelfArea >= minSurfaceArea else { continue }
            
            let accessibility = evaluateShelfAccessibility(
                shelfIndex: index,
                height: shelfZ,
                totalShelves: shelfLevels.count
            )
            
            let surface = PlacementSurface(
                id: UUID(),
                center: surfaceCenter,
                normal: Vector3D(x: 0, y: 0, z: 1),
                area: shelfArea,
                accessibility: accessibility,
                powerProximity: nil
            )
            
            surfaces.append(surface)
        }
        
        return surfaces
    }
    
    // MARK: - Shelf Analysis
    
    private func detectShelfLevels(from mesh: MDLMesh, bounds: BoundingBox) -> [Double] {
        // For MVP, use heuristic based on furniture height
        // TODO: Implement proper mesh analysis for actual shelf detection
        
        let totalHeight = bounds.size.z
        let estimatedShelfCount = max(1, Int(totalHeight / 0.35)) // ~35cm between shelves
        
        var shelfLevels: [Double] = []
        let baseZ = bounds.min.z
        
        for i in 0..<min(estimatedShelfCount, 6) { // Max 6 shelves
            let shelfHeight = 0.02 // 2cm shelf thickness
            let shelfSpacing = totalHeight / Double(estimatedShelfCount)
            let shelfZ = baseZ + (Double(i) * shelfSpacing) + shelfHeight
            
            shelfLevels.append(shelfZ)
        }
        
        return shelfLevels
    }
    
    // MARK: - Surface Quality Assessment
    
    private func calculateEffectivePlacementArea(
        totalArea: Double,
        bounds: BoundingBox,
        furnitureType: FurnitureType
    ) -> Double {
        
        // Account for furniture edge design and unusable areas
        let edgeReduction: Double
        
        switch furnitureType {
        case .table:
            edgeReduction = 0.85 // Tables often have clean tops
        case .desk:
            edgeReduction = 0.75 // Desks may have keyboards, monitors
        case .counter:
            edgeReduction = 0.60 // Counters often have appliances, clutter
        case .dresser, .cabinet:
            edgeReduction = 0.70 // Some areas may be blocked by items
        case .nightstand:
            edgeReduction = 0.80 // Usually small and clean
        default:
            edgeReduction = 0.70
        }
        
        let effectiveArea = totalArea * edgeReduction
        
        // Ensure minimum device footprint is available
        let deviceFootprint = minDeviceSpace * minDeviceSpace
        return max(effectiveArea, deviceFootprint)
    }
    
    private func evaluateAccessibility(
        furnitureType: FurnitureType,
        height: Double,
        bounds: BoundingBox
    ) -> SurfaceAccessibility {
        
        // Height-based accessibility
        let heightScore: Double
        switch height {
        case 0.6...1.2:  // Ideal working height
            heightScore = 1.0
        case 0.4..<0.6, 1.2..<1.8:  // Acceptable but not ideal
            heightScore = 0.7
        case 0.2..<0.4, 1.8..<2.2:  // Poor but usable
            heightScore = 0.4
        default:  // Too high or too low
            heightScore = 0.1
        }
        
        // Furniture type based accessibility
        let typeScore: Double
        switch furnitureType {
        case .table, .desk:
            typeScore = 1.0  // Usually clear and accessible
        case .counter:
            typeScore = 0.8  // May have appliances or clutter
        case .dresser, .nightstand:
            typeScore = 0.7  // May have personal items
        case .cabinet:
            typeScore = 0.6  // Often has items on top
        default:
            typeScore = 0.5
        }
        
        // Size-based accessibility (larger surfaces are generally better)
        let area = bounds.size.x * bounds.size.y
        let sizeScore: Double
        switch area {
        case 0.5...:     // Large surface
            sizeScore = 1.0
        case 0.2..<0.5:  // Medium surface
            sizeScore = 0.8
        case 0.05..<0.2: // Small surface
            sizeScore = 0.6
        default:         // Very small surface
            sizeScore = 0.4
        }
        
        let overallScore = (heightScore + typeScore + sizeScore) / 3.0
        
        switch overallScore {
        case 0.8...:
            return .excellent
        case 0.6..<0.8:
            return .good
        default:
            return .poor
        }
    }
    
    private func evaluateShelfAccessibility(
        shelfIndex: Int,
        height: Double,
        totalShelves: Int
    ) -> SurfaceAccessibility {
        
        // Height accessibility
        let heightScore: Double
        switch height {
        case 0.8...1.6:  // Eye level range
            heightScore = 1.0
        case 0.4..<0.8, 1.6..<2.0:  // Reachable but not ideal
            heightScore = 0.7
        case 0.2..<0.4, 2.0..<2.2:  // Difficult to reach
            heightScore = 0.4
        default:
            heightScore = 0.1
        }
        
        // Position on shelf unit (middle shelves are usually more accessible)
        let positionScore: Double
        if totalShelves <= 2 {
            positionScore = 1.0  // All shelves are accessible
        } else {
            let normalizedPosition = Double(shelfIndex) / Double(totalShelves - 1)
            switch normalizedPosition {
            case 0.3...0.7:  // Middle shelves
                positionScore = 1.0
            case 0.1..<0.3, 0.7..<0.9:  // Lower-middle, upper-middle
                positionScore = 0.8
            default:  // Top or bottom shelves
                positionScore = 0.5
            }
        }
        
        let overallScore = (heightScore + positionScore) / 2.0
        
        switch overallScore {
        case 0.8...:
            return .excellent
        case 0.6..<0.8:
            return .good
        default:
            return .poor
        }
    }
}

// MARK: - Surface Validation

extension SurfaceAnalyzer {
    
    /// Validate that a surface can accommodate a specific device
    /// - Parameters:
    ///   - surface: The placement surface to validate
    ///   - deviceDimensions: The device dimensions (width, depth, height)
    /// - Returns: True if the device fits with clearance
    public func canAccommodateDevice(
        surface: PlacementSurface,
        deviceDimensions: Vector3D
    ) -> Bool {
        
        let requiredArea = deviceDimensions.x * deviceDimensions.y
        let availableArea = surface.area
        
        // Require 20% extra space around device for clearance
        let requiredAreaWithClearance = requiredArea * 1.2
        
        return availableArea >= requiredAreaWithClearance
    }
    
    /// Calculate optimal device placement on a surface
    /// - Parameters:
    ///   - surface: The placement surface
    ///   - deviceDimensions: The device dimensions
    /// - Returns: Optimal position and orientation for the device
    public func calculateOptimalPlacement(
        on surface: PlacementSurface,
        for deviceDimensions: Vector3D
    ) -> DevicePlacement? {
        
        guard canAccommodateDevice(surface: surface, deviceDimensions: deviceDimensions) else {
            return nil
        }
        
        // For now, place device at surface center
        // TODO: Consider edge proximity, cable routing, etc.
        let devicePosition = Point3D(
            x: surface.center.x,
            y: surface.center.y,
            z: surface.center.z + deviceDimensions.z / 2
        )
        
        return DevicePlacement(
            position: devicePosition,
            orientation: 0.0, // No rotation for now
            surfaceId: surface.id
        )
    }
}

// MARK: - Supporting Types

public struct DevicePlacement {
    public let position: Point3D
    public let orientation: Double // Rotation around Z-axis in radians
    public let surfaceId: UUID
    
    public init(position: Point3D, orientation: Double, surfaceId: UUID) {
        self.position = position
        self.orientation = orientation
        self.surfaceId = surfaceId
    }
}