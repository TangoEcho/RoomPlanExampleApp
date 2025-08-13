import Foundation
import simd

// MARK: - RF Prediction Results

/// Signal prediction result for a specific location
public struct SignalPrediction: Codable {
    /// Location of the prediction
    public let location: Point3D
    
    /// Predicted RSSI values per frequency band
    public let predictedRSSI: [FrequencyBand: RSSIPrediction]
    
    /// Path loss components per frequency band
    public let pathLoss: [FrequencyBand: Double]
    
    /// Obstacles affecting signal propagation
    public let obstacles: [Obstacle]
    
    /// Confidence score (0-1) for this prediction
    public let confidence: Double
    
    /// Time taken to calculate this prediction (seconds)
    public let calculationTime: TimeInterval
    
    public init(
        location: Point3D,
        predictedRSSI: [FrequencyBand: RSSIPrediction],
        pathLoss: [FrequencyBand: Double],
        obstacles: [Obstacle],
        confidence: Double,
        calculationTime: TimeInterval
    ) {
        self.location = location
        self.predictedRSSI = predictedRSSI
        self.pathLoss = pathLoss
        self.obstacles = obstacles
        self.confidence = confidence
        self.calculationTime = calculationTime
    }
    
    /// Get the best predicted RSSI across all bands
    public var bestRSSI: Float {
        return predictedRSSI.values.map(\.rssi).max() ?? -100.0
    }
    
    /// Get signal quality based on best RSSI
    public var signalQuality: SignalQuality {
        return SignalQuality.fromRSSI(bestRSSI)
    }
    
    /// Check if this location has usable signal
    public var isUsable: Bool {
        return bestRSSI > -80.0 && confidence > 0.3
    }
}

/// RSSI prediction with additional metrics
public struct RSSIPrediction: Codable {
    /// Predicted RSSI value in dBm
    public let rssi: Float
    
    /// Estimated Signal-to-Noise Ratio in dB
    public let snr: Float
    
    /// Confidence score for this specific prediction
    public let confidence: Double
    
    public init(rssi: Float, snr: Float, confidence: Double) {
        self.rssi = rssi
        self.snr = snr
        self.confidence = confidence
    }
    
    /// Estimated throughput based on RSSI and SNR
    public var estimatedThroughput: Double {
        // Simplified throughput estimation based on signal quality
        switch rssi {
        case -50...:
            return 1000.0 // Gbps range
        case -60..<(-50):
            return 500.0
        case -70..<(-60):
            return 200.0
        case -80..<(-70):
            return 50.0
        default:
            return 10.0
        }
    }
}

/// Combined signal prediction from multiple routers
public struct CombinedSignalPrediction: Codable {
    /// Individual predictions from each router
    public let routerPredictions: [UUID: SignalPrediction]
    
    /// Combined/best RSSI values per band
    public let combinedRSSI: [FrequencyBand: Float]
    
    /// Overall signal quality at this location
    public let overallQuality: SignalQuality
    
    /// Primary serving router (strongest signal)
    public let primaryRouter: UUID
    
    public init(
        routerPredictions: [UUID: SignalPrediction],
        combinedRSSI: [FrequencyBand: Float],
        overallQuality: SignalQuality,
        primaryRouter: UUID
    ) {
        self.routerPredictions = routerPredictions
        self.combinedRSSI = combinedRSSI
        self.overallQuality = overallQuality
        self.primaryRouter = primaryRouter
    }
    
    /// Get the strongest signal across all routers and bands
    public var peakSignalStrength: Float {
        return combinedRSSI.values.max() ?? -100.0
    }
    
    /// Check if location has redundant coverage (multiple routers)
    public var hasRedundantCoverage: Bool {
        let usableRouters = routerPredictions.values.filter { $0.bestRSSI > -75.0 }
        return usableRouters.count > 1
    }
}

// MARK: - Coverage Map

/// Complete coverage map for an area
public struct CoverageMap: Codable {
    /// Spatial bounds of the coverage map
    public let bounds: BoundingBox
    
    /// Grid resolution in meters
    public let resolution: Double
    
    /// Coverage data at grid points
    public let coverageData: [Point3D: CombinedSignalPrediction]
    
    /// Router configurations used for this map
    public let routers: [RouterConfiguration]
    
    /// Time taken to generate this map
    public let generationTime: TimeInterval
    
    public init(
        bounds: BoundingBox,
        resolution: Double,
        coverageData: [Point3D: CombinedSignalPrediction],
        routers: [RouterConfiguration],
        generationTime: TimeInterval
    ) {
        self.bounds = bounds
        self.resolution = resolution
        self.coverageData = coverageData
        self.routers = routers
        self.generationTime = generationTime
    }
    
    /// Get coverage statistics for this map
    public var statistics: CoverageStatistics {
        let totalPoints = coverageData.count
        let excellentPoints = coverageData.values.filter { $0.overallQuality == .excellent }.count
        let goodPoints = coverageData.values.filter { $0.overallQuality == .good }.count
        let fairPoints = coverageData.values.filter { $0.overallQuality == .fair }.count
        let poorPoints = coverageData.values.filter { $0.overallQuality == .poor }.count
        let unusablePoints = coverageData.values.filter { $0.overallQuality == .unusable }.count
        
        return CoverageStatistics(
            totalPoints: totalPoints,
            excellentCoverage: Double(excellentPoints) / Double(totalPoints),
            goodCoverage: Double(goodPoints) / Double(totalPoints),
            fairCoverage: Double(fairPoints) / Double(totalPoints),
            poorCoverage: Double(poorPoints) / Double(totalPoints),
            unusableCoverage: Double(unusablePoints) / Double(totalPoints),
            averageSignalStrength: coverageData.values.map(\.peakSignalStrength).reduce(0, +) / Float(totalPoints),
            redundantCoveragePercentage: Double(coverageData.values.filter(\.hasRedundantCoverage).count) / Double(totalPoints)
        )
    }
    
    /// Find dead zones (areas with poor or no coverage)
    public var deadZones: [DeadZone] {
        var zones: [DeadZone] = []
        let poorPoints = coverageData.filter { $0.value.overallQuality == .poor || $0.value.overallQuality == .unusable }
        
        // Group nearby poor coverage points into zones
        // This is a simplified implementation - production code would use clustering
        for (point, prediction) in poorPoints {
            let zone = DeadZone(
                center: point,
                radius: Float(resolution * 2), // Estimate zone radius
                signalQuality: prediction.overallQuality,
                affectedArea: Float(resolution * resolution) // Estimate affected area
            )
            zones.append(zone)
        }
        
        return zones
    }
}

/// Coverage statistics summary
public struct CoverageStatistics: Codable {
    public let totalPoints: Int
    public let excellentCoverage: Double    // Percentage (0-1)
    public let goodCoverage: Double
    public let fairCoverage: Double
    public let poorCoverage: Double
    public let unusableCoverage: Double
    public let averageSignalStrength: Float
    public let redundantCoveragePercentage: Double
    
    /// Overall coverage quality score (0-1)
    public var overallQualityScore: Double {
        return excellentCoverage * 1.0 + goodCoverage * 0.8 + fairCoverage * 0.6 + poorCoverage * 0.3
    }
    
    /// Percentage of area with usable signal
    public var usableCoveragePercentage: Double {
        return excellentCoverage + goodCoverage + fairCoverage
    }
}

/// Represents an area with poor WiFi coverage
public struct DeadZone: Codable, Identifiable {
    public let id = UUID()
    public let center: Point3D
    public let radius: Float
    public let signalQuality: SignalQuality
    public let affectedArea: Float // Square meters
    
    public init(center: Point3D, radius: Float, signalQuality: SignalQuality, affectedArea: Float) {
        self.center = center
        self.radius = radius
        self.signalQuality = signalQuality
        self.affectedArea = affectedArea
    }
}

// MARK: - Router Configuration

/// Router configuration with position and specifications
public struct RouterConfiguration: Codable, Identifiable {
    public let id: UUID
    public let position: Point3D
    public let deviceSpec: DeviceSpec
    public let orientation: Float // Radians, for directional antennas
    public let elevation: Float   // Height above floor in meters
    
    public init(
        id: UUID,
        position: Point3D,
        deviceSpec: DeviceSpec,
        orientation: Float = 0.0,
        elevation: Float = 1.5 // Default table height
    ) {
        self.id = id
        self.position = position
        self.deviceSpec = deviceSpec
        self.orientation = orientation
        self.elevation = elevation
    }
    
    /// Get effective position including elevation
    public var effectivePosition: Point3D {
        return simd_float3(position.x, position.y + elevation, position.z)
    }
    
    /// Check if router supports a specific frequency band
    public func supports(band: FrequencyBand) -> Bool {
        return deviceSpec.supportedStandards.flatMap { $0.supportedBands }.contains(band)
    }
}

// MARK: - Path Loss Analysis

/// Detailed path loss calculation result
public struct PathLossResult {
    /// Total path loss in dB
    public let totalPathLoss: Double
    
    /// Confidence in this calculation (0-1)
    public let confidence: Double
    
    /// Breakdown of path loss components
    public let components: [String: Double]
    
    public init(totalPathLoss: Double, confidence: Double, components: [String: Double]) {
        self.totalPathLoss = totalPathLoss
        self.confidence = confidence
        self.components = components
    }
    
    /// Get the dominant path loss component
    public var dominantComponent: (name: String, loss: Double)? {
        return components.max { $0.value < $1.value }.map { (name: $0.key, loss: $0.value) }
    }
}

/// Wall intersection information for path loss calculations
public struct WallIntersection {
    /// The wall that was intersected
    public let wall: WallElement
    
    /// Point where signal path intersects the wall
    public let intersectionPoint: Point3D
    
    /// Angle of incidence in radians (0 = perpendicular)
    public let incidenceAngle: Double
    
    public init(wall: WallElement, intersectionPoint: Point3D, incidenceAngle: Double) {
        self.wall = wall
        self.intersectionPoint = intersectionPoint
        self.incidenceAngle = incidenceAngle
    }
    
    /// Get penetration loss for this intersection
    public func penetrationLoss(frequency: Double) -> Double {
        return PropagationModels.WallPenetrationModel.penetrationLoss(
            material: wall.material,
            thickness: Double(wall.thickness),
            frequency: frequency,
            incidenceAngle: incidenceAngle
        )
    }
}

// MARK: - Performance Optimization Structures

/// Spatial index for efficient geometric queries
public class RTreeIndex {
    private var nodes: [IndexNode] = []
    
    public init() {}
    
    /// Add a wall to the spatial index
    public func addWall(_ wall: WallElement) {
        let bounds = BoundingBox(min: wall.startPoint, max: wall.endPoint)
        nodes.append(IndexNode(bounds: bounds, wall: wall))
    }
    
    /// Find walls that might intersect with a line segment
    public func findCandidateWalls(from start: Point3D, to end: Point3D) -> [WallElement] {
        let queryBounds = BoundingBox(min: start, max: end)
        return nodes.filter { $0.bounds.intersects(queryBounds) }.map(\.wall)
    }
    
    private struct IndexNode {
        let bounds: BoundingBox
        let wall: WallElement
    }
}

// MARK: - Calibration Support

/// Calibration data point comparing prediction vs measurement
public struct CalibrationPoint: Codable {
    /// Location of the measurement
    public let location: Point3D
    
    /// Predicted signal strength
    public let prediction: SignalPrediction
    
    /// Actual measured values
    public let measurement: WiFiMeasurement
    
    /// Timestamp of calibration
    public let timestamp: Date
    
    public init(
        location: Point3D,
        prediction: SignalPrediction,
        measurement: WiFiMeasurement,
        timestamp: Date = Date()
    ) {
        self.location = location
        self.prediction = prediction
        self.measurement = measurement
        self.timestamp = timestamp
    }
    
    /// Calculate prediction error for each band
    public var predictionErrors: [FrequencyBand: Double] {
        var errors: [FrequencyBand: Double] = [:]
        
        for band in FrequencyBand.allCases {
            if let predictedRSSI = prediction.predictedRSSI[band]?.rssi,
               let measuredBand = measurement.bands.first(where: { FrequencyBand.fromFrequency(Float($0.frequency)) == band }) {
                errors[band] = abs(Double(predictedRSSI) - measuredBand.rssi)
            }
        }
        
        return errors
    }
    
    /// Overall prediction accuracy score (0-1, higher is better)
    public var accuracyScore: Double {
        let errors = predictionErrors.values
        guard !errors.isEmpty else { return 0.0 }
        
        let meanError = errors.reduce(0, +) / Double(errors.count)
        // Convert error to accuracy score (6dB error = 50% accuracy)
        return max(0.0, 1.0 - meanError / 12.0)
    }
}

/// Environment-specific calibration factors
public struct EnvironmentCalibration: Codable {
    /// Environment type this calibration applies to
    public let environment: IndoorEnvironment
    
    /// Path loss exponent adjustment
    public let pathLossAdjustment: Double
    
    /// Wall penetration multiplier
    public let wallPenetrationMultiplier: Double
    
    /// Clutter/furniture loss multiplier
    public let clutterMultiplier: Double
    
    /// Number of calibration points used
    public let calibrationPoints: Int
    
    /// Validation score (0-1)
    public let validationScore: Double
    
    public init(
        environment: IndoorEnvironment,
        pathLossAdjustment: Double,
        wallPenetrationMultiplier: Double,
        clutterMultiplier: Double,
        calibrationPoints: Int,
        validationScore: Double
    ) {
        self.environment = environment
        self.pathLossAdjustment = pathLossAdjustment
        self.wallPenetrationMultiplier = wallPenetrationMultiplier
        self.clutterMultiplier = clutterMultiplier
        self.calibrationPoints = calibrationPoints
        self.validationScore = validationScore
    }
    
    /// Whether this calibration is reliable enough to use
    public var isReliable: Bool {
        return calibrationPoints >= 10 && validationScore > 0.7
    }
}

// MARK: - Array Extensions for Performance

extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Grid Generation Helpers

extension RFPropagationEngine {
    /// Create calculation grid for coverage map generation
    func createCalculationGrid(bounds: BoundingBox, resolution: Double) -> [Point3D] {
        var gridPoints: [Point3D] = []
        
        let minX = Double(bounds.min.x)
        let minZ = Double(bounds.min.z)
        let maxX = Double(bounds.max.x)
        let maxZ = Double(bounds.max.z)
        let fixedY = Double(bounds.min.y) + 1.0 // 1m above floor
        
        var x = minX
        while x <= maxX {
            var z = minZ
            while z <= maxZ {
                gridPoints.append(simd_float3(Float(x), Float(fixedY), Float(z)))
                z += resolution
            }
            x += resolution
        }
        
        print("🔧 Generated \(gridPoints.count) grid points")
        print("   Grid: \(Int((maxX - minX) / resolution + 1)) x \(Int((maxZ - minZ) / resolution + 1))")
        
        return gridPoints
    }
    
    /// Calculate combined signal prediction from multiple routers
    func calculateCombinedSignalAt(
        point: Point3D,
        routers: [RouterConfiguration],
        floorPlan: RoomModel
    ) -> CombinedSignalPrediction {
        var routerPredictions: [UUID: SignalPrediction] = [:]
        var bestRSSIPerBand: [FrequencyBand: Float] = [:]
        var primaryRouterId: UUID = routers.first?.id ?? UUID()
        var maxSignalStrength: Float = -200.0
        
        for router in routers {
            let prediction = calculateSignalStrength(
                from: router,
                to: point,
                in: floorPlan
            )
            
            routerPredictions[router.id] = prediction
            
            // Update best RSSI per band
            for (band, rssiPrediction) in prediction.predictedRSSI {
                if bestRSSIPerBand[band] == nil || rssiPrediction.rssi > bestRSSIPerBand[band]! {
                    bestRSSIPerBand[band] = rssiPrediction.rssi
                }
            }
            
            // Track primary (strongest) router
            if prediction.bestRSSI > maxSignalStrength {
                maxSignalStrength = prediction.bestRSSI
                primaryRouterId = router.id
            }
        }
        
        let overallQuality = SignalQuality.fromRSSI(maxSignalStrength)
        
        return CombinedSignalPrediction(
            routerPredictions: routerPredictions,
            combinedRSSI: bestRSSIPerBand,
            overallQuality: overallQuality,
            primaryRouter: primaryRouterId
        )
    }
    
    /// Interpolate coverage data to fill gaps
    func interpolateCoverageData(
        coverageData: [Point3D: CombinedSignalPrediction],
        bounds: BoundingBox,
        resolution: Double
    ) -> [Point3D: CombinedSignalPrediction] {
        // For now, return the original data
        // In a full implementation, this would use spatial interpolation
        // to fill gaps and smooth coverage predictions
        return coverageData
    }
    
    // MARK: - Caching Implementation
    
    /// Generate cache key for signal prediction
    func generateCacheKey(router: RouterConfiguration, testPoint: Point3D, frequency: Float?) -> String {
        let routerStr = "\(router.id.uuidString)_\(router.position)"
        let pointStr = "\(testPoint.x)_\(testPoint.y)_\(testPoint.z)"
        let freqStr = frequency.map { "\($0)" } ?? "all"
        return "\(routerStr)_\(pointStr)_\(freqStr)"
    }
    
    /// Get cached result if available
    func getCachedResult(for key: String) -> SignalPrediction? {
        return cacheQueue.sync {
            return calculationCache[key]
        }
    }
    
    /// Store result in cache
    func setCachedResult(_ result: SignalPrediction, for key: String) {
        cacheQueue.async(flags: .barrier) {
            // Remove oldest entries if cache is full
            if self.calculationCache.count >= self.maxCacheSize {
                let keysToRemove = Array(self.calculationCache.keys.prefix(self.maxCacheSize / 4))
                keysToRemove.forEach { self.calculationCache.removeValue(forKey: $0) }
            }
            
            self.calculationCache[key] = result
        }
    }
}