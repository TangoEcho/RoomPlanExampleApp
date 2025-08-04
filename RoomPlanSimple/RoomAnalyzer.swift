import Foundation
import RoomPlan
import ARKit
import simd

class RoomAnalyzer: ObservableObject {
    @Published var identifiedRooms: [IdentifiedRoom] = []
    @Published var furnitureItems: [FurnitureItem] = []
    @Published var roomConnections: [RoomConnection] = []
    
    struct IdentifiedRoom {
        let id = UUID()
        let type: RoomType
        let bounds: CapturedRoom.Surface
        let center: simd_float3
        let area: Float
        let confidence: Float
        let wallPoints: [simd_float2] // Actual room boundary points from RoomPlan
        let doorways: [simd_float2] // Door/opening positions from RoomPlan
    }
    
    struct FurnitureItem {
        let id = UUID()
        let category: CapturedRoom.Object.Category
        let position: simd_float3
        let dimensions: simd_float3
        let roomId: UUID?
        let confidence: Float
    }
    
    struct RoomConnection {
        let roomA: UUID
        let roomB: UUID
        let doorPosition: simd_float3
        let type: ConnectionType
    }
    
    enum ConnectionType {
        case door
        case archway
        case opening
    }
    
    func analyzeCapturedRoom(_ capturedRoom: CapturedRoom) {
        identifyRoomTypes(from: capturedRoom)
        catalogFurniture(from: capturedRoom)
        mapRoomConnections(from: capturedRoom)
    }
    
    // MARK: - Apple RoomPlan Data Processing
    
    private func identifyRoomTypes(from capturedRoom: CapturedRoom) {
        var rooms: [IdentifiedRoom] = []
        
        print("🏠 Analyzing \(capturedRoom.floors.count) floor surfaces and \(capturedRoom.objects.count) objects")
        
        // Use Apple's intended approach: process each floor surface directly
        if capturedRoom.floors.count == 1 && capturedRoom.objects.count > 5 {
            print("🔍 Single floor with furniture - segmenting into logical rooms")
            rooms = segmentSingleFloorIntoRooms(capturedRoom: capturedRoom)
        } else {
            // Multiple floors detected - process each separately
            for surface in capturedRoom.floors {
                let room = createRoomFromRoomPlanSurface(surface: surface, capturedRoom: capturedRoom)
                rooms.append(room)
            }
        }
        
        print("✅ Identified \(rooms.count) rooms: \(rooms.map { $0.type.rawValue }.joined(separator: ", "))")
        
        DispatchQueue.main.async {
            self.identifiedRooms = rooms
        }
    }
    
    private func createRoomFromRoomPlanSurface(surface: CapturedRoom.Surface, capturedRoom: CapturedRoom) -> IdentifiedRoom {
        let roomType = classifyRoomByFurniture(surface: surface, objects: capturedRoom.objects)
        let center = extractSurfaceCenter(surface)
        let area = calculateSurfaceArea(surface)
        
        // Use RoomPlan's surface data directly for room boundaries
        let wallPoints = createRoomBoundaryFromSurface(surface)
        let doorways = extractDoorwaysFromRoomPlan(capturedRoom: capturedRoom)
        
        return IdentifiedRoom(
            type: roomType,
            bounds: surface,
            center: center,
            area: area,
            confidence: calculateRoomTypeConfidence(roomType: roomType, objects: capturedRoom.objects, surface: surface),
            wallPoints: wallPoints,
            doorways: doorways
        )
    }
    
    private func segmentSingleFloorIntoRooms(capturedRoom: CapturedRoom) -> [IdentifiedRoom] {
        let mainFloor = capturedRoom.floors.first!
        let furnitureGroups = clusterFurnitureByProximity(capturedRoom.objects)
        
        print("   Found \(furnitureGroups.count) furniture clusters")
        
        var rooms: [IdentifiedRoom] = []
        
        for (index, group) in furnitureGroups.enumerated() {
            let roomType = classifyRoomFromFurnitureGroup(group)
            let roomCenter = calculateCenterFromFurniture(group)
            
            // Create room boundary based on furniture cluster area
            let roomBoundary = createRoomBoundaryFromFurnitureCluster(group, floor: mainFloor)
            let roomArea = calculateAreaFromWallPoints(roomBoundary)
            let doorways = extractDoorwaysFromRoomPlan(capturedRoom: capturedRoom)
            
            let room = IdentifiedRoom(
                type: roomType,
                bounds: mainFloor,
                center: roomCenter,
                area: roomArea,
                confidence: calculateConfidenceFromFurniture(group, roomType: roomType),
                wallPoints: roomBoundary,
                doorways: doorways
            )
            
            rooms.append(room)
            print("   Room \(index + 1): \(roomType.rawValue) with \(group.count) furniture items")
        }
        
        // Ensure at least one room exists
        if rooms.isEmpty {
            let fallbackRoom = createRoomFromRoomPlanSurface(surface: mainFloor, capturedRoom: capturedRoom)
            rooms.append(fallbackRoom)
        }
        
        return rooms
    }
    
    // MARK: - RoomPlan Geometry Extraction
    
    private func createRoomBoundaryFromSurface(_ surface: CapturedRoom.Surface) -> [simd_float2] {
        let center = extractSurfaceCenter(surface)
        let dimensions = surface.dimensions
        let transform = surface.transform
        
        print("🏗️ Creating room boundary from RoomPlan surface")
        print("   Center: (\(String(format: "%.2f", center.x)), \(String(format: "%.2f", center.z)))")
        print("   Dimensions: \(String(format: "%.2f", dimensions.x)) x \(String(format: "%.2f", dimensions.z))")
        
        // Ensure minimum room size for visibility
        let roomWidth = max(dimensions.x, 1.0)
        let roomDepth = max(dimensions.z, 1.0)
        
        let halfWidth = roomWidth / 2
        let halfDepth = roomDepth / 2
        
        // Extract rotation from transform matrix
        let rotation = atan2(transform.columns.0.z, transform.columns.0.x)
        
        // Create corners in local space
        let corners = [
            simd_float2(-halfWidth, -halfDepth), // bottom-left
            simd_float2(halfWidth, -halfDepth),  // bottom-right
            simd_float2(halfWidth, halfDepth),   // top-right
            simd_float2(-halfWidth, halfDepth)   // top-left
        ]
        
        // Transform to world coordinates
        let center2D = simd_float2(center.x, center.z)
        return corners.map { corner in
            let rotatedX = corner.x * cos(rotation) - corner.y * sin(rotation)
            let rotatedZ = corner.x * sin(rotation) + corner.y * cos(rotation)
            return center2D + simd_float2(rotatedX, rotatedZ)
        }
    }
    
    private func createRoomBoundaryFromFurnitureCluster(_ furniture: [CapturedRoom.Object], floor: CapturedRoom.Surface) -> [simd_float2] {
        let furnitureCenter = calculateCenterFromFurniture(furniture)
        let furnitureBounds = calculateBoundsFromFurniture(furniture)
        
        // Create room boundary with padding around furniture
        let padding: Float = 1.5
        let roomWidth = max(furnitureBounds.max.x - furnitureBounds.min.x + padding * 2, 2.0)
        let roomDepth = max(furnitureBounds.max.z - furnitureBounds.min.z + padding * 2, 2.0)
        
        let halfWidth = roomWidth / 2
        let halfDepth = roomDepth / 2
        let center2D = simd_float2(furnitureCenter.x, furnitureCenter.z)
        
        return [
            center2D + simd_float2(-halfWidth, -halfDepth), // bottom-left
            center2D + simd_float2(halfWidth, -halfDepth),  // bottom-right
            center2D + simd_float2(halfWidth, halfDepth),   // top-right
            center2D + simd_float2(-halfWidth, halfDepth)   // top-left
        ]
    }
    
    private func extractDoorwaysFromRoomPlan(capturedRoom: CapturedRoom) -> [simd_float2] {
        var doorways: [simd_float2] = []
        
        // Use RoomPlan's built-in door/window/opening detection
        for door in capturedRoom.doors {
            let pos = simd_float3(door.transform.columns.3.x, door.transform.columns.3.y, door.transform.columns.3.z)
            doorways.append(simd_float2(pos.x, pos.z))
        }
        
        for window in capturedRoom.windows {
            let pos = simd_float3(window.transform.columns.3.x, window.transform.columns.3.y, window.transform.columns.3.z)
            doorways.append(simd_float2(pos.x, pos.z))
        }
        
        for opening in capturedRoom.openings {
            let pos = simd_float3(opening.transform.columns.3.x, opening.transform.columns.3.y, opening.transform.columns.3.z)
            doorways.append(simd_float2(pos.x, pos.z))
        }
        
        return doorways
    }
    
    // MARK: - Helper Methods
    
    private func extractSurfaceCenter(_ surface: CapturedRoom.Surface) -> simd_float3 {
        let transform = surface.transform
        return simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
    
    private func calculateSurfaceArea(_ surface: CapturedRoom.Surface) -> Float {
        let area = surface.dimensions.x * surface.dimensions.z
        return area > 0 ? area : 10.0 // Fallback to reasonable minimum
    }
    
    private func calculateAreaFromWallPoints(_ points: [simd_float2]) -> Float {
        guard points.count >= 3 else { return 0.0 }
        
        // Shoelace formula for polygon area
        var area: Float = 0.0
        let n = points.count
        
        for i in 0..<n {
            let j = (i + 1) % n
            area += points[i].x * points[j].y
            area -= points[j].x * points[i].y
        }
        
        return abs(area) / 2.0
    }
    
    private func clusterFurnitureByProximity(_ objects: [CapturedRoom.Object]) -> [[CapturedRoom.Object]] {
        let clusterDistance: Float = 2.5
        var clusters: [[CapturedRoom.Object]] = []
        var unprocessed = objects
        
        while !unprocessed.isEmpty {
            var currentCluster = [unprocessed.removeFirst()]
            
            var foundNewItems = true
            while foundNewItems {
                foundNewItems = false
                
                for (index, item) in unprocessed.enumerated().reversed() {
                    let itemPos = simd_float3(item.transform.columns.3.x, item.transform.columns.3.y, item.transform.columns.3.z)
                    
                    let isNearCluster = currentCluster.contains { clusterItem in
                        let clusterPos = simd_float3(clusterItem.transform.columns.3.x, clusterItem.transform.columns.3.y, clusterItem.transform.columns.3.z)
                        return simd_distance(itemPos, clusterPos) <= clusterDistance
                    }
                    
                    if isNearCluster {
                        currentCluster.append(item)
                        unprocessed.remove(at: index)
                        foundNewItems = true
                    }
                }
            }
            
            if currentCluster.count >= 2 {
                clusters.append(currentCluster)
            }
        }
        
        return splitConflictingClusters(clusters)
    }
    
    private func splitConflictingClusters(_ clusters: [[CapturedRoom.Object]]) -> [[CapturedRoom.Object]] {
        var resultClusters: [[CapturedRoom.Object]] = []
        
        for cluster in clusters {
            let hasBedroomFurniture = cluster.contains { $0.category == .bed }
            let hasBathroomFurniture = cluster.contains { $0.category == .toilet || $0.category == .bathtub }
            let hasKitchenFurniture = cluster.contains { $0.category == .refrigerator || $0.category == .oven }
            
            // Split conflicting room types
            if (hasBedroomFurniture && hasBathroomFurniture) || 
               (hasBedroomFurniture && hasKitchenFurniture) ||
               (hasBathroomFurniture && hasKitchenFurniture) {
                
                var bedroomItems: [CapturedRoom.Object] = []
                var bathroomItems: [CapturedRoom.Object] = []
                var kitchenItems: [CapturedRoom.Object] = []
                var otherItems: [CapturedRoom.Object] = []
                
                for item in cluster {
                    switch item.category {
                    case .bed:
                        bedroomItems.append(item)
                    case .toilet, .bathtub:
                        bathroomItems.append(item)
                    case .refrigerator, .oven, .dishwasher:
                        kitchenItems.append(item)
                    default:
                        otherItems.append(item)
                    }
                }
                
                if !bedroomItems.isEmpty { resultClusters.append(bedroomItems + otherItems.prefix(otherItems.count / 2)) }
                if !bathroomItems.isEmpty { resultClusters.append(bathroomItems) }
                if !kitchenItems.isEmpty { resultClusters.append(kitchenItems) }
            } else {
                resultClusters.append(cluster)
            }
        }
        
        return resultClusters
    }
    
    private func classifyRoomFromFurnitureGroup(_ furniture: [CapturedRoom.Object]) -> RoomType {
        var scores = [RoomType: Int]()
        
        for item in furniture {
            switch item.category {
            case .bed:
                scores[.bedroom, default: 0] += 4
            case .toilet, .bathtub:
                scores[.bathroom, default: 0] += 4
            case .refrigerator, .oven, .dishwasher:
                scores[.kitchen, default: 0] += 3
            case .sofa, .television:
                scores[.livingRoom, default: 0] += 3
            case .table:
                scores[.diningRoom, default: 0] += 2
            case .sink:
                scores[.kitchen, default: 0] += 2
                scores[.bathroom, default: 0] += 1
            default:
                break
            }
        }
        
        return scores.max(by: { $0.value < $1.value })?.key ?? .unknown
    }
    
    private func classifyRoomByFurniture(surface: CapturedRoom.Surface, objects: [CapturedRoom.Object]) -> RoomType {
        let nearbyObjects = objects.filter { object in
            let objectPos = simd_float3(object.transform.columns.3.x, object.transform.columns.3.y, object.transform.columns.3.z)
            let surfaceCenter = extractSurfaceCenter(surface)
            let distance = simd_distance(objectPos, surfaceCenter)
            return distance <= 5.0 // Within 5m of surface center
        }
        
        return classifyRoomFromFurnitureGroup(nearbyObjects)
    }
    
    private func calculateCenterFromFurniture(_ furniture: [CapturedRoom.Object]) -> simd_float3 {
        let positions = furniture.map { simd_float3($0.transform.columns.3.x, $0.transform.columns.3.y, $0.transform.columns.3.z) }
        let sum = positions.reduce(simd_float3(0, 0, 0)) { $0 + $1 }
        return sum / Float(positions.count)
    }
    
    private func calculateBoundsFromFurniture(_ furniture: [CapturedRoom.Object]) -> (min: simd_float3, max: simd_float3) {
        let positions = furniture.map { simd_float3($0.transform.columns.3.x, $0.transform.columns.3.y, $0.transform.columns.3.z) }
        
        let minX = positions.map { $0.x }.min() ?? 0
        let maxX = positions.map { $0.x }.max() ?? 0
        let minZ = positions.map { $0.z }.min() ?? 0
        let maxZ = positions.map { $0.z }.max() ?? 0
        let y = positions.first?.y ?? 0
        
        return (min: simd_float3(minX, y, minZ), max: simd_float3(maxX, y, maxZ))
    }
    
    private func calculateConfidenceFromFurniture(_ furniture: [CapturedRoom.Object], roomType: RoomType) -> Float {
        let relevantCount = furniture.filter { item in
            switch roomType {
            case .kitchen:
                return [.refrigerator, .oven, .dishwasher, .sink].contains(item.category)
            case .bedroom:
                return [.bed].contains(item.category)
            case .bathroom:
                return [.toilet, .bathtub, .sink].contains(item.category)
            case .livingRoom:
                return [.sofa, .television].contains(item.category)
            case .diningRoom:
                return [.table, .chair].contains(item.category)
            default:
                return false
            }
        }.count
        
        return furniture.isEmpty ? 0.3 : Float(relevantCount) / Float(furniture.count)
    }
    
    private func calculateRoomTypeConfidence(roomType: RoomType, objects: [CapturedRoom.Object], surface: CapturedRoom.Surface) -> Float {
        return calculateConfidenceFromFurniture(objects, roomType: roomType)
    }
    
    // MARK: - Room Containment
    
    func findRoomContaining(position: simd_float3) -> IdentifiedRoom? {
        print("🔍 Checking room containment for position (\(String(format: "%.2f", position.x)), \(String(format: "%.2f", position.z)))")
        
        for room in identifiedRooms {
            print("   Testing room \(room.type.rawValue) at (\(String(format: "%.2f", room.center.x)), \(String(format: "%.2f", room.center.z)))")
            
            if room.wallPoints.count >= 3 {
                let isInside = isPointInPolygon(simd_float2(position.x, position.z), polygon: room.wallPoints)
                print("     Polygon test: \(isInside)")
                if isInside {
                    return room
                }
            }
        }
        
        print("   ❌ Position not found in any room")
        return nil
    }
    
    private func isPointInPolygon(_ point: simd_float2, polygon: [simd_float2]) -> Bool {
        guard polygon.count > 2 else { return false }
        
        var inside = false
        var j = polygon.count - 1
        
        for i in 0..<polygon.count {
            let xi = polygon[i].x
            let yi = polygon[i].y
            let xj = polygon[j].x
            let yj = polygon[j].y
            
            if ((yi > point.y) != (yj > point.y)) && (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi) {
                inside = !inside
            }
            j = i
        }
        
        return inside
    }
    
    // MARK: - Catalog and Connections (Simplified)
    
    private func catalogFurniture(from capturedRoom: CapturedRoom) {
        var furniture: [FurnitureItem] = []
        
        for object in capturedRoom.objects {
            let item = FurnitureItem(
                category: object.category,
                position: simd_float3(object.transform.columns.3.x, object.transform.columns.3.y, object.transform.columns.3.z),
                dimensions: object.dimensions,
                roomId: nil, // Could be assigned based on containment
                confidence: 1.0
            )
            furniture.append(item)
        }
        
        DispatchQueue.main.async {
            self.furnitureItems = furniture
        }
    }
    
    private func mapRoomConnections(from capturedRoom: CapturedRoom) {
        // Simplified - no connections for now
        DispatchQueue.main.async {
            self.roomConnections = []
        }
    }
}