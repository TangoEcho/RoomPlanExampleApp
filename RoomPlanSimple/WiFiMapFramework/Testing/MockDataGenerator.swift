import Foundation

/// Generates mock data for testing RoomPlan integration and WiFi analysis
public class MockDataGenerator {
    
    // MARK: - Properties
    
    private let random = SystemRandomNumberGenerator()
    
    // MARK: - Room Generation
    
    /// Generate a standard test room with typical furniture
    /// - Parameters:
    ///   - roomType: Type of room to generate
    ///   - size: Room dimensions (optional, uses defaults based on type)
    /// - Returns: Mock room model
    public func generateStandardRoom(
        type roomType: RoomType = .livingRoom,
        size: Vector3D? = nil
    ) -> RoomModel {
        
        let roomSize = size ?? defaultSizeForRoom(type: roomType)
        let bounds = BoundingBox(
            min: Point3D.zero,
            max: Point3D(x: roomSize.x, y: roomSize.y, z: roomSize.z)
        )
        
        let walls = generateWalls(for: bounds)
        let furniture = generateFurniture(for: roomType, bounds: bounds)
        let openings = generateOpenings(for: bounds, roomType: roomType)
        let floor = FloorPlan(bounds: bounds, area: roomSize.x * roomSize.y)
        
        return RoomModel(
            id: UUID(),
            name: roomType.displayName,
            bounds: bounds,
            walls: walls,
            furniture: furniture,
            openings: openings,
            floor: floor
        )
    }
    
    /// Generate a room with specific characteristics for testing
    /// - Parameters:
    ///   - size: Room dimensions
    ///   - furnitureCount: Number of furniture items to generate
    ///   - complexity: Room complexity level
    /// - Returns: Mock room model
    public func generateCustomRoom(
        size: Vector3D,
        furnitureCount: Int = 5,
        complexity: RoomComplexity = .medium
    ) -> RoomModel {
        
        let bounds = BoundingBox(
            min: Point3D.zero,
            max: Point3D(x: size.x, y: size.y, z: size.z)
        )
        
        let walls = generateWalls(for: bounds, complexity: complexity)
        let furniture = generateRandomFurniture(count: furnitureCount, bounds: bounds)
        let openings = generateOpenings(for: bounds, complexity: complexity)
        let floor = FloorPlan(bounds: bounds, area: size.x * size.y)
        
        return RoomModel(
            id: UUID(),
            name: "Custom Test Room",
            bounds: bounds,
            walls: walls,
            furniture: furniture,
            openings: openings,
            floor: floor
        )
    }
    
    // MARK: - Wall Generation
    
    private func generateWalls(for bounds: BoundingBox, complexity: RoomComplexity = .medium) -> [WallElement] {
        var walls: [WallElement] = []
        
        let wallHeight = bounds.size.z
        let wallThickness = 0.1 // 10cm
        
        // Basic rectangular room walls
        let corners = [
            bounds.min,
            Point3D(x: bounds.max.x, y: bounds.min.y, z: bounds.min.z),
            Point3D(x: bounds.max.x, y: bounds.max.y, z: bounds.min.z),
            Point3D(x: bounds.min.x, y: bounds.max.y, z: bounds.min.z)
        ]
        
        for i in 0..<corners.count {
            let start = corners[i]
            let end = corners[(i + 1) % corners.count]
            
            let wall = WallElement(
                id: UUID(),
                startPoint: start,
                endPoint: end,
                height: wallHeight,
                thickness: wallThickness,
                material: randomWallMaterial()
            )
            walls.append(wall)
        }
        
        // Add additional walls for complex rooms
        if complexity == .high {
            walls.append(contentsOf: generateAdditionalWalls(bounds: bounds))
        }
        
        return walls
    }
    
    private func generateAdditionalWalls(bounds: BoundingBox) -> [WallElement] {
        var additionalWalls: [WallElement] = []
        
        // Add a dividing wall in the middle for complex rooms
        let midY = bounds.center.y
        let dividerWall = WallElement(
            id: UUID(),
            startPoint: Point3D(x: bounds.min.x + bounds.size.x * 0.3, y: midY, z: bounds.min.z),
            endPoint: Point3D(x: bounds.max.x - bounds.size.x * 0.3, y: midY, z: bounds.min.z),
            height: bounds.size.z,
            thickness: 0.1,
            material: .drywall
        )
        additionalWalls.append(dividerWall)
        
        return additionalWalls
    }
    
    private func randomWallMaterial() -> WallMaterial {
        let materials: [WallMaterial] = [.drywall, .concrete, .brick, .wood]
        return materials.randomElement() ?? .drywall
    }
    
    // MARK: - Furniture Generation
    
    private func generateFurniture(for roomType: RoomType, bounds: BoundingBox) -> [FurnitureItem] {
        let furnitureSpecs = furnitureSpecsForRoom(type: roomType)
        var furniture: [FurnitureItem] = []
        
        for spec in furnitureSpecs {
            if let furnitureItem = generateFurnitureItem(spec: spec, bounds: bounds, existingFurniture: furniture) {
                furniture.append(furnitureItem)
            }
        }
        
        return furniture
    }
    
    private func generateRandomFurniture(count: Int, bounds: BoundingBox) -> [FurnitureItem] {
        let allFurnitureTypes: [FurnitureType] = [
            .table, .desk, .dresser, .shelf, .cabinet, .counter, .nightstand, .sofa, .chair, .bed
        ]
        
        var furniture: [FurnitureItem] = []
        
        for _ in 0..<count {
            let furnitureType = allFurnitureTypes.randomElement() ?? .table
            let spec = FurnitureSpec(
                type: furnitureType,
                dimensions: defaultDimensionsForFurniture(type: furnitureType),
                position: .random
            )
            
            if let furnitureItem = generateFurnitureItem(spec: spec, bounds: bounds, existingFurniture: furniture) {
                furniture.append(furnitureItem)
            }
        }
        
        return furniture
    }
    
    private func generateFurnitureItem(
        spec: FurnitureSpec,
        bounds: BoundingBox,
        existingFurniture: [FurnitureItem]
    ) -> FurnitureItem? {
        
        let dimensions = spec.dimensions
        let position = calculateFurniturePosition(spec: spec, bounds: bounds, existingFurniture: existingFurniture)
        
        let furnitureBounds = BoundingBox(
            min: Point3D(
                x: position.x - dimensions.x/2,
                y: position.y - dimensions.y/2,
                z: bounds.min.z
            ),
            max: Point3D(
                x: position.x + dimensions.x/2,
                y: position.y + dimensions.y/2,
                z: bounds.min.z + dimensions.z
            )
        )
        
        // Check for overlaps with existing furniture
        for existing in existingFurniture {
            if furnitureBounds.intersects(existing.bounds) {
                return nil // Skip if overlapping
            }
        }
        
        // Generate surfaces
        let surfaces = generateSurfaces(for: spec.type, bounds: furnitureBounds)
        
        // Generate confidence score
        let confidence = Double.random(in: 0.7...0.95)
        
        return FurnitureItem(
            id: UUID(),
            type: spec.type,
            bounds: furnitureBounds,
            surfaces: surfaces,
            confidence: confidence
        )
    }
    
    private func calculateFurniturePosition(
        spec: FurnitureSpec,
        bounds: BoundingBox,
        existingFurniture: [FurnitureItem]
    ) -> Point3D {
        
        let roomSize = bounds.size
        let furnitureSize = spec.dimensions
        
        // Ensure furniture fits within room with margin
        let margin = 0.5
        let validArea = BoundingBox(
            min: Point3D(
                x: bounds.min.x + margin + furnitureSize.x/2,
                y: bounds.min.y + margin + furnitureSize.y/2,
                z: bounds.min.z
            ),
            max: Point3D(
                x: bounds.max.x - margin - furnitureSize.x/2,
                y: bounds.max.y - margin - furnitureSize.y/2,
                z: bounds.max.z
            )
        )
        
        switch spec.position {
        case .center:
            return validArea.center
            
        case .wall:
            // Place against a wall
            let walls = [
                Point3D(x: validArea.min.x, y: validArea.center.y, z: validArea.min.z), // Left wall
                Point3D(x: validArea.max.x, y: validArea.center.y, z: validArea.min.z), // Right wall
                Point3D(x: validArea.center.x, y: validArea.min.y, z: validArea.min.z), // Front wall
                Point3D(x: validArea.center.x, y: validArea.max.y, z: validArea.min.z)  // Back wall
            ]
            return walls.randomElement() ?? validArea.center
            
        case .corner:
            // Place in a corner
            let corners = [
                Point3D(x: validArea.min.x, y: validArea.min.y, z: validArea.min.z),
                Point3D(x: validArea.max.x, y: validArea.min.y, z: validArea.min.z),
                Point3D(x: validArea.max.x, y: validArea.max.y, z: validArea.min.z),
                Point3D(x: validArea.min.x, y: validArea.max.y, z: validArea.min.z)
            ]
            return corners.randomElement() ?? validArea.center
            
        case .random:
            return Point3D(
                x: Double.random(in: validArea.min.x...validArea.max.x),
                y: Double.random(in: validArea.min.y...validArea.max.y),
                z: validArea.min.z
            )
        }
    }
    
    private func generateSurfaces(for furnitureType: FurnitureType, bounds: BoundingBox) -> [PlacementSurface] {
        var surfaces: [PlacementSurface] = []
        
        switch furnitureType {
        case .table, .desk, .counter, .dresser, .cabinet, .nightstand:
            // Top surface
            let topSurface = PlacementSurface(
                id: UUID(),
                center: Point3D(x: bounds.center.x, y: bounds.center.y, z: bounds.max.z),
                normal: Vector3D(x: 0, y: 0, z: 1),
                area: bounds.size.x * bounds.size.y * 0.8, // 80% usable area
                accessibility: randomAccessibility(),
                powerProximity: Double.random(in: 0.5...3.0)
            )
            surfaces.append(topSurface)
            
        case .shelf:
            // Multiple shelf levels
            let shelfCount = Int.random(in: 2...5)
            let shelfSpacing = bounds.size.z / Double(shelfCount)
            
            for i in 0..<shelfCount {
                let shelfZ = bounds.min.z + (Double(i) + 0.5) * shelfSpacing
                let shelfSurface = PlacementSurface(
                    id: UUID(),
                    center: Point3D(x: bounds.center.x, y: bounds.center.y, z: shelfZ),
                    normal: Vector3D(x: 0, y: 0, z: 1),
                    area: bounds.size.x * min(bounds.size.y, 0.4), // Limited depth
                    accessibility: i == 1 || i == 2 ? .good : .poor, // Middle shelves more accessible
                    powerProximity: Double.random(in: 1.0...4.0)
                )
                surfaces.append(shelfSurface)
            }
            
        default:
            // No surfaces for seating furniture
            break
        }
        
        return surfaces
    }
    
    private func randomAccessibility() -> SurfaceAccessibility {
        let accessibilities: [SurfaceAccessibility] = [.excellent, .good, .poor]
        return accessibilities.randomElement() ?? .good
    }
    
    // MARK: - Opening Generation
    
    private func generateOpenings(for bounds: BoundingBox, roomType: RoomType = .livingRoom, complexity: RoomComplexity = .medium) -> [Opening] {
        var openings: [Opening] = []
        
        // Always add at least one door
        let doorWidth = 0.8
        let doorHeight = 2.0
        let doorPosition = Point3D(
            x: bounds.min.x + bounds.size.x * Double.random(in: 0.2...0.8),
            y: bounds.min.y, // On front wall
            z: bounds.min.z
        )
        
        let doorBounds = BoundingBox(
            min: doorPosition,
            max: Point3D(
                x: doorPosition.x + doorWidth,
                y: doorPosition.y + 0.1, // Door thickness
                z: doorPosition.z + doorHeight
            )
        )
        
        let door = Opening(
            id: UUID(),
            type: .door,
            bounds: doorBounds,
            isPassable: true
        )
        openings.append(door)
        
        // Add windows based on room type and complexity
        let windowCount = windowCountForRoom(type: roomType, complexity: complexity)
        
        for i in 0..<windowCount {
            let windowWidth = Double.random(in: 1.0...2.0)
            let windowHeight = Double.random(in: 1.0...1.5)
            let windowSillHeight = Double.random(in: 0.8...1.2)
            
            // Place on different walls
            let wallChoice = i % 4
            var windowPosition: Point3D
            
            switch wallChoice {
            case 0: // Back wall
                windowPosition = Point3D(
                    x: bounds.min.x + bounds.size.x * Double.random(in: 0.2...0.8),
                    y: bounds.max.y,
                    z: bounds.min.z + windowSillHeight
                )
            case 1: // Right wall
                windowPosition = Point3D(
                    x: bounds.max.x,
                    y: bounds.min.y + bounds.size.y * Double.random(in: 0.2...0.8),
                    z: bounds.min.z + windowSillHeight
                )
            case 2: // Left wall
                windowPosition = Point3D(
                    x: bounds.min.x,
                    y: bounds.min.y + bounds.size.y * Double.random(in: 0.2...0.8),
                    z: bounds.min.z + windowSillHeight
                )
            default: // Front wall (but not near door)
                windowPosition = Point3D(
                    x: bounds.min.x + bounds.size.x * 0.1, // Far from door
                    y: bounds.min.y,
                    z: bounds.min.z + windowSillHeight
                )
            }
            
            let windowBounds = BoundingBox(
                min: windowPosition,
                max: Point3D(
                    x: windowPosition.x + windowWidth,
                    y: windowPosition.y + 0.1,
                    z: windowPosition.z + windowHeight
                )
            )
            
            let window = Opening(
                id: UUID(),
                type: .window,
                bounds: windowBounds,
                isPassable: false
            )
            openings.append(window)
        }
        
        return openings
    }
    
    // MARK: - WiFi Measurement Generation
    
    /// Generate realistic WiFi measurements for a room
    /// - Parameters:
    ///   - room: The room model
    ///   - routerLocation: Location of the WiFi router
    ///   - measurementCount: Number of measurement points
    /// - Returns: Array of WiFi measurements
    public func generateWiFiMeasurements(
        for room: RoomModel,
        routerLocation: Point3D,
        measurementCount: Int = 20
    ) -> [WiFiMeasurement] {
        
        var measurements: [WiFiMeasurement] = []
        
        for i in 0..<measurementCount {
            // Generate random measurement location within room
            let measurementLocation = Point3D(
                x: Double.random(in: room.bounds.min.x...room.bounds.max.x),
                y: Double.random(in: room.bounds.min.y...room.bounds.max.y),
                z: Double.random(in: 1.0...1.8) // Typical device height
            )
            
            // Calculate realistic signal strength based on distance and obstacles
            let distance = routerLocation.distance(to: measurementLocation)
            let baseRSSI = calculateBaseRSSI(distance: distance)
            
            // Add attenuation for walls/obstacles between points
            let obstacleAttenuation = calculateObstacleAttenuation(
                from: routerLocation,
                to: measurementLocation,
                room: room
            )
            
            // Generate measurements for different bands
            let bands = [
                BandMeasurement(
                    frequency: 2400.0,
                    rssi: baseRSSI - obstacleAttenuation + Double.random(in: -3...3), // 2.4GHz
                    snr: Double.random(in: 15...40),
                    channelWidth: 20,
                    txRate: Double.random(in: 50...150),
                    rxRate: Double.random(in: 50...150)
                ),
                BandMeasurement(
                    frequency: 5000.0,
                    rssi: baseRSSI - obstacleAttenuation - 2 + Double.random(in: -3...3), // 5GHz (slightly weaker)
                    snr: Double.random(in: 20...45),
                    channelWidth: 80,
                    txRate: Double.random(in: 100...400),
                    rxRate: Double.random(in: 100...400)
                ),
                BandMeasurement(
                    frequency: 6000.0,
                    rssi: baseRSSI - obstacleAttenuation - 4 + Double.random(in: -3...3), // 6GHz (weaker)
                    snr: Double.random(in: 25...50),
                    channelWidth: 160,
                    txRate: Double.random(in: 200...600),
                    rxRate: Double.random(in: 200...600)
                )
            ]
            
            let measurement = WiFiMeasurement(
                id: UUID(),
                location: measurementLocation,
                timestamp: Date().addingTimeInterval(-Double(i * 60)), // Spaced 1 minute apart
                bands: bands,
                deviceId: "mock_device_\(i)"
            )
            
            measurements.append(measurement)
        }
        
        return measurements
    }
    
    private func calculateBaseRSSI(distance: Double) -> Double {
        // Free space path loss at 5GHz
        let pathLoss = 20 * log10(distance) + 20 * log10(5000) + 92.45
        let txPower = 20.0 // 20dBm transmit power
        return txPower - pathLoss
    }
    
    private func calculateObstacleAttenuation(from: Point3D, to: Point3D, room: RoomModel) -> Double {
        var attenuation = 0.0
        
        // Simple line-of-sight check for walls
        for wall in room.walls {
            if lineIntersectsWall(from: from, to: to, wall: wall) {
                attenuation += wall.material.rfAttenuation(frequency: 5000.0)
            }
        }
        
        return attenuation
    }
    
    private func lineIntersectsWall(from: Point3D, to: Point3D, wall: WallElement) -> Bool {
        // Simplified 2D intersection check
        // This is a basic implementation for testing purposes
        let wallStart = wall.startPoint
        let wallEnd = wall.endPoint
        
        // Check if line segment intersects wall segment in 2D (ignoring Z)
        return linesIntersect2D(
            p1: Point2D(x: from.x, y: from.y),
            p2: Point2D(x: to.x, y: to.y),
            p3: Point2D(x: wallStart.x, y: wallStart.y),
            p4: Point2D(x: wallEnd.x, y: wallEnd.y)
        )
    }
    
    private func linesIntersect2D(p1: Point2D, p2: Point2D, p3: Point2D, p4: Point2D) -> Bool {
        let denom = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
        if abs(denom) < 1e-10 { return false } // Lines are parallel
        
        let t = ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / denom
        let u = -((p1.x - p2.x) * (p1.y - p3.y) - (p1.y - p2.y) * (p1.x - p3.x)) / denom
        
        return t >= 0 && t <= 1 && u >= 0 && u <= 1
    }
    
    // MARK: - Helper Methods
    
    private func defaultSizeForRoom(type: RoomType) -> Vector3D {
        switch type {
        case .bedroom:
            return Vector3D(x: 4.0, y: 3.5, z: 2.5)
        case .livingRoom:
            return Vector3D(x: 6.0, y: 5.0, z: 2.5)
        case .kitchen:
            return Vector3D(x: 4.5, y: 3.0, z: 2.5)
        case .office:
            return Vector3D(x: 3.5, y: 3.0, z: 2.5)
        case .diningRoom:
            return Vector3D(x: 4.0, y: 4.0, z: 2.5)
        }
    }
    
    private func furnitureSpecsForRoom(type: RoomType) -> [FurnitureSpec] {
        switch type {
        case .bedroom:
            return [
                FurnitureSpec(type: .bed, dimensions: Vector3D(x: 2.0, y: 1.5, z: 0.6), position: .wall),
                FurnitureSpec(type: .nightstand, dimensions: Vector3D(x: 0.5, y: 0.4, z: 0.6), position: .wall),
                FurnitureSpec(type: .dresser, dimensions: Vector3D(x: 1.2, y: 0.5, z: 1.0), position: .wall)
            ]
            
        case .livingRoom:
            return [
                FurnitureSpec(type: .sofa, dimensions: Vector3D(x: 2.2, y: 0.9, z: 0.8), position: .wall),
                FurnitureSpec(type: .table, dimensions: Vector3D(x: 1.2, y: 0.8, z: 0.45), position: .center),
                FurnitureSpec(type: .shelf, dimensions: Vector3D(x: 1.5, y: 0.3, z: 1.8), position: .wall),
                FurnitureSpec(type: .chair, dimensions: Vector3D(x: 0.6, y: 0.6, z: 0.9), position: .random)
            ]
            
        case .kitchen:
            return [
                FurnitureSpec(type: .counter, dimensions: Vector3D(x: 2.5, y: 0.6, z: 0.9), position: .wall),
                FurnitureSpec(type: .cabinet, dimensions: Vector3D(x: 1.0, y: 0.6, z: 2.0), position: .wall),
                FurnitureSpec(type: .table, dimensions: Vector3D(x: 1.0, y: 1.0, z: 0.75), position: .center)
            ]
            
        case .office:
            return [
                FurnitureSpec(type: .desk, dimensions: Vector3D(x: 1.5, y: 0.8, z: 0.75), position: .wall),
                FurnitureSpec(type: .chair, dimensions: Vector3D(x: 0.6, y: 0.6, z: 1.1), position: .random),
                FurnitureSpec(type: .shelf, dimensions: Vector3D(x: 1.0, y: 0.3, z: 1.5), position: .wall)
            ]
            
        case .diningRoom:
            return [
                FurnitureSpec(type: .table, dimensions: Vector3D(x: 1.8, y: 1.0, z: 0.75), position: .center),
                FurnitureSpec(type: .chair, dimensions: Vector3D(x: 0.5, y: 0.5, z: 0.9), position: .random),
                FurnitureSpec(type: .cabinet, dimensions: Vector3D(x: 1.2, y: 0.4, z: 1.2), position: .wall)
            ]
        }
    }
    
    private func defaultDimensionsForFurniture(type: FurnitureType) -> Vector3D {
        switch type {
        case .table:
            return Vector3D(x: 1.2, y: 0.8, z: 0.75)
        case .desk:
            return Vector3D(x: 1.5, y: 0.8, z: 0.75)
        case .dresser:
            return Vector3D(x: 1.2, y: 0.5, z: 1.0)
        case .shelf:
            return Vector3D(x: 1.0, y: 0.3, z: 1.8)
        case .cabinet:
            return Vector3D(x: 0.8, y: 0.4, z: 1.5)
        case .counter:
            return Vector3D(x: 2.0, y: 0.6, z: 0.9)
        case .nightstand:
            return Vector3D(x: 0.5, y: 0.4, z: 0.6)
        case .sofa:
            return Vector3D(x: 2.0, y: 0.9, z: 0.8)
        case .chair:
            return Vector3D(x: 0.6, y: 0.6, z: 0.9)
        case .bed:
            return Vector3D(x: 2.0, y: 1.5, z: 0.6)
        case .stool:
            return Vector3D(x: 0.4, y: 0.4, z: 0.6)
        }
    }
    
    private func windowCountForRoom(type: RoomType, complexity: RoomComplexity) -> Int {
        let baseCount: Int
        switch type {
        case .bedroom, .office:
            baseCount = 1
        case .livingRoom, .diningRoom:
            baseCount = 2
        case .kitchen:
            baseCount = 1
        }
        
        switch complexity {
        case .low:
            return max(0, baseCount - 1)
        case .medium:
            return baseCount
        case .high:
            return baseCount + 1
        }
    }
}

// MARK: - Supporting Types

public enum RoomType: String, CaseIterable {
    case bedroom = "bedroom"
    case livingRoom = "living_room"
    case kitchen = "kitchen"
    case office = "office"
    case diningRoom = "dining_room"
    
    public var displayName: String {
        switch self {
        case .bedroom: return "Bedroom"
        case .livingRoom: return "Living Room"
        case .kitchen: return "Kitchen"
        case .office: return "Office"
        case .diningRoom: return "Dining Room"
        }
    }
}

public enum RoomComplexity {
    case low    // Simple rectangular room
    case medium // Standard room with typical features
    case high   // Complex room with additional walls, alcoves, etc.
}

private struct FurnitureSpec {
    let type: FurnitureType
    let dimensions: Vector3D
    let position: FurniturePosition
}

private enum FurniturePosition {
    case center
    case wall
    case corner
    case random
}