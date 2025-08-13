import Foundation
import RoomPlan
import ARKit
import simd

class RoomAnalyzer: ObservableObject {
    @Published var identifiedRooms: [IdentifiedRoom] = []
    @Published var furnitureItems: [FurnitureItem] = []
    @Published var roomConnections: [RoomConnection] = []
    @Published var floorHeights: [Float] = []
    
    struct IdentifiedRoom {
        let id = UUID()
        let type: RoomType
        let bounds: CapturedRoom.Surface
        let center: simd_float3
        let area: Float
        let confidence: Float
        let wallPoints: [simd_float2] // Actual room boundary points from RoomPlan
        let doorways: [simd_float2] // Door/opening positions from RoomPlan
        let floorIndex: Int
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
        // Compute floor clusters first
        computeFloors(from: capturedRoom)
        identifyRoomTypes(from: capturedRoom)
        catalogFurniture(from: capturedRoom)
        mapRoomConnections(from: capturedRoom)
    }
    
    // MARK: - Apple RoomPlan Data Processing
    
    private func identifyRoomTypes(from capturedRoom: CapturedRoom) {
        var rooms: [IdentifiedRoom] = []
        
        print("🏠 Analyzing \(capturedRoom.floors.count) floor surfaces and \(capturedRoom.objects.count) objects")
        
        // Check for invalid surface dimensions that indicate segmentation needed
        let hasInvalidDimensions = capturedRoom.floors.contains { surface in
            surface.dimensions.x <= 0 || surface.dimensions.z <= 0 ||
            !surface.dimensions.x.isFinite || !surface.dimensions.z.isFinite
        }
        
        // Use Apple's intended approach: process each floor surface directly
        if capturedRoom.floors.count == 1 && (capturedRoom.objects.count > 5 || hasInvalidDimensions) {
            print("🔍 Single floor with furniture or invalid dimensions - segmenting into logical rooms")
            rooms = segmentSingleFloorIntoRooms(capturedRoom: capturedRoom)
        } else {
            // Multiple floors detected - process each separately
            for surface in capturedRoom.floors {
                // Skip surfaces with invalid dimensions
                if surface.dimensions.x <= 0 || surface.dimensions.z <= 0 {
                    print("⚠️ Skipping surface with invalid dimensions: \(surface.dimensions.x) x \(surface.dimensions.z)")
                    continue
                }
                let room = createRoomFromRoomPlanSurface(surface: surface, capturedRoom: capturedRoom)
                rooms.append(room)
            }
        }
        
        // If no valid rooms were created, force segmentation
        if rooms.isEmpty && !capturedRoom.floors.isEmpty {
            print("🔧 No valid rooms found, forcing furniture-based segmentation")
            rooms = segmentSingleFloorIntoRooms(capturedRoom: capturedRoom)
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
        let wallPoints = createRoomBoundaryFromSurface(surface)
        let doorways = extractDoorwaysFromRoomPlan(capturedRoom: capturedRoom)
        let fIndex = determineFloorIndex(forY: center.y)
        
        return IdentifiedRoom(
            type: roomType,
            bounds: surface,
            center: center,
            area: area,
            confidence: calculateRoomTypeConfidence(roomType: roomType, objects: capturedRoom.objects, surface: surface),
            wallPoints: wallPoints,
            doorways: doorways,
            floorIndex: fIndex
        )
    }
    
    private func segmentSingleFloorIntoRooms(capturedRoom: CapturedRoom) -> [IdentifiedRoom] {
        let mainFloor = capturedRoom.floors.first!
        let furnitureGroups = clusterFurnitureByProximity(capturedRoom.objects)
        
        print("   Found \(furnitureGroups.count) furniture clusters")
        
        var rooms: [IdentifiedRoom] = []
        let fIndex = determineFloorIndex(forY: extractSurfaceCenter(mainFloor).y)
        
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
                doorways: doorways,
                floorIndex: fIndex
            )
            
            rooms.append(room)
            print("   Room \(index + 1): \(roomType.rawValue) with \(group.count) furniture items")
        }
        
        // Ensure at least one room exists - create multiple logical rooms if needed
        if rooms.isEmpty {
            print("   No furniture clusters found, creating logical room divisions based on space analysis")
            rooms = createLogicalRoomDivisions(capturedRoom: capturedRoom, mainFloor: mainFloor)
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
    
    private func createLogicalRoomDivisions(capturedRoom: CapturedRoom, mainFloor: CapturedRoom.Surface) -> [IdentifiedRoom] {
        var rooms: [IdentifiedRoom] = []
        
        // Analyze the space and furniture to create logical room divisions
        let allObjects = capturedRoom.objects
        let spaceCenter = extractSurfaceCenter(mainFloor)
        let fIndex = determineFloorIndex(forY: spaceCenter.y)
        
        // Create rooms based on furniture distribution and typical home layout
        if allObjects.count >= 3 {
            // Kitchen area - look for kitchen-specific objects
            let kitchenObjects = allObjects.compactMap { object in
                [.refrigerator, .stove, .dishwasher, .sink].contains(object.category) ? object : nil
            }
            
            if kitchenObjects.count >= 1 {
                let kitchenRoom = createRoomFromObjectGroup(
                    objects: kitchenObjects,
                    fallbackObjects: Array(allObjects.prefix(3)),
                    roomType: .kitchen,
                    baseFloor: mainFloor,
                    capturedRoom: capturedRoom
                )
                rooms.append(kitchenRoom)
            }
            
            // Living area - look for living room furniture
            let livingObjects = allObjects.compactMap { object in
                [.sofa, .chair, .table, .television].contains(object.category) ? object : nil
            }
            
            if livingObjects.count >= 1 {
                let livingRoom = createRoomFromObjectGroup(
                    objects: livingObjects,
                    fallbackObjects: Array(allObjects.dropFirst(3).prefix(3)),
                    roomType: .livingRoom,
                    baseFloor: mainFloor,
                    capturedRoom: capturedRoom
                )
                rooms.append(livingRoom)
            }
            
            // Dining area - look for dining furniture not already in living room
            let diningObjects = allObjects.compactMap { object -> CapturedRoom.Object? in
                let isDiningFurniture = [.table, .chair].contains(object.category)
                let objectPos = simd_float3(object.transform.columns.3.x, object.transform.columns.3.y, object.transform.columns.3.z)
                let notInLiving = !livingObjects.contains { livingObj in
                    let livingPos = simd_float3(livingObj.transform.columns.3.x, livingObj.transform.columns.3.y, livingObj.transform.columns.3.z)
                    return simd_distance(objectPos, livingPos) < 0.1 // Same object if within 10cm
                }
                return (isDiningFurniture && notInLiving) ? object : nil
            }
            
            if diningObjects.count >= 1 {
                let diningRoom = createRoomFromObjectGroup(
                    objects: diningObjects,
                    fallbackObjects: Array(allObjects.suffix(3)),
                    roomType: .diningRoom,
                    baseFloor: mainFloor,
                    capturedRoom: capturedRoom
                )
                rooms.append(diningRoom)
            }
        }
        
        // If no specific rooms were created, create a reasonable default layout
        if rooms.isEmpty {
            rooms = createDefaultRoomLayout(capturedRoom: capturedRoom, mainFloor: mainFloor)
        }
        
        return rooms
    }
    
    private func createRoomFromObjectGroup(
        objects: [CapturedRoom.Object],
        fallbackObjects: [CapturedRoom.Object],
        roomType: RoomType,
        baseFloor: CapturedRoom.Surface,
        capturedRoom: CapturedRoom
    ) -> IdentifiedRoom {
        let roomObjects = objects.isEmpty ? fallbackObjects : objects
        let roomCenter = calculateCenterFromFurniture(roomObjects)
        let roomBoundary = createRoomBoundaryFromFurnitureCluster(roomObjects, floor: baseFloor)
        let roomArea = calculateAreaFromWallPoints(roomBoundary)
        let doorways = extractDoorwaysFromRoomPlan(capturedRoom: capturedRoom)
        let fIndex = determineFloorIndex(forY: extractSurfaceCenter(baseFloor).y)
        
        return IdentifiedRoom(
            type: roomType,
            bounds: baseFloor,
            center: roomCenter,
            area: roomArea,
            confidence: calculateConfidenceFromFurniture(roomObjects, roomType: roomType),
            wallPoints: roomBoundary,
            doorways: doorways,
            floorIndex: fIndex
        )
    }
    
    private func createDefaultRoomLayout(capturedRoom: CapturedRoom, mainFloor: CapturedRoom.Surface) -> [IdentifiedRoom] {
        let spaceCenter = extractSurfaceCenter(mainFloor)
        let allObjects = capturedRoom.objects
        let fIndex = determineFloorIndex(forY: spaceCenter.y)
        
        // Create a reasonable default layout with multiple rooms
        var rooms: [IdentifiedRoom] = []
        
        // Use the overall space bounds but create logical divisions
        let totalObjects = allObjects.count
        
        // Living room (main area)
        let livingCenter = simd_float3(spaceCenter.x - 2.0, spaceCenter.y, spaceCenter.z)
        let livingBoundary = createRectangularBoundary(center: simd_float2(livingCenter.x, livingCenter.z), width: 4.0, depth: 4.0)
        
        let livingRoom = IdentifiedRoom(
            type: .livingRoom,
            bounds: mainFloor,
            center: livingCenter,
            area: 16.0,
            confidence: 0.4,
            wallPoints: livingBoundary,
            doorways: extractDoorwaysFromRoomPlan(capturedRoom: capturedRoom),
            floorIndex: fIndex
        )
        rooms.append(livingRoom)
        
        // Kitchen area
        let kitchenCenter = simd_float3(spaceCenter.x + 2.0, spaceCenter.y, spaceCenter.z - 2.0)
        let kitchenBoundary = createRectangularBoundary(center: simd_float2(kitchenCenter.x, kitchenCenter.z), width: 3.0, depth: 3.0)
        
        let kitchen = IdentifiedRoom(
            type: .kitchen,
            bounds: mainFloor,
            center: kitchenCenter,
            area: 9.0,
            confidence: 0.4,
            wallPoints: kitchenBoundary,
            doorways: extractDoorwaysFromRoomPlan(capturedRoom: capturedRoom),
            floorIndex: fIndex
        )
        rooms.append(kitchen)
        
        // Dining area (if enough objects)
        if totalObjects >= 6 {
            let diningCenter = simd_float3(spaceCenter.x, spaceCenter.y, spaceCenter.z + 2.0)
            let diningBoundary = createRectangularBoundary(center: simd_float2(diningCenter.x, diningCenter.z), width: 3.0, depth: 3.0)
            
            let diningRoom = IdentifiedRoom(
                type: .diningRoom,
                bounds: mainFloor,
                center: diningCenter,
                area: 9.0,
                confidence: 0.4,
                wallPoints: diningBoundary,
                doorways: extractDoorwaysFromRoomPlan(capturedRoom: capturedRoom),
                floorIndex: fIndex
            )
            rooms.append(diningRoom)
        }
        
        return rooms
    }
    
    private func createRectangularBoundary(center: simd_float2, width: Float, depth: Float) -> [simd_float2] {
        let halfWidth = width / 2
        let halfDepth = depth / 2
        
        return [
            simd_float2(center.x - halfWidth, center.y - halfDepth), // bottom-left
            simd_float2(center.x + halfWidth, center.y - halfDepth), // bottom-right
            simd_float2(center.x + halfWidth, center.y + halfDepth), // top-right
            simd_float2(center.x - halfWidth, center.y + halfDepth)  // top-left
        ]
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
        guard !furniture.isEmpty else { return 0.3 }
        
        let relevantObjects = furniture.filter { item in
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
        
        if relevantObjects.isEmpty {
            return 0.3 // Fallback for rooms without relevant furniture
        }
        
        // Weight by both relevance AND RoomPlan's confidence in detecting those objects
        let relevanceScore = Float(relevantObjects.count) / Float(furniture.count)
        let avgRelevantObjectConfidence = relevantObjects.map { confidenceToFloat($0.confidence) }.reduce(0, +) / Float(relevantObjects.count)
        
        // Combine relevance with object detection confidence
        return (relevanceScore * 0.7) + (avgRelevantObjectConfidence * 0.3)
    }
    
    private func calculateRoomTypeConfidence(roomType: RoomType, objects: [CapturedRoom.Object], surface: CapturedRoom.Surface) -> Float {
        // Enhanced confidence calculation using RoomPlan's built-in scores
        let surfaceConfidence = confidenceToFloat(surface.confidence) // Convert RoomPlan's surface confidence to Float
        let furnitureConfidence = calculateConfidenceFromFurniture(objects, roomType: roomType)
        let objectConfidence = calculateObjectConfidenceAverage(objects)
        
        // Weighted combination: 40% surface + 40% furniture relevance + 20% object detection
        let combinedConfidence = (surfaceConfidence * 0.4) + (furnitureConfidence * 0.4) + (objectConfidence * 0.2)
        
        print("🎯 Room confidence breakdown - Surface: \(String(format: "%.2f", surfaceConfidence)), Furniture: \(String(format: "%.2f", furnitureConfidence)), Objects: \(String(format: "%.2f", objectConfidence)), Combined: \(String(format: "%.2f", combinedConfidence))")
        
        return combinedConfidence
    }
    
    private func calculateObjectConfidenceAverage(_ objects: [CapturedRoom.Object]) -> Float {
        guard !objects.isEmpty else { return 0.0 }
        
        let totalConfidence = objects.map { confidenceToFloat($0.confidence) }.reduce(0, +)
        return totalConfidence / Float(objects.count)
    }
    
    // MARK: - Helper Methods
    
    private func confidenceToFloat(_ confidence: CapturedRoom.Confidence) -> Float {
        switch confidence {
        case .high:
            return 0.9
        case .medium:
            return 0.6
        case .low:
            return 0.3
        }
    }
    
    // MARK: - Room Containment
    
    func findRoomContaining(position: simd_float3) -> IdentifiedRoom? {
        print("🔍 Checking room containment for position (\(String(format: "%.2f", position.x)), \(String(format: "%.2f", position.z)))")
        
        for room in identifiedRooms {
            // Floor-aware filter: ensure Y is within reasonable range of this room's floor
            let yDelta = abs(position.y - room.center.y)
            if yDelta > 3.0 { // more than ~3m above/below the floor center => different floor
                continue
            }
            
            print("   Testing room \(room.type.rawValue) at (\(String(format: "%.2f", room.center.x)), \(String(format: "%.2f", room.center.z))) on floor \(room.floorIndex)")
            
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
            // Extract RoomPlan's confidence score for this object
            let roomPlanConfidence = object.confidence
            
            let item = FurnitureItem(
                category: object.category,
                position: simd_float3(object.transform.columns.3.x, object.transform.columns.3.y, object.transform.columns.3.z),
                dimensions: object.dimensions,
                roomId: nil, // Could be assigned based on containment
                confidence: confidenceToFloat(roomPlanConfidence) // Use RoomPlan's actual confidence converted to Float
            )
            furniture.append(item)
            
            print("📦 Object \(object.category) detected with confidence: \(String(format: "%.2f", confidenceToFloat(roomPlanConfidence)))")
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
    
    // MARK: - Floor detection & helpers
    
    private func computeFloors(from capturedRoom: CapturedRoom) {
        let heights = capturedRoom.floors.map { extractSurfaceCenter($0).y }
        let clustered = clusterHeights(heights)
        let sorted = clustered.sorted()
        DispatchQueue.main.async {
            self.floorHeights = sorted
        }
        print("🏢 Detected floors at heights: \(sorted.map { String(format: "%.2f", $0) }.joined(separator: ", "))")
    }
    
    private func clusterHeights(_ heights: [Float], tolerance: Float = 0.5) -> [Float] {
        guard !heights.isEmpty else { return [] }
        let sorted = heights.sorted()
        var clusters: [[Float]] = []
        for h in sorted {
            if var last = clusters.last, let representative = last.last, abs(h - representative) <= tolerance {
                last.append(h)
                clusters[clusters.count - 1] = last
            } else {
                clusters.append([h])
            }
        }
        // Use average of each cluster as the floor height
        return clusters.map { cluster in
            cluster.reduce(0, +) / Float(cluster.count)
        }
    }
    
    private func determineFloorIndex(forY y: Float) -> Int {
        // If we have no floors, treat as ground
        guard !floorHeights.isEmpty else { return 0 }
        var bestIndex = 0
        var bestDelta = Float.greatestFiniteMagnitude
        for (idx, fh) in floorHeights.enumerated() {
            let delta = abs(fh - y)
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = idx
            }
        }
        return bestIndex
    }
    
    func floorIndexForPosition(_ position: simd_float3) -> Int? {
        guard !floorHeights.isEmpty else { return 0 }
        let deltas = floorHeights.map { abs($0 - position.y) }
        if let (idx, minDelta) = deltas.enumerated().min(by: { $0.element < $1.element }) {
            return minDelta <= 1.5 ? idx : idx // Allow generous tolerance for handheld device height
        }
        return nil
    }
}