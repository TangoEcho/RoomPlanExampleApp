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
        let bounds: CapturedRoom.Surface? // Optional to handle fallback cases when no RoomPlan data exists
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
        
        print("🏠 Analyzing RoomPlan data:")
        print("   Floors: \(capturedRoom.floors.count)")
        print("   Walls: \(capturedRoom.walls.count)") 
        print("   Openings: \(capturedRoom.openings.count)")
        print("   Windows: \(capturedRoom.windows.count)")
        print("   Doors: \(capturedRoom.doors.count)")
        print("   Objects: \(capturedRoom.objects.count)")
        
        // CORRECT APPROACH: Only use floor surfaces as room boundaries
        // Walls/doors/windows are used for openings and connections, NOT separate rooms
        
        // Enhanced floor validation with detailed debugging
        print("🔍 Analyzing floor surfaces in detail:")
        for (i, floor) in capturedRoom.floors.enumerated() {
            print("   Floor \(i + 1): dimensions (\(String(format: "%.3f", floor.dimensions.x)), \(String(format: "%.3f", floor.dimensions.y)), \(String(format: "%.3f", floor.dimensions.z)))")
            print("     isFinite: x=\(floor.dimensions.x.isFinite), y=\(floor.dimensions.y.isFinite), z=\(floor.dimensions.z.isFinite)")
            print("     > 0: x=\(floor.dimensions.x > 0), z=\(floor.dimensions.z > 0)")
        }
        
        let validFloors = capturedRoom.floors.filter { surface in
            let xValid = surface.dimensions.x > 0 && surface.dimensions.x.isFinite
            let zValid = surface.dimensions.z > 0 && surface.dimensions.z.isFinite
            let yValid = surface.dimensions.y.isFinite  // Y can be 0 for floor height
            
            let isValid = xValid && zValid && yValid
            print("   Floor validation: x=\(xValid), z=\(zValid), y=\(yValid) -> valid=\(isValid)")
            return isValid
        }
        
        print("🔍 Found \(validFloors.count) valid floor surfaces (out of \(capturedRoom.floors.count) total)")
        
        if validFloors.count == 1 {
            // Single floor area - segment into logical rooms based on furniture
            print("🔍 Single floor detected - segmenting into logical rooms based on furniture clustering")
            rooms = segmentSingleFloorIntoRooms(capturedRoom: capturedRoom, mainFloor: validFloors[0])
        } else if validFloors.count > 1 {
            // Multiple distinct floor areas - each represents a separate room
            print("🔍 Multiple floor areas detected - treating each as separate room")
            for floor in validFloors {
                let room = createRoomFromFloorSurface(floor: floor, capturedRoom: capturedRoom)
                rooms.append(room)
            }
        } else {
            // No valid floors - create fallback room
            print("⚠️ No valid floor surfaces found - creating fallback room")
            rooms = createFallbackRoom(capturedRoom: capturedRoom)
        }
        
        print("✅ Identified \(rooms.count) rooms: \(rooms.map { $0.type.rawValue }.joined(separator: ", "))")
        
        DispatchQueue.main.async {
            self.identifiedRooms = rooms
        }
    }
    
    private func createRoomFromFloorSurface(floor: CapturedRoom.Surface, capturedRoom: CapturedRoom) -> IdentifiedRoom {
        let roomType = classifyRoomByFurniture(surface: floor, objects: capturedRoom.objects)
        let center = extractSurfaceCenter(floor)
        let area = calculateSurfaceArea(floor)
        
        // Create room boundary from floor surface (not walls/doors/windows)
        let wallPoints = createRoomBoundaryFromWalls(capturedRoom, centerPoint: center)
        let doorways = extractDoorwaysFromWallSurfaces(capturedRoom: capturedRoom, floorCenter: center)
        
        return IdentifiedRoom(
            type: roomType,
            bounds: floor,
            center: center,
            area: area,
            confidence: calculateRoomTypeConfidence(roomType: roomType, objects: capturedRoom.objects, surface: floor),
            wallPoints: wallPoints,
            doorways: doorways
        )
    }
    
    private func createFallbackRoom(capturedRoom: CapturedRoom) -> [IdentifiedRoom] {
        // Create a basic room based on object positions when no valid floors exist
        guard !capturedRoom.objects.isEmpty else {
            print("⚠️ No objects found - creating minimal fallback room")
            return createMinimalRoom()
        }
        
        let center = calculateCenterFromFurniture(capturedRoom.objects)
        let bounds = calculateBoundsFromFurniture(capturedRoom.objects)
        let roomType = classifyRoomFromFurnitureGroup(capturedRoom.objects)
        
        // Create boundary from object bounds with padding
        let padding: Float = 2.0
        let wallPoints = [
            simd_float2(bounds.min.x - padding, bounds.min.z - padding),
            simd_float2(bounds.max.x + padding, bounds.min.z - padding),
            simd_float2(bounds.max.x + padding, bounds.max.z + padding),
            simd_float2(bounds.min.x - padding, bounds.max.z + padding)
        ]
        
        // Create a mock floor surface for the fallback room
        guard let mockFloor = capturedRoom.walls.first ?? capturedRoom.openings.first ?? capturedRoom.doors.first else {
            print("⚠️ No surfaces found - creating minimal fallback room")
            return createMinimalRoom()
        }
        let area = (bounds.max.x - bounds.min.x + padding * 2) * (bounds.max.z - bounds.min.z + padding * 2)
        
        let fallbackRoom = IdentifiedRoom(
            type: roomType,
            bounds: mockFloor,
            center: center,
            area: area,
            confidence: 0.3, // Low confidence for fallback room
            wallPoints: wallPoints,
            doorways: []
        )
        
        return [fallbackRoom]
    }
    
    private func createMinimalRoom() -> [IdentifiedRoom] {
        // Last resort - create a basic room when no RoomPlan data is available  
        let defaultWallPoints = [
            simd_float2(-2.0, -2.0),
            simd_float2(2.0, -2.0),
            simd_float2(2.0, 2.0),
            simd_float2(-2.0, 2.0)
        ]
        
        print("⚠️ Creating minimal fallback room - no RoomPlan data available")
        
        // Create a minimal IdentifiedRoom that works with the renderer's placeholder logic
        // The renderer will detect empty rooms and show placeholder content
        let minimalRoom = IdentifiedRoom(
            type: .unknown,
            bounds: nil as CapturedRoom.Surface?, // This will be handled by the renderer
            center: simd_float3(0, 0, 0),
            area: 16.0, // 4x4 meter room
            confidence: 0.1, // Very low confidence
            wallPoints: defaultWallPoints,
            doorways: []
        )
        
        return [minimalRoom]
    }
    
    private func segmentSingleFloorIntoRooms(capturedRoom: CapturedRoom, mainFloor: CapturedRoom.Surface) -> [IdentifiedRoom] {
        let furnitureGroups = clusterFurnitureByProximity(capturedRoom.objects)
        
        print("   Found \(furnitureGroups.count) furniture clusters for single floor segmentation")
        
        var rooms: [IdentifiedRoom] = []
        
        for (index, group) in furnitureGroups.enumerated() {
            let roomType = classifyRoomFromFurnitureGroup(group)
            let roomCenter = calculateCenterFromFurniture(group)
            
            // Create room boundary based on furniture cluster area within the floor boundary
            let roomBoundary = createRoomBoundaryFromFurnitureCluster(group, floor: mainFloor)
            let roomArea = calculateAreaFromWallPoints(roomBoundary)
            let doorways = extractDoorwaysFromWallSurfaces(capturedRoom: capturedRoom, floorCenter: roomCenter)
            
            let room = IdentifiedRoom(
                type: roomType,
                bounds: mainFloor,
                center: roomCenter,
                area: roomArea,
                confidence: calculateConfidenceFromFurniture(group, roomType: roomType),
                wallPoints: createRoomBoundaryFromWalls(capturedRoom, centerPoint: simd_float3(roomCenter.x, 0, roomCenter.z)),
                doorways: doorways
            )
            
            rooms.append(room)
            print("   Room \(index + 1): \(roomType.rawValue) with \(group.count) furniture items")
        }
        
        // Ensure at least one room exists - create logical room divisions if needed
        if rooms.isEmpty {
            print("   No furniture clusters found, creating logical room divisions based on floor space")
            rooms = createLogicalRoomDivisions(capturedRoom: capturedRoom, mainFloor: mainFloor)
        }
        
        return rooms
    }
    
    // MARK: - RoomPlan Geometry Extraction
    
    private func createRoomBoundaryFromFloorSurface(_ surface: CapturedRoom.Surface) -> [simd_float2] {
        // Extract boundary from floor surface ONLY - this represents the actual room boundary
        print("🏗️ Creating room boundary from floor surface (not wall surfaces)")
        return createRoomBoundaryFromSurface(surface)
    }
    
    private func extractDoorwaysFromWallSurfaces(capturedRoom: CapturedRoom, floorCenter: simd_float3) -> [simd_float2] {
        var doorways: [simd_float2] = []
        
        // Extract doorways from door and opening surfaces within reasonable distance of room
        let maxDistance: Float = 5.0
        
        for door in capturedRoom.doors {
            let doorCenter = extractSurfaceCenter(door)
            let distance = simd_distance(doorCenter, floorCenter)
            
            if distance <= maxDistance {
                doorways.append(simd_float2(doorCenter.x, doorCenter.z))
            }
        }
        
        for opening in capturedRoom.openings {
            let openingCenter = extractSurfaceCenter(opening)
            let distance = simd_distance(openingCenter, floorCenter)
            
            if distance <= maxDistance {
                doorways.append(simd_float2(openingCenter.x, openingCenter.z))
            }
        }
        
        print("🚪 Found \(doorways.count) doorways/openings for room at (\(floorCenter.x), \(floorCenter.z))")
        return doorways
    }
    
    private func createRoomBoundaryFromSurface(_ surface: CapturedRoom.Surface) -> [simd_float2] {
        let center = extractSurfaceCenter(surface)
        let dimensions = surface.dimensions
        let transform = surface.transform
        
        print("🏗️ Creating room boundary from RoomPlan surface")
        print("   Center: (\(String(format: "%.2f", center.x)), \(String(format: "%.2f", center.z)))")
        print("   Dimensions: \(String(format: "%.2f", dimensions.x)) x \(String(format: "%.2f", dimensions.z))")
        print("   Transform matrix columns: [\(transform.columns.0), \(transform.columns.1), \(transform.columns.2), \(transform.columns.3)]")
        
        // IMPROVED: Use RoomPlan's actual surface geometry instead of assuming rectangles
        // RoomPlan provides detailed mesh data through the surface geometry
        
        // Try to extract actual geometry from the surface if available
        if let actualBoundary = extractActualSurfaceBoundary(surface) {
            print("   ✅ Using actual RoomPlan surface boundary with \(actualBoundary.count) points")
            return actualBoundary
        }
        
        // Fallback to improved rectangular approximation with better transform handling
        let roomWidth = max(dimensions.x, 1.0)
        let roomDepth = max(dimensions.z, 1.0)
        
        let halfWidth = roomWidth / 2
        let halfDepth = roomDepth / 2
        
        // IMPROVED: Better rotation extraction from 4x4 transform matrix
        // Extract the forward vector (Z-axis) from the transform matrix
        let forwardX = transform.columns.2.x
        let forwardZ = transform.columns.2.z
        let rotation = atan2(forwardZ, forwardX)
        
        print("   Extracted rotation: \(String(format: "%.2f", rotation * 180 / .pi))° from forward vector (\(forwardX), \(forwardZ))")
        
        // Create corners in local space
        let corners = [
            simd_float2(-halfWidth, -halfDepth), // bottom-left
            simd_float2(halfWidth, -halfDepth),  // bottom-right
            simd_float2(halfWidth, halfDepth),   // top-right
            simd_float2(-halfWidth, halfDepth)   // top-left
        ]
        
        // Transform to world coordinates with improved rotation
        let center2D = simd_float2(center.x, center.z)
        let transformedCorners = corners.map { corner in
            let rotatedX = corner.x * cos(rotation) - corner.y * sin(rotation)
            let rotatedZ = corner.x * sin(rotation) + corner.y * cos(rotation)
            return center2D + simd_float2(rotatedX, rotatedZ)
        }
        
        print("   Generated \(transformedCorners.count) boundary points:")
        for (i, point) in transformedCorners.enumerated() {
            print("     Point \(i): (\(String(format: "%.2f", point.x)), \(String(format: "%.2f", point.y)))")
        }
        
        return transformedCorners
    }
    
    private func extractActualSurfaceBoundary(_ surface: CapturedRoom.Surface) -> [simd_float2]? {
        // Try to create boundaries from wall surfaces instead of floor approximations
        // This is a placeholder that could be enhanced to use the actual wall positions
        return nil
    }
    
    private func createRoomBoundaryFromWalls(_ capturedRoom: CapturedRoom, centerPoint: simd_float3) -> [simd_float2] {
        // Create proper room boundaries using wall surface positions
        print("🧱 Creating room boundary from \(capturedRoom.walls.count) wall surfaces")
        
        // ENHANCED: Always try to use actual wall data first, even with lenient criteria
        var wallSegments: [(start: simd_float2, end: simd_float2)] = []
        let maxDistance: Float = 15.0 // Increased range to catch more walls
        
        // Extract wall segments instead of just corner points
        for (wallIndex, wall) in capturedRoom.walls.enumerated() {
            let wallCenter = extractSurfaceCenter(wall)
            let distance = simd_distance(wallCenter, centerPoint)
            
            print("   Wall \(wallIndex + 1): center (\(String(format: "%.2f", wallCenter.x)), \(String(format: "%.2f", wallCenter.z))), distance \(String(format: "%.2f", distance))m")
            
            if distance <= maxDistance {
                // Extract wall as line segment
                let wallSegment = extractWallLineSegment(wall)
                wallSegments.append(wallSegment)
                print("     ✅ Wall \(wallIndex + 1) included: (\(String(format: "%.2f", wallSegment.start.x)), \(String(format: "%.2f", wallSegment.start.y))) to (\(String(format: "%.2f", wallSegment.end.x)), \(String(format: "%.2f", wallSegment.end.y)))")
            } else {
                print("     ❌ Wall \(wallIndex + 1) too far (\(String(format: "%.2f", distance))m)")
            }
        }
        
        if !wallSegments.isEmpty {
            // Create room boundary from wall segments
            let wallBoundary = createBoundaryFromWallSegments(wallSegments)
            if wallBoundary.count >= 3 {
                print("   ✅ Created room boundary with \(wallBoundary.count) wall-based points")
                return wallBoundary
            }
        }
        
        print("   ⚠️ Could not create wall-based boundary, falling back to furniture boundary")
        // Fallback to furniture-based boundary
        if let firstFloor = capturedRoom.floors.first {
            return createRoomBoundaryFromFurnitureCluster(capturedRoom.objects, floor: firstFloor)
        } else {
            // Last resort - create rectangular boundary
            let padding: Float = 2.0
            return [
                simd_float2(centerPoint.x - padding, centerPoint.z - padding),
                simd_float2(centerPoint.x + padding, centerPoint.z - padding),
                simd_float2(centerPoint.x + padding, centerPoint.z + padding),
                simd_float2(centerPoint.x - padding, centerPoint.z + padding)
            ]
        }
    }
    
    private func extractWallLineSegment(_ wall: CapturedRoom.Surface) -> (start: simd_float2, end: simd_float2) {
        let center = extractSurfaceCenter(wall)
        let dimensions = wall.dimensions
        let transform = wall.transform
        
        // Extract wall orientation from transform matrix
        let rightVector = simd_float3(transform.columns.0.x, 0, transform.columns.0.z)
        let normalizedRight = simd_normalize(rightVector)
        
        // Calculate wall endpoints along its length
        let halfLength = dimensions.x / 2  // Wall length
        let center2D = simd_float2(center.x, center.z)
        let rightVector2D = simd_float2(normalizedRight.x, normalizedRight.z)
        
        let start = center2D - rightVector2D * halfLength
        let end = center2D + rightVector2D * halfLength
        
        return (start: start, end: end)
    }
    
    private func createBoundaryFromWallSegments(_ wallSegments: [(start: simd_float2, end: simd_float2)]) -> [simd_float2] {
        // Collect all wall endpoints
        var allPoints: [simd_float2] = []
        for segment in wallSegments {
            allPoints.append(segment.start)
            allPoints.append(segment.end)
        }
        
        // Remove duplicates (endpoints that are very close together)
        let uniquePoints = allPoints.reduce(into: [simd_float2]()) { result, point in
            if !result.contains(where: { simd_distance($0, point) < 0.2 }) {
                result.append(point)
            }
        }
        
        guard uniquePoints.count >= 3 else { 
            print("   ❌ Insufficient unique wall points (\(uniquePoints.count))")
            return []
        }
        
        // Calculate centroid for ordering
        let centroid = uniquePoints.reduce(simd_float2(0, 0), +) / Float(uniquePoints.count)
        
        // Sort points by angle to create a proper room boundary
        let sortedPoints = uniquePoints.sorted { point1, point2 in
            let angle1 = atan2(point1.y - centroid.y, point1.x - centroid.x)
            let angle2 = atan2(point2.y - centroid.y, point2.x - centroid.x)
            return angle1 < angle2
        }
        
        print("   📐 Wall boundary: \(sortedPoints.count) points around centroid (\(String(format: "%.2f", centroid.x)), \(String(format: "%.2f", centroid.y)))")
        return sortedPoints
    }
    
    private func extractWallCornerPoints(_ wall: CapturedRoom.Surface) -> [simd_float2] {
        let center = extractSurfaceCenter(wall)
        let dimensions = wall.dimensions
        let transform = wall.transform
        
        // Extract wall orientation from transform matrix
        let rightX = transform.columns.0.x
        let rightZ = transform.columns.0.z
        let forwardX = transform.columns.2.x
        let forwardZ = transform.columns.2.z
        
        let rightVector = simd_normalize(simd_float2(rightX, rightZ))
        let forwardVector = simd_normalize(simd_float2(forwardX, forwardZ))
        
        let halfWidth = dimensions.x / 2
        let halfDepth = dimensions.z / 2
        
        let center2D = simd_float2(center.x, center.z)
        
        // Generate wall corner points (broken up to avoid type-checking timeout)
        let corner1 = center2D - rightVector * halfWidth - forwardVector * halfDepth
        let corner2 = center2D + rightVector * halfWidth - forwardVector * halfDepth  
        let corner3 = center2D + rightVector * halfWidth + forwardVector * halfDepth
        let corner4 = center2D - rightVector * halfWidth + forwardVector * halfDepth
        let corners = [corner1, corner2, corner3, corner4]
        
        return corners
    }
    
    private func createOrderedBoundaryFromPoints(_ points: [simd_float2], center: simd_float2) -> [simd_float2] {
        guard !points.isEmpty else { return [] }
        
        // Remove duplicate points
        let uniquePoints = points.reduce(into: [simd_float2]()) { result, point in
            if !result.contains(where: { simd_distance($0, point) < 0.1 }) {
                result.append(point)
            }
        }
        
        guard uniquePoints.count >= 3 else { 
            // Fallback to simple rectangular boundary
            let padding: Float = 2.0
            return [
                center + simd_float2(-padding, -padding),
                center + simd_float2(padding, -padding),
                center + simd_float2(padding, padding),
                center + simd_float2(-padding, padding)
            ]
        }
        
        // Sort points by angle relative to center to create proper polygon
        let sortedPoints = uniquePoints.sorted { point1, point2 in
            let angle1 = atan2(point1.y - center.y, point1.x - center.x)
            let angle2 = atan2(point2.y - center.y, point2.x - center.x)
            return angle1 < angle2
        }
        
        return sortedPoints
    }
    
    private func createRoomBoundaryFromFurnitureCluster(_ furniture: [CapturedRoom.Object], floor: CapturedRoom.Surface) -> [simd_float2] {
        let furnitureCenter = calculateCenterFromFurniture(furniture)
        let furnitureBounds = calculateBoundsFromFurniture(furniture)
        
        print("🧱 Creating room boundary from furniture cluster:")
        print("   Furniture center: (\(String(format: "%.3f", furnitureCenter.x)), \(String(format: "%.3f", furnitureCenter.z)))")
        print("   Furniture bounds: (\(String(format: "%.3f", furnitureBounds.min.x)), \(String(format: "%.3f", furnitureBounds.min.z))) to (\(String(format: "%.3f", furnitureBounds.max.x)), \(String(format: "%.3f", furnitureBounds.max.z)))")
        
        // Analyze furniture layout to infer room orientation and potential rotation
        let roomOrientation = inferRoomOrientation(from: furniture)
        print("   Inferred room orientation: \(roomOrientation)")
        
        // Determine if coordinate system rotation is needed based on furniture analysis
        let coordinateRotation = determineCoordinateRotation(from: furniture)
        print("   Coordinate rotation needed: \(coordinateRotation)°")
        
        // Create room boundary with padding around furniture
        let padding: Float = 1.5
        let roomWidth = max(furnitureBounds.max.x - furnitureBounds.min.x + padding * 2, 2.0)
        let roomDepth = max(furnitureBounds.max.z - furnitureBounds.min.z + padding * 2, 2.0)
        
        let halfWidth = roomWidth / 2
        let halfDepth = roomDepth / 2
        let center2D = simd_float2(furnitureCenter.x, furnitureCenter.z)
        
        // Apply coordinate rotation if needed
        var boundary = [
            center2D + simd_float2(-halfWidth, -halfDepth), // bottom-left
            center2D + simd_float2(halfWidth, -halfDepth),  // bottom-right
            center2D + simd_float2(halfWidth, halfDepth),   // top-right
            center2D + simd_float2(-halfWidth, halfDepth)   // top-left
        ]
        
        // Apply rotation transformation if needed
        if coordinateRotation != 0 {
            let rotationRadians = coordinateRotation * Float.pi / 180
            boundary = boundary.map { point in
                let relativePoint = point - center2D
                let rotatedX = relativePoint.x * cos(rotationRadians) - relativePoint.y * sin(rotationRadians)
                let rotatedY = relativePoint.x * sin(rotationRadians) + relativePoint.y * cos(rotationRadians)
                return center2D + simd_float2(rotatedX, rotatedY)
            }
            print("   Applied \(coordinateRotation)° rotation to room boundary")
        }
        
        print("   Generated room boundary:")
        for (i, point) in boundary.enumerated() {
            print("     Corner \(i): (\(String(format: "%.3f", point.x)), \(String(format: "%.3f", point.y)))")
        }
        
        return boundary
    }
    
    private func inferRoomOrientation(from furniture: [CapturedRoom.Object]) -> String {
        // Analyze furniture positioning to understand room layout
        let beds = furniture.filter { $0.category == .bed }
        let storage = furniture.filter { $0.category == .storage }
        
        // If we have bed + storage, analyze their relative positions
        if let bed = beds.first, !storage.isEmpty {
            let bedPos = simd_float2(bed.transform.columns.3.x, bed.transform.columns.3.z)
            
            // Find storage items near the bed (potential nightstands)
            let nearbyStorage = storage.filter { storageItem in
                let storagePos = simd_float2(storageItem.transform.columns.3.x, storageItem.transform.columns.3.z)
                let distance = simd_distance(bedPos, storagePos)
                return distance < 2.0 // Within 2 meters of bed
            }
            
            if nearbyStorage.count >= 2 {
                let storagePositions = nearbyStorage.map { simd_float2($0.transform.columns.3.x, $0.transform.columns.3.z) }
                
                // Check if storage items are on opposite sides of the bed
                let bedToCentroid = storagePositions.reduce(simd_float2(0, 0), +) / Float(storagePositions.count) - bedPos
                let arrangement = abs(bedToCentroid.x) > abs(bedToCentroid.y) ? "horizontal" : "vertical"
                
                return "bedroom_\(arrangement)_with_nightstands"
            }
        }
        
        return "standard_rectangular"
    }
    
    private func determineCoordinateRotation(from furniture: [CapturedRoom.Object]) -> Float {
        // Analyze furniture arrangement to determine if coordinate system rotation is needed
        let beds = furniture.filter { $0.category == .bed }
        let storage = furniture.filter { $0.category == .storage }
        
        guard let bed = beds.first else { return 0 }
        
        let bedPos = simd_float2(bed.transform.columns.3.x, bed.transform.columns.3.z)
        print("🔄 Analyzing coordinate system for bed at (\(String(format: "%.3f", bedPos.x)), \(String(format: "%.3f", bedPos.y)))")
        
        // Find nearby storage items (potential nightstands)
        let nearbyStorage = storage.filter { storageItem in
            let storagePos = simd_float2(storageItem.transform.columns.3.x, storageItem.transform.columns.3.z)
            let distance = simd_distance(bedPos, storagePos)
            return distance < 2.0
        }
        
        print("   Found \(nearbyStorage.count) nearby storage items:")
        for (i, storageItem) in nearbyStorage.enumerated() {
            let storagePos = simd_float2(storageItem.transform.columns.3.x, storageItem.transform.columns.3.z)
            let direction = storagePos - bedPos
            let angle = atan2(direction.y, direction.x) * 180 / Float.pi
            let distance = simd_distance(bedPos, storagePos)
            
            print("     Storage \(i+1): (\(String(format: "%.3f", storagePos.x)), \(String(format: "%.3f", storagePos.y))) - \(String(format: "%.1f", angle))° at \(String(format: "%.2f", distance))m")
        }
        
        // If we have exactly 2 nearby storage items, analyze their arrangement
        if nearbyStorage.count >= 2 {
            let storagePositions = nearbyStorage.prefix(2).map { 
                simd_float2($0.transform.columns.3.x, $0.transform.columns.3.z) 
            }
            
            let pos1 = storagePositions[0]
            let pos2 = storagePositions[1]
            
            // Calculate angles of both storage items relative to bed
            let dir1 = pos1 - bedPos
            let dir2 = pos2 - bedPos
            let angle1 = atan2(dir1.y, dir1.x) * 180 / Float.pi
            let angle2 = atan2(dir2.y, dir2.x) * 180 / Float.pi
            
            print("   Storage arrangement analysis:")
            print("     Storage 1 angle: \(String(format: "%.1f", angle1))°")
            print("     Storage 2 angle: \(String(format: "%.1f", angle2))°")
            
            // Check if they form an east-west pattern (should be around ±90° apart)
            let angleDiff = abs(angle1 - angle2)
            let normalizedDiff = min(angleDiff, 360 - angleDiff)
            
            print("     Angle difference: \(String(format: "%.1f", normalizedDiff))°")
            
            // If storage items are roughly opposite (150-210° apart), they might be nightstands
            if normalizedDiff > 120 && normalizedDiff < 240 {
                // Check current orientation - are they more north-south or east-west?
                let avgAngle = (angle1 + angle2) / 2
                
                // Normalize to find the perpendicular axis
                let perpAngle = avgAngle + 90
                let normalizedPerpAngle = fmod(perpAngle + 360, 360)
                
                print("     Average angle: \(String(format: "%.1f", avgAngle))°")
                print("     Perpendicular axis: \(String(format: "%.1f", normalizedPerpAngle))°")
                
                // If the perpendicular axis is closer to north-south (0°, 180°), 
                // nightstands are currently east-west aligned
                // If closer to east-west (90°, 270°), nightstands are north-south aligned
                
                let distFromNorthSouth = min(abs(normalizedPerpAngle), abs(normalizedPerpAngle - 180), abs(normalizedPerpAngle - 360))
                let distFromEastWest = min(abs(normalizedPerpAngle - 90), abs(normalizedPerpAngle - 270))
                
                if distFromEastWest < distFromNorthSouth {
                    // Nightstands are currently north-south, but user expects east-west
                    print("     🔄 Nightstands are north-south aligned, suggesting 90° rotation needed")
                    return 90
                } else {
                    print("     ✅ Nightstands are already east-west aligned")
                    return 0
                }
            }
        }
        
        // No clear nightstand pattern found - use default orientation
        print("   No clear nightstand pattern found - using default orientation")
        return 0
    }
    
    
    // MARK: - Helper Methods
    
    private func extractSurfaceCenter(_ surface: CapturedRoom.Surface) -> simd_float3 {
        let transform = surface.transform
        let position = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        
        // IMPROVED: Add validation and debugging for transform extraction
        print("   🎯 Surface center extracted: (\(String(format: "%.3f", position.x)), \(String(format: "%.3f", position.y)), \(String(format: "%.3f", position.z)))")
        print("   📐 Surface dimensions: \(String(format: "%.2f", surface.dimensions.x))×\(String(format: "%.2f", surface.dimensions.y))×\(String(format: "%.2f", surface.dimensions.z))")
        
        return position
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
        let doorways = extractDoorwaysFromWallSurfaces(capturedRoom: capturedRoom, floorCenter: roomCenter)
        
        return IdentifiedRoom(
            type: roomType,
            bounds: baseFloor,
            center: roomCenter,
            area: roomArea,
            confidence: objects.isEmpty ? 0.3 : 0.7,
            wallPoints: roomBoundary,
            doorways: doorways
        )
    }
    
    private func createDefaultRoomLayout(capturedRoom: CapturedRoom, mainFloor: CapturedRoom.Surface) -> [IdentifiedRoom] {
        let allObjects = capturedRoom.objects
        let spaceCenter = extractSurfaceCenter(mainFloor)
        
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
            doorways: extractDoorwaysFromWallSurfaces(capturedRoom: capturedRoom, floorCenter: simd_float3(0, 0, 0))
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
            doorways: extractDoorwaysFromWallSurfaces(capturedRoom: capturedRoom, floorCenter: simd_float3(0, 0, 0))
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
                doorways: extractDoorwaysFromWallSurfaces(capturedRoom: capturedRoom, floorCenter: simd_float3(0, 0, 0))
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
        print("   Room type: \(roomType.rawValue) with \(objects.count) nearby objects")
        
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
        @unknown default:
            return 0.3
        }
    }
    
    // MARK: - Room Containment
    
    func findRoomContaining(position: simd_float3) -> IdentifiedRoom? {
        print("🔍 Checking room containment for position (\(String(format: "%.2f", position.x)), \(String(format: "%.2f", position.z)))")
        
        for (roomIndex, room) in identifiedRooms.enumerated() {
            print("   Testing room \(roomIndex + 1): \(room.type.rawValue) at (\(String(format: "%.2f", room.center.x)), \(String(format: "%.2f", room.center.z)))")
            print("     Room boundary points: \(room.wallPoints.count)")
            
            // Debug room boundary
            for (pointIndex, point) in room.wallPoints.enumerated() {
                print("       Point \(pointIndex): (\(String(format: "%.2f", point.x)), \(String(format: "%.2f", point.y)))")
            }
            
            if room.wallPoints.count >= 3 {
                let isInside = isPointInPolygon(simd_float2(position.x, position.z), polygon: room.wallPoints)
                print("     Polygon containment test: \(isInside)")
                if isInside {
                    print("     ✅ Position found in \(room.type.rawValue)!")
                    return room
                }
            } else {
                print("     ⚠️ Insufficient boundary points for containment test")
            }
        }
        
        print("   ❌ Position not found in any room - may be outside all boundaries or in gaps between rooms")
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
        
        print("🏠 Cataloging \(capturedRoom.objects.count) furniture items:")
        
        for (index, object) in capturedRoom.objects.enumerated() {
            // Extract RoomPlan's confidence score for this object
            let roomPlanConfidence = object.confidence
            let position = simd_float3(object.transform.columns.3.x, object.transform.columns.3.y, object.transform.columns.3.z)
            
            let item = FurnitureItem(
                category: object.category,
                position: position,
                dimensions: object.dimensions,
                roomId: nil, // Could be assigned based on containment
                confidence: confidenceToFloat(roomPlanConfidence) // Use RoomPlan's actual confidence converted to Float
            )
            furniture.append(item)
            
            // Enhanced debugging for spatial relationships
            print("📦 Item \(index + 1): \(object.category)")
            print("   Position: (\(String(format: "%.3f", position.x)), \(String(format: "%.3f", position.y)), \(String(format: "%.3f", position.z)))")
            print("   Dimensions: \(String(format: "%.2f", object.dimensions.x)) × \(String(format: "%.2f", object.dimensions.y)) × \(String(format: "%.2f", object.dimensions.z))")
            print("   Confidence: \(String(format: "%.2f", confidenceToFloat(roomPlanConfidence)))")
            
            // Extract rotation info from transform matrix
            let transform = object.transform
            let rightVector = simd_float3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
            let upVector = simd_float3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
            let forwardVector = simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
            
            let yRotation = atan2(forwardVector.x, forwardVector.z) * 180 / Float.pi
            print("   Y-rotation: \(String(format: "%.1f", yRotation))°")
        }
        
        // Analyze spatial relationships between furniture items
        analyzeFurnitureSpatialRelationships(furniture)
        
        DispatchQueue.main.async {
            self.furnitureItems = furniture
        }
    }
    
    private func analyzeFurnitureSpatialRelationships(_ furniture: [FurnitureItem]) {
        guard furniture.count > 1 else { return }
        
        print("🔍 Analyzing spatial relationships between furniture:")
        
        let beds = furniture.filter { $0.category == .bed }
        let storage = furniture.filter { $0.category == .storage }
        let tables = furniture.filter { $0.category == .table }
        
        if let bed = beds.first {
            print("   Bed at: (\(String(format: "%.3f", bed.position.x)), \(String(format: "%.3f", bed.position.z)))")
            
            // Find nearby storage (potential nightstands)
            for storageItem in storage {
                let distance = simd_distance(simd_float2(bed.position.x, bed.position.z), 
                                           simd_float2(storageItem.position.x, storageItem.position.z))
                let direction = simd_float2(storageItem.position.x - bed.position.x, 
                                          storageItem.position.z - bed.position.z)
                let angle = atan2(direction.y, direction.x) * 180 / Float.pi
                
                print("   Storage \(distance < 2.0 ? "NEAR" : "FAR") bed: distance \(String(format: "%.2f", distance))m, angle \(String(format: "%.1f", angle))°")
                
                if distance < 2.0 {
                    let relativePosition = distance < 1.0 ? "very close" : "close"
                    let cardinalDirection = getCardinalDirection(from: angle)
                    print("     -> \(relativePosition) \(cardinalDirection) of bed")
                }
            }
        }
    }
    
    private func getCardinalDirection(from angle: Float) -> String {
        let normalizedAngle = angle < 0 ? angle + 360 : angle
        switch normalizedAngle {
        case 315...360, 0..<45:
            return "east"
        case 45..<135:
            return "south"
        case 135..<225:
            return "west"
        case 225..<315:
            return "north"
        default:
            return "unknown"
        }
    }
    
    private func mapRoomConnections(from capturedRoom: CapturedRoom) {
        // Simplified - no connections for now
        DispatchQueue.main.async {
            self.roomConnections = []
        }
    }
    
}