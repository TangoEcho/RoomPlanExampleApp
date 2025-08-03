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
    
    func analyzeCapturedRoom(_ capturedRoom: CapturedRoom) {
        identifyRoomTypes(from: capturedRoom)
        catalogFurniture(from: capturedRoom)
        mapRoomConnections(from: capturedRoom)
    }
    
    private func identifyRoomTypes(from capturedRoom: CapturedRoom) {
        var rooms: [IdentifiedRoom] = []
        
        print("🏠 Analyzing \(capturedRoom.floors.count) floor surfaces and \(capturedRoom.objects.count) objects")
        
        // If RoomPlan only detected one large floor, try to segment it based on furniture
        if capturedRoom.floors.count == 1 && capturedRoom.objects.count > 5 {
            print("🔍 Single large floor detected - attempting furniture-based room segmentation")
            rooms = segmentRoomsByFurniture(capturedRoom: capturedRoom)
        } else {
            // Process each floor surface normally
            for surface in capturedRoom.floors {
                let room = createRoomFromSurface(surface: surface, capturedRoom: capturedRoom)
                rooms.append(room)
            }
        }
        
        // Validate and fix room boundaries
        rooms = validateAndFixRoomBoundaries(rooms)
        
        print("✅ Identified \(rooms.count) rooms: \(rooms.map { $0.type.rawValue }.joined(separator: ", "))")
        
        DispatchQueue.main.async {
            self.identifiedRooms = rooms
        }
    }
    
    private func createRoomFromSurface(surface: CapturedRoom.Surface, capturedRoom: CapturedRoom) -> IdentifiedRoom {
        let roomType = classifyRoom(surface: surface, objects: capturedRoom.objects)
        let center = calculateSurfaceCenter(surface)
        let area = calculateSurfaceArea(surface)
        
        let wallPoints = extractWallPoints(from: surface, capturedRoom: capturedRoom)
        let doorways = findDoorways(for: surface, capturedRoom: capturedRoom)
        
        return IdentifiedRoom(
            type: roomType,
            bounds: surface,
            center: center,
            area: area,
            confidence: calculateRoomConfidence(roomType: roomType, objects: capturedRoom.objects, surface: surface),
            wallPoints: wallPoints,
            doorways: doorways
        )
    }
    
    private func segmentRoomsByFurniture(capturedRoom: CapturedRoom) -> [IdentifiedRoom] {
        print("🪑 Segmenting rooms based on \(capturedRoom.objects.count) furniture items")
        
        // Group furniture by spatial proximity to identify room clusters
        let furnitureGroups = clusterFurnitureByProximity(capturedRoom.objects)
        print("   Found \(furnitureGroups.count) furniture clusters")
        
        var rooms: [IdentifiedRoom] = []
        let mainSurface = capturedRoom.floors.first!
        
        for (index, group) in furnitureGroups.enumerated() {
            // Create a room for each furniture cluster
            let roomBounds = calculateBoundsFromFurniture(group)
            let roomCenter = calculateCenterFromFurniture(group)
            let roomType = classifyRoomFromFurnitureGroup(group)
            
            // Create wall points that encompass the furniture
            let wallPoints = createWallPointsFromBounds(roomBounds, expandBy: 1.0) // 1m padding
            
            let room = IdentifiedRoom(
                type: roomType,
                bounds: mainSurface, // Use main surface as base
                center: roomCenter,
                area: calculateAreaFromBounds(roomBounds),
                confidence: calculateConfidenceFromFurniture(group, roomType: roomType),
                wallPoints: wallPoints,
                doorways: []
            )
            
            rooms.append(room)
            print("   Room \(index + 1): \(roomType.rawValue) with \(group.count) furniture items at \(roomCenter)")
        }
        
        // If no clear furniture groups, create at least one room
        if rooms.isEmpty {
            let fallbackRoom = createRoomFromSurface(surface: mainSurface, capturedRoom: capturedRoom)
            rooms.append(fallbackRoom)
        }
        
        return rooms
    }
    
    private func clusterFurnitureByProximity(_ objects: [CapturedRoom.Object]) -> [[CapturedRoom.Object]] {
        let clusterDistance: Float = 4.0 // 4 meters max distance for same room
        var clusters: [[CapturedRoom.Object]] = []
        var unprocessed = objects
        
        while !unprocessed.isEmpty {
            var currentCluster = [unprocessed.removeFirst()]
            
            var foundNewItems = true
            while foundNewItems {
                foundNewItems = false
                
                for (index, item) in unprocessed.enumerated().reversed() {
                    let itemPos = simd_float3(item.transform.columns.3.x, item.transform.columns.3.y, item.transform.columns.3.z)
                    
                    // Check if item is close to any item in current cluster
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
            
            clusters.append(currentCluster)
        }
        
        return clusters.filter { $0.count >= 2 } // Only clusters with 2+ items
    }
    
    private func classifyRoomFromFurnitureGroup(_ furniture: [CapturedRoom.Object]) -> RoomType {
        var kitchenScore = 0
        var bedroomScore = 0
        var bathroomScore = 0
        var livingRoomScore = 0
        var diningRoomScore = 0
        
        for item in furniture {
            switch item.category {
            case .refrigerator, .oven, .dishwasher:
                kitchenScore += 3
            case .sink:
                kitchenScore += 2
                bathroomScore += 1
            case .bed:
                bedroomScore += 4
            case .sofa, .television:
                livingRoomScore += 3
            case .toilet, .bathtub:
                bathroomScore += 4
            case .table:
                diningRoomScore += 2
                livingRoomScore += 1
            case .chair:
                diningRoomScore += 1
            default:
                break
            }
        }
        
        let scores = [
            (RoomType.kitchen, kitchenScore),
            (RoomType.bedroom, bedroomScore),
            (RoomType.bathroom, bathroomScore),
            (RoomType.livingRoom, livingRoomScore),
            (RoomType.diningRoom, diningRoomScore)
        ]
        
        return scores.max(by: { $0.1 < $1.1 })?.0 ?? .unknown
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
    
    private func calculateCenterFromFurniture(_ furniture: [CapturedRoom.Object]) -> simd_float3 {
        let positions = furniture.map { simd_float3($0.transform.columns.3.x, $0.transform.columns.3.y, $0.transform.columns.3.z) }
        let sum = positions.reduce(simd_float3(0, 0, 0)) { $0 + $1 }
        return sum / Float(positions.count)
    }
    
    private func createWallPointsFromBounds(_ bounds: (min: simd_float3, max: simd_float3), expandBy: Float) -> [simd_float2] {
        let minX = bounds.min.x - expandBy
        let maxX = bounds.max.x + expandBy
        let minZ = bounds.min.z - expandBy
        let maxZ = bounds.max.z + expandBy
        
        return [
            simd_float2(minX, minZ), // bottom-left
            simd_float2(maxX, minZ), // bottom-right
            simd_float2(maxX, maxZ), // top-right
            simd_float2(minX, maxZ)  // top-left
        ]
    }
    
    private func calculateAreaFromBounds(_ bounds: (min: simd_float3, max: simd_float3)) -> Float {
        let width = bounds.max.x - bounds.min.x
        let depth = bounds.max.z - bounds.min.z
        return width * depth
    }
    
    private func calculateConfidenceFromFurniture(_ furniture: [CapturedRoom.Object], roomType: RoomType) -> Float {
        let relevantFurniture = furniture.filter { item in
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
        }
        
        return furniture.isEmpty ? 0.3 : Float(relevantFurniture.count) / Float(furniture.count)
    }
    
    private func validateAndFixRoomBoundaries(_ rooms: [IdentifiedRoom]) -> [IdentifiedRoom] {
        return rooms.map { room in
            // Fix invalid dimensions
            if room.bounds.dimensions.x <= 0.1 || room.bounds.dimensions.z <= 0.1 {
                print("⚠️ Fixing invalid room dimensions for \(room.type.rawValue)")
                
                // Calculate proper dimensions from wall points
                if room.wallPoints.count >= 4 {
                    let minX = room.wallPoints.map { $0.x }.min() ?? room.center.x - 2
                    let maxX = room.wallPoints.map { $0.x }.max() ?? room.center.x + 2
                    let minZ = room.wallPoints.map { $0.y }.min() ?? room.center.z - 2
                    let maxZ = room.wallPoints.map { $0.y }.max() ?? room.center.z + 2
                    
                    let fixedArea = (maxX - minX) * (maxZ - minZ)
                    
                    return IdentifiedRoom(
                        type: room.type,
                        bounds: room.bounds,
                        center: room.center,
                        area: fixedArea,
                        confidence: room.confidence,
                        wallPoints: room.wallPoints,
                        doorways: room.doorways
                    )
                }
            }
            
            return room
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
        let halfWidth = max(surface.dimensions.x / 2, 2.0) // Minimum 2m radius
        let halfDepth = max(surface.dimensions.z / 2, 2.0) // Minimum 2m radius
        
        return abs(position.x - surfaceCenter.x) <= halfWidth &&
               abs(position.z - surfaceCenter.z) <= halfDepth
    }
    
    // New method for checking if position is in any identified room
    func findRoomContaining(position: simd_float3) -> IdentifiedRoom? {
        print("🔍 Checking room containment for position (\(String(format: "%.2f", position.x)), \(String(format: "%.2f", position.z)))")
        
        for room in identifiedRooms {
            print("   Testing room \(room.type.rawValue) at (\(String(format: "%.2f", room.center.x)), \(String(format: "%.2f", room.center.z)))")
            
            // Test using wall points if available
            if room.wallPoints.count >= 3 {
                let isInside = isPointInRoomPolygon(position, room: room)
                print("     Polygon test: \(isInside)")
                if isInside {
                    return room
                }
            } else {
                // Fallback to expanded rectangular boundary test
                let expandedRadius: Float = 3.0 // 3m radius for containment
                let distance = simd_distance(simd_float2(position.x, position.z), simd_float2(room.center.x, room.center.z))
                let isInside = distance <= expandedRadius
                print("     Distance test: \(String(format: "%.2f", distance))m <= \(expandedRadius)m = \(isInside)")
                if isInside {
                    return room
                }
            }
        }
        
        print("   ❌ Position not found in any room")
        return nil
    }
    
    private func isPointInRoomPolygon(_ point: simd_float3, room: IdentifiedRoom) -> Bool {
        let point2D = simd_float2(point.x, point.z)
        return isPointInPolygon(point2D, polygon: room.wallPoints)
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