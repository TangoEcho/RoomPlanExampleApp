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
        
        // Handle invalid dimensions safely
        let safeWidth = max(width, 0.1) // Ensure non-zero
        let safeDepth = max(depth, 0.1) // Ensure non-zero
        let aspectRatio = max(safeWidth, safeDepth) / min(safeWidth, safeDepth)
        
        print("   Fallback classification by size: \(String(format: "%.1f", area))m², aspect ratio: \(String(format: "%.2f", aspectRatio))")
        print("   Surface dimensions: \(String(format: "%.2f", width)) x \(String(format: "%.2f", depth))")
        
        // If dimensions are effectively zero, use a heuristic approach
        if width <= 0.1 || depth <= 0.1 {
            print("   Invalid dimensions detected, defaulting to living room classification")
            return .livingRoom
        }
        
        // Very small rooms are likely bathrooms or closets
        if area < 6.0 {
            return aspectRatio > 2.0 ? .hallway : .bathroom
        }
        // Small rooms
        else if area < 12.0 {
            return aspectRatio > 2.0 ? .hallway : .bedroom
        }
        // Medium rooms - be more specific about living vs dining
        else if area < 25.0 {
            // Medium rectangular rooms are often dining rooms
            return aspectRatio < 1.5 ? .diningRoom : .bedroom
        }
        // Large rooms are likely living areas
        else if area < 50.0 {
            return .livingRoom
        }
        // Very large areas might be open concept or multiple rooms
        else {
            return .livingRoom
        }
    }
    
    private func calculateSurfaceCenter(_ surface: CapturedRoom.Surface) -> simd_float3 {
        let transform = surface.transform
        return simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
    
    private func calculateSurfaceArea(_ surface: CapturedRoom.Surface) -> Float {
        let area = surface.dimensions.x * surface.dimensions.z
        
        // Validate area calculation - if dimensions are 0 or invalid, calculate from bounds
        if area <= 0 || !area.isFinite {
            print("⚠️ Invalid surface dimensions (\(surface.dimensions.x) x \(surface.dimensions.z)), attempting bounds calculation")
            
            // Try to calculate area from transform matrix bounds
            let transform = surface.transform
            let scale = simd_float3(
                simd_length(simd_float3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)),
                simd_length(simd_float3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)),
                simd_length(simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
            )
            
            // For floor surfaces, use X and Z scale components
            let estimatedArea = scale.x * scale.z
            
            if estimatedArea > 0 && estimatedArea.isFinite {
                print("   Estimated area from transform: \(estimatedArea)m²")
                return estimatedArea
            }
            
            // Fallback: assume minimum reasonable room size
            let fallbackArea: Float = 10.0 // 10 square meters
            print("   Using fallback area: \(fallbackArea)m²")
            return fallbackArea
        }
        
        return area
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
        let floorCenter = calculateSurfaceCenter(surface)
        let floorBounds = surface.dimensions
        
        print("🏠 Creating room outlines for \(capturedRoom.walls.count) walls")
        print("   Floor center: (\(String(format: "%.2f", floorCenter.x)), \(String(format: "%.2f", floorCenter.z)))")
        print("   Floor bounds: \(String(format: "%.2f", floorBounds.x)) x \(String(format: "%.2f", floorBounds.z))")
        
        // Check for invalid floor dimensions first
        if floorBounds.x <= 0.1 || floorBounds.z <= 0.1 {
            print("⚠️ Invalid floor dimensions detected, using fallback rectangular room")
            return createFallbackRectangularRoom(center: floorCenter, bounds: floorBounds)
        }
        
        // Collect and filter wall segments that belong to this room
        var relevantWalls: [(center: simd_float2, direction: simd_float2, length: Float)] = []
        
        for wall in capturedRoom.walls {
            let wallCenter3D = simd_float3(wall.transform.columns.3.x, wall.transform.columns.3.y, wall.transform.columns.3.z)
            let wallCenter2D = simd_float2(wallCenter3D.x, wallCenter3D.z)
            let distance = simd_distance(simd_float2(floorCenter.x, floorCenter.z), wallCenter2D)
            
            // Only include walls that are close to this floor and reasonably sized
            let maxDistance = max(floorBounds.x, floorBounds.z) * 0.8
            if distance < maxDistance && wall.dimensions.x > 0.3 { // At least 30cm long
                let wallDirection = simd_float2(wall.transform.columns.0.x, wall.transform.columns.0.z)
                let normalizedDirection = simd_length(wallDirection) > 0 ? simd_normalize(wallDirection) : simd_float2(1, 0)
                
                relevantWalls.append((center: wallCenter2D, direction: normalizedDirection, length: wall.dimensions.x))
            }
        }
        
        print("   Found \(relevantWalls.count) relevant walls after filtering")
        
        // If we have too many wall segments (indicating mesh triangulation), simplify
        if relevantWalls.count > 12 {
            print("   Too many wall segments (\(relevantWalls.count)), creating simplified boundary")
            return createSimplifiedRoomBoundary(center: floorCenter, bounds: floorBounds, walls: relevantWalls)
        }
        
        // If we have a reasonable number of walls, try to create a proper boundary
        if relevantWalls.count >= 3 {
            let boundary = createOrderedRoomBoundary(walls: relevantWalls, floorCenter: floorCenter, floorBounds: floorBounds)
            if validateRoomBoundary(boundary) {
                print("   Created ordered boundary with \(boundary.count) points")
                return boundary
            } else {
                print("   Boundary validation failed, using fallback")
            }
        }
        
        // Fallback to rectangular room if wall detection fails
        print("   Using rectangular fallback room")
        return createFallbackRectangularRoom(center: floorCenter, bounds: floorBounds)
    }
    
    private func createSimplifiedRoomBoundary(center: simd_float3, bounds: simd_float3, walls: [(center: simd_float2, direction: simd_float2, length: Float)]) -> [simd_float2] {
        // Group walls by similar directions to reduce complexity
        var horizontalWalls: [simd_float2] = []
        var verticalWalls: [simd_float2] = []
        
        for wall in walls {
            // Check if wall is more horizontal or vertical
            if abs(wall.direction.x) > abs(wall.direction.y) {
                horizontalWalls.append(wall.center)
            } else {
                verticalWalls.append(wall.center)
            }
        }
        
        // Find boundary extents from wall positions
        let center2D = simd_float2(center.x, center.z)
        let allWallCenters = walls.map { $0.center }
        
        if allWallCenters.isEmpty {
            return createFallbackRectangularRoom(center: center, bounds: bounds)
        }
        
        let minX = allWallCenters.map { $0.x }.min() ?? (center2D.x - bounds.x/2)
        let maxX = allWallCenters.map { $0.x }.max() ?? (center2D.x + bounds.x/2)
        let minZ = allWallCenters.map { $0.y }.min() ?? (center2D.y - bounds.z/2)
        let maxZ = allWallCenters.map { $0.y }.max() ?? (center2D.y + bounds.z/2)
        
        // Create a simplified rectangular boundary from wall extents
        return [
            simd_float2(minX, minZ), // bottom-left
            simd_float2(maxX, minZ), // bottom-right
            simd_float2(maxX, maxZ), // top-right
            simd_float2(minX, maxZ)  // top-left
        ]
    }
    
    private func createOrderedRoomBoundary(walls: [(center: simd_float2, direction: simd_float2, length: Float)], floorCenter: simd_float3, floorBounds: simd_float3) -> [simd_float2] {
        // Create wall endpoints
        var wallEndpoints: [simd_float2] = []
        
        for wall in walls {
            let halfLength = wall.length / 2
            let endpoint1 = wall.center - wall.direction * halfLength
            let endpoint2 = wall.center + wall.direction * halfLength
            wallEndpoints.append(endpoint1)
            wallEndpoints.append(endpoint2)
        }
        
        // Remove duplicate points (merge points that are very close)
        let mergedPoints = mergeNearbyPoints(wallEndpoints, threshold: 0.3)
        
        if mergedPoints.count < 3 {
            return createFallbackRectangularRoom(center: floorCenter, bounds: floorBounds)
        }
        
        // Order points to form a coherent boundary (convex hull or clockwise ordering)
        let orderedPoints = orderPointsClockwise(mergedPoints, center: simd_float2(floorCenter.x, floorCenter.z))
        
        return orderedPoints
    }
    
    private func mergeNearbyPoints(_ points: [simd_float2], threshold: Float) -> [simd_float2] {
        var mergedPoints: [simd_float2] = []
        
        for point in points {
            var shouldAdd = true
            for existingPoint in mergedPoints {
                if simd_distance(point, existingPoint) < threshold {
                    shouldAdd = false
                    break
                }
            }
            if shouldAdd {
                mergedPoints.append(point)
            }
        }
        
        return mergedPoints
    }
    
    private func orderPointsClockwise(_ points: [simd_float2], center: simd_float2) -> [simd_float2] {
        // Sort points by angle from center (clockwise)
        let sortedPoints = points.sorted { point1, point2 in
            let angle1 = atan2(point1.y - center.y, point1.x - center.x)
            let angle2 = atan2(point2.y - center.y, point2.x - center.x)
            return angle1 < angle2
        }
        
        return sortedPoints
    }
    
    private func validateRoomBoundary(_ boundary: [simd_float2]) -> Bool {
        // Check if boundary has at least 3 points and forms a reasonable shape
        if boundary.count < 3 {
            return false
        }
        
        // Check if points are not all collinear or in a tiny area
        let minX = boundary.map { $0.x }.min() ?? 0
        let maxX = boundary.map { $0.x }.max() ?? 0
        let minY = boundary.map { $0.y }.min() ?? 0
        let maxY = boundary.map { $0.y }.max() ?? 0
        
        let width = maxX - minX
        let height = maxY - minY
        
        // Room should be at least 0.5m x 0.5m
        return width > 0.5 && height > 0.5
    }
    
    private func createFallbackRectangularRoom(center: simd_float3, bounds: simd_float3) -> [simd_float2] {
        // Ensure minimum room dimensions for visibility
        let minDimension: Float = 1.0
        let roomWidth = max(bounds.x, minDimension)
        let roomDepth = max(bounds.z, minDimension)
        
        let halfWidth = roomWidth / 2
        let halfDepth = roomDepth / 2
        let center2D = simd_float2(center.x, center.z)
        
        return [
            center2D + simd_float2(-halfWidth, -halfDepth), // bottom-left
            center2D + simd_float2(halfWidth, -halfDepth),  // bottom-right
            center2D + simd_float2(halfWidth, halfDepth),   // top-right
            center2D + simd_float2(-halfWidth, halfDepth)   // top-left
        ]
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