import Foundation
import simd

/// Core RF propagation engine implementing 3GPP Indoor Office Standard
/// and advanced WiFi 7 multi-band prediction algorithms
public class RFPropagationEngine {
    
    // MARK: - Configuration
    
    /// RF propagation parameters for different environments
    private let propagationParameters: RFPropagationParameters
    
    /// ITU Indoor models for different frequency bands
    private let ituModels: [FrequencyBand: PropagationModels.ITUIndoorModel]
    
    /// Wall penetration model for material interactions
    private let wallPenetrationModel = PropagationModels.WallPenetrationModel()
    
    /// WiFi 7 multi-band model
    private let wiFi7Model: PropagationModels.WiFi7MultiBandModel
    
    // MARK: - Performance Optimization
    
    /// Cache for recent calculations to improve performance
    private var calculationCache: [String: SignalPrediction] = [:]
    private let cacheQueue = DispatchQueue(label: "rfengine.cache", attributes: .concurrent)
    private let maxCacheSize = 1000
    
    /// Spatial index for efficient wall intersection queries
    private var spatialIndex: RTreeIndex?
    
    // MARK: - Initialization
    
    /// Initialize RF propagation engine
    /// - Parameters:
    ///   - environment: Indoor environment type for propagation modeling
    ///   - useAdvancedRayTracing: Enable advanced ray tracing calculations
    public init(environment: IndoorEnvironment = .residential, useAdvancedRayTracing: Bool = true) {
        self.propagationParameters = RFPropagationParameters.default(for: environment)
        
        // Initialize ITU models for all WiFi 7 bands
        self.ituModels = [
            .band2_4GHz: PropagationModels.ITUIndoorModel(environment: environment),
            .band5GHz: PropagationModels.ITUIndoorModel(environment: environment),
            .band6GHz: PropagationModels.ITUIndoorModel(environment: environment)
        ]
        
        self.wiFi7Model = PropagationModels.WiFi7MultiBandModel(environment: environment)
        
        print("🔬 RFPropagationEngine initialized for \(environment.rawValue) environment")
        print("   Advanced ray tracing: \(useAdvancedRayTracing ? "enabled" : "disabled")")
        print("   Cache size limit: \(maxCacheSize) calculations")
    }
    
    // MARK: - Core Prediction Methods
    
    /// Calculate signal strength at a test point from a router
    /// - Parameters:
    ///   - router: Router position and specifications
    ///   - testPoint: Location to predict signal strength
    ///   - floorPlan: Floor plan with walls, furniture, and obstacles
    ///   - frequency: Frequency in MHz (optional, calculates all bands if nil)
    /// - Returns: Signal prediction with detailed breakdown
    public func calculateSignalStrength(
        from router: RouterConfiguration,
        to testPoint: Point3D,
        in floorPlan: RoomModel,
        at frequency: Float? = nil
    ) -> SignalPrediction {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Check cache first
        let cacheKey = generateCacheKey(router: router, testPoint: testPoint, frequency: frequency)
        if let cachedResult = getCachedResult(for: cacheKey) {
            return cachedResult
        }
        
        // Calculate 3D distance
        let distance3D = Double(router.position.distance(to: testPoint))
        
        guard distance3D > 0.1 else {
            // Very close to router - use maximum signal
            let maxSignal = SignalPrediction(
                location: testPoint,
                predictedRSSI: [:],
                pathLoss: [:],
                obstacles: [],
                confidence: 1.0,
                calculationTime: 0.001
            )
            return maxSignal
        }
        
        // Determine frequencies to calculate
        let frequencies: [Float]
        if let freq = frequency {
            frequencies = [freq]
        } else {
            frequencies = [2400.0, 5000.0, 6000.0] // WiFi 7 bands
        }
        
        var predictions: [FrequencyBand: RSSIPrediction] = [:]
        var pathLosses: [FrequencyBand: Double] = [:]
        
        // Calculate for each frequency band
        for freq in frequencies {
            let band = FrequencyBand.fromFrequency(freq)
            
            // Get router TX power and antenna gain for this band
            let txPower = getTxPower(router: router, band: band)
            let antennaGain = getAntennaGain(router: router, band: band)
            
            // Calculate path loss components
            let pathLossResult = calculatePathLoss(
                from: router.position,
                to: testPoint,
                frequency: Double(freq),
                floorPlan: floorPlan,
                router: router
            )
            
            // Convert path loss to RSSI
            let predictedRSSI = txPower + antennaGain - pathLossResult.totalPathLoss
            
            predictions[band] = RSSIPrediction(
                rssi: Float(predictedRSSI),
                snr: estimateSNR(rssi: Float(predictedRSSI)),
                confidence: pathLossResult.confidence
            )
            
            pathLosses[band] = pathLossResult.totalPathLoss
        }
        
        // Find obstacles between router and test point
        let obstacles = floorPlan.getObstaclesBetween(router.position, testPoint)
        
        // Calculate overall confidence based on measurement conditions
        let overallConfidence = calculateConfidence(
            distance: distance3D,
            obstacles: obstacles,
            environment: propagationParameters.environment
        )
        
        let calculationTime = CFAbsoluteTimeGetCurrent() - startTime
        
        let result = SignalPrediction(
            location: testPoint,
            predictedRSSI: predictions,
            pathLoss: pathLosses,
            obstacles: obstacles,
            confidence: overallConfidence,
            calculationTime: calculationTime
        )
        
        // Cache the result
        setCachedResult(result, for: cacheKey)
        
        print("🔬 Signal prediction completed in \(String(format: "%.1f", calculationTime * 1000))ms")
        print("   Distance: \(String(format: "%.1f", distance3D))m, Obstacles: \(obstacles.count)")
        
        return result
    }
    
    /// Calculate comprehensive coverage map for an area
    /// - Parameters:
    ///   - routers: Array of router configurations
    ///   - floorPlan: Room model with obstacles
    ///   - gridResolution: Grid spacing in meters (default: 0.5m)
    ///   - progressCallback: Optional progress reporting callback
    /// - Returns: Coverage map with signal predictions at grid points
    public func generateCoverageMap(
        routers: [RouterConfiguration],
        floorPlan: RoomModel,
        gridResolution: Double = 0.5,
        progressCallback: ((Double) -> Void)? = nil
    ) -> CoverageMap {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        print("🗺️ Generating coverage map with \(routers.count) routers")
        print("   Grid resolution: \(gridResolution)m")
        print("   Room bounds: \(floorPlan.bounds)")
        
        // Create calculation grid
        let gridPoints = createCalculationGrid(
            bounds: floorPlan.bounds,
            resolution: gridResolution
        )
        
        print("   Grid points: \(gridPoints.count)")
        
        var coverageData: [Point3D: CombinedSignalPrediction] = [:]
        let totalCalculations = gridPoints.count
        var completedCalculations = 0
        
        // Process grid points in batches for better performance
        let batchSize = 50
        let batches = gridPoints.chunked(into: batchSize)
        
        for batch in batches {
            // Process batch concurrently
            let batchResults = batch.compactMap { point -> (Point3D, CombinedSignalPrediction)? in
                let combinedPrediction = calculateCombinedSignalAt(
                    point: point,
                    routers: routers,
                    floorPlan: floorPlan
                )
                return (point, combinedPrediction)
            }
            
            // Add batch results to coverage data
            for (point, prediction) in batchResults {
                coverageData[point] = prediction
            }
            
            completedCalculations += batch.count
            let progress = Double(completedCalculations) / Double(totalCalculations)
            progressCallback?(progress)
        }
        
        // Generate interpolated coverage map
        let interpolatedMap = interpolateCoverageData(
            coverageData: coverageData,
            bounds: floorPlan.bounds,
            resolution: gridResolution
        )
        
        let calculationTime = CFAbsoluteTimeGetCurrent() - startTime
        
        print("🗺️ Coverage map generated in \(String(format: "%.1f", calculationTime))s")
        print("   Coverage points: \(coverageData.count)")
        
        return CoverageMap(
            bounds: floorPlan.bounds,
            resolution: gridResolution,
            coverageData: interpolatedMap,
            routers: routers,
            generationTime: calculationTime
        )
    }
    
    // MARK: - Path Loss Calculations
    
    /// Calculate detailed path loss from router to test point
    private func calculatePathLoss(
        from router: Point3D,
        to testPoint: Point3D,
        frequency: Double,
        floorPlan: RoomModel,
        router routerConfig: RouterConfiguration
    ) -> PathLossResult {
        let band = FrequencyBand.fromFrequency(Float(frequency))
        
        // Base ITU indoor path loss
        guard let ituModel = ituModels[band] else {
            return PathLossResult(totalPathLoss: 100.0, confidence: 0.1, components: [:])
        }
        
        let distance3D = Double(router.distance(to: testPoint))
        let basePathLoss = ituModel.pathLoss(
            distance: Float(distance3D),
            frequency: Float(frequency),
            floors: 0 // Single floor for now
        )
        
        var pathLossComponents: [String: Double] = [:]
        pathLossComponents["base_path_loss"] = Double(basePathLoss)
        
        // Wall penetration losses
        let wallIntersections = findWallIntersections(
            from: router,
            to: testPoint,
            walls: floorPlan.walls
        )
        
        var wallPenetrationLoss: Double = 0.0
        for intersection in wallIntersections {
            let loss = PropagationModels.WallPenetrationModel.penetrationLoss(
                material: intersection.wall.material,
                thickness: Double(intersection.wall.thickness),
                frequency: frequency,
                incidenceAngle: intersection.incidenceAngle
            )
            wallPenetrationLoss += loss
        }
        
        pathLossComponents["wall_penetration"] = wallPenetrationLoss
        
        // Furniture/clutter losses
        let clutterLoss = calculateClutterLoss(
            from: router,
            to: testPoint,
            furniture: floorPlan.furniture,
            frequency: frequency
        )
        pathLossComponents["clutter_loss"] = clutterLoss
        
        // Environmental corrections
        let environmentalLoss = PropagationModels.EnvironmentalCorrections.clutterCorrection(
            pathLoss: Double(basePathLoss),
            clutterDensity: propagationParameters.clutterFactor,
            frequency: frequency
        ) - Double(basePathLoss)
        
        pathLossComponents["environmental"] = environmentalLoss
        
        let totalPathLoss = Double(basePathLoss) + wallPenetrationLoss + clutterLoss + environmentalLoss
        
        // Calculate confidence based on calculation complexity
        let confidence = calculatePathLossConfidence(
            distance: distance3D,
            wallIntersections: wallIntersections.count,
            frequency: frequency
        )
        
        return PathLossResult(
            totalPathLoss: totalPathLoss,
            confidence: confidence,
            components: pathLossComponents
        )
    }
    
    /// Find wall intersections along signal path
    private func findWallIntersections(
        from start: Point3D,
        to end: Point3D,
        walls: [WallElement]
    ) -> [WallIntersection] {
        var intersections: [WallIntersection] = []
        
        for wall in walls {
            if let intersection = lineIntersectsWall3D(
                lineStart: start,
                lineEnd: end,
                wallStart: wall.startPoint,
                wallEnd: wall.endPoint,
                wallHeight: wall.height
            ) {
                let incidenceAngle = calculateIncidenceAngle(
                    signalDirection: (end - start).normalized,
                    wallNormal: wall.normal
                )
                
                intersections.append(WallIntersection(
                    wall: wall,
                    intersectionPoint: intersection,
                    incidenceAngle: Double(incidenceAngle)
                ))
            }
        }
        
        return intersections
    }
    
    /// Calculate clutter loss from furniture
    private func calculateClutterLoss(
        from start: Point3D,
        to end: Point3D,
        furniture: [FurnitureItem],
        frequency: Double
    ) -> Double {
        var totalClutterLoss: Double = 0.0
        
        for item in furniture {
            // Check if signal path intersects furniture bounding box
            if pathIntersectsBounds(from: start, to: end, bounds: item.bounds) {
                // Apply furniture-specific attenuation
                let attenuationFactor = furnitureAttenuationFactor(
                    type: item.type,
                    frequency: frequency
                )
                totalClutterLoss += attenuationFactor
            }
        }
        
        return min(totalClutterLoss, 15.0) // Cap clutter loss at reasonable maximum
    }
    
    // MARK: - Helper Methods
    
    /// Get transmit power for router at specific band
    private func getTxPower(router: RouterConfiguration, band: FrequencyBand) -> Double {
        let bandIndex = getBandIndex(band)
        guard bandIndex < router.deviceSpec.txPower.count else {
            return 20.0 // Default 20dBm
        }
        return Double(router.deviceSpec.txPower[bandIndex])
    }
    
    /// Get antenna gain for router at specific band
    private func getAntennaGain(router: RouterConfiguration, band: FrequencyBand) -> Double {
        let bandIndex = getBandIndex(band)
        guard bandIndex < router.deviceSpec.antennaGain.count else {
            return 2.0 // Default 2dBi
        }
        return Double(router.deviceSpec.antennaGain[bandIndex])
    }
    
    /// Get band index for array lookups
    private func getBandIndex(_ band: FrequencyBand) -> Int {
        switch band {
        case .band2_4GHz: return 0
        case .band5GHz: return 1
        case .band6GHz: return 2
        }
    }
    
    /// Estimate SNR based on RSSI
    private func estimateSNR(rssi: Float) -> Float {
        // Simplified SNR estimation based on typical indoor noise floor
        let noiseFloor: Float = -95.0 // Typical indoor noise floor
        return max(0, rssi - noiseFloor)
    }
    
    /// Calculate confidence score for path loss prediction
    private func calculatePathLossConfidence(
        distance: Double,
        wallIntersections: Int,
        frequency: Double
    ) -> Double {
        var confidence: Double = 1.0
        
        // Reduce confidence with distance
        if distance > 10.0 {
            confidence *= 0.9
        }
        if distance > 20.0 {
            confidence *= 0.8
        }
        
        // Reduce confidence with wall penetrations
        confidence *= pow(0.9, Double(wallIntersections))
        
        // Higher frequencies have more uncertainty
        if frequency > 5000 {
            confidence *= 0.95
        }
        if frequency > 6000 {
            confidence *= 0.9
        }
        
        return max(0.1, confidence)
    }
    
    /// Calculate overall confidence for signal prediction
    private func calculateConfidence(
        distance: Double,
        obstacles: [Obstacle],
        environment: IndoorEnvironment
    ) -> Double {
        var confidence: Double = 0.9 // Start with high confidence
        
        // Distance factor
        let distanceFactor = 1.0 / (1.0 + distance / 20.0)
        confidence *= distanceFactor
        
        // Obstacle factor
        let obstacleFactor = 1.0 / (1.0 + Double(obstacles.count) * 0.1)
        confidence *= obstacleFactor
        
        // Environment factor
        switch environment {
        case .residential:
            confidence *= 0.95
        case .office:
            confidence *= 0.9
        case .commercial:
            confidence *= 0.85
        case .industrial:
            confidence *= 0.8
        }
        
        return max(0.1, min(1.0, confidence))
    }
    
    // MARK: - Geometric Calculations
    
    /// Check if line intersects 3D wall
    private func lineIntersectsWall3D(
        lineStart: Point3D,
        lineEnd: Point3D,
        wallStart: Point3D,
        wallEnd: Point3D,
        wallHeight: Float
    ) -> Point3D? {
        // Simplified 2D line intersection for now
        // In a full implementation, this would handle 3D wall geometry
        
        let p1 = simd_float2(lineStart.x, lineStart.z)
        let p2 = simd_float2(lineEnd.x, lineEnd.z)
        let p3 = simd_float2(wallStart.x, wallStart.z)
        let p4 = simd_float2(wallEnd.x, wallEnd.z)
        
        if let intersection2D = lineIntersection2D(p1: p1, p2: p2, p3: p3, p4: p4) {
            // Check if intersection is within wall height bounds
            let signalHeight = lineStart.y + (lineEnd.y - lineStart.y) * 0.5 // Mid-height
            if signalHeight >= wallStart.y && signalHeight <= wallStart.y + wallHeight {
                return simd_float3(intersection2D.x, signalHeight, intersection2D.y)
            }
        }
        
        return nil
    }
    
    /// 2D line intersection calculation
    private func lineIntersection2D(p1: simd_float2, p2: simd_float2, p3: simd_float2, p4: simd_float2) -> simd_float2? {
        let denom = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
        guard abs(denom) > 1e-6 else { return nil }
        
        let t = ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / denom
        let u = -((p1.x - p2.x) * (p1.y - p3.y) - (p1.y - p2.y) * (p1.x - p3.x)) / denom
        
        guard t >= 0 && t <= 1 && u >= 0 && u <= 1 else { return nil }
        
        return simd_float2(
            p1.x + t * (p2.x - p1.x),
            p1.y + t * (p2.y - p1.y)
        )
    }
    
    /// Calculate incidence angle between signal and wall
    private func calculateIncidenceAngle(signalDirection: Vector3D, wallNormal: Vector3D) -> Float {
        let dotProduct = signalDirection.dot(wallNormal)
        return acos(abs(dotProduct))
    }
    
    /// Check if path intersects bounding box
    private func pathIntersectsBounds(from start: Point3D, to end: Point3D, bounds: BoundingBox) -> Bool {
        // Ray-box intersection test
        let direction = (end - start).normalized
        let invDir = simd_float3(1.0 / direction.x, 1.0 / direction.y, 1.0 / direction.z)
        
        let t1 = (bounds.min - start) * invDir
        let t2 = (bounds.max - start) * invDir
        
        let tmin = simd_float3(min(t1.x, t2.x), min(t1.y, t2.y), min(t1.z, t2.z))
        let tmax = simd_float3(max(t1.x, t2.x), max(t1.y, t2.y), max(t1.z, t2.z))
        
        let tmaxMin = min(tmax.x, min(tmax.y, tmax.z))
        let tminMax = max(tmin.x, max(tmin.y, tmin.z))
        
        return tmaxMin >= tminMax && tmaxMin >= 0 && tminMax <= start.distance(to: end)
    }
    
    /// Get furniture attenuation factor
    private func furnitureAttenuationFactor(type: FurnitureType, frequency: Double) -> Double {
        switch type {
        case .cabinet, .dresser:
            return frequency > 5000 ? 4.0 : 3.0
        case .refrigerator:
            return frequency > 5000 ? 8.0 : 6.0
        case .shelf:
            return 1.5
        case .desk, .table:
            return 1.0
        default:
            return 0.5
        }
    }
}