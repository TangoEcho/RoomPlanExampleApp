import Foundation
import RoomPlan
import simd

class NetworkDeviceManager: ObservableObject {
    
    // MARK: - Data Models
    
    struct NetworkDevice {
        let id = UUID()
        let type: DeviceType
        let position: simd_float3
        let surfaceId: UUID? // Associated furniture/surface ID
        let isUserPlaced: Bool
        let confidence: Float // Placement confidence score (0-1)
        
        enum DeviceType: String, CaseIterable {
            case router = "Router"
            case extender = "WiFi Extender"
            
            var emoji: String {
                switch self {
                case .router:
                    return "📡"
                case .extender:
                    return "📶"
                }
            }
        }
    }
    
    struct SuitableSurface {
        let furnitureItem: RoomAnalyzer.FurnitureItem
        let suitabilityScore: Float // 0-1, higher is better
        let placementPosition: simd_float3 // Recommended placement point on surface
        
        enum SurfaceType {
            case table // Primary choice
            case counter // Secondary choice  
            case sofa // Last resort
            case other
        }
        
        var surfaceType: SurfaceType {
            switch furnitureItem.category {
            case .table:
                return .table
            case .sofa:
                return .sofa
            default:
                return .other
            }
        }
    }
    
    // MARK: - Properties
    
    @Published var router: NetworkDevice?
    @Published var extenders: [NetworkDevice] = []
    @Published var suitableSurfaces: [SuitableSurface] = []
    @Published var isRouterPlacementMode: Bool = false
    
    private let minExtenderHeight: Float = 0.5 // Minimum height for extender placement
    private let maxExtenderHeight: Float = 2.0 // Maximum height for extender placement
    
    // MARK: - Router Management
    
    func enableRouterPlacementMode() {
        isRouterPlacementMode = true
        print("📡 Router placement mode enabled - tap in AR to place router")
    }
    
    func disableRouterPlacementMode() {
        isRouterPlacementMode = false
        print("📡 Router placement mode disabled")
    }
    
    func placeRouter(at position: simd_float3) {
        let newRouter = NetworkDevice(
            type: .router,
            position: position,
            surfaceId: nil,
            isUserPlaced: true,
            confidence: 1.0 // User-placed has maximum confidence
        )
        
        router = newRouter
        isRouterPlacementMode = false
        
        print("📡 Router placed at position (\(String(format: "%.2f", position.x)), \(String(format: "%.2f", position.y)), \(String(format: "%.2f", position.z)))")
        
        // Trigger extender recommendations after router placement
        recommendExtenderPlacements()
    }
    
    // MARK: - Surface Detection and Analysis
    
    func analyzeSuitableSurfaces(from furnitureItems: [RoomAnalyzer.FurnitureItem]) {
        let surfaces = furnitureItems.compactMap { item -> SuitableSurface? in
            guard isSuitableForExtender(item) else { return nil }
            
            let score = calculateSuitabilityScore(for: item)
            let placementPosition = calculateOptimalPlacementPosition(for: item)
            
            return SuitableSurface(
                furnitureItem: item,
                suitabilityScore: score,
                placementPosition: placementPosition
            )
        }
        
        // Sort by suitability score (highest first)
        suitableSurfaces = surfaces.sorted { $0.suitabilityScore > $1.suitabilityScore }
        
        print("🔍 Found \(suitableSurfaces.count) suitable surfaces for extender placement")
        for (index, surface) in suitableSurfaces.prefix(3).enumerated() {
            print("   \(index + 1). \(surface.furnitureItem.category) (score: \(String(format: "%.2f", surface.suitabilityScore)))")
        }
    }
    
    private func isSuitableForExtender(_ item: RoomAnalyzer.FurnitureItem) -> Bool {
        // Check height constraints
        let height = item.position.y
        guard height >= minExtenderHeight && height <= maxExtenderHeight else {
            return false
        }
        
        // Check furniture category
        switch item.category {
        case .table:
            return true // Primary choice
        case .sofa:
            return true // Secondary choice
        default:
            return false // MVP: Only tables and sofas
        }
    }
    
    private func calculateSuitabilityScore(for item: RoomAnalyzer.FurnitureItem) -> Float {
        var score: Float = 0.0
        
        // Base score by furniture type
        switch item.category {
        case .table:
            score += 0.8 // Tables are ideal
        case .sofa:
            score += 0.4 // Sofas are OK but not ideal
        default:
            score += 0.1
        }
        
        // Height bonus (waist height is ideal)
        let idealHeight: Float = 1.0
        let heightDifference = abs(item.position.y - idealHeight)
        let heightScore = max(0, 0.2 - heightDifference * 0.1)
        score += heightScore
        
        // Surface area bonus (larger surfaces are better)
        let surfaceArea = item.dimensions.x * item.dimensions.z
        let areaScore = min(0.2, surfaceArea * 0.02)
        score += areaScore
        
        // Confidence bonus from RoomPlan
        score += item.confidence * 0.1
        
        return min(1.0, score)
    }
    
    private func calculateOptimalPlacementPosition(for item: RoomAnalyzer.FurnitureItem) -> simd_float3 {
        // For MVP, place at center of surface with small height offset
        let heightOffset: Float = 0.1 // 10cm above surface
        return simd_float3(
            item.position.x,
            item.position.y + (item.dimensions.y / 2) + heightOffset,
            item.position.z
        )
    }
    
    // MARK: - Extender Placement
    
    func recommendExtenderPlacements() {
        guard !suitableSurfaces.isEmpty else {
            print("⚠️ No suitable surfaces found for extender placement")
            return
        }
        
        // MVP: Just use the best available surface
        if let bestSurface = suitableSurfaces.first {
            placeExtenderOnSurface(bestSurface)
        }
    }
    
    func placeExtenderOnBestSurface() -> NetworkDevice? {
        guard let bestSurface = suitableSurfaces.first else {
            print("⚠️ No suitable surfaces available for extender")
            return nil
        }
        
        return placeExtenderOnSurface(bestSurface)
    }
    
    @discardableResult
    private func placeExtenderOnSurface(_ surface: SuitableSurface) -> NetworkDevice {
        let extender = NetworkDevice(
            type: .extender,
            position: surface.placementPosition,
            surfaceId: surface.furnitureItem.id,
            isUserPlaced: false,
            confidence: surface.suitabilityScore
        )
        
        extenders.append(extender)
        
        print("📶 Extender placed on \(surface.furnitureItem.category) at (\(String(format: "%.2f", surface.placementPosition.x)), \(String(format: "%.2f", surface.placementPosition.y)), \(String(format: "%.2f", surface.placementPosition.z)))")
        print("   Placement confidence: \(String(format: "%.2f", surface.suitabilityScore))")
        
        return extender
    }
    
    // MARK: - Device Management
    
    func removeRouter() {
        router = nil
        print("📡 Router removed")
    }
    
    func removeExtender(_ extender: NetworkDevice) {
        extenders.removeAll { $0.id == extender.id }
        print("📶 Extender removed")
    }
    
    func clearAllDevices() {
        router = nil
        extenders.removeAll()
        print("🧹 All network devices cleared")
    }
    
    // MARK: - Status and Information
    
    func getDeviceCount() -> (routers: Int, extenders: Int) {
        return (routers: router != nil ? 1 : 0, extenders: extenders.count)
    }
    
    func getAllDevices() -> [NetworkDevice] {
        var devices: [NetworkDevice] = []
        if let router = router {
            devices.append(router)
        }
        devices.append(contentsOf: extenders)
        return devices
    }
    
    func getPlacementSummary() -> String {
        let deviceCount = getDeviceCount()
        let surfaceCount = suitableSurfaces.count
        
        var summary = "Network Setup: "
        if deviceCount.routers > 0 {
            summary += "\(deviceCount.routers) router"
        }
        if deviceCount.extenders > 0 {
            if deviceCount.routers > 0 { summary += ", " }
            summary += "\(deviceCount.extenders) extender\(deviceCount.extenders > 1 ? "s" : "")"
        }
        if deviceCount.routers == 0 && deviceCount.extenders == 0 {
            summary += "No devices placed"
        }
        summary += " | \(surfaceCount) suitable surfaces found"
        
        return summary
    }
}

// MARK: - Future WiFi Range Calculations

extension NetworkDeviceManager {
    
    // TODO: Implement WiFi range and coverage calculations
    func calculateWiFiCoverage(for device: NetworkDevice) -> Float {
        // Placeholder for future implementation
        // Would consider walls, distance, interference, etc.
        return 0.8
    }
    
    func findOptimalExtenderPositions(basedOnCoverage coverage: [simd_float3: Float]) -> [simd_float3] {
        // Placeholder for future smart placement algorithm
        // Would analyze WiFi dead zones and recommend optimal positions
        return []
    }
}