import Foundation

/// High-performance coverage calculation engine for WiFi signal prediction
public class CoverageEngine {
    
    // MARK: - Properties
    
    private let propagationModels: PropagationModels.Type
    private let rayTracer: RayTracing
    private let gridResolution: Double
    private let processingQueue: DispatchQueue
    private let cache: CoverageCache
    
    // MARK: - Configuration
    
    public struct Configuration {
        public let gridResolution: Double
        public let maxProcessingThreads: Int
        public let enableCaching: Bool
        public let enableMultipath: Bool
        public let enableEnvironmentalCorrections: Bool
        public let rayTracingConfig: RayTracing.Configuration
        
        public init(
            gridResolution: Double = 0.5,
            maxProcessingThreads: Int = ProcessInfo.processInfo.processorCount,
            enableCaching: Bool = true,
            enableMultipath: Bool = true,
            enableEnvironmentalCorrections: Bool = false,
            rayTracingConfig: RayTracing.Configuration = .default
        ) {
            self.gridResolution = gridResolution
            self.maxProcessingThreads = maxProcessingThreads
            self.enableCaching = enableCaching
            self.enableMultipath = enableMultipath
            self.enableEnvironmentalCorrections = enableEnvironmentalCorrections
            self.rayTracingConfig = rayTracingConfig
        }
        
        public static let `default` = Configuration()
        public static let highAccuracy = Configuration(gridResolution: 0.25, enableMultipath: true)
        public static let fastProcessing = Configuration(gridResolution: 1.0, enableMultipath: false)
    }
    
    private let configuration: Configuration
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.propagationModels = PropagationModels.self
        self.rayTracer = RayTracing(
            maxReflections: configuration.rayTracingConfig.maxReflections,
            minSignalThreshold: configuration.rayTracingConfig.minSignalThreshold
        )
        self.gridResolution = configuration.gridResolution
        self.processingQueue = DispatchQueue(
            label: "com.wifimap.coverage",
            qos: .userInitiated,
            attributes: .concurrent
        )
        self.cache = CoverageCache(enabled: configuration.enableCaching)
    }
    
    // MARK: - Public Interface
    
    /// Calculate coverage grid for a room with given transmitters
    /// - Parameters:
    ///   - room: Room model with walls and obstacles
    ///   - transmitters: Array of RF transmitters
    ///   - frequencies: Frequencies to analyze (MHz)
    ///   - environment: Environmental parameters
    /// - Returns: Complete coverage map
    public func calculateCoverage(
        room: RoomModel,
        transmitters: [RFTransmitter],
        frequencies: [Double],
        environment: RFEnvironment = .default
    ) async throws -> CoverageMap {
        return try await calculateCoverage(
            room: room,
            transmitters: transmitters,
            frequencies: frequencies,
            environment: environment,
            floors: nil
        )
    }
    
    /// Enhanced coverage calculation with multi-floor support
    /// - Parameters:
    ///   - room: Primary room model
    ///   - transmitters: Array of RF transmitters
    ///   - frequencies: Frequencies to analyze (MHz)
    ///   - environment: Environmental parameters
    ///   - floors: Optional array of floor models for multi-floor analysis
    /// - Returns: Complete coverage map including inter-floor propagation
    public func calculateCoverage(
        room: RoomModel,
        transmitters: [RFTransmitter],
        frequencies: [Double],
        environment: RFEnvironment = .default,
        floors: [FloorModel]?
    ) async throws -> CoverageMap {
        
        let startTime = Date()
        
        // Check cache first
        let cacheKey = generateCacheKey(room: room, transmitters: transmitters, frequencies: frequencies)
        if let cachedResult = cache.getCachedCoverage(key: cacheKey) {
            return cachedResult
        }
        
        // Create analysis grid
        let analysisGrid = createAnalysisGrid(for: room.bounds)
        
        // Calculate coverage for each grid point
        let coverageResults = try await calculateGridCoverage(
            grid: analysisGrid,
            room: room,
            transmitters: transmitters,
            frequencies: frequencies,
            environment: environment,
            floors: floors
        )
        
        // Build coverage map
        let coverageMap = buildCoverageMap(
            from: coverageResults,
            bounds: room.bounds,
            gridResolution: gridResolution
        )
        
        // Cache result
        cache.storeCoverage(coverageMap, for: cacheKey)
        
        let processingTime = Date().timeIntervalSince(startTime)
        print("Coverage calculation completed in \(processingTime)s for \(analysisGrid.count) points")
        
        return coverageMap
    }
    
    /// Calculate coverage for a single transmitter (optimized)
    /// - Parameters:
    ///   - room: Room model
    ///   - transmitter: Single transmitter
    ///   - frequencies: Frequencies to analyze
    ///   - environment: Environmental parameters
    /// - Returns: Coverage map for single transmitter
    public func calculateSingleTransmitterCoverage(
        room: RoomModel,
        transmitter: RFTransmitter,
        frequencies: [Double],
        environment: RFEnvironment = .default
    ) async throws -> CoverageMap {
        
        return try await calculateCoverage(
            room: room,
            transmitters: [transmitter],
            frequencies: frequencies,
            environment: environment
        )
    }
    
    /// Calculate predicted coverage improvement with additional transmitter
    /// - Parameters:
    ///   - baselineCoverage: Current coverage map
    ///   - room: Room model
    ///   - newTransmitter: Proposed additional transmitter
    ///   - frequencies: Frequencies to analyze
    /// - Returns: Coverage improvement analysis
    public func calculateCoverageImprovement(
        baseline baselineCoverage: CoverageMap,
        room: RoomModel,
        addingTransmitter newTransmitter: RFTransmitter,
        frequencies: [Double]
    ) async throws -> CoverageImprovementAnalysis {
        
        // Calculate coverage with new transmitter
        let newTransmitterCoverage = try await calculateSingleTransmitterCoverage(
            room: room,
            transmitter: newTransmitter,
            frequencies: frequencies
        )
        
        // Combine with baseline
        let combinedCoverage = combineCoverageMaps(
            baseline: baselineCoverage,
            additional: newTransmitterCoverage
        )
        
        // Analyze improvement
        return analyzeCoverageImprovement(
            baseline: baselineCoverage,
            improved: combinedCoverage,
            room: room
        )
    }
    
    // MARK: - Grid Generation
    
    private func createAnalysisGrid(for bounds: BoundingBox) -> [GridPoint] {
        var gridPoints: [GridPoint] = []
        
        let xSteps = Int(ceil(bounds.size.x / gridResolution))
        let ySteps = Int(ceil(bounds.size.y / gridResolution))
        let zSteps = max(1, Int(ceil(bounds.size.z / (gridResolution * 2)))) // Fewer Z levels
        
        for x in 0..<xSteps {
            for y in 0..<ySteps {
                for z in 0..<zSteps {
                    let point = Point3D(
                        x: bounds.min.x + Double(x) * gridResolution + gridResolution / 2,
                        y: bounds.min.y + Double(y) * gridResolution + gridResolution / 2,
                        z: bounds.min.z + Double(z) * gridResolution * 2 + 1.0 // Start at 1m height
                    )
                    
                    // Only include points within room bounds
                    if bounds.contains(point) {
                        gridPoints.append(GridPoint(
                            location: point,
                            gridIndices: (x, y, z)
                        ))
                    }
                }
            }
        }
        
        return gridPoints
    }
    
    // MARK: - Coverage Calculation
    
    private func calculateGridCoverage(
        grid: [GridPoint],
        room: RoomModel,
        transmitters: [RFTransmitter],
        frequencies: [Double],
        environment: RFEnvironment,
        floors: [FloorModel]? = nil
    ) async throws -> [GridPoint: SignalStrength] {
        
        // Process grid points concurrently in batches and aggregate results
        return try await withThrowingTaskGroup(of: [(GridPoint, SignalStrength)].self) { group in
            var results: [GridPoint: SignalStrength] = [:]
            
            let batchSize = max(1, grid.count / configuration.maxProcessingThreads)
            let batches = grid.chunked(into: batchSize)
            
            for batch in batches {
                group.addTask {
                    return try await self.processBatch(
                        batch: batch,
                        room: room,
                        transmitters: transmitters,
                        frequencies: frequencies,
                        environment: environment,
                        floors: floors
                    )
                }
            }
            
            for try await batchResults in group {
                for (point, signal) in batchResults {
                    results[point] = signal
                }
            }
            
            return results
        }
    }
    
    private func processBatch(
        batch: [GridPoint],
        room: RoomModel,
        transmitters: [RFTransmitter],
        frequencies: [Double],
        environment: RFEnvironment,
        floors: [FloorModel]? = nil
    ) async throws -> [(GridPoint, SignalStrength)] {
        
        var batchResults: [(GridPoint, SignalStrength)] = []
        
        for gridPoint in batch {
            let signalStrength = try await calculatePointCoverage(
                point: gridPoint.location,
                room: room,
                transmitters: transmitters,
                frequencies: frequencies,
                environment: environment,
                floors: floors
            )
            batchResults.append((gridPoint, signalStrength))
        }
        
        return batchResults
    }
    
    private func calculatePointCoverage(
        point: Point3D,
        room: RoomModel,
        transmitters: [RFTransmitter],
        frequencies: [Double],
        environment: RFEnvironment,
        floors: [FloorModel]? = nil
    ) async throws -> SignalStrength {
        
        var bandSignals: [FrequencyBand: Double] = [:]
        
        for frequency in frequencies {
            let band = FrequencyBand.fromFrequency(frequency)
            var maxSignalForBand = -200.0 // Very weak initial value
            
            // Calculate signal from each transmitter
            for transmitter in transmitters {
                let signalFromTx = try await calculateSignalFromTransmitter(
                    transmitter: transmitter,
                    receiver: point,
                    frequency: frequency,
                    room: room,
                    environment: environment,
                    floors: floors
                )
                
                // Use maximum signal (dominant transmitter)
                maxSignalForBand = max(maxSignalForBand, signalFromTx)
            }
            
            // Apply environmental corrections if enabled
            if configuration.enableEnvironmentalCorrections {
                maxSignalForBand = applyEnvironmentalCorrections(
                    signal: maxSignalForBand,
                    frequency: frequency,
                    environment: environment
                )
            }
            
            bandSignals[band] = maxSignalForBand
        }
        
        // Determine dominant band and overall quality
        let dominantBand = bandSignals.max(by: { $0.value < $1.value })?.key ?? .band5GHz
        let dominantSignal = bandSignals[dominantBand] ?? -200.0
        
        return SignalStrength(
            location: point,
            bands: bandSignals,
            quality: SignalQuality.fromRSSI(dominantSignal),
            dominantBand: dominantBand
        )
    }
    
    private func calculateSignalFromTransmitter(
        transmitter: RFTransmitter,
        receiver: Point3D,
        frequency: Double,
        room: RoomModel,
        environment: RFEnvironment,
        floors: [FloorModel]? = nil
    ) async throws -> Double {
        
        if configuration.enableMultipath {
            // Use ray tracing for multipath analysis
            let rayPaths = rayTracer.traceRays(
                from: transmitter,
                to: receiver,
                through: room,
                at: frequency,
                floors: floors
            )
            
            if !rayPaths.isEmpty {
                // Combine multipath signals
                let multipathResult = combineMultipathSignals(paths: rayPaths)
                return multipathResult.totalSignalStrength
            }
        }
        
        // Fallback to simple path loss calculation
        return calculateSimplePathLoss(
            from: transmitter,
            to: receiver,
            frequency: frequency,
            room: room,
            environment: environment
        )
    }
    
    private func calculateSimplePathLoss(
        from transmitter: RFTransmitter,
        to receiver: Point3D,
        frequency: Double,
        room: RoomModel,
        environment: RFEnvironment
    ) -> Double {
        
        let distance = transmitter.location.distance(to: receiver)
        let direction = (receiver - transmitter.location).normalized
        
        // Base path loss
        let pathLossModel = PropagationModels.ITUIndoorModel(environment: environment.type)
        var totalLoss = pathLossModel.pathLoss(distance: distance, frequency: frequency)
        
        // Add obstacle losses
        let obstacles = room.getObstaclesBetween(transmitter.location, receiver)
        for obstacle in obstacles {
            totalLoss += obstacle.rfAttenuation(frequency: frequency)
        }
        
        // Calculate received power
        let txPower = transmitter.effectiveTransmitPower(direction: direction, frequency: frequency)
        return txPower - totalLoss
    }
    
    // MARK: - Signal Processing
    
    private func combineMultipathSignals(paths: [RayPath]) -> MultipathResult {
        guard !paths.isEmpty else {
            return MultipathResult(
                totalSignalStrength: -200.0,
                dominantPath: nil,
                pathCount: 0,
                fadingMargin: 0.0
            )
        }
        
        // Convert to linear power scale
        let linearPowers = paths.map { pow(10, $0.receivedPower / 10.0) }
        let totalLinearPower = linearPowers.reduce(0, +)
        
        // Convert back to dB
        let totalSignalStrength = 10 * log10(totalLinearPower)
        
        // Find dominant path
        let dominantPath = paths.max(by: { $0.receivedPower < $1.receivedPower })
        
        // Calculate fading margin
        let fadingMargin = totalSignalStrength - (dominantPath?.receivedPower ?? totalSignalStrength)
        
        return MultipathResult(
            totalSignalStrength: totalSignalStrength,
            dominantPath: dominantPath,
            pathCount: paths.count,
            fadingMargin: fadingMargin
        )
    }
    
    private func applyEnvironmentalCorrections(
        signal: Double,
        frequency: Double,
        environment: RFEnvironment
    ) -> Double {
        
        var correctedSignal = signal
        
        // Apply humidity correction
        if let humidity = environment.humidity {
            correctedSignal = PropagationModels.EnvironmentalCorrections.humidityCorrection(
                pathLoss: -correctedSignal, // Convert to path loss
                humidity: humidity,
                frequency: frequency
            )
            correctedSignal = -correctedSignal // Convert back to signal strength
        }
        
        // Apply temperature correction
        if let temperature = environment.temperature {
            correctedSignal = PropagationModels.EnvironmentalCorrections.temperatureCorrection(
                pathLoss: -correctedSignal,
                temperature: temperature
            )
            correctedSignal = -correctedSignal
        }
        
        // Apply clutter correction
        correctedSignal = PropagationModels.EnvironmentalCorrections.clutterCorrection(
            pathLoss: -correctedSignal,
            clutterDensity: environment.clutterDensity,
            frequency: frequency
        )
        correctedSignal = -correctedSignal
        
        return correctedSignal
    }
    
    // MARK: - Coverage Map Construction
    
    private func buildCoverageMap(
        from results: [GridPoint: SignalStrength],
        bounds: BoundingBox,
        gridResolution: Double
    ) -> CoverageMap {
        
        // Determine grid dimensions
        let xSize = Int(ceil(bounds.size.x / gridResolution))
        let ySize = Int(ceil(bounds.size.y / gridResolution))
        let zSize = max(1, Int(ceil(bounds.size.z / (gridResolution * 2))))
        
        // Initialize 3D grid
        var signalGrid: [[[SignalStrength]]] = Array(
            repeating: Array(
                repeating: Array(
                    repeating: SignalStrength.zero,
                    count: zSize
                ),
                count: ySize
            ),
            count: xSize
        )
        
        // Fill grid with results
        for (gridPoint, signalStrength) in results {
            let indices = gridPoint.gridIndices
            if indices.x < xSize && indices.y < ySize && indices.z < zSize {
                signalGrid[indices.x][indices.y][indices.z] = signalStrength
            }
        }
        
        return CoverageMap(
            gridResolution: gridResolution,
            bounds: bounds,
            signalGrid: signalGrid,
            timestamp: Date()
        )
    }
    
    // MARK: - Coverage Analysis
    
    private func combineCoverageMaps(baseline: CoverageMap, additional: CoverageMap) -> CoverageMap {
        // Ensure compatible grids
        guard baseline.bounds == additional.bounds,
              baseline.gridResolution == additional.gridResolution else {
            return baseline // Return baseline if incompatible
        }
        
        let xSize = baseline.signalGrid.count
        let ySize = baseline.signalGrid[0].count
        let zSize = baseline.signalGrid[0][0].count
        
        var combinedGrid: [[[SignalStrength]]] = Array(
            repeating: Array(
                repeating: Array(
                    repeating: SignalStrength.zero,
                    count: zSize
                ),
                count: ySize
            ),
            count: xSize
        )
        
        // Combine signals at each grid point
        for x in 0..<xSize {
            for y in 0..<ySize {
                for z in 0..<zSize {
                    let baselineSignal = baseline.signalGrid[x][y][z]
                    let additionalSignal = additional.signalGrid[x][y][z]
                    
                    combinedGrid[x][y][z] = combineSignalStrengths(
                        baselineSignal,
                        additionalSignal
                    )
                }
            }
        }
        
        return CoverageMap(
            gridResolution: baseline.gridResolution,
            bounds: baseline.bounds,
            signalGrid: combinedGrid,
            timestamp: Date()
        )
    }
    
    private func combineSignalStrengths(
        _ signal1: SignalStrength,
        _ signal2: SignalStrength
    ) -> SignalStrength {
        
        var combinedBands: [FrequencyBand: Double] = [:]
        
        // Get all bands from both signals
        let allBands = Set(signal1.bands.keys).union(Set(signal2.bands.keys))
        
        for band in allBands {
            let power1 = signal1.bands[band] ?? -200.0
            let power2 = signal2.bands[band] ?? -200.0
            
            // Convert to linear, add, convert back to dB
            let linear1 = pow(10, power1 / 10.0)
            let linear2 = pow(10, power2 / 10.0)
            let combinedLinear = linear1 + linear2
            let combinedPower = 10 * log10(combinedLinear)
            
            combinedBands[band] = combinedPower
        }
        
        // Determine new dominant band
        let dominantBand = combinedBands.max(by: { $0.value < $1.value })?.key ?? .band5GHz
        let dominantSignal = combinedBands[dominantBand] ?? -200.0
        
        return SignalStrength(
            location: signal1.location, // Use first signal's location
            bands: combinedBands,
            quality: SignalQuality.fromRSSI(dominantSignal),
            dominantBand: dominantBand
        )
    }
    
    private func analyzeCoverageImprovement(
        baseline: CoverageMap,
        improved: CoverageMap,
        room: RoomModel
    ) -> CoverageImprovementAnalysis {
        
        let thresholds = [-70.0, -65.0, -60.0] // Good, very good, excellent
        var improvementByThreshold: [Double: Double] = [:]
        var newlyServedArea = 0.0
        
        let gridArea = baseline.gridResolution * baseline.gridResolution
        
        for threshold in thresholds {
            let baselineCoverage = baseline.coveragePercentage(threshold: threshold)
            let improvedCoverage = improved.coveragePercentage(threshold: threshold)
            let improvement = improvedCoverage - baselineCoverage
            improvementByThreshold[threshold] = improvement
            
            if threshold == -70.0 { // Use -70dB as the standard for "newly served"
                newlyServedArea = improvement * room.bounds.size.x * room.bounds.size.y
            }
        }
        
        let overallImprovement = improvementByThreshold[-70.0] ?? 0.0
        let improvementFactor = baseline.coveragePercentage(threshold: -70.0) > 0 ? 
            improved.coveragePercentage(threshold: -70.0) / baseline.coveragePercentage(threshold: -70.0) : 1.0
        
        return CoverageImprovementAnalysis(
            beforeCoverage: baseline.coveragePercentage(threshold: -70.0),
            afterCoverage: improved.coveragePercentage(threshold: -70.0),
            absoluteImprovement: overallImprovement,
            improvementFactor: improvementFactor,
            newlyServedArea: newlyServedArea,
            improvementByThreshold: improvementByThreshold
        )
    }
    
    // MARK: - Utilities
    
    private func generateCacheKey(
        room: RoomModel,
        transmitters: [RFTransmitter],
        frequencies: [Double]
    ) -> String {
        let roomHash = "\(room.id.uuidString)_\(room.bounds.hashValue)"
        let txHash = transmitters.map { "\($0.location)_\($0.power)" }.joined(separator: "_")
        let freqHash = frequencies.map { String($0) }.joined(separator: "_")
        return "\(roomHash)_\(txHash)_\(freqHash)_\(gridResolution)"
    }
}

// MARK: - Supporting Types

/// Grid point for coverage analysis
private struct GridPoint: Hashable {
    let location: Point3D
    let gridIndices: (x: Int, y: Int, z: Int)
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(location.x)
        hasher.combine(location.y)
        hasher.combine(location.z)
    }
    
    static func == (lhs: GridPoint, rhs: GridPoint) -> Bool {
        return lhs.location == rhs.location
    }
}

/// Environmental parameters for RF analysis
public struct RFEnvironment {
    public let type: IndoorEnvironment
    public let temperature: Double? // Celsius
    public let humidity: Double? // Percentage
    public let clutterDensity: Double // 0-1
    
    public init(
        type: IndoorEnvironment = .residential,
        temperature: Double? = nil,
        humidity: Double? = nil,
        clutterDensity: Double = 0.3
    ) {
        self.type = type
        self.temperature = temperature
        self.humidity = humidity
        self.clutterDensity = clutterDensity
    }
    
    public static let `default` = RFEnvironment()
}

/// Coverage improvement analysis result
public struct CoverageImprovementAnalysis {
    public let beforeCoverage: Double // Percentage (0-1)
    public let afterCoverage: Double // Percentage (0-1)
    public let absoluteImprovement: Double // Percentage points
    public let improvementFactor: Double // Multiplier
    public let newlyServedArea: Double // Square meters
    public let improvementByThreshold: [Double: Double] // Per threshold
    
    public init(
        beforeCoverage: Double,
        afterCoverage: Double,
        absoluteImprovement: Double,
        improvementFactor: Double,
        newlyServedArea: Double,
        improvementByThreshold: [Double: Double]
    ) {
        self.beforeCoverage = beforeCoverage
        self.afterCoverage = afterCoverage
        self.absoluteImprovement = absoluteImprovement
        self.improvementFactor = improvementFactor
        self.newlyServedArea = newlyServedArea
        self.improvementByThreshold = improvementByThreshold
    }
    
    /// Whether the improvement is significant
    public var isSignificant: Bool {
        return absoluteImprovement > 0.1 && improvementFactor > 1.2
    }
}

/// Simple caching system for coverage results
private class CoverageCache {
    private var cache: [String: CoverageMap] = [:]
    private let maxCacheSize = 50
    private let enabled: Bool
    private let cacheQueue = DispatchQueue(label: "com.wifimap.cache", attributes: .concurrent)
    
    init(enabled: Bool) {
        self.enabled = enabled
    }
    
    func getCachedCoverage(key: String) -> CoverageMap? {
        guard enabled else { return nil }
        
        return cacheQueue.sync {
            return cache[key]
        }
    }
    
    func storeCoverage(_ coverage: CoverageMap, for key: String) {
        guard enabled else { return }
        
        cacheQueue.async(flags: .barrier) {
            if self.cache.count >= self.maxCacheSize {
                // Remove oldest entries (simplified LRU)
                let keysToRemove = Array(self.cache.keys.prefix(10))
                keysToRemove.forEach { self.cache.removeValue(forKey: $0) }
            }
            
            self.cache[key] = coverage
        }
    }
}

// MARK: - Extensions

extension RayTracing {
    struct Configuration {
        let maxReflections: Int
        let minSignalThreshold: Double
        
        static let `default` = Configuration(maxReflections: 2, minSignalThreshold: -100.0)
    }
}