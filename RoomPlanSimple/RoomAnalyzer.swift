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
        let wallPoints: [simd_float2] // Actual room boundary points
        let doorways: [simd_float2] // Door/opening positions
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
    
    @available(iOS 17.0, *)
    func analyzeCapturedRoom(_ capturedRoom: CapturedRoom) {
        identifyRoomTypes(from: capturedRoom)
        catalogFurniture(from: capturedRoom)
        mapRoomConnections(from: capturedRoom)
    }
    
    @available(iOS 17.0, *)
    private func identifyRoomTypes(from capturedRoom: CapturedRoom) {
        var rooms: [IdentifiedRoom] = []
        
        for surface in capturedRoom.floors {
            let roomType = classifyRoom(surface: surface, objects: capturedRoom.objects)
            let center = calculateSurfaceCenter(surface)
            let area = calculateSurfaceArea(surface)
            
            let wallPoints = extractWallPoints(from: surface, capturedRoom: capturedRoom)
            let doorways = findDoorways(for: surface, capturedRoom: capturedRoom)
            
            let room = IdentifiedRoom(
                type: roomType,
                bounds: surface,
                center: center,
                area: area,
                confidence: calculateRoomConfidence(roomType: roomType, objects: capturedRoom.objects, surface: surface),
                wallPoints: wallPoints,
                doorways: doorways
            )
            rooms.append(room)
        }
        
        DispatchQueue.main.async {
            self.identifiedRooms = rooms
        }
    }
    
    private func catalogFurniture(from capturedRoom: CapturedRoom) {
        var furniture: [FurnitureItem] = []
        
        for object in capturedRoom.objects {
            let roomId = findContainingRoom(for: object.transform.columns.3)
            
            let item = FurnitureItem(
                category: object.category,
                position: simd_float3(object.transform.columns.3.x, object.transform.columns.3.y, object.transform.columns.3.z),
                dimensions: object.dimensions,
                roomId: roomId,
                confidence: 1.0
            )
            furniture.append(item)
        }
        
        DispatchQueue.main.async {
            self.furnitureItems = furniture
        }
    }
    
    private func mapRoomConnections(from capturedRoom: CapturedRoom) {
        var connections: [RoomConnection] = []
        
        let doorObjects = capturedRoom.objects.filter { _ in
            // For now, consider any object as potential door/opening
            // In a real implementation, we'd filter by specific category
            return false // Disable door detection for now
        }
        
        for door in doorObjects {
            let doorPosition = simd_float3(door.transform.columns.3.x, door.transform.columns.3.y, door.transform.columns.3.z)
            let nearbyRooms = findNearbyRooms(to: doorPosition)
            
            if nearbyRooms.count >= 2 {
                let connection = RoomConnection(
                    roomA: nearbyRooms[0],
                    roomB: nearbyRooms[1],
                    doorPosition: doorPosition,
                    type: .door
                )
                connections.append(connection)
            }
        }
        
        DispatchQueue.main.async {
            self.roomConnections = connections
        }
    }
    
    private func classifyRoom(surface: CapturedRoom.Surface, objects: [CapturedRoom.Object]) -> RoomType {
        let nearbyObjects = objects.filter { object in
            let objectPos = simd_float3(object.transform.columns.3.x, object.transform.columns.3.y, object.transform.columns.3.z)
            return isObjectInSurface(objectPos, surface: surface)
        }
        
        print("🏠 Classifying room with \(nearbyObjects.count) nearby objects")
        for obj in nearbyObjects {
            print("   Object: \(obj.category)")
        }
        
        var kitchenScore = 0
        var bedroomScore = 0
        var bathroomScore = 0
        var livingRoomScore = 0
        var officeScore = 0
        var diningRoomScore = 0
        
        for object in nearbyObjects {
            switch object.category {
            case .refrigerator, .oven, .dishwasher:
                kitchenScore += 3
            case .sink:
                kitchenScore += 2
                bathroomScore += 2
            case .bed:
                bedroomScore += 4
            case .sofa, .television:
                livingRoomScore += 3
            case .toilet, .bathtub:
                bathroomScore += 4
            case .table:
                if nearbyObjects.contains(where: { $0.category == .refrigerator }) {
                    kitchenScore += 1
                } else if nearbyObjects.contains(where: { $0.category == .chair }) {
                    diningRoomScore += 2
                    officeScore += 1
                } else {
                    livingRoomScore += 1
                }
            case .chair:
                if nearbyObjects.contains(where: { $0.category == .table }) {
                    diningRoomScore += 1
                    officeScore += 1
                } else {
                    officeScore += 1
                }
            default:
                break
            }
        }
        
        let scores = [
            (RoomType.kitchen, kitchenScore),
            (RoomType.bedroom, bedroomScore),
            (RoomType.bathroom, bathroomScore),
            (RoomType.livingRoom, livingRoomScore),
            (RoomType.office, officeScore),
            (RoomType.diningRoom, diningRoomScore)
        ]
        
        let maxScore = scores.max(by: { $0.1 < $1.1 })
        
        // If no clear winner, use room size and shape heuristics
        if maxScore?.1 == 0 {
            return classifyRoomBySize(surface: surface)
        }
        
        print("   Best classification: \(maxScore?.0.rawValue ?? "unknown") with score \(maxScore?.1 ?? 0)")
        return maxScore?.0 ?? .unknown
    }
    
    private func classifyRoomBySize(surface: CapturedRoom.Surface) -> RoomType {
        let area = calculateSurfaceArea(surface)
        let width = surface.dimensions.x
        let depth = surface.dimensions.z
        let aspectRatio = max(width, depth) / min(width, depth)
        
        print("   Fallback classification by size: \(area)m², aspect ratio: \(aspectRatio)")
        
        // Very small rooms are likely bathrooms or closets
        if area < 6.0 {
            return aspectRatio > 2.0 ? .hallway : .bathroom
        }
        // Small rooms
        else if area < 12.0 {
            return aspectRatio > 2.0 ? .hallway : .bedroom
        }
        // Medium rooms
        else if area < 25.0 {
            return .bedroom
        }
        // Large rooms are likely living areas
        else {
            return .livingRoom
        }
    }
    
    private func calculateSurfaceCenter(_ surface: CapturedRoom.Surface) -> simd_float3 {
        let transform = surface.transform
        return simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
    
    private func calculateSurfaceArea(_ surface: CapturedRoom.Surface) -> Float {
        return surface.dimensions.x * surface.dimensions.z
    }
    
    private func calculateRoomConfidence(roomType: RoomType, objects: [CapturedRoom.Object], surface: CapturedRoom.Surface) -> Float {
        let nearbyObjects = objects.filter { object in
            let objectPos = simd_float3(object.transform.columns.3.x, object.transform.columns.3.y, object.transform.columns.3.z)
            return isObjectInSurface(objectPos, surface: surface)
        }
        
        let relevantObjects = nearbyObjects.filter { object in
            switch roomType {
            case .kitchen:
                return [.refrigerator, .oven, .dishwasher, .sink].contains(object.category)
            case .bedroom:
                return [.bed].contains(object.category)
            case .bathroom:
                return [.toilet, .bathtub, .sink].contains(object.category)
            case .livingRoom:
                return [.sofa, .television].contains(object.category)
            case .office:
                return [.table, .chair].contains(object.category)
            default:
                return false
            }
        }
        
        if nearbyObjects.isEmpty {
            return 0.3
        }
        
        return Float(relevantObjects.count) / Float(nearbyObjects.count)
    }
    
    private func isObjectInSurface(_ position: simd_float3, surface: CapturedRoom.Surface) -> Bool {
        let surfaceCenter = calculateSurfaceCenter(surface)
        let halfWidth = surface.dimensions.x / 2
        let halfDepth = surface.dimensions.z / 2
        
        return abs(position.x - surfaceCenter.x) <= halfWidth &&
               abs(position.z - surfaceCenter.z) <= halfDepth
    }
    
    private func findContainingRoom(for position: simd_float4) -> UUID? {
        let pos3D = simd_float3(position.x, position.y, position.z)
        
        for room in identifiedRooms {
            if isObjectInSurface(pos3D, surface: room.bounds) {
                return room.id
            }
        }
        return nil
    }
    
    private func findNearbyRooms(to position: simd_float3, threshold: Float = 2.0) -> [UUID] {
        return identifiedRooms.compactMap { room in
            let distance = simd_distance(position, room.center)
            return distance <= threshold ? room.id : nil
        }
    }
    
    private func extractWallPoints(from surface: CapturedRoom.Surface, capturedRoom: CapturedRoom) -> [simd_float2] {
        // Try to find walls that bound this floor
        let floorCenter = calculateSurfaceCenter(surface)
        let floorBounds = surface.dimensions
        
        var wallPoints: [simd_float2] = []
        
        // Look for walls near this floor
        for wall in capturedRoom.walls {
            let wallCenter = simd_float3(wall.transform.columns.3.x, wall.transform.columns.3.y, wall.transform.columns.3.z)
            let distance = simd_distance(simd_float2(floorCenter.x, floorCenter.z), simd_float2(wallCenter.x, wallCenter.z))
            
            // If wall is close to floor, add its endpoints
            if distance < (max(floorBounds.x, floorBounds.z) * 0.7) {
                let wallLength = wall.dimensions.x
                let wallDirection = simd_float2(wall.transform.columns.0.x, wall.transform.columns.0.z)
                let wallNormal = simd_normalize(wallDirection)
                
                let point1 = simd_float2(wallCenter.x, wallCenter.z) - wallNormal * (wallLength / 2)
                let point2 = simd_float2(wallCenter.x, wallCenter.z) + wallNormal * (wallLength / 2)
                
                wallPoints.append(point1)
                wallPoints.append(point2)
            }
        }
        
        // If no walls found, create rectangular boundary from floor dimensions
        if wallPoints.isEmpty {
            let halfWidth = floorBounds.x / 2
            let halfDepth = floorBounds.z / 2
            let center2D = simd_float2(floorCenter.x, floorCenter.z)
            
            wallPoints = [
                center2D + simd_float2(-halfWidth, -halfDepth), // bottom-left
                center2D + simd_float2(halfWidth, -halfDepth),  // bottom-right
                center2D + simd_float2(halfWidth, halfDepth),   // top-right
                center2D + simd_float2(-halfWidth, halfDepth)   // top-left
            ]
        }
        
        return wallPoints
    }
    
    private func findDoorways(for surface: CapturedRoom.Surface, capturedRoom: CapturedRoom) -> [simd_float2] {
        let floorCenter = calculateSurfaceCenter(surface)
        var doorways: [simd_float2] = []
        
        // Look for door objects near this floor
        for object in capturedRoom.objects {
            let objectPos = simd_float3(object.transform.columns.3.x, object.transform.columns.3.y, object.transform.columns.3.z)
            
            // Check if object is on or near this floor level
            if abs(objectPos.y - floorCenter.y) < 1.0 { // Within 1 meter height
                if isObjectInSurface(objectPos, surface: surface) {
                    // Could be a door or opening - for now, add all objects as potential doorways
                    doorways.append(simd_float2(objectPos.x, objectPos.z))
                }
            }
        }
        
        return doorways
    }
}