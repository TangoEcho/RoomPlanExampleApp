import Foundation

/// Performance optimization system for RF propagation calculations
public class PerformanceOptimizer {
    
    // MARK: - Properties
    
    private let adaptiveCache: AdaptiveCache
    private let computationScheduler: ComputationScheduler
    private let memoryManager: MemoryManager
    private let performanceMonitor: PerformanceMonitor
    
    // MARK: - Configuration
    
    public struct Configuration {
        public let cacheStrategy: CacheStrategy
        public let parallelizationLevel: ParallelizationLevel
        public let memoryThreshold: MemoryThreshold
        public let adaptiveOptimization: Bool
        
        public init(
            cacheStrategy: CacheStrategy = .adaptive,
            parallelizationLevel: ParallelizationLevel = .balanced,
            memoryThreshold: MemoryThreshold = .moderate,
            adaptiveOptimization: Bool = true
        ) {
            self.cacheStrategy = cacheStrategy
            self.parallelizationLevel = parallelizationLevel
            self.memoryThreshold = memoryThreshold
            self.adaptiveOptimization = adaptiveOptimization
        }
        
        public static let `default` = Configuration()
        public static let highPerformance = Configuration(
            cacheStrategy: .aggressive,
            parallelizationLevel: .maximum,
            memoryThreshold: .high
        )
        public static let lowMemory = Configuration(
            cacheStrategy: .conservative,
            parallelizationLevel: .minimal,
            memoryThreshold: .low
        )
    }
    
    private let configuration: Configuration
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.adaptiveCache = AdaptiveCache(strategy: configuration.cacheStrategy)
        self.computationScheduler = ComputationScheduler(level: configuration.parallelizationLevel)
        self.memoryManager = MemoryManager(threshold: configuration.memoryThreshold)
        self.performanceMonitor = PerformanceMonitor()
    }
    
    // MARK: - Optimization Interface
    
    /// Optimize coverage calculation with intelligent caching and parallelization
    /// - Parameters:
    ///   - request: Coverage calculation request
    ///   - calculator: Coverage calculation function
    /// - Returns: Optimized coverage result
    public func optimizeCoverageCalculation<T>(
        request: CoverageRequest,
        calculator: @escaping (CoverageRequest) async throws -> T
    ) async throws -> OptimizedResult<T> {
        
        let startTime = Date()
        
        // Check cache first
        if let cached = adaptiveCache.getCoverage(for: request) as? T {
            let duration = Date().timeIntervalSince(startTime)
            performanceMonitor.recordCacheHit(duration: duration)
            
            return OptimizedResult(
                result: cached,
                optimizationInfo: OptimizationInfo(
                    cacheHit: true,
                    computationTime: duration,
                    parallelizationUsed: false,
                    memoryOptimized: false
                )
            )
        }
        
        // Optimize request for computation
        let optimizedRequest = await optimizeRequest(request)
        
        // Perform calculation with optimization
        let result = try await performOptimizedCalculation(
            request: optimizedRequest,
            calculator: calculator
        )
        
        // Cache result
        adaptiveCache.storeCoverage(result, for: request)
        
        let totalDuration = Date().timeIntervalSince(startTime)
        performanceMonitor.recordCalculation(duration: totalDuration)
        
        return OptimizedResult(
            result: result,
            optimizationInfo: OptimizationInfo(
                cacheHit: false,
                computationTime: totalDuration,
                parallelizationUsed: optimizedRequest.useParallelization,
                memoryOptimized: optimizedRequest.memoryOptimized
            )
        )
    }
    
    /// Optimize grid point processing for large coverage areas
    /// - Parameters:
    ///   - gridPoints: Grid points to process
    ///   - processor: Processing function for each point
    /// - Returns: Processed results with optimization info
    public func optimizeGridProcessing<T>(
        gridPoints: [GridPoint],
        processor: @escaping (GridPoint) async throws -> T
    ) async throws -> [T] {
        
        // Determine optimal batch size based on system resources
        let batchSize = computationScheduler.calculateOptimalBatchSize(
            totalItems: gridPoints.count,
            itemComplexity: .medium
        )
        
        // Memory-aware batch processing
        let batches = createOptimizedBatches(
            points: gridPoints,
            batchSize: batchSize
        )
        
        var results: [T] = []
        results.reserveCapacity(gridPoints.count)
        
        // Process batches with adaptive parallelization
        for batch in batches {
            await memoryManager.ensureMemoryAvailable()
            
            let batchResults = try await computationScheduler.processParallel(
                items: batch,
                processor: processor
            )
            
            results.append(contentsOf: batchResults)
            
            // Trigger garbage collection if needed
            if memoryManager.shouldTriggerCleanup() {
                await memoryManager.performCleanup()
            }
        }
        
        return results
    }
    
    /// Optimize ray tracing calculations with intelligent path reduction
    /// - Parameters:
    ///   - rayRequest: Ray tracing request
    ///   - tracer: Ray tracing function
    /// - Returns: Optimized ray paths
    public func optimizeRayTracing(
        request: RayTracingRequest,
        tracer: @escaping (RayTracingRequest) async throws -> [RayPath]
    ) async throws -> [RayPath] {
        
        // Check if simplified ray tracing is sufficient
        let simplifiedRequest = simplifyRayTracingRequest(request)
        
        if shouldUseSimplifiedTracing(request) {
            return try await tracer(simplifiedRequest)
        }
        
        // Use full ray tracing with optimization
        let paths = try await tracer(request)
        
        // Post-process to remove redundant paths
        return optimizeRayPaths(paths)
    }
    
    // MARK: - Private Optimization Methods
    
    private func optimizeRequest(_ request: CoverageRequest) async -> OptimizedCoverageRequest {
        var optimized = OptimizedCoverageRequest(original: request)
        
        // Grid resolution optimization
        optimized.gridResolution = adaptiveCache.getOptimalGridResolution(for: request)
        
        // Frequency optimization
        optimized.frequencies = optimizeFrequencySet(request.frequencies)
        
        // Parallelization decision
        optimized.useParallelization = shouldUseParallelization(for: request)
        
        // Memory optimization
        optimized.memoryOptimized = await memoryManager.shouldOptimizeForMemory()
        
        return optimized
    }
    
    private func performOptimizedCalculation<T>(
        request: OptimizedCoverageRequest,
        calculator: @escaping (CoverageRequest) async throws -> T
    ) async throws -> T {
        
        if request.memoryOptimized {
            return try await performMemoryOptimizedCalculation(request: request, calculator: calculator)
        } else {
            return try await calculator(request.original)
        }
    }
    
    private func performMemoryOptimizedCalculation<T>(
        request: OptimizedCoverageRequest,
        calculator: @escaping (CoverageRequest) async throws -> T
    ) async throws -> T {
        
        // Break large calculations into smaller chunks
        if request.original.estimatedMemoryUsage > memoryManager.threshold.maxMemoryUsage {
            return try await performChunkedCalculation(request: request, calculator: calculator)
        }
        
        return try await calculator(request.original)
    }
    
    private func performChunkedCalculation<T>(
        request: OptimizedCoverageRequest,
        calculator: @escaping (CoverageRequest) async throws -> T
    ) async throws -> T {
        
        // This is a simplified implementation - would need to be customized based on T
        // For now, just perform the calculation normally
        return try await calculator(request.original)
    }
    
    private func createOptimizedBatches(
        points: [GridPoint],
        batchSize: Int
    ) -> [[GridPoint]] {
        
        // Spatial locality optimization - group nearby points together
        let sortedPoints = points.sorted { point1, point2 in
            // Simple spatial sorting using Z-order curve approximation
            let z1 = calculateZOrder(point1.location)
            let z2 = calculateZOrder(point2.location)
            return z1 < z2
        }
        
        return sortedPoints.chunked(into: batchSize)
    }
    
    private func calculateZOrder(_ point: Point3D) -> UInt64 {
        // Simplified Z-order calculation for spatial locality
        let x = UInt64(max(0, min(1023, point.x * 100)))
        let y = UInt64(max(0, min(1023, point.y * 100)))
        let z = UInt64(max(0, min(1023, point.z * 100)))
        
        return interleave3D(x, y, z)
    }
    
    private func interleave3D(_ x: UInt64, _ y: UInt64, _ z: UInt64) -> UInt64 {
        // Simple 3D bit interleaving for Z-order
        var result: UInt64 = 0
        for i in 0..<21 { // 21 bits each for 64-bit result
            result |= ((x >> i) & 1) << (i * 3)
            result |= ((y >> i) & 1) << (i * 3 + 1)
            result |= ((z >> i) & 1) << (i * 3 + 2)
        }
        return result
    }
    
    private func simplifyRayTracingRequest(_ request: RayTracingRequest) -> RayTracingRequest {
        var simplified = request
        
        // Reduce reflections for distant points
        if request.distance > 20.0 {
            simplified.maxReflections = min(1, request.maxReflections)
        }
        
        // Increase signal threshold for faster computation
        simplified.minSignalThreshold = max(request.minSignalThreshold, -90.0)
        
        return simplified
    }
    
    private func shouldUseSimplifiedTracing(_ request: RayTracingRequest) -> Bool {
        // Use simplified tracing for distant or weak signals
        return request.distance > 15.0 || request.expectedSignalStrength < -80.0
    }
    
    private func optimizeRayPaths(_ paths: [RayPath]) -> [RayPath] {
        // Remove redundant paths with similar characteristics
        var optimized: [RayPath] = []
        
        for path in paths.sorted(by: { $0.receivedPower > $1.receivedPower }) {
            if !isPathRedundant(path, existing: optimized) {
                optimized.append(path)
            }
            
            // Limit number of paths to prevent excessive computation
            if optimized.count >= 10 {
                break
            }
        }
        
        return optimized
    }
    
    private func isPathRedundant(_ path: RayPath, existing: [RayPath]) -> Bool {
        for existingPath in existing {
            if arePathsSimilar(path, existingPath) {
                return true
            }
        }
        return false
    }
    
    private func arePathsSimilar(_ path1: RayPath, _ path2: RayPath) -> Bool {
        // Consider paths similar if they have similar received power and path type
        let powerDifference = abs(path1.receivedPower - path2.receivedPower)
        let samePathType = path1.pathType == path2.pathType
        
        return powerDifference < 3.0 && samePathType
    }
    
    private func optimizeFrequencySet(_ frequencies: [Double]) -> [Double] {
        // For WiFi 7, optimize to representative frequencies
        let wifiFrequencies = Set(frequencies)
        var optimized: [Double] = []
        
        // Representative frequencies for each band
        if wifiFrequencies.contains(where: { $0 >= 2400 && $0 <= 2500 }) {
            optimized.append(2450) // 2.4GHz representative
        }
        if wifiFrequencies.contains(where: { $0 >= 5000 && $0 <= 6000 }) {
            optimized.append(5500) // 5GHz representative
        }
        if wifiFrequencies.contains(where: { $0 >= 6000 && $0 <= 7200 }) {
            optimized.append(6000) // 6GHz representative
        }
        
        return optimized.isEmpty ? frequencies : optimized
    }
    
    private func shouldUseParallelization(for request: CoverageRequest) -> Bool {
        // Use parallelization for large areas or complex scenarios
        return request.estimatedComplexity > .medium || 
               request.gridPointCount > 1000
    }
    
    // MARK: - Performance Monitoring
    
    /// Get current performance statistics
    public func getPerformanceStatistics() -> PerformanceStatistics {
        return performanceMonitor.getCurrentStatistics()
    }
    
    /// Reset performance counters
    public func resetPerformanceCounters() {
        performanceMonitor.reset()
    }
}

// MARK: - Supporting Classes

/// Adaptive cache with intelligent eviction policies
private class AdaptiveCache {
    private var coverageCache: [String: Any] = [:]
    private var accessTimes: [String: Date] = [:]
    private var hitCounts: [String: Int] = [:]
    private let maxCacheSize: Int
    private let strategy: CacheStrategy
    private let queue = DispatchQueue(label: "com.wifimap.cache", attributes: .concurrent)
    
    init(strategy: CacheStrategy) {
        self.strategy = strategy
        self.maxCacheSize = strategy.maxCacheSize
    }
    
    func getCoverage(for request: CoverageRequest) -> Any? {
        let key = generateCacheKey(request)
        
        return queue.sync {
            guard let cached = coverageCache[key] else { return nil }
            
            // Update access statistics
            accessTimes[key] = Date()
            hitCounts[key] = (hitCounts[key] ?? 0) + 1
            
            return cached
        }
    }
    
    func storeCoverage(_ coverage: Any, for request: CoverageRequest) {
        let key = generateCacheKey(request)
        
        queue.async(flags: .barrier) {
            // Evict if cache is full
            if self.coverageCache.count >= self.maxCacheSize {
                self.evictUsingStrategy()
            }
            
            self.coverageCache[key] = coverage
            self.accessTimes[key] = Date()
            self.hitCounts[key] = 0
        }
    }
    
    func getOptimalGridResolution(for request: CoverageRequest) -> Double {
        // Adaptive grid resolution based on room size and accuracy requirements
        let roomSize = request.roomBounds.volume
        
        switch roomSize {
        case 0..<50:    return 0.25  // Small rooms - high resolution
        case 50..<200:  return 0.5   // Medium rooms - balanced resolution
        case 200..<500: return 1.0   // Large rooms - lower resolution
        default:        return 1.5   // Very large rooms - coarse resolution
        }
    }
    
    private func evictUsingStrategy() {
        let evictionCount = maxCacheSize / 4 // Evict 25%
        var keysToEvict: [String] = []
        
        switch strategy {
        case .lru:
            keysToEvict = Array(accessTimes.sorted { $0.value < $1.value }
                .prefix(evictionCount)
                .map(\.key))
            
        case .lfu:
            keysToEvict = Array(hitCounts.sorted { $0.value < $1.value }
                .prefix(evictionCount)
                .map(\.key))
            
        case .adaptive:
            // Hybrid LRU/LFU strategy
            let sortedByScore = coverageCache.keys.sorted { key1, key2 in
                let score1 = calculateAdaptiveScore(key1)
                let score2 = calculateAdaptiveScore(key2)
                return score1 < score2
            }
            keysToEvict = Array(sortedByScore.prefix(evictionCount))
            
        case .conservative, .aggressive:
            // Simple LRU for these strategies
            keysToEvict = Array(accessTimes.sorted { $0.value < $1.value }
                .prefix(evictionCount)
                .map(\.key))
        }
        
        // Remove evicted keys
        for key in keysToEvict {
            coverageCache.removeValue(forKey: key)
            accessTimes.removeValue(forKey: key)
            hitCounts.removeValue(forKey: key)
        }
    }
    
    private func calculateAdaptiveScore(_ key: String) -> Double {
        let now = Date()
        let lastAccess = accessTimes[key] ?? now
        let timeSinceAccess = now.timeIntervalSince(lastAccess)
        let hitCount = Double(hitCounts[key] ?? 0)
        
        // Higher score = more valuable to keep
        return hitCount / max(1.0, timeSinceAccess / 3600.0) // Normalize by hours
    }
    
    private func generateCacheKey(_ request: CoverageRequest) -> String {
        // Generate unique key for coverage request
        return "\(request.roomBounds.hashValue)_\(request.transmitterCount)_\(request.frequencies.count)"
    }
}

/// Intelligent computation scheduler
private class ComputationScheduler {
    private let level: ParallelizationLevel
    private let maxConcurrency: Int
    
    init(level: ParallelizationLevel) {
        self.level = level
        
        let processorCount = ProcessInfo.processInfo.processorCount
        self.maxConcurrency = switch level {
            case .minimal: 1
            case .balanced: max(1, processorCount / 2)
            case .maximum: processorCount
        }
    }
    
    func calculateOptimalBatchSize(totalItems: Int, itemComplexity: ItemComplexity) -> Int {
        let baseSize = max(1, totalItems / (maxConcurrency * 2))
        
        return switch itemComplexity {
            case .low: baseSize * 4
            case .medium: baseSize * 2
            case .high: baseSize
        }
    }
    
    func processParallel<T, U>(
        items: [T],
        processor: @escaping (T) async throws -> U
    ) async throws -> [U] {
        
        return try await withThrowingTaskGroup(of: (Int, U).self) { group in
            var results: [U?] = Array(repeating: nil, count: items.count)
            
            // Add tasks with controlled concurrency
            for (index, item) in items.enumerated() {
                group.addTask {
                    let result = try await processor(item)
                    return (index, result)
                }
                
                // Limit concurrent tasks
                if group.taskCount >= maxConcurrency {
                    let (index, result) = try await group.next()!
                    results[index] = result
                }
            }
            
            // Collect remaining results
            while let (index, result) = try await group.next() {
                results[index] = result
            }
            
            return results.compactMap { $0 }
        }
    }
}

/// Memory management for large calculations
private class MemoryManager {
    let threshold: MemoryThreshold
    
    init(threshold: MemoryThreshold) {
        self.threshold = threshold
    }
    
    func ensureMemoryAvailable() async {
        if shouldTriggerCleanup() {
            await performCleanup()
        }
    }
    
    func shouldOptimizeForMemory() async -> Bool {
        return getCurrentMemoryUsage() > threshold.optimizationThreshold
    }
    
    func shouldTriggerCleanup() -> Bool {
        return getCurrentMemoryUsage() > threshold.cleanupThreshold
    }
    
    func performCleanup() async {
        // Force garbage collection
        autoreleasepool {
            // This will be deallocated at the end of the pool
        }
        
        // Brief pause to allow cleanup
        try? await Task.sleep(for: .milliseconds(10))
    }
    
    private func getCurrentMemoryUsage() -> Double {
        // Simplified memory usage calculation
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0 // MB
        }
        
        return 0.0
    }
}

/// Performance monitoring and statistics
private class PerformanceMonitor {
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    private var totalCalculations: Int = 0
    private var totalComputationTime: TimeInterval = 0
    private var averageComputationTime: TimeInterval = 0
    private let queue = DispatchQueue(label: "com.wifimap.performance", attributes: .concurrent)
    
    func recordCacheHit(duration: TimeInterval) {
        queue.async(flags: .barrier) {
            self.cacheHits += 1
        }
    }
    
    func recordCalculation(duration: TimeInterval) {
        queue.async(flags: .barrier) {
            self.cacheMisses += 1
            self.totalCalculations += 1
            self.totalComputationTime += duration
            self.averageComputationTime = self.totalComputationTime / Double(self.totalCalculations)
        }
    }
    
    func getCurrentStatistics() -> PerformanceStatistics {
        return queue.sync {
            return PerformanceStatistics(
                cacheHitRate: Double(cacheHits) / Double(max(1, cacheHits + cacheMisses)),
                averageComputationTime: averageComputationTime,
                totalCalculations: totalCalculations,
                totalComputationTime: totalComputationTime
            )
        }
    }
    
    func reset() {
        queue.async(flags: .barrier) {
            self.cacheHits = 0
            self.cacheMisses = 0
            self.totalCalculations = 0
            self.totalComputationTime = 0
            self.averageComputationTime = 0
        }
    }
}

// MARK: - Configuration Types

public enum CacheStrategy {
    case conservative // Smaller cache, less memory usage
    case balanced     // Balanced cache size and performance
    case aggressive   // Large cache, high memory usage
    case adaptive     // Adapts based on system resources
    case lru          // Least Recently Used
    case lfu          // Least Frequently Used
    
    var maxCacheSize: Int {
        switch self {
        case .conservative: return 50
        case .balanced: return 200
        case .aggressive: return 1000
        case .adaptive: return 500
        case .lru: return 300
        case .lfu: return 300
        }
    }
}

public enum ParallelizationLevel {
    case minimal  // Single-threaded or minimal parallelization
    case balanced // Moderate parallelization
    case maximum  // Maximum available cores
}

public struct MemoryThreshold {
    let maxMemoryUsage: Double // MB
    let optimizationThreshold: Double // MB
    let cleanupThreshold: Double // MB
    
    public static let low = MemoryThreshold(maxMemoryUsage: 50, optimizationThreshold: 30, cleanupThreshold: 40)
    public static let moderate = MemoryThreshold(maxMemoryUsage: 200, optimizationThreshold: 150, cleanupThreshold: 180)
    public static let high = MemoryThreshold(maxMemoryUsage: 500, optimizationThreshold: 400, cleanupThreshold: 450)
}

// MARK: - Request Types

public struct CoverageRequest {
    let roomBounds: BoundingBox
    let transmitterCount: Int
    let frequencies: [Double]
    let gridPointCount: Int
    let estimatedComplexity: ItemComplexity
    let estimatedMemoryUsage: Double // MB
}

public struct OptimizedCoverageRequest {
    let original: CoverageRequest
    var gridResolution: Double
    var frequencies: [Double]
    var useParallelization: Bool
    var memoryOptimized: Bool
    
    init(original: CoverageRequest) {
        self.original = original
        self.gridResolution = 0.5
        self.frequencies = original.frequencies
        self.useParallelization = false
        self.memoryOptimized = false
    }
}

public struct RayTracingRequest {
    let distance: Double
    let maxReflections: Int
    var minSignalThreshold: Double
    let expectedSignalStrength: Double
}

public enum ItemComplexity {
    case low
    case medium
    case high
}

// MARK: - Result Types

public struct OptimizedResult<T> {
    public let result: T
    public let optimizationInfo: OptimizationInfo
}

public struct OptimizationInfo {
    public let cacheHit: Bool
    public let computationTime: TimeInterval
    public let parallelizationUsed: Bool
    public let memoryOptimized: Bool
}

public struct PerformanceStatistics {
    public let cacheHitRate: Double // 0-1
    public let averageComputationTime: TimeInterval
    public let totalCalculations: Int
    public let totalComputationTime: TimeInterval
    
    public var cacheMissRate: Double {
        return 1.0 - cacheHitRate
    }
    
    public var calculationsPerSecond: Double {
        return totalComputationTime > 0 ? Double(totalCalculations) / totalComputationTime : 0
    }
}

// MARK: - Extensions

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}