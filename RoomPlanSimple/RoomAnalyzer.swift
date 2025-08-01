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
        
        guard #available(iOS 17.0, *) else { return }
        for surface in capturedRoom.floors {
            let roomType = classifyRoom(surface: surface, objects: capturedRoom.objects)
            let center = calculateSurfaceCenter(surface)
            let area = calculateSurfaceArea(surface)
            
            let room = IdentifiedRoom(
                type: roomType,
                bounds: surface,
                center: center,
                area: area,
                confidence: calculateRoomConfidence(roomType: roomType, objects: capturedRoom.objects, surface: surface)
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
        
        var kitchenScore = 0
        var bedroomScore = 0
        var bathroomScore = 0
        var livingRoomScore = 0
        var officeScore = 0
        
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
                } else {
                    officeScore += 1
                    livingRoomScore += 1
                }
            case .chair:
                officeScore += 1
            default:
                break
            }
        }
        
        let scores = [
            (RoomType.kitchen, kitchenScore),
            (RoomType.bedroom, bedroomScore),
            (RoomType.bathroom, bathroomScore),
            (RoomType.livingRoom, livingRoomScore),
            (RoomType.office, officeScore)
        ]
        
        return scores.max(by: { $0.1 < $1.1 })?.0 ?? .unknown
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
}