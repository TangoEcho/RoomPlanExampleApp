import Foundation

// MARK: - Placement Analysis Results

/// Complete analysis result with placement recommendations
public struct PlacementAnalysis: Codable, Identifiable {
    public let id: UUID
    public let roomModel: RoomModel
    public let currentCoverage: CoverageMap
    public let recommendations: [PlacementRecommendation]
    public let projectedCoverage: CoverageMap?
    public let analysisMetadata: AnalysisMetadata
    
    public init(
        id: UUID = UUID(),
        roomModel: RoomModel,
        currentCoverage: CoverageMap,
        recommendations: [PlacementRecommendation],
        projectedCoverage: CoverageMap? = nil,
        analysisMetadata: AnalysisMetadata
    ) {
        self.id = id
        self.roomModel = roomModel
        self.currentCoverage = currentCoverage
        self.recommendations = recommendations
        self.projectedCoverage = projectedCoverage
        self.analysisMetadata = analysisMetadata
    }
    
    /// Get the best recommendation (if any)
    public var bestRecommendation: PlacementRecommendation? {
        return recommendations.first
    }
    
    /// Calculate overall improvement potential
    public var improvementPotential: Double {
        guard let projected = projectedCoverage else { return 0.0 }
        
        let currentGoodCoverage = currentCoverage.coveragePercentage(threshold: -70.0)
        let projectedGoodCoverage = projected.coveragePercentage(threshold: -70.0)
        
        return projectedGoodCoverage - currentGoodCoverage
    }
}

/// Individual placement recommendation
public struct PlacementRecommendation: Codable, Identifiable {
    public let id: UUID
    public let location: Point3D
    public let surface: PlacementSurface?
    public let confidence: Double
    public let expectedImprovement: CoverageImprovement
    public let feasibilityScore: Double
    public let reasoning: [RecommendationReason]
    public let devicePlacement: DevicePlacement?
    
    public init(
        id: UUID = UUID(),
        location: Point3D,
        surface: PlacementSurface?,
        confidence: Double,
        expectedImprovement: CoverageImprovement,
        feasibilityScore: Double,
        reasoning: [RecommendationReason],
        devicePlacement: DevicePlacement? = nil
    ) {
        self.id = id
        self.location = location
        self.surface = surface
        self.confidence = confidence
        self.expectedImprovement = expectedImprovement
        self.feasibilityScore = feasibilityScore
        self.reasoning = reasoning
        self.devicePlacement = devicePlacement
    }
    
    /// Overall recommendation quality score
    public var qualityScore: Double {
        return (confidence + feasibilityScore + expectedImprovement.improvementFactor.clamped(to: 0...1)) / 3.0
    }
    
    /// Estimated installation time in minutes
    public func estimatedInstallationTime() -> TimeInterval {
        var baseTime: TimeInterval = 15 // 15 minutes base
        
        // Adjust based on surface type
        if let surface = surface {
            switch surface.accessibility {
            case .excellent:
                baseTime += 5
            case .good:
                baseTime += 10
            case .poor:
                baseTime += 20
            }
        } else {
            baseTime += 10 // Wall mounting
        }
        
        // Adjust based on power proximity
        if let powerDistance = surface?.powerProximity, powerDistance > 2.0 {
            baseTime += 10 // Additional time for power extension
        }
        
        return baseTime * 60 // Convert to seconds
    }
    
    /// Check if this recommendation is viable for installation
    public var isViable: Bool {
        return confidence > 0.5 && feasibilityScore > 0.6 && expectedImprovement.improvementFactor > 1.1
    }
}

/// Expected coverage improvement from a placement
public struct CoverageImprovement: Codable {
    public let beforeCoverage: Double           // Percentage (0-1)
    public let afterCoverage: Double            // Percentage (0-1)
    public let newlyServedArea: Double          // Square meters
    public let improvementFactor: Double        // Multiplier (e.g., 1.5 = 50% improvement)
    public let bandSpecificGains: [FrequencyBand: Double]
    public let weakSpotReduction: Double        // Percentage of weak spots eliminated
    
    public init(
        beforeCoverage: Double,
        afterCoverage: Double,
        newlyServedArea: Double,
        improvementFactor: Double,
        bandSpecificGains: [FrequencyBand: Double],
        weakSpotReduction: Double
    ) {
        self.beforeCoverage = beforeCoverage
        self.afterCoverage = afterCoverage
        self.newlyServedArea = newlyServedArea
        self.improvementFactor = improvementFactor
        self.bandSpecificGains = bandSpecificGains
        self.weakSpotReduction = weakSpotReduction
    }
    
    /// Absolute improvement in coverage percentage
    public var absoluteImprovement: Double {
        return afterCoverage - beforeCoverage
    }
    
    /// Whether this represents a significant improvement
    public var isSignificant: Bool {
        return absoluteImprovement > 0.1 && improvementFactor > 1.2
    }
}

/// Reasons supporting a placement recommendation
public enum RecommendationReason: String, Codable, CaseIterable {
    case optimalBackhaul = "optimal_backhaul"
    case maximumCoverage = "maximum_coverage"
    case goodSurface = "good_surface"
    case powerAccess = "power_access"
    case centralLocation = "central_location"
    case minimalObstacles = "minimal_obstacles"
    case weakSpotCoverage = "weak_spot_coverage"
    case userTrafficArea = "user_traffic_area"
    case aestheticallyAcceptable = "aesthetically_acceptable"
    case futureExpansion = "future_expansion"
    
    public var description: String {
        switch self {
        case .optimalBackhaul:
            return "Excellent signal strength to router for reliable backhaul"
        case .maximumCoverage:
            return "Maximizes coverage of areas with poor signal"
        case .goodSurface:
            return "Suitable furniture or surface available for placement"
        case .powerAccess:
            return "Close to power outlet for easy installation"
        case .centralLocation:
            return "Centrally located for even signal distribution"
        case .minimalObstacles:
            return "Few RF obstacles in coverage area"
        case .weakSpotCoverage:
            return "Effectively covers identified weak signal areas"
        case .userTrafficArea:
            return "Located in area of high device usage"
        case .aestheticallyAcceptable:
            return "Placement location is aesthetically acceptable"
        case .futureExpansion:
            return "Good position for potential network expansion"
        }
    }
    
    /// Importance weight for scoring
    public var weight: Double {
        switch self {
        case .optimalBackhaul, .maximumCoverage:
            return 1.0 // Critical factors
        case .goodSurface, .weakSpotCoverage:
            return 0.8 // Important factors
        case .powerAccess, .centralLocation, .minimalObstacles:
            return 0.6 // Moderate factors
        case .userTrafficArea, .aestheticallyAcceptable, .futureExpansion:
            return 0.4 // Nice-to-have factors
        }
    }
}

/// Constraints for placement optimization
public struct PlacementConstraints: Codable {
    public let minBackhaulRSSI: Double
    public let maxDistanceFromRouter: Double
    public let requiredSurfaceArea: Double
    public let maxPowerDistance: Double
    public let avoidZones: [BoundingBox]
    public let preferredZones: [BoundingBox]?
    public let aestheticPreferences: AestheticPreferences
    public let maxExtenders: Int
    public let deviceSpecifications: DeviceSpec?
    
    public init(
        minBackhaulRSSI: Double = -65.0,
        maxDistanceFromRouter: Double = 15.0,
        requiredSurfaceArea: Double = 0.02,
        maxPowerDistance: Double = 3.0,
        avoidZones: [BoundingBox] = [],
        preferredZones: [BoundingBox]? = nil,
        aestheticPreferences: AestheticPreferences = AestheticPreferences(),
        maxExtenders: Int = 3,
        deviceSpecifications: DeviceSpec? = nil
    ) {
        self.minBackhaulRSSI = minBackhaulRSSI
        self.maxDistanceFromRouter = maxDistanceFromRouter
        self.requiredSurfaceArea = requiredSurfaceArea
        self.maxPowerDistance = maxPowerDistance
        self.avoidZones = avoidZones
        self.preferredZones = preferredZones
        self.aestheticPreferences = aestheticPreferences
        self.maxExtenders = maxExtenders
        self.deviceSpecifications = deviceSpecifications
    }
    
    public static let standard = PlacementConstraints()
    
    /// Check if a location satisfies the constraints
    public func satisfies(location: Point3D, routerLocation: Point3D) -> Bool {
        // Check distance constraint
        let distance = location.distance(to: routerLocation)
        if distance > maxDistanceFromRouter {
            return false
        }
        
        // Check avoid zones
        for avoidZone in avoidZones {
            if avoidZone.contains(location) {
                return false
            }
        }
        
        return true
    }
}

/// Aesthetic preferences for placement
public struct AestheticPreferences: Codable {
    public let hiddenPreferred: Bool
    public let wallMountAcceptable: Bool
    public let colorPreference: String?
    public let sizeConstraints: Vector3D?
    public let minimalistDesign: Bool
    
    public init(
        hiddenPreferred: Bool = false,
        wallMountAcceptable: Bool = true,
        colorPreference: String? = nil,
        sizeConstraints: Vector3D? = nil,
        minimalistDesign: Bool = true
    ) {
        self.hiddenPreferred = hiddenPreferred
        self.wallMountAcceptable = wallMountAcceptable
        self.colorPreference = colorPreference
        self.sizeConstraints = sizeConstraints
        self.minimalistDesign = minimalistDesign
    }
}

/// Analysis metadata
public struct AnalysisMetadata: Codable {
    public let analysisTime: Date
    public let processingDuration: TimeInterval
    public let algorithmVersion: String
    public let configurationUsed: String
    public let qualityMetrics: AnalysisQualityMetrics?
    
    public init(
        analysisTime: Date = Date(),
        processingDuration: TimeInterval,
        algorithmVersion: String,
        configurationUsed: String,
        qualityMetrics: AnalysisQualityMetrics? = nil
    ) {
        self.analysisTime = analysisTime
        self.processingDuration = processingDuration
        self.algorithmVersion = algorithmVersion
        self.configurationUsed = configurationUsed
        self.qualityMetrics = qualityMetrics
    }
}

/// Quality metrics for the analysis
public struct AnalysisQualityMetrics: Codable {
    public let confidenceLevel: Double
    public let coverageAccuracy: Double
    public let placementViability: Double
    public let computationalComplexity: String
    
    public init(
        confidenceLevel: Double,
        coverageAccuracy: Double,
        placementViability: Double,
        computationalComplexity: String
    ) {
        self.confidenceLevel = confidenceLevel
        self.coverageAccuracy = coverageAccuracy
        self.placementViability = placementViability
        self.computationalComplexity = computationalComplexity
    }
    
    /// Overall quality score
    public var overallQuality: Double {
        return (confidenceLevel + coverageAccuracy + placementViability) / 3.0
    }
}

// MARK: - Coverage Map

/// Signal coverage map for a room
public struct CoverageMap: Codable {
    public let gridResolution: Double
    public let bounds: BoundingBox
    public let signalGrid: [[[SignalStrength]]] // 3D grid [x][y][z]
    public let timestamp: Date
    
    public init(
        gridResolution: Double,
        bounds: BoundingBox,
        signalGrid: [[[SignalStrength]]],
        timestamp: Date = Date()
    ) {
        self.gridResolution = gridResolution
        self.bounds = bounds
        self.signalGrid = signalGrid
        self.timestamp = timestamp
    }
    
    /// Get signal strength at a specific point via interpolation
    public func interpolatedSignal(at point: Point3D) -> SignalStrength? {
        guard bounds.contains(point) else { return nil }
        
        // Convert point to grid coordinates
        let relativePoint = point - Vector3D(x: bounds.min.x, y: bounds.min.y, z: bounds.min.z)
        let gridX = relativePoint.x / gridResolution
        let gridY = relativePoint.y / gridResolution
        let gridZ = relativePoint.z / gridResolution
        
        // Get grid indices
        let x0 = Int(floor(gridX))
        let y0 = Int(floor(gridY))
        let z0 = Int(floor(gridZ))
        
        // Check bounds
        guard x0 >= 0 && x0 < signalGrid.count - 1,
              y0 >= 0 && y0 < signalGrid[0].count - 1,
              z0 >= 0 && z0 < signalGrid[0][0].count - 1 else {
            // Return nearest neighbor if interpolation not possible
            let clampedX = max(0, min(signalGrid.count - 1, Int(round(gridX))))
            let clampedY = max(0, min(signalGrid[0].count - 1, Int(round(gridY))))
            let clampedZ = max(0, min(signalGrid[0][0].count - 1, Int(round(gridZ))))
            return signalGrid[clampedX][clampedY][clampedZ]
        }
        
        // Trilinear interpolation
        let fx = gridX - Double(x0)
        let fy = gridY - Double(y0)
        let fz = gridZ - Double(z0)
        
        // Get 8 corner values
        let c000 = signalGrid[x0][y0][z0]
        let c001 = signalGrid[x0][y0][z0 + 1]
        let c010 = signalGrid[x0][y0 + 1][z0]
        let c011 = signalGrid[x0][y0 + 1][z0 + 1]
        let c100 = signalGrid[x0 + 1][y0][z0]
        let c101 = signalGrid[x0 + 1][y0][z0 + 1]
        let c110 = signalGrid[x0 + 1][y0 + 1][z0]
        let c111 = signalGrid[x0 + 1][y0 + 1][z0 + 1]
        
        // Interpolate
        return interpolateSignalStrength(
            c000: c000, c001: c001, c010: c010, c011: c011,
            c100: c100, c101: c101, c110: c110, c111: c111,
            fx: fx, fy: fy, fz: fz,
            location: point
        )
    }
    
    /// Calculate coverage percentage above a threshold
    public func coveragePercentage(threshold: Double) -> Double {
        var totalPoints = 0
        var coveredPoints = 0
        
        for x in signalGrid.indices {
            for y in signalGrid[x].indices {
                for z in signalGrid[x][y].indices {
                    let signal = signalGrid[x][y][z]
                    let maxSignal = signal.bands.values.max() ?? -200.0
                    
                    totalPoints += 1
                    if maxSignal >= threshold {
                        coveredPoints += 1
                    }
                }
            }
        }
        
        return totalPoints > 0 ? Double(coveredPoints) / Double(totalPoints) : 0.0
    }
    
    /// Find areas with weak signal (below threshold)
    public func weakSpotAreas(threshold: Double) -> [BoundingBox] {
        var weakSpots: [BoundingBox] = []
        
        // Simple implementation: find contiguous regions below threshold
        // This is a simplified version - a proper implementation would use region growing
        
        for x in signalGrid.indices {
            for y in signalGrid[x].indices {
                for z in signalGrid[x][y].indices {
                    let signal = signalGrid[x][y][z]
                    let maxSignal = signal.bands.values.max() ?? -200.0
                    
                    if maxSignal < threshold {
                        let gridPoint = Point3D(
                            x: bounds.min.x + Double(x) * gridResolution,
                            y: bounds.min.y + Double(y) * gridResolution,
                            z: bounds.min.z + Double(z) * gridResolution
                        )
                        
                        let weakSpot = BoundingBox(
                            min: gridPoint,
                            max: gridPoint.moved(by: Vector3D(x: gridResolution, y: gridResolution, z: gridResolution))
                        )
                        
                        weakSpots.append(weakSpot)
                    }
                }
            }
        }
        
        return mergeAdjacentBounds(weakSpots)
    }
    
    /// Create an empty coverage map
    public static func empty() -> CoverageMap {
        return CoverageMap(
            gridResolution: 1.0,
            bounds: BoundingBox(min: Point3D.zero, max: Point3D.zero),
            signalGrid: [],
            timestamp: Date()
        )
    }
    
    // MARK: - Private Helpers
    
    private func interpolateSignalStrength(
        c000: SignalStrength, c001: SignalStrength, c010: SignalStrength, c011: SignalStrength,
        c100: SignalStrength, c101: SignalStrength, c110: SignalStrength, c111: SignalStrength,
        fx: Double, fy: Double, fz: Double,
        location: Point3D
    ) -> SignalStrength {
        
        // Interpolate each band separately
        var interpolatedBands: [FrequencyBand: Double] = [:]
        
        let allBands = Set([c000, c001, c010, c011, c100, c101, c110, c111].flatMap { $0.bands.keys })
        
        for band in allBands {
            let v000 = c000.bands[band] ?? -200.0
            let v001 = c001.bands[band] ?? -200.0
            let v010 = c010.bands[band] ?? -200.0
            let v011 = c011.bands[band] ?? -200.0
            let v100 = c100.bands[band] ?? -200.0
            let v101 = c101.bands[band] ?? -200.0
            let v110 = c110.bands[band] ?? -200.0
            let v111 = c111.bands[band] ?? -200.0
            
            // Trilinear interpolation
            let v00 = v000 * (1 - fx) + v100 * fx
            let v01 = v001 * (1 - fx) + v101 * fx
            let v10 = v010 * (1 - fx) + v110 * fx
            let v11 = v011 * (1 - fx) + v111 * fx
            
            let v0 = v00 * (1 - fy) + v10 * fy
            let v1 = v01 * (1 - fy) + v11 * fy
            
            let interpolatedValue = v0 * (1 - fz) + v1 * fz
            interpolatedBands[band] = interpolatedValue
        }
        
        // Find dominant band
        let dominantBand = interpolatedBands.max(by: { $0.value < $1.value })?.key ?? .band5GHz
        let dominantSignal = interpolatedBands[dominantBand] ?? -200.0
        
        return SignalStrength(
            location: location,
            bands: interpolatedBands,
            quality: SignalQuality.fromRSSI(dominantSignal),
            dominantBand: dominantBand
        )
    }
    
    private func mergeAdjacentBounds(_ bounds: [BoundingBox]) -> [BoundingBox] {
        // Simplified merge - just return original bounds
        // A proper implementation would merge adjacent/overlapping boxes
        return bounds
    }
}

/// Signal strength at a specific location
public struct SignalStrength: Codable {
    public let location: Point3D
    public let bands: [FrequencyBand: Double] // RSSI per band
    public let quality: SignalQuality
    public let dominantBand: FrequencyBand
    
    public init(
        location: Point3D,
        bands: [FrequencyBand: Double],
        quality: SignalQuality,
        dominantBand: FrequencyBand
    ) {
        self.location = location
        self.bands = bands
        self.quality = quality
        self.dominantBand = dominantBand
    }
    
    /// Get effective range for this signal strength
    public func effectiveRange() -> Double {
        let dominantRSSI = bands[dominantBand] ?? -200.0
        
        // Rough estimation based on signal strength
        switch dominantRSSI {
        case -50...:
            return 15.0 // Strong signal, good range
        case -60..<(-50):
            return 10.0 // Good signal
        case -70..<(-60):
            return 7.0  // Fair signal
        case -80..<(-70):
            return 4.0  // Poor signal
        default:
            return 1.0  // Very weak signal
        }
    }
    
    /// Check if signal is adequate for backhaul
    public func isAdequateForBackhaul() -> Bool {
        let dominantRSSI = bands[dominantBand] ?? -200.0
        return dominantRSSI >= -65.0
    }
    
    public static let zero = SignalStrength(
        location: Point3D.zero,
        bands: [:],
        quality: .unusable,
        dominantBand: .band5GHz
    )
}

// MARK: - Utility Extensions

extension Double {
    /// Clamp value to a range
    func clamped(to range: ClosedRange<Double>) -> Double {
        return Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}