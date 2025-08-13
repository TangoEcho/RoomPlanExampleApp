import Foundation
import simd
import RoomPlan

// MARK: - RF Propagation Model
/// Advanced RF propagation model for WiFi signal analysis
class RFPropagationModel {
    
    // MARK: - Constants
    struct Constants {
        // Path loss exponents for different environments
        static let freeSpacePathLossExponent: Float = 2.0
        static let indoorPathLossExponent: Float = 3.0
        static let obstructedPathLossExponent: Float = 4.0
        
        // Frequency bands
        static let frequency2_4GHz: Float = 2400.0 // MHz
        static let frequency5GHz: Float = 5000.0 // MHz
        static let frequency6GHz: Float = 6000.0 // MHz
        
        // Material attenuation (dB)
        static let wallAttenuation: Float = 5.0
        static let floorAttenuation: Float = 15.0
        static let glassAttenuation: Float = 2.0
        static let doorAttenuation: Float = 3.0
        static let concreteAttenuation: Float = 10.0
        static let woodAttenuation: Float = 4.0
        static let metalAttenuation: Float = 20.0
        
        // Signal quality thresholds (dBm)
        static let excellentSignal: Float = -30.0
        static let goodSignal: Float = -50.0
        static let fairSignal: Float = -70.0
        static let poorSignal: Float = -85.0
        static let noSignal: Float = -100.0
    }
    
    // MARK: - Enums
    enum MaterialType {
        case air
        case drywall
        case concrete
        case glass
        case wood
        case metal
        case floor
        case door
        
        var attenuationDB: Float {
            switch self {
            case .air: return 0.0
            case .drywall: return Constants.wallAttenuation
            case .concrete: return Constants.concreteAttenuation
            case .glass: return Constants.glassAttenuation
            case .wood: return Constants.woodAttenuation
            case .metal: return Constants.metalAttenuation
            case .floor: return Constants.floorAttenuation
            case .door: return Constants.doorAttenuation
            }
        }
    }
    
    enum FrequencyBand {
        case band2_4GHz
        case band5GHz
        case band6GHz
        
        var frequency: Float {
            switch self {
            case .band2_4GHz: return Constants.frequency2_4GHz
            case .band5GHz: return Constants.frequency5GHz
            case .band6GHz: return Constants.frequency6GHz
            }
        }
        
        var wavelength: Float {
            // wavelength = c / f (c = 3e8 m/s)
            return 300.0 / frequency // in meters
        }
    }
    
    // MARK: - Properties
    private var rooms: [RoomAnalyzer.IdentifiedRoom] = []
    private var walls: [Wall] = []
    private var accessPoints: [AccessPoint] = []
    private var frequencyBand: FrequencyBand = .band2_4GHz
    
    // MARK: - Structures
    struct Wall {
        let startPoint: simd_float3
        let endPoint: simd_float3
        let height: Float
        let material: MaterialType
        
        func intersects(ray: Ray) -> Bool {
            // Simple ray-plane intersection for wall
            let wallNormal = normalize(cross(endPoint - startPoint, simd_float3(0, height, 0)))
            let denominator = dot(ray.direction, wallNormal)
            
            guard abs(denominator) > 0.0001 else { return false }
            
            let t = dot(startPoint - ray.origin, wallNormal) / denominator
            guard t >= 0 else { return false }
            
            let intersectionPoint = ray.origin + t * ray.direction
            
            // Check if intersection point is within wall bounds
            return isPointOnWall(intersectionPoint)
        }
        
        private func isPointOnWall(_ point: simd_float3) -> Bool {
            // Check if point is within wall boundaries
            let minX = min(startPoint.x, endPoint.x)
            let maxX = max(startPoint.x, endPoint.x)
            let minZ = min(startPoint.z, endPoint.z)
            let maxZ = max(startPoint.z, endPoint.z)
            
            return point.x >= minX && point.x <= maxX &&
                   point.z >= minZ && point.z <= maxZ &&
                   point.y >= 0 && point.y <= height
        }
    }
    
    struct Ray {
        let origin: simd_float3
        let direction: simd_float3
    }
    
    struct AccessPoint {
        let position: simd_float3
        let transmitPower: Float // dBm
        let antennaGain: Float // dBi
        let frequency: FrequencyBand
        let name: String
    }
    
    struct PropagationPoint {
        let position: simd_float3
        let signalStrength: Float // dBm
        let pathLoss: Float // dB
        let quality: SignalQuality
        let dominantAP: AccessPoint?
    }
    
    enum SignalQuality {
        case excellent
        case good
        case fair
        case poor
        case none
        
        var color: (r: Float, g: Float, b: Float, a: Float) {
            switch self {
            case .excellent: return (0.0, 1.0, 0.0, 0.8)  // Green
            case .good: return (0.5, 1.0, 0.0, 0.7)       // Yellow-green
            case .fair: return (1.0, 1.0, 0.0, 0.6)       // Yellow
            case .poor: return (1.0, 0.5, 0.0, 0.5)       // Orange
            case .none: return (1.0, 0.0, 0.0, 0.4)       // Red
            }
        }
    }
    
    // MARK: - Initialization
    init() {
        print("🔬 RF Propagation Model initialized")
    }
    
    // MARK: - Configuration
    func configureWithRooms(_ rooms: [RoomAnalyzer.IdentifiedRoom]) {
        self.rooms = rooms
        self.walls = extractWallsFromRooms(rooms)
        print("📐 Configured with \(rooms.count) rooms and \(walls.count) walls")
    }
    
    func addAccessPoint(position: simd_float3, transmitPower: Float = 20.0, name: String = "AP") {
        let ap = AccessPoint(
            position: position,
            transmitPower: transmitPower,
            antennaGain: 2.15, // Standard dipole antenna
            frequency: frequencyBand,
            name: name
        )
        accessPoints.append(ap)
        print("📡 Added access point '\(name)' at position \(position)")
    }
    
    func setFrequencyBand(_ band: FrequencyBand) {
        self.frequencyBand = band
        print("📻 Set frequency band to \(band)")
    }
    
    // MARK: - Path Loss Calculations
    
    /// Calculate free space path loss (FSPL)
    private func calculateFreeSpacePathLoss(distance: Float, frequency: Float) -> Float {
        guard distance > 0 else { return 0 }
        // FSPL (dB) = 20 * log10(d) + 20 * log10(f) + 20 * log10(4π/c)
        // Simplified: FSPL = 20 * log10(d) + 20 * log10(f) - 147.55
        return 20.0 * log10(distance) + 20.0 * log10(frequency) - 147.55
    }
    
    /// Calculate indoor path loss using ITU-R model
    private func calculateIndoorPathLoss(distance: Float, frequency: Float, numWalls: Int, numFloors: Int) -> Float {
        let fspl = calculateFreeSpacePathLoss(distance: distance, frequency: frequency)
        
        // Add wall and floor losses
        let wallLoss = Float(numWalls) * Constants.wallAttenuation
        let floorLoss = Float(numFloors) * Constants.floorAttenuation
        
        // Add distance-dependent indoor factor
        let indoorFactor = 10.0 * log10(distance) * (Constants.indoorPathLossExponent - Constants.freeSpacePathLossExponent)
        
        return fspl + wallLoss + floorLoss + indoorFactor
    }
    
    /// Calculate path loss with obstacles
    private func calculatePathLoss(from source: simd_float3, to destination: simd_float3) -> Float {
        let distance = simd_distance(source, destination)
        let frequency = frequencyBand.frequency
        
        // Count obstacles
        let obstacles = countObstacles(from: source, to: destination)
        
        // Calculate total path loss
        let pathLoss = calculateIndoorPathLoss(
            distance: distance,
            frequency: frequency,
            numWalls: obstacles.walls,
            numFloors: obstacles.floors
        )
        
        // Add material-specific losses
        let materialLoss = obstacles.materials.reduce(0.0) { $0 + $1.attenuationDB }
        
        return pathLoss + materialLoss
    }
    
    /// Count obstacles between two points
    private func countObstacles(from source: simd_float3, to destination: simd_float3) -> (walls: Int, floors: Int, materials: [MaterialType]) {
        let ray = Ray(
            origin: source,
            direction: normalize(destination - source)
        )
        
        var wallCount = 0
        var floorCount = 0
        var materials: [MaterialType] = []
        
        for wall in walls {
            if wall.intersects(ray: ray) {
                wallCount += 1
                materials.append(wall.material)
            }
        }
        
        // Check floor crossings
        let heightDiff = abs(destination.y - source.y)
        floorCount = Int(heightDiff / 3.0) // Assume 3m floor height
        
        return (wallCount, floorCount, materials)
    }
    
    // MARK: - Signal Strength Calculation
    
    /// Calculate received signal strength at a point
    func calculateSignalStrength(at point: simd_float3, from ap: AccessPoint) -> Float {
        let pathLoss = calculatePathLoss(from: ap.position, to: point)
        let receivedPower = ap.transmitPower + ap.antennaGain - pathLoss
        return receivedPower
    }
    
    /// Calculate signal quality from strength
    private func signalQuality(from strength: Float) -> SignalQuality {
        switch strength {
        case Constants.excellentSignal...:
            return .excellent
        case Constants.goodSignal..<Constants.excellentSignal:
            return .good
        case Constants.fairSignal..<Constants.goodSignal:
            return .fair
        case Constants.poorSignal..<Constants.fairSignal:
            return .poor
        default:
            return .none
        }
    }
    
    // MARK: - Propagation Map Generation
    
    /// Generate RF propagation map for the environment
    func generatePropagationMap(resolution: Float = 0.5) -> [PropagationPoint] {
        var propagationPoints: [PropagationPoint] = []
        
        guard !accessPoints.isEmpty else {
            print("⚠️ No access points configured")
            return propagationPoints
        }
        
        // Calculate bounds
        let bounds = calculateEnvironmentBounds()
        
        // Generate grid points
        let gridPoints = generateGridPoints(bounds: bounds, resolution: resolution)
        
        print("🗺 Generating propagation map with \(gridPoints.count) points...")
        
        for point in gridPoints {
            // Calculate signal from all APs
            var maxSignal: Float = Constants.noSignal
            var dominantAP: AccessPoint?
            
            for ap in accessPoints {
                let signal = calculateSignalStrength(at: point, from: ap)
                if signal > maxSignal {
                    maxSignal = signal
                    dominantAP = ap
                }
            }
            
            let quality = signalQuality(from: maxSignal)
            let pathLoss = dominantAP != nil ? 
                calculatePathLoss(from: dominantAP!.position, to: point) : 0
            
            let propagationPoint = PropagationPoint(
                position: point,
                signalStrength: maxSignal,
                pathLoss: pathLoss,
                quality: quality,
                dominantAP: dominantAP
            )
            
            propagationPoints.append(propagationPoint)
        }
        
        print("✅ Generated \(propagationPoints.count) propagation points")
        return propagationPoints
    }
    
    /// Generate 3D propagation volume
    func generate3DPropagationVolume(resolution: Float = 1.0, heightLevels: Int = 3) -> [PropagationPoint] {
        var volumePoints: [PropagationPoint] = []
        
        let bounds = calculateEnvironmentBounds()
        let heightStep = 3.0 / Float(heightLevels) // Assume 3m ceiling
        
        for level in 0..<heightLevels {
            let height = Float(level) * heightStep + 1.0 // Start at 1m height
            let levelPoints = generatePropagationMapAtHeight(height, resolution: resolution, bounds: bounds)
            volumePoints.append(contentsOf: levelPoints)
        }
        
        print("🎯 Generated 3D volume with \(volumePoints.count) points across \(heightLevels) levels")
        return volumePoints
    }
    
    private func generatePropagationMapAtHeight(_ height: Float, resolution: Float, bounds: (min: simd_float3, max: simd_float3)) -> [PropagationPoint] {
        var points: [PropagationPoint] = []
        
        let xSteps = Int((bounds.max.x - bounds.min.x) / resolution)
        let zSteps = Int((bounds.max.z - bounds.min.z) / resolution)
        
        for x in 0...xSteps {
            for z in 0...zSteps {
                let point = simd_float3(
                    bounds.min.x + Float(x) * resolution,
                    height,
                    bounds.min.z + Float(z) * resolution
                )
                
                // Check if point is inside any room
                if isPointInsideRooms(point) {
                    var maxSignal: Float = Constants.noSignal
                    var dominantAP: AccessPoint?
                    
                    for ap in accessPoints {
                        let signal = calculateSignalStrength(at: point, from: ap)
                        if signal > maxSignal {
                            maxSignal = signal
                            dominantAP = ap
                        }
                    }
                    
                    let quality = signalQuality(from: maxSignal)
                    let pathLoss = dominantAP != nil ?
                        calculatePathLoss(from: dominantAP!.position, to: point) : 0
                    
                    points.append(PropagationPoint(
                        position: point,
                        signalStrength: maxSignal,
                        pathLoss: pathLoss,
                        quality: quality,
                        dominantAP: dominantAP
                    ))
                }
            }
        }
        
        return points
    }
    
    // MARK: - Helper Methods
    
    private func extractWallsFromRooms(_ rooms: [RoomAnalyzer.IdentifiedRoom]) -> [Wall] {
        var walls: [Wall] = []
        
        for room in rooms {
            let wallPoints = room.wallPoints
            guard wallPoints.count >= 2 else { continue }
            
            // Create walls from consecutive points
            for i in 0..<wallPoints.count {
                let startPoint = wallPoints[i]
                let endPoint = wallPoints[(i + 1) % wallPoints.count]
                
                // Determine material based on room type
                let material: MaterialType = room.type == .bathroom ? .concrete : .drywall
                
                let wall = Wall(
                    startPoint: startPoint,
                    endPoint: endPoint,
                    height: 3.0, // Standard ceiling height
                    material: material
                )
                walls.append(wall)
            }
        }
        
        return walls
    }
    
    private func calculateEnvironmentBounds() -> (min: simd_float3, max: simd_float3) {
        guard !rooms.isEmpty else {
            return (simd_float3(-10, 0, -10), simd_float3(10, 3, 10))
        }
        
        let allPoints = rooms.flatMap { $0.wallPoints }
        
        let minX = allPoints.map { $0.x }.min() ?? -10
        let maxX = allPoints.map { $0.x }.max() ?? 10
        let minZ = allPoints.map { $0.z }.min() ?? -10
        let maxZ = allPoints.map { $0.z }.max() ?? 10
        
        return (
            simd_float3(minX - 1, 0, minZ - 1),
            simd_float3(maxX + 1, 3, maxZ + 1)
        )
    }
    
    private func generateGridPoints(bounds: (min: simd_float3, max: simd_float3), resolution: Float) -> [simd_float3] {
        var points: [simd_float3] = []
        
        let xSteps = Int((bounds.max.x - bounds.min.x) / resolution)
        let zSteps = Int((bounds.max.z - bounds.min.z) / resolution)
        
        for x in 0...xSteps {
            for z in 0...zSteps {
                let point = simd_float3(
                    bounds.min.x + Float(x) * resolution,
                    1.0, // Standard measurement height
                    bounds.min.z + Float(z) * resolution
                )
                
                // Only add points inside rooms
                if isPointInsideRooms(point) {
                    points.append(point)
                }
            }
        }
        
        return points
    }
    
    private func isPointInsideRooms(_ point: simd_float3) -> Bool {
        for room in rooms {
            if isPointInsidePolygon(point, polygon: room.wallPoints) {
                return true
            }
        }
        return false
    }
    
    private func isPointInsidePolygon(_ point: simd_float3, polygon: [simd_float3]) -> Bool {
        guard polygon.count >= 3 else { return false }
        
        var inside = false
        let p1x = point.x
        let p1z = point.z
        
        for i in 0..<polygon.count {
            let p2x = polygon[i].x
            let p2z = polygon[i].z
            let p3x = polygon[(i + 1) % polygon.count].x
            let p3z = polygon[(i + 1) % polygon.count].z
            
            if ((p2z > p1z) != (p3z > p1z)) &&
               (p1x < (p3x - p2x) * (p1z - p2z) / (p3z - p2z) + p2x) {
                inside = !inside
            }
        }
        
        return inside
    }
    
    // MARK: - Optimization Methods
    
    /// Find optimal access point placements
    func findOptimalAPPlacements(targetCoverage: Float = 0.95, maxAPs: Int = 3) -> [simd_float3] {
        var optimalPositions: [simd_float3] = []
        
        let bounds = calculateEnvironmentBounds()
        let candidatePositions = generateCandidatePositions(bounds: bounds)
        
        print("🎯 Finding optimal AP placements from \(candidatePositions.count) candidates...")
        
        // Greedy algorithm: place APs to maximize coverage
        var uncoveredPoints = Set(generateGridPoints(bounds: bounds, resolution: 1.0))
        
        while optimalPositions.count < maxAPs && !uncoveredPoints.isEmpty {
            var bestPosition: simd_float3?
            var bestCoverage = 0
            
            for candidate in candidatePositions {
                // Skip if too close to existing APs
                if optimalPositions.contains(where: { simd_distance($0, candidate) < 3.0 }) {
                    continue
                }
                
                // Count coverage for this candidate
                let coverage = countCoverage(apPosition: candidate, points: Array(uncoveredPoints))
                
                if coverage > bestCoverage {
                    bestCoverage = coverage
                    bestPosition = candidate
                }
            }
            
            if let position = bestPosition {
                optimalPositions.append(position)
                
                // Remove covered points
                uncoveredPoints = uncoveredPoints.filter { point in
                    let signal = calculateSignalStrength(
                        at: point,
                        from: AccessPoint(
                            position: position,
                            transmitPower: 20.0,
                            antennaGain: 2.15,
                            frequency: frequencyBand,
                            name: "Optimal"
                        )
                    )
                    return signal < Constants.fairSignal
                }
                
                print("   Added AP at \(position), \(uncoveredPoints.count) points remaining")
            } else {
                break
            }
        }
        
        print("✅ Found \(optimalPositions.count) optimal AP positions")
        return optimalPositions
    }
    
    private func generateCandidatePositions(bounds: (min: simd_float3, max: simd_float3)) -> [simd_float3] {
        var candidates: [simd_float3] = []
        
        // Generate candidates on a coarse grid
        let spacing: Float = 2.0
        let xSteps = Int((bounds.max.x - bounds.min.x) / spacing)
        let zSteps = Int((bounds.max.z - bounds.min.z) / spacing)
        
        for x in 0...xSteps {
            for z in 0...zSteps {
                let point = simd_float3(
                    bounds.min.x + Float(x) * spacing,
                    2.5, // Ceiling mount height
                    bounds.min.z + Float(z) * spacing
                )
                
                if isPointInsideRooms(point) {
                    candidates.append(point)
                }
            }
        }
        
        return candidates
    }
    
    private func countCoverage(apPosition: simd_float3, points: [simd_float3]) -> Int {
        let ap = AccessPoint(
            position: apPosition,
            transmitPower: 20.0,
            antennaGain: 2.15,
            frequency: frequencyBand,
            name: "Test"
        )
        
        return points.filter { point in
            calculateSignalStrength(at: point, from: ap) >= Constants.fairSignal
        }.count
    }
}