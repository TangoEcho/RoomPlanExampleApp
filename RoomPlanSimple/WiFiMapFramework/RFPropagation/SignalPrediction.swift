import Foundation

/// Advanced signal strength prediction algorithms for WiFi network planning
public class SignalPredictor {
    
    // MARK: - Properties
    
    private let coverageEngine: CoverageEngine
    private let propagationModels: PropagationModels.Type
    private let predictionCache: PredictionCache
    
    // MARK: - Configuration
    
    public struct Configuration {
        public let signalThresholds: SignalThresholds
        public let predictionAccuracy: PredictionAccuracy
        public let coverageRequirements: CoverageRequirements
        public let optimizationWeights: OptimizationWeights
        
        public init(
            signalThresholds: SignalThresholds = .default,
            predictionAccuracy: PredictionAccuracy = .balanced,
            coverageRequirements: CoverageRequirements = .residential,
            optimizationWeights: OptimizationWeights = .default
        ) {
            self.signalThresholds = signalThresholds
            self.predictionAccuracy = predictionAccuracy
            self.coverageRequirements = coverageRequirements
            self.optimizationWeights = optimizationWeights
        }
        
        public static let `default` = Configuration()
    }
    
    private let configuration: Configuration
    
    // MARK: - Initialization
    
    public init(
        coverageEngine: CoverageEngine,
        configuration: Configuration = .default
    ) {
        self.coverageEngine = coverageEngine
        self.propagationModels = PropagationModels.self
        self.configuration = configuration
        self.predictionCache = PredictionCache(maxSize: 1000)
    }
    
    // MARK: - Signal Strength Prediction
    
    /// Predict signal strength at a specific location
    /// - Parameters:
    ///   - location: 3D point where to predict signal
    ///   - transmitters: Array of RF transmitters
    ///   - room: Room environment
    ///   - frequencies: Frequencies to analyze
    /// - Returns: Comprehensive signal prediction
    public func predictSignalStrength(
        at location: Point3D,
        from transmitters: [RFTransmitter],
        in room: RoomModel,
        frequencies: [Double] = [2400, 5500, 6000]
    ) async throws -> SignalPrediction {
        
        let cacheKey = generatePredictionKey(location: location, transmitters: transmitters, room: room)
        if let cached = predictionCache.get(key: cacheKey) {
            return cached
        }
        
        // Calculate coverage at the specific location
        let analysisGrid = [GridPoint(location: location, gridIndices: (0, 0, 0))]
        let coverageResults = try await coverageEngine.calculateGridCoverage(
            grid: analysisGrid,
            room: room,
            transmitters: transmitters,
            frequencies: frequencies,
            environment: .default
        )
        
        guard let signalStrength = coverageResults[analysisGrid[0]] else {
            throw SignalPredictionError.calculationFailed
        }
        
        // Enhanced prediction analysis
        let prediction = await analyzePrediction(
            signalStrength: signalStrength,
            location: location,
            transmitters: transmitters,
            room: room,
            frequencies: frequencies
        )
        
        predictionCache.store(prediction, for: cacheKey)
        return prediction
    }
    
    /// Predict coverage improvement with additional transmitter
    /// - Parameters:
    ///   - baseline: Current transmitter configuration
    ///   - candidate: Candidate transmitter to add
    ///   - room: Room environment
    ///   - floors: Optional multi-floor model
    /// - Returns: Coverage improvement prediction
    public func predictCoverageImprovement(
        baseline: [RFTransmitter],
        addingTransmitter candidate: RFTransmitter,
        in room: RoomModel,
        floors: [FloorModel]? = nil
    ) async throws -> CoverageImprovementPrediction {
        
        let frequencies = [2400.0, 5500.0, 6000.0] // WiFi 7 representative frequencies
        
        // Calculate baseline coverage
        let baselineCoverage = try await coverageEngine.calculateCoverage(
            room: room,
            transmitters: baseline,
            frequencies: frequencies,
            floors: floors
        )
        
        // Calculate improved coverage
        let improvedTransmitters = baseline + [candidate]
        let improvedCoverage = try await coverageEngine.calculateCoverage(
            room: room,
            transmitters: improvedTransmitters,
            frequencies: frequencies,
            floors: floors
        )
        
        // Analyze improvement
        let improvement = coverageEngine.analyzeCoverageImprovement(
            baseline: baselineCoverage,
            improved: improvedCoverage,
            room: room
        )
        
        // Calculate detailed metrics
        let detailedAnalysis = await analyzeDetailedImprovement(
            baseline: baselineCoverage,
            improved: improvedCoverage,
            candidate: candidate,
            room: room
        )
        
        return CoverageImprovementPrediction(
            baselineImprovement: improvement,
            detailedAnalysis: detailedAnalysis,
            candidate: candidate,
            costBenefitRatio: calculateCostBenefitRatio(improvement: improvement),
            recommendationConfidence: calculateConfidence(improvement: improvement)
        )
    }
    
    /// Find optimal transmitter placement locations
    /// - Parameters:
    ///   - room: Room environment
    ///   - candidateLocations: Potential placement locations
    ///   - objective: Optimization objective
    /// - Returns: Ranked placement recommendations
    public func findOptimalPlacement(
        in room: RoomModel,
        candidateLocations: [Point3D],
        objective: OptimizationObjective = .maxCoverage
    ) async throws -> [PlacementRecommendation] {
        
        var recommendations: [PlacementRecommendation] = []
        
        for location in candidateLocations {
            let transmitter = createStandardTransmitter(at: location)
            
            let prediction = try await predictSignalStrength(
                at: location,
                from: [transmitter],
                in: room
            )
            
            let score = calculatePlacementScore(
                prediction: prediction,
                location: location,
                room: room,
                objective: objective
            )
            
            recommendations.append(PlacementRecommendation(
                location: location,
                transmitter: transmitter,
                prediction: prediction,
                score: score,
                reasoning: generateRecommendationReasoning(prediction: prediction, location: location)
            ))
        }
        
        // Sort by score (highest first)
        return recommendations.sorted { $0.score > $1.score }
    }
    
    /// Predict signal quality and performance characteristics
    /// - Parameters:
    ///   - signalStrength: Raw signal strength measurements
    ///   - environment: RF environment conditions
    /// - Returns: Quality and performance prediction
    public func predictSignalQuality(
        signalStrength: SignalStrength,
        environment: RFEnvironment
    ) -> SignalQualityPrediction {
        
        let snrEstimate = estimateSignalToNoiseRatio(signalStrength: signalStrength, environment: environment)
        let throughputEstimate = estimateThroughput(signalStrength: signalStrength, snr: snrEstimate)
        let reliabilityScore = calculateReliabilityScore(signalStrength: signalStrength)
        let interferenceRisk = assessInterferenceRisk(signalStrength: signalStrength, environment: environment)
        
        return SignalQualityPrediction(
            signalToNoiseRatio: snrEstimate,
            estimatedThroughput: throughputEstimate,
            reliabilityScore: reliabilityScore,
            interferenceRisk: interferenceRisk,
            overallQuality: calculateOverallQuality(
                snr: snrEstimate,
                throughput: throughputEstimate,
                reliability: reliabilityScore
            )
        )
    }
    
    // MARK: - Private Analysis Methods
    
    private func analyzePrediction(
        signalStrength: SignalStrength,
        location: Point3D,
        transmitters: [RFTransmitter],
        room: RoomModel,
        frequencies: [Double]
    ) async -> SignalPrediction {
        
        // Analyze signal characteristics per frequency band
        var bandAnalysis: [FrequencyBand: BandPrediction] = [:]
        
        for (band, power) in signalStrength.bands {
            let frequency = band.rawValue
            let pathLoss = calculateTotalPathLoss(
                from: transmitters,
                to: location,
                frequency: frequency,
                room: room
            )
            
            let fadeMargin = calculateFadeMargin(signalPower: power, pathLoss: pathLoss)
            let coverageProbability = calculateCoverageProbability(signalPower: power, band: band)
            
            bandAnalysis[band] = BandPrediction(
                frequency: frequency,
                signalPower: power,
                pathLoss: pathLoss,
                fadeMargin: fadeMargin,
                coverageProbability: coverageProbability,
                quality: SignalQuality.fromRSSI(power)
            )
        }
        
        // Overall prediction metrics
        let dominantBand = signalStrength.dominantBand
        let overallQuality = signalStrength.quality
        let confidence = calculatePredictionConfidence(signalStrength: signalStrength, location: location)
        
        return SignalPrediction(
            location: location,
            overallStrength: signalStrength,
            bandAnalysis: bandAnalysis,
            dominantBand: dominantBand,
            overallQuality: overallQuality,
            confidence: confidence,
            timestamp: Date()
        )
    }
    
    private func analyzeDetailedImprovement(
        baseline: CoverageMap,
        improved: CoverageMap,
        candidate: RFTransmitter,
        room: RoomModel
    ) async -> DetailedImprovementAnalysis {
        
        // Calculate coverage statistics
        let baselineStats = calculateCoverageStatistics(coverageMap: baseline, room: room)
        let improvedStats = calculateCoverageStatistics(coverageMap: improved, room: room)
        
        // Find areas of improvement
        let improvedAreas = findImprovedAreas(baseline: baseline, improved: improved)
        let newlyCoveredAreas = findNewlyCoveredAreas(baseline: baseline, improved: improved)
        
        // Analyze placement effectiveness
        let placementEffectiveness = analyzePlacementEffectiveness(
            candidate: candidate,
            room: room,
            improvedAreas: improvedAreas
        )
        
        return DetailedImprovementAnalysis(
            baselineStats: baselineStats,
            improvedStats: improvedStats,
            improvedAreas: improvedAreas,
            newlyCoveredAreas: newlyCoveredAreas,
            placementEffectiveness: placementEffectiveness
        )
    }
    
    private func calculateTotalPathLoss(
        from transmitters: [RFTransmitter],
        to location: Point3D,
        frequency: Double,
        room: RoomModel
    ) -> Double {
        
        var minPathLoss = Double.infinity
        
        for transmitter in transmitters {
            let distance = transmitter.location.distance(to: location)
            let obstacles = room.getObstaclesBetween(transmitter.location, location)
            
            var pathLoss = PropagationModels.freeSpacePathLoss(distance: distance, frequency: frequency)
            
            // Add obstacle losses
            for obstacle in obstacles {
                pathLoss += obstacle.rfAttenuation(frequency: frequency)
            }
            
            minPathLoss = min(minPathLoss, pathLoss)
        }
        
        return minPathLoss == Double.infinity ? 200.0 : minPathLoss
    }
    
    private func calculateFadeMargin(signalPower: Double, pathLoss: Double) -> Double {
        let threshold = configuration.signalThresholds.minimumUsable
        return signalPower - threshold
    }
    
    private func calculateCoverageProbability(signalPower: Double, band: FrequencyBand) -> Double {
        let threshold = configuration.signalThresholds.forBand(band)
        let margin = signalPower - threshold
        
        // Probability based on fade margin using log-normal distribution
        let sigma = 8.0 // Standard deviation for indoor environments
        return 0.5 * (1 + erf(margin / (sigma * sqrt(2))))
    }
    
    private func calculatePredictionConfidence(
        signalStrength: SignalStrength,
        location: Point3D
    ) -> Double {
        // Base confidence on signal strength and number of bands
        let strengthConfidence = min(1.0, max(0.0, (signalStrength.bands.values.max() ?? -100.0 + 100.0) / 50.0))
        let bandDiversityConfidence = Double(signalStrength.bands.count) / 3.0
        
        return (strengthConfidence + bandDiversityConfidence) / 2.0
    }
    
    private func calculatePlacementScore(
        prediction: SignalPrediction,
        location: Point3D,
        room: RoomModel,
        objective: OptimizationObjective
    ) -> Double {
        
        switch objective {
        case .maxCoverage:
            return prediction.overallQuality.score * prediction.confidence
            
        case .minInterference:
            let interferenceScore = 1.0 - assessLocationInterference(location: location, room: room)
            return prediction.overallQuality.score * interferenceScore
            
        case .balanced:
            let coverageScore = prediction.overallQuality.score
            let interferenceScore = 1.0 - assessLocationInterference(location: location, room: room)
            let accessibilityScore = assessLocationAccessibility(location: location, room: room)
            
            return (coverageScore * configuration.optimizationWeights.coverage +
                   interferenceScore * configuration.optimizationWeights.interference +
                   accessibilityScore * configuration.optimizationWeights.accessibility) / 3.0
        }
    }
    
    private func estimateSignalToNoiseRatio(
        signalStrength: SignalStrength,
        environment: RFEnvironment
    ) -> Double {
        let dominantSignal = signalStrength.bands[signalStrength.dominantBand] ?? -100.0
        let noiseFloor = estimateNoiseFloor(environment: environment, band: signalStrength.dominantBand)
        return dominantSignal - noiseFloor
    }
    
    private func estimateThroughput(signalStrength: SignalStrength, snr: Double) -> ThroughputEstimate {
        let maxThroughput: Double
        
        // WiFi 7 theoretical maximums per band
        switch signalStrength.dominantBand {
        case .band2_4GHz: maxThroughput = 688 // Mbps
        case .band5GHz: maxThroughput = 2882 // Mbps  
        case .band6GHz: maxThroughput = 2882 // Mbps
        }
        
        // SNR-based throughput estimation using Shannon's theorem approximation
        let efficiency = calculateSpectralEfficiency(snr: snr)
        let estimatedThroughput = maxThroughput * efficiency
        
        return ThroughputEstimate(
            theoretical: maxThroughput,
            estimated: estimatedThroughput,
            efficiency: efficiency
        )
    }
    
    private func calculateSpectralEfficiency(snr: Double) -> Double {
        // Approximate WiFi spectral efficiency based on SNR
        switch snr {
        case let x where x >= 35: return 0.9  // Very high SNR
        case let x where x >= 25: return 0.75 // High SNR
        case let x where x >= 15: return 0.6  // Good SNR
        case let x where x >= 10: return 0.4  // Acceptable SNR
        case let x where x >= 5:  return 0.2  // Poor SNR
        default: return 0.05                   // Very poor SNR
        }
    }
    
    private func estimateNoiseFloor(environment: RFEnvironment, band: FrequencyBand) -> Double {
        // Typical noise floors for different environments and bands
        let baseNoiseFloor: Double
        
        switch band {
        case .band2_4GHz: baseNoiseFloor = -95.0 // More interference in 2.4GHz
        case .band5GHz: baseNoiseFloor = -100.0  // Cleaner 5GHz band
        case .band6GHz: baseNoiseFloor = -102.0  // Cleanest 6GHz band
        }
        
        // Adjust for environment clutter
        let clutterAdjustment = environment.clutterDensity * 5.0
        
        return baseNoiseFloor + clutterAdjustment
    }
    
    // MARK: - Helper Methods
    
    private func createStandardTransmitter(at location: Point3D) -> RFTransmitter {
        return RFTransmitter(
            location: location,
            power: [
                .band2_4GHz: 20.0, // dBm
                .band5GHz: 23.0,   // dBm
                .band6GHz: 23.0    // dBm
            ],
            antennaGain: [
                .band2_4GHz: 2.0,  // dBi
                .band5GHz: 3.0,    // dBi
                .band6GHz: 3.0     // dBi
            ],
            antennaPattern: .omnidirectional
        )
    }
    
    private func calculateCostBenefitRatio(improvement: CoverageImprovementAnalysis) -> Double {
        // Simplified cost-benefit calculation
        let benefit = improvement.absoluteImprovement
        let estimatedCost = 1.0 // Normalized unit cost
        return benefit / estimatedCost
    }
    
    private func calculateConfidence(improvement: CoverageImprovementAnalysis) -> Double {
        // Confidence based on improvement magnitude and consistency
        let magnitude = min(1.0, improvement.absoluteImprovement / 0.3) // 30% improvement = max confidence
        let consistency = improvement.isSignificant ? 1.0 : 0.5
        return (magnitude + consistency) / 2.0
    }
    
    private func generatePredictionKey(
        location: Point3D,
        transmitters: [RFTransmitter],
        room: RoomModel
    ) -> String {
        let locationKey = "\(location.x)_\(location.y)_\(location.z)"
        let txKey = transmitters.map { "\($0.location)" }.joined(separator: "_")
        let roomKey = room.id.uuidString
        return "\(locationKey)_\(txKey)_\(roomKey)"
    }
    
    // MARK: - Placeholder implementations for complex algorithms
    
    private func calculateCoverageStatistics(coverageMap: CoverageMap, room: RoomModel) -> CoverageStatistics {
        // Implementation would analyze coverage map statistics
        return CoverageStatistics(
            totalArea: room.bounds.area,
            coveredArea: room.bounds.area * 0.8, // Placeholder
            averageSignalStrength: -65.0,
            signalUniformity: 0.7
        )
    }
    
    private func findImprovedAreas(baseline: CoverageMap, improved: CoverageMap) -> [ImprovedArea] {
        // Implementation would compare coverage maps and identify improved regions
        return []
    }
    
    private func findNewlyCoveredAreas(baseline: CoverageMap, improved: CoverageMap) -> [CoveredArea] {
        // Implementation would identify newly covered areas
        return []
    }
    
    private func analyzePlacementEffectiveness(
        candidate: RFTransmitter,
        room: RoomModel,
        improvedAreas: [ImprovedArea]
    ) -> PlacementEffectiveness {
        // Implementation would analyze how effectively the placement improves coverage
        return PlacementEffectiveness(
            coverageRadius: 15.0, // meters
            interferenceLevel: 0.2,
            accessibilityScore: 0.8
        )
    }
    
    private func assessLocationInterference(location: Point3D, room: RoomModel) -> Double {
        // Implementation would assess potential interference at location
        return 0.3 // Placeholder
    }
    
    private func assessLocationAccessibility(location: Point3D, room: RoomModel) -> Double {
        // Implementation would assess how accessible the location is for installation
        return 0.8 // Placeholder
    }
    
    private func generateRecommendationReasoning(
        prediction: SignalPrediction,
        location: Point3D
    ) -> String {
        return "Optimal location provides \(prediction.overallQuality) coverage with \(Int(prediction.confidence * 100))% confidence"
    }
    
    private func calculateOverallQuality(snr: Double, throughput: ThroughputEstimate, reliability: Double) -> SignalQuality {
        let combinedScore = (snr/40.0 + throughput.efficiency + reliability) / 3.0
        return SignalQuality.fromScore(combinedScore)
    }
    
    private func calculateReliabilityScore(signalStrength: SignalStrength) -> Double {
        // Base reliability on signal strength stability across bands
        let bandVariance = calculateBandVariance(signalStrength.bands)
        return max(0.0, 1.0 - bandVariance / 20.0)
    }
    
    private func calculateBandVariance(_ bands: [FrequencyBand: Double]) -> Double {
        let values = Array(bands.values)
        guard values.count > 1 else { return 0.0 }
        
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return sqrt(variance)
    }
    
    private func assessInterferenceRisk(signalStrength: SignalStrength, environment: RFEnvironment) -> InterferenceRisk {
        let clutterFactor = environment.clutterDensity
        let bandCongestion = assessBandCongestion(signalStrength.dominantBand)
        
        let riskScore = (clutterFactor + bandCongestion) / 2.0
        
        switch riskScore {
        case 0.0..<0.3: return .low
        case 0.3..<0.7: return .medium
        default: return .high
        }
    }
    
    private func assessBandCongestion(_ band: FrequencyBand) -> Double {
        // Implementation would assess typical congestion levels per band
        switch band {
        case .band2_4GHz: return 0.8 // High congestion
        case .band5GHz: return 0.4   // Medium congestion
        case .band6GHz: return 0.1   // Low congestion
        }
    }
}

// MARK: - Supporting Types

/// Comprehensive signal prediction result
public struct SignalPrediction {
    public let location: Point3D
    public let overallStrength: SignalStrength
    public let bandAnalysis: [FrequencyBand: BandPrediction]
    public let dominantBand: FrequencyBand
    public let overallQuality: SignalQuality
    public let confidence: Double // 0-1
    public let timestamp: Date
}

/// Prediction analysis for a specific frequency band
public struct BandPrediction {
    public let frequency: Double // MHz
    public let signalPower: Double // dBm
    public let pathLoss: Double // dB
    public let fadeMargin: Double // dB
    public let coverageProbability: Double // 0-1
    public let quality: SignalQuality
}

/// Coverage improvement prediction with detailed analysis
public struct CoverageImprovementPrediction {
    public let baselineImprovement: CoverageImprovementAnalysis
    public let detailedAnalysis: DetailedImprovementAnalysis
    public let candidate: RFTransmitter
    public let costBenefitRatio: Double
    public let recommendationConfidence: Double // 0-1
}

/// Detailed analysis of coverage improvement
public struct DetailedImprovementAnalysis {
    public let baselineStats: CoverageStatistics
    public let improvedStats: CoverageStatistics
    public let improvedAreas: [ImprovedArea]
    public let newlyCoveredAreas: [CoveredArea]
    public let placementEffectiveness: PlacementEffectiveness
}

/// Signal quality and performance prediction
public struct SignalQualityPrediction {
    public let signalToNoiseRatio: Double // dB
    public let estimatedThroughput: ThroughputEstimate
    public let reliabilityScore: Double // 0-1
    public let interferenceRisk: InterferenceRisk
    public let overallQuality: SignalQuality
}

/// Throughput estimation
public struct ThroughputEstimate {
    public let theoretical: Double // Mbps
    public let estimated: Double // Mbps
    public let efficiency: Double // 0-1
}

/// Placement recommendation with scoring
public struct PlacementRecommendation {
    public let location: Point3D
    public let transmitter: RFTransmitter
    public let prediction: SignalPrediction
    public let score: Double // 0-1
    public let reasoning: String
}

// MARK: - Configuration Types

/// Signal threshold configuration for different quality levels
public struct SignalThresholds {
    public let excellent: Double // dBm
    public let good: Double // dBm
    public let acceptable: Double // dBm
    public let minimumUsable: Double // dBm
    
    public init(excellent: Double = -50, good: Double = -60, acceptable: Double = -70, minimumUsable: Double = -80) {
        self.excellent = excellent
        self.good = good
        self.acceptable = acceptable
        self.minimumUsable = minimumUsable
    }
    
    public static let `default` = SignalThresholds()
    
    public func forBand(_ band: FrequencyBand) -> Double {
        // Adjust thresholds based on band characteristics
        switch band {
        case .band2_4GHz: return acceptable - 2.0 // Slightly more tolerant for 2.4GHz
        case .band5GHz: return acceptable
        case .band6GHz: return acceptable + 2.0 // Slightly more demanding for 6GHz
        }
    }
}

/// Prediction accuracy configuration
public enum PredictionAccuracy {
    case fast      // Lower accuracy, faster computation
    case balanced  // Balanced accuracy and speed
    case precise   // Higher accuracy, slower computation
}

/// Coverage requirements for different scenarios
public struct CoverageRequirements {
    public let minimumCoverage: Double // 0-1, percentage of area
    public let targetSignalLevel: Double // dBm
    public let reliabilityRequirement: Double // 0-1
    
    public init(minimumCoverage: Double = 0.9, targetSignalLevel: Double = -65, reliabilityRequirement: Double = 0.95) {
        self.minimumCoverage = minimumCoverage
        self.targetSignalLevel = targetSignalLevel
        self.reliabilityRequirement = reliabilityRequirement
    }
    
    public static let residential = CoverageRequirements(minimumCoverage: 0.9, targetSignalLevel: -65, reliabilityRequirement: 0.9)
    public static let enterprise = CoverageRequirements(minimumCoverage: 0.95, targetSignalLevel: -60, reliabilityRequirement: 0.99)
}

/// Optimization weights for different objectives
public struct OptimizationWeights {
    public let coverage: Double
    public let interference: Double
    public let accessibility: Double
    
    public init(coverage: Double = 0.5, interference: Double = 0.3, accessibility: Double = 0.2) {
        self.coverage = coverage
        self.interference = interference
        self.accessibility = accessibility
    }
    
    public static let `default` = OptimizationWeights()
}

/// Optimization objective
public enum OptimizationObjective {
    case maxCoverage
    case minInterference
    case balanced
}

// MARK: - Analysis Types

public struct CoverageStatistics {
    public let totalArea: Double // m²
    public let coveredArea: Double // m²
    public let averageSignalStrength: Double // dBm
    public let signalUniformity: Double // 0-1
}

public struct ImprovedArea {
    public let bounds: BoundingBox
    public let improvementAmount: Double // dB
    public let areaSize: Double // m²
}

public struct CoveredArea {
    public let bounds: BoundingBox
    public let signalLevel: Double // dBm
    public let areaSize: Double // m²
}

public struct PlacementEffectiveness {
    public let coverageRadius: Double // meters
    public let interferenceLevel: Double // 0-1
    public let accessibilityScore: Double // 0-1
}

public enum InterferenceRisk {
    case low
    case medium
    case high
}

// MARK: - Errors

public enum SignalPredictionError: Error {
    case calculationFailed
    case insufficientData
    case invalidConfiguration
}

// MARK: - Caching

private class PredictionCache {
    private var cache: [String: SignalPrediction] = [:]
    private let maxSize: Int
    private let queue = DispatchQueue(label: "com.wifimap.prediction.cache", attributes: .concurrent)
    
    init(maxSize: Int) {
        self.maxSize = maxSize
    }
    
    func get(key: String) -> SignalPrediction? {
        return queue.sync {
            return cache[key]
        }
    }
    
    func store(_ prediction: SignalPrediction, for key: String) {
        queue.async(flags: .barrier) {
            if self.cache.count >= self.maxSize {
                // Simple LRU: remove oldest entries
                let keysToRemove = Array(self.cache.keys.prefix(self.maxSize / 4))
                keysToRemove.forEach { self.cache.removeValue(forKey: $0) }
            }
            self.cache[key] = prediction
        }
    }
}

// MARK: - Extensions

extension SignalQuality {
    static func fromScore(_ score: Double) -> SignalQuality {
        switch score {
        case 0.8...1.0: return .excellent
        case 0.6..<0.8: return .good
        case 0.4..<0.6: return .fair
        default: return .poor
        }
    }
}