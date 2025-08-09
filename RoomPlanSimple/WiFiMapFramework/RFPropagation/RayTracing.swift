import Foundation

/// 2D Ray tracing system for multipath analysis and RF propagation
public class RayTracing {
    
    // MARK: - Properties
    
    private let maxReflections: Int
    private let minSignalThreshold: Double
    private let rayResolution: Double
    private let reflectionCoefficient: Double
    
    // MARK: - Initialization
    
    public init(
        maxReflections: Int = 2,
        minSignalThreshold: Double = -100.0,
        rayResolution: Double = 0.1,
        reflectionCoefficient: Double = 0.7
    ) {
        self.maxReflections = maxReflections
        self.minSignalThreshold = minSignalThreshold
        self.rayResolution = rayResolution
        self.reflectionCoefficient = reflectionCoefficient
    }
    
    // MARK: - Public Interface
    
    /// Trace rays from transmitter to receiver through a room environment
    /// - Parameters:
    ///   - transmitter: Transmitter location and properties
    ///   - receiver: Receiver location
    ///   - room: Room model with walls and obstacles
    ///   - frequency: Operating frequency in MHz
    /// - Returns: Array of ray paths with their characteristics
    public func traceRays(
        from transmitter: RFTransmitter,
        to receiver: Point3D,
        through room: RoomModel,
        at frequency: Double
    ) -> [RayPath] {
        return traceRays(
            from: transmitter,
            to: receiver,
            through: room,
            at: frequency,
            floors: nil
        )
    }
    
    /// Enhanced ray tracing with multi-floor support
    /// - Parameters:
    ///   - transmitter: Transmitter location and properties
    ///   - receiver: Receiver location
    ///   - room: Primary room model
    ///   - frequency: Operating frequency in MHz
    ///   - floors: Optional array of floor models for multi-floor analysis
    /// - Returns: Array of ray paths including inter-floor paths
    public func traceRays(
        from transmitter: RFTransmitter,
        to receiver: Point3D,
        through room: RoomModel,
        at frequency: Double,
        floors: [FloorModel]?
    ) -> [RayPath] {
        
        var validPaths: [RayPath] = []
        
        // Direct path (Line of Sight)
        if let directPath = traceDirectPath(
            from: transmitter.location,
            to: receiver,
            room: room,
            frequency: frequency,
            transmitter: transmitter,
            floors: floors
        ) {
            validPaths.append(directPath)
        }
        
        // Reflected paths
        let reflectedPaths = traceReflectedPaths(
            from: transmitter,
            to: receiver,
            room: room,
            frequency: frequency,
            floors: floors
        )
        validPaths.append(contentsOf: reflectedPaths)
        
        // Inter-floor paths (if multiple floors available)
        if let floors = floors, floors.count > 1 {
            let interFloorPaths = traceInterFloorPaths(
                from: transmitter,
                to: receiver,
                floors: floors,
                frequency: frequency
            )
            validPaths.append(contentsOf: interFloorPaths)
        }
        
        // Sort paths by signal strength (strongest first)
        return validPaths.sorted { $0.receivedPower > $1.receivedPower }
    }
    
    /// Calculate multipath propagation for coverage analysis
    /// - Parameters:
    ///   - transmitter: RF transmitter
    ///   - points: Array of receiver points
    ///   - room: Room environment
    ///   - frequency: Operating frequency
    /// - Returns: Dictionary mapping points to their strongest signal
    public func calculateMultipathCoverage(
        transmitter: RFTransmitter,
        points: [Point3D],
        room: RoomModel,
        frequency: Double
    ) -> [Point3D: MultipathResult] {
        
        var results: [Point3D: MultipathResult] = [:]
        
        // Process points in batches for performance
        let batchSize = 100
        let batches = points.chunked(into: batchSize)
        
        DispatchQueue.concurrentPerform(iterations: batches.count) { batchIndex in
            let batch = batches[batchIndex]
            var batchResults: [Point3D: MultipathResult] = [:]
            
            for point in batch {
                let paths = traceRays(
                    from: transmitter,
                    to: point,
                    through: room,
                    at: frequency
                )
                
                let multipathResult = combineMultipathSignals(paths: paths)
                batchResults[point] = multipathResult
            }
            
            // Thread-safe result merging
            DispatchQueue.main.async {
                results.merge(batchResults) { _, new in new }
            }
        }
        
        return results
    }
    
    // MARK: - Direct Path Tracing
    
    private func traceDirectPath(
        from transmitter: Point3D,
        to receiver: Point3D,
        room: RoomModel,
        frequency: Double,
        transmitter txModel: RFTransmitter,
        floors: [FloorModel]? = nil
    ) -> RayPath? {
        
        let distance = transmitter.distance(to: receiver)
        let direction = (receiver - transmitter).normalized
        
        // Check for obstacles along the direct path
        let obstacles = findObstaclesAlongPath(
            from: transmitter,
            to: receiver,
            room: room
        )
        
        // Calculate path loss
        var totalLoss = PropagationModels.freeSpacePathLoss(
            distance: distance,
            frequency: frequency
        )
        
        // Add obstacle penetration losses
        for obstacle in obstacles {
            totalLoss += obstacle.attenuationLoss(frequency: frequency)
        }
        
        // Calculate received power
        let txPower = txModel.effectiveTransmitPower(direction: direction, frequency: frequency)
        let receivedPower = txPower - totalLoss
        
        // Check if signal is above threshold
        guard receivedPower > minSignalThreshold else { return nil }
        
        return RayPath(
            segments: [RaySegment(start: transmitter, end: receiver, type: .direct)],
            totalDistance: distance,
            totalLoss: totalLoss,
            receivedPower: receivedPower,
            reflectionCount: 0,
            obstacles: obstacles
        )
    }
    
    // MARK: - Reflected Path Tracing
    
    private func traceReflectedPaths(
        from transmitter: RFTransmitter,
        to receiver: Point3D,
        room: RoomModel,
        frequency: Double,
        floors: [FloorModel]? = nil
    ) -> [RayPath] {
        
        var reflectedPaths: [RayPath] = []
        
        // Single reflection paths
        for wall in room.walls {
            if let path = traceSingleReflection(
                from: transmitter,
                to: receiver,
                reflector: wall,
                room: room,
                frequency: frequency
            ) {
                reflectedPaths.append(path)
            }
        }
        
        // Double reflection paths (if enabled)
        if maxReflections >= 2 {
            let doubleReflectionPaths = traceDoubleReflections(
                from: transmitter,
                to: receiver,
                room: room,
                frequency: frequency
            )
            reflectedPaths.append(contentsOf: doubleReflectionPaths)
        }
        
        return reflectedPaths.filter { $0.receivedPower > minSignalThreshold }
    }
    
    private func traceSingleReflection(
        from transmitter: RFTransmitter,
        to receiver: Point3D,
        reflector: WallElement,
        room: RoomModel,
        frequency: Double
    ) -> RayPath? {
        
        // Find reflection point using mirror image method
        guard let reflectionPoint = findReflectionPoint(
            transmitter: transmitter.location,
            receiver: receiver,
            wall: reflector
        ) else { return nil }
        
        // Validate reflection point is on the wall
        guard isPointOnWallSegment(reflectionPoint, wall: reflector) else { return nil }
        
        // Create ray segments
        let segment1 = RaySegment(
            start: transmitter.location,
            end: reflectionPoint,
            type: .incident
        )
        let segment2 = RaySegment(
            start: reflectionPoint,
            end: receiver,
            type: .reflected
        )
        
        let totalDistance = segment1.length + segment2.length
        
        // Calculate path loss for each segment
        var totalLoss = 0.0
        
        // First segment
        let obstacles1 = findObstaclesAlongPath(
            from: transmitter.location,
            to: reflectionPoint,
            room: room,
            excluding: reflector
        )
        totalLoss += PropagationModels.freeSpacePathLoss(
            distance: segment1.length,
            frequency: frequency
        )
        totalLoss += obstacles1.reduce(0.0) { $0 + $1.attenuationLoss(frequency: frequency) }
        
        // Reflection loss
        totalLoss += calculateReflectionLoss(
            wall: reflector,
            frequency: frequency,
            incidenceAngle: calculateIncidenceAngle(segment1, segment2)
        )
        
        // Second segment
        let obstacles2 = findObstaclesAlongPath(
            from: reflectionPoint,
            to: receiver,
            room: room,
            excluding: reflector
        )
        totalLoss += PropagationModels.freeSpacePathLoss(
            distance: segment2.length,
            frequency: frequency
        )
        totalLoss += obstacles2.reduce(0.0) { $0 + $1.attenuationLoss(frequency: frequency) }
        
        // Calculate received power
        let direction = (reflectionPoint - transmitter.location).normalized
        let txPower = transmitter.effectiveTransmitPower(direction: direction, frequency: frequency)
        let receivedPower = txPower - totalLoss
        
        return RayPath(
            segments: [segment1, segment2],
            totalDistance: totalDistance,
            totalLoss: totalLoss,
            receivedPower: receivedPower,
            reflectionCount: 1,
            obstacles: obstacles1 + obstacles2
        )
    }
    
    private func traceDoubleReflections(
        from transmitter: RFTransmitter,
        to receiver: Point3D,
        room: RoomModel,
        frequency: Double
    ) -> [RayPath] {
        
        var doubleReflectionPaths: [RayPath] = []
        
        // Try combinations of two different walls
        for (i, wall1) in room.walls.enumerated() {
            for (j, wall2) in room.walls.enumerated() {
                guard i != j else { continue } // Different walls
                
                if let path = traceDoubleReflection(
                    from: transmitter,
                    to: receiver,
                    reflector1: wall1,
                    reflector2: wall2,
                    room: room,
                    frequency: frequency
                ) {
                    doubleReflectionPaths.append(path)
                }
            }
        }
        
        return doubleReflectionPaths
    }
    
    private func traceDoubleReflection(
        from transmitter: RFTransmitter,
        to receiver: Point3D,
        reflector1: WallElement,
        reflector2: WallElement,
        room: RoomModel,
        frequency: Double
    ) -> RayPath? {
        
        // This is a simplified implementation
        // A full implementation would use the method of images for both reflections
        
        // Find first reflection point
        guard let reflection1 = findReflectionPoint(
            transmitter: transmitter.location,
            receiver: receiver,
            wall: reflector1
        ) else { return nil }
        
        // Find second reflection point
        guard let reflection2 = findReflectionPoint(
            transmitter: reflection1,
            receiver: receiver,
            wall: reflector2
        ) else { return nil }
        
        // Validate both reflection points
        guard isPointOnWallSegment(reflection1, wall: reflector1),
              isPointOnWallSegment(reflection2, wall: reflector2) else { return nil }
        
        // Create segments
        let segments = [
            RaySegment(start: transmitter.location, end: reflection1, type: .incident),
            RaySegment(start: reflection1, end: reflection2, type: .reflected),
            RaySegment(start: reflection2, end: receiver, type: .reflected)
        ]
        
        let totalDistance = segments.reduce(0.0) { $0 + $1.length }
        
        // Calculate total path loss (simplified)
        var totalLoss = PropagationModels.freeSpacePathLoss(
            distance: totalDistance,
            frequency: frequency
        )
        
        // Add reflection losses
        totalLoss += 2 * calculateReflectionLoss(wall: reflector1, frequency: frequency, incidenceAngle: 0.0)
        
        // Calculate received power
        let direction = (reflection1 - transmitter.location).normalized
        let txPower = transmitter.effectiveTransmitPower(direction: direction, frequency: frequency)
        let receivedPower = txPower - totalLoss
        
        guard receivedPower > minSignalThreshold else { return nil }
        
        return RayPath(
            segments: segments,
            totalDistance: totalDistance,
            totalLoss: totalLoss,
            receivedPower: receivedPower,
            reflectionCount: 2,
            obstacles: []
        )
    }
    
    // MARK: - Inter-Floor Path Tracing
    
    /// Trace inter-floor signal paths for multi-floor scenarios
    /// - Parameters:
    ///   - transmitter: RF transmitter
    ///   - receiver: Receiver location
    ///   - floors: Array of floor models
    ///   - frequency: Operating frequency
    /// - Returns: Array of inter-floor ray paths
    private func traceInterFloorPaths(
        from transmitter: RFTransmitter,
        to receiver: Point3D,
        floors: [FloorModel],
        frequency: Double
    ) -> [RayPath] {
        
        var interFloorPaths: [RayPath] = []
        
        // Find transmitter and receiver floors
        guard let txFloor = findFloorContaining(point: transmitter.location, in: floors),
              let rxFloor = findFloorContaining(point: receiver, in: floors),
              txFloor.level != rxFloor.level else {
            return interFloorPaths // Same floor or floors not found
        }
        
        // Calculate floor separation
        let floorSeparation = abs(rxFloor.level - txFloor.level)
        
        // Direct vertical path (through floors)
        if let verticalPath = traceVerticalPath(
            from: transmitter,
            to: receiver,
            txFloor: txFloor,
            rxFloor: rxFloor,
            frequency: frequency,
            floorSeparation: floorSeparation
        ) {
            interFloorPaths.append(verticalPath)
        }
        
        // Stairwell/opening-based paths
        let openingPaths = traceOpeningBasedPaths(
            from: transmitter,
            to: receiver,
            floors: floors,
            frequency: frequency
        )
        interFloorPaths.append(contentsOf: openingPaths)
        
        return interFloorPaths.filter { $0.receivedPower > minSignalThreshold }
    }
    
    private func traceVerticalPath(
        from transmitter: RFTransmitter,
        to receiver: Point3D,
        txFloor: FloorModel,
        rxFloor: FloorModel,
        frequency: Double,
        floorSeparation: Int
    ) -> RayPath? {
        
        let horizontalDistance = sqrt(
            pow(receiver.x - transmitter.location.x, 2) +
            pow(receiver.y - transmitter.location.y, 2)
        )
        let verticalDistance = abs(receiver.z - transmitter.location.z)
        let totalDistance = transmitter.location.distance(to: receiver)
        
        // Use multi-floor propagation model
        let multiFloorModel = PropagationModels.MultiFloorModel(environment: .residential)
        let pathLoss = multiFloorModel.pathLoss(
            distance3D: totalDistance,
            horizontalDistance: horizontalDistance,
            verticalDistance: verticalDistance,
            frequency: frequency,
            floorsSeparated: floorSeparation
        )
        
        // Calculate received power
        let direction = (receiver - transmitter.location).normalized
        let txPower = transmitter.effectiveTransmitPower(direction: direction, frequency: frequency)
        let receivedPower = txPower - pathLoss
        
        guard receivedPower > minSignalThreshold else { return nil }
        
        return RayPath(
            segments: [RaySegment(
                start: transmitter.location,
                end: receiver,
                type: .direct
            )],
            totalDistance: totalDistance,
            totalLoss: pathLoss,
            receivedPower: receivedPower,
            reflectionCount: 0,
            obstacles: []
        )
    }
    
    private func traceOpeningBasedPaths(
        from transmitter: RFTransmitter,
        to receiver: Point3D,
        floors: [FloorModel],
        frequency: Double
    ) -> [RayPath] {
        
        var openingPaths: [RayPath] = []
        
        // Find stairwells and elevator shafts that connect floors
        let verticalOpenings = floors.flatMap { floor in
            floor.verticalOpenings.filter { opening in
                opening.type == .stairwell || opening.type == .elevator
            }
        }
        
        // Trace paths through each vertical opening
        for opening in verticalOpenings {
            if let path = tracePathThroughOpening(
                from: transmitter,
                to: receiver,
                through: opening,
                frequency: frequency
            ) {
                openingPaths.append(path)
            }
        }
        
        return openingPaths
    }
    
    private func tracePathThroughOpening(
        from transmitter: RFTransmitter,
        to receiver: Point3D,
        through opening: VerticalOpening,
        frequency: Double
    ) -> RayPath? {
        
        // Simplified opening-based path calculation
        // In a full implementation, this would use more sophisticated geometry
        
        let openingCenter = opening.bounds.center
        
        // Path: transmitter -> opening -> receiver
        let segment1 = RaySegment(
            start: transmitter.location,
            end: openingCenter,
            type: .direct
        )
        let segment2 = RaySegment(
            start: openingCenter,
            end: receiver,
            type: .direct
        )
        
        let totalDistance = segment1.length + segment2.length
        
        // Calculate path loss with opening bonus (less attenuation)
        let baseLoss = PropagationModels.freeSpacePathLoss(
            distance: totalDistance,
            frequency: frequency
        )
        
        // Opening provides less attenuation than solid floors
        let openingBonus = opening.type == .stairwell ? -5.0 : -8.0 // dB
        let totalLoss = baseLoss + openingBonus
        
        // Calculate received power
        let direction = (openingCenter - transmitter.location).normalized
        let txPower = transmitter.effectiveTransmitPower(direction: direction, frequency: frequency)
        let receivedPower = txPower - totalLoss
        
        guard receivedPower > minSignalThreshold else { return nil }
        
        return RayPath(
            segments: [segment1, segment2],
            totalDistance: totalDistance,
            totalLoss: totalLoss,
            receivedPower: receivedPower,
            reflectionCount: 0,
            obstacles: []
        )
    }
    
    private func findFloorContaining(point: Point3D, in floors: [FloorModel]) -> FloorModel? {
        return floors.first { floor in
            floor.bounds.contains(point)
        }
    }
    
    // MARK: - Geometric Calculations
    
    private func findReflectionPoint(
        transmitter: Point3D,
        receiver: Point3D,
        wall: WallElement
    ) -> Point3D? {
        
        // Use mirror image method
        let mirrorImage = mirrorPointAcrossWall(transmitter, wall: wall)
        
        // Find intersection of line from mirror image to receiver with the wall
        return lineWallIntersection(
            from: mirrorImage,
            to: receiver,
            wall: wall
        )
    }
    
    private func mirrorPointAcrossWall(_ point: Point3D, wall: WallElement) -> Point3D {
        // Get wall direction and normal
        let wallDirection = (wall.endPoint - wall.startPoint).normalized
        let wallNormal = Vector3D(x: -wallDirection.y, y: wallDirection.x, z: 0)
        
        // Project point onto wall to find closest point
        let toPoint = point - wall.startPoint
        let projectionLength = toPoint.dot(wallDirection)
        let projectionPoint = wall.startPoint + wallDirection.scaled(by: projectionLength)
        
        // Calculate mirror image
        let toWall = projectionPoint - point
        let mirrorPoint = point + toWall.scaled(by: 2.0)
        
        return mirrorPoint
    }
    
    private func lineWallIntersection(
        from start: Point3D,
        to end: Point3D,
        wall: WallElement
    ) -> Point3D? {
        
        // 2D line intersection calculation
        let x1 = start.x, y1 = start.y
        let x2 = end.x, y2 = end.y
        let x3 = wall.startPoint.x, y3 = wall.startPoint.y
        let x4 = wall.endPoint.x, y4 = wall.endPoint.y
        
        let denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        guard abs(denom) > 1e-10 else { return nil } // Lines are parallel
        
        let t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denom
        let u = -((x1 - x2) * (y1 - y3) - (y1 - y2) * (x1 - x3)) / denom
        
        // Check if intersection is within both line segments
        guard t >= 0 && t <= 1 && u >= 0 && u <= 1 else { return nil }
        
        let intersectionX = x1 + t * (x2 - x1)
        let intersectionY = y1 + t * (y2 - y1)
        
        // Assume same Z level for 2D analysis
        let intersectionZ = start.z + t * (end.z - start.z)
        
        return Point3D(x: intersectionX, y: intersectionY, z: intersectionZ)
    }
    
    private func isPointOnWallSegment(_ point: Point3D, wall: WallElement) -> Bool {
        let wallLength = wall.startPoint.distance(to: wall.endPoint)
        let distToStart = point.distance(to: wall.startPoint)
        let distToEnd = point.distance(to: wall.endPoint)
        
        // Point is on wall if distances sum to wall length (within tolerance)
        let tolerance = 0.01
        return abs(distToStart + distToEnd - wallLength) < tolerance
    }
    
    private func calculateIncidenceAngle(_ incident: RaySegment, _ reflected: RaySegment) -> Double {
        let incidentDir = (incident.end - incident.start).normalized
        let reflectedDir = (reflected.end - reflected.start).normalized
        
        return incidentDir.angleFrom(reflectedDir) / 2.0 // Half the angle between rays
    }
    
    // MARK: - Obstacle Detection
    
    private func findObstaclesAlongPath(
        from start: Point3D,
        to end: Point3D,
        room: RoomModel,
        excluding excludedWall: WallElement? = nil
    ) -> [RayObstacle] {
        
        var obstacles: [RayObstacle] = []
        
        // Check wall intersections
        for wall in room.walls {
            if let excludedWall = excludedWall, wall.id == excludedWall.id {
                continue
            }
            
            if lineIntersectsWall(from: start, to: end, wall: wall) {
                obstacles.append(.wall(wall))
            }
        }
        
        // Check furniture intersections
        for furniture in room.furniture {
            if lineIntersectsBounds(from: start, to: end, bounds: furniture.bounds) {
                obstacles.append(.furniture(furniture))
            }
        }
        
        return obstacles
    }
    
    private func lineIntersectsWall(from start: Point3D, to end: Point3D, wall: WallElement) -> Bool {
        return lineWallIntersection(from: start, to: end, wall: wall) != nil
    }
    
    private func lineIntersectsBounds(from start: Point3D, to end: Point3D, bounds: BoundingBox) -> Bool {
        // Simplified ray-box intersection test
        // A full implementation would use proper ray-AABB intersection
        
        let rayDir = (end - start).normalized
        let rayLength = start.distance(to: end)
        
        // Check if ray passes through bounding box
        let tMin = (bounds.min - start)
        let tMax = (bounds.max - start)
        
        // This is a simplified check - a proper implementation would handle all axes
        return bounds.intersects(BoundingBox(min: start, max: end))
    }
    
    // MARK: - Signal Combination
    
    private func combineMultipathSignals(paths: [RayPath]) -> MultipathResult {
        guard !paths.isEmpty else {
            return MultipathResult(
                totalSignalStrength: minSignalThreshold,
                dominantPath: nil,
                pathCount: 0,
                fadingMargin: 0.0
            )
        }
        
        // Convert power values to linear scale for combination
        let linearPowers = paths.map { pow(10, $0.receivedPower / 10.0) }
        let totalLinearPower = linearPowers.reduce(0, +)
        
        // Convert back to dB
        let totalSignalStrength = 10 * log10(totalLinearPower)
        
        // Find dominant path (strongest)
        let dominantPath = paths.max(by: { $0.receivedPower < $1.receivedPower })
        
        // Calculate fading margin (difference between total and dominant)
        let fadingMargin = totalSignalStrength - (dominantPath?.receivedPower ?? totalSignalStrength)
        
        return MultipathResult(
            totalSignalStrength: totalSignalStrength,
            dominantPath: dominantPath,
            pathCount: paths.count,
            fadingMargin: fadingMargin
        )
    }
    
    private func calculateReflectionLoss(
        wall: WallElement,
        frequency: Double,
        incidenceAngle: Double
    ) -> Double {
        // Simplified reflection loss model
        // A full implementation would use Fresnel equations
        
        let baseLoss = 3.0 // dB for typical wall reflection
        let materialFactor = wall.material.reflectionLoss(frequency: frequency)
        let angleFactor = 1.0 + abs(sin(incidenceAngle)) * 0.5
        
        return baseLoss + materialFactor * angleFactor * reflectionCoefficient
    }
}

// MARK: - Supporting Types

/// Ray path through the environment
public struct RayPath {
    public let segments: [RaySegment]
    public let totalDistance: Double
    public let totalLoss: Double
    public let receivedPower: Double
    public let reflectionCount: Int
    public let obstacles: [RayObstacle]
    
    public init(
        segments: [RaySegment],
        totalDistance: Double,
        totalLoss: Double,
        receivedPower: Double,
        reflectionCount: Int,
        obstacles: [RayObstacle]
    ) {
        self.segments = segments
        self.totalDistance = totalDistance
        self.totalLoss = totalLoss
        self.receivedPower = receivedPower
        self.reflectionCount = reflectionCount
        self.obstacles = obstacles
    }
    
    /// Path type classification
    public var pathType: PathType {
        switch reflectionCount {
        case 0: return .direct
        case 1: return .singleReflection
        case 2: return .doubleReflection
        default: return .multipleReflection
        }
    }
    
    /// Calculate path delay in nanoseconds
    public var propagationDelay: Double {
        let speedOfLight = 3e8 // m/s
        return totalDistance / speedOfLight * 1e9 // Convert to ns
    }
}

/// Individual ray segment
public struct RaySegment {
    public let start: Point3D
    public let end: Point3D
    public let type: SegmentType
    
    public init(start: Point3D, end: Point3D, type: SegmentType) {
        self.start = start
        self.end = end
        self.type = type
    }
    
    public var length: Double {
        return start.distance(to: end)
    }
    
    public var direction: Vector3D {
        return (end - start).normalized
    }
    
    public enum SegmentType {
        case direct
        case incident
        case reflected
        case diffracted
    }
}

/// Path classification
public enum PathType {
    case direct
    case singleReflection
    case doubleReflection
    case multipleReflection
    case diffracted
}

/// Obstacles encountered by rays
public enum RayObstacle {
    case wall(WallElement)
    case furniture(FurnitureItem)
    case opening(Opening)
    
    public func attenuationLoss(frequency: Double) -> Double {
        switch self {
        case .wall(let wall):
            return PropagationModels.WallPenetrationModel.penetrationLoss(
                material: wall.material,
                thickness: wall.thickness,
                frequency: frequency
            )
        case .furniture(let furniture):
            // Simplified furniture attenuation
            switch furniture.type {
            case .cabinet, .dresser:
                return 5.0 // dB
            case .shelf:
                return 2.0 // dB
            default:
                return 1.0 // dB
            }
        case .opening:
            return 0.0 // No attenuation for openings
        }
    }
}

/// Multipath analysis result
public struct MultipathResult {
    public let totalSignalStrength: Double
    public let dominantPath: RayPath?
    public let pathCount: Int
    public let fadingMargin: Double
    
    public init(
        totalSignalStrength: Double,
        dominantPath: RayPath?,
        pathCount: Int,
        fadingMargin: Double
    ) {
        self.totalSignalStrength = totalSignalStrength
        self.dominantPath = dominantPath
        self.pathCount = pathCount
        self.fadingMargin = fadingMargin
    }
    
    /// Signal quality based on multipath characteristics
    public var signalQuality: SignalQuality {
        return SignalQuality.fromRSSI(totalSignalStrength)
    }
    
    /// Whether multipath causes significant fading
    public var hasSignificantFading: Bool {
        return fadingMargin > 6.0 // More than 6dB difference indicates fading issues
    }
}

/// RF Transmitter model
public struct RFTransmitter {
    public let location: Point3D
    public let power: [FrequencyBand: Double] // dBm
    public let antennaGain: [FrequencyBand: Double] // dBi
    public let antennaPattern: AntennaPattern
    
    public init(
        location: Point3D,
        power: [FrequencyBand: Double],
        antennaGain: [FrequencyBand: Double],
        antennaPattern: AntennaPattern = .omnidirectional
    ) {
        self.location = location
        self.power = power
        self.antennaGain = antennaGain
        self.antennaPattern = antennaPattern
    }
    
    /// Calculate effective transmit power in a given direction
    public func effectiveTransmitPower(direction: Vector3D, frequency: Double) -> Double {
        let band = FrequencyBand.fromFrequency(frequency)
        let basePower = power[band] ?? 20.0
        let gain = antennaGain[band] ?? 0.0
        let patternGain = antennaPattern.gain(in: direction)
        
        return basePower + gain + patternGain
    }
}

/// Antenna radiation patterns
public enum AntennaPattern {
    case omnidirectional
    case directional(azimuth: Double, elevation: Double, beamwidth: Double)
    case sector(azimuth: Double, beamwidth: Double)
    
    /// Calculate antenna gain in a specific direction
    public func gain(in direction: Vector3D) -> Double {
        switch self {
        case .omnidirectional:
            return 0.0
            
        case .directional(let azimuth, let elevation, let beamwidth):
            let targetDirection = Vector3D(
                x: cos(azimuth) * cos(elevation),
                y: sin(azimuth) * cos(elevation),
                z: sin(elevation)
            )
            let angle = direction.angleFrom(targetDirection)
            return max(-20.0, 10 * log10(cos(angle / beamwidth)))
            
        case .sector(let azimuth, let beamwidth):
            let targetDirection = Vector3D(x: cos(azimuth), y: sin(azimuth), z: 0)
            let angle = direction.angleFrom(targetDirection)
            return angle <= beamwidth / 2 ? 0.0 : -20.0
        }
    }
}

// MARK: - Extensions

extension WallMaterial {
    /// Reflection loss for this material
    func reflectionLoss(frequency: Double) -> Double {
        switch self {
        case .drywall: return 2.0
        case .concrete: return 1.0
        case .brick: return 1.5
        case .wood: return 2.5
        case .glass: return 0.5
        case .metal: return 0.1
        }
    }
}

/// Multi-floor building model for inter-floor ray tracing
public struct FloorModel {
    public let level: Int
    public let bounds: BoundingBox
    public let rooms: [RoomModel]
    public let verticalOpenings: [VerticalOpening]
    
    public init(
        level: Int,
        bounds: BoundingBox,
        rooms: [RoomModel],
        verticalOpenings: [VerticalOpening] = []
    ) {
        self.level = level
        self.bounds = bounds
        self.rooms = rooms
        self.verticalOpenings = verticalOpenings
    }
}

/// Vertical openings that connect floors (stairwells, elevators, etc.)
public struct VerticalOpening {
    public let id: UUID
    public let type: OpeningType
    public let bounds: BoundingBox
    public let floorLevels: [Int] // Floors this opening connects
    
    public init(
        id: UUID = UUID(),
        type: OpeningType,
        bounds: BoundingBox,
        floorLevels: [Int]
    ) {
        self.id = id
        self.type = type
        self.bounds = bounds
        self.floorLevels = floorLevels
    }
    
    public enum OpeningType {
        case stairwell
        case elevator
        case atrium
        case ductwork
    }
}

extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}