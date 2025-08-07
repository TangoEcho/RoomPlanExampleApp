import Foundation
import UIKit
import simd

// MARK: - Performance Monitoring

final class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    private var operationStartTimes: [String: CFAbsoluteTime] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    func startOperation(_ name: String) {
        lock.withLock {
            operationStartTimes[name] = CFAbsoluteTimeGetCurrent()
        }
    }
    
    func endOperation(_ name: String) {
        let endTime = CFAbsoluteTimeGetCurrent()
        
        lock.withLock {
            if let startTime = operationStartTimes.removeValue(forKey: name) {
                let duration = endTime - startTime
                print("⏱️ Performance: \(name) took \(String(format: "%.3f", duration * 1000))ms")
                
                // Log slow operations
                if duration > 0.1 { // 100ms threshold
                    print("🐌 SLOW OPERATION: \(name) took \(String(format: "%.3f", duration))s")
                }
            }
        }
    }
}

// MARK: - Performance Wrapper

func measurePerformance<T>(_ operationName: String, _ operation: () throws -> T) rethrows -> T {
    PerformanceMonitor.shared.startOperation(operationName)
    defer { PerformanceMonitor.shared.endOperation(operationName) }
    return try operation()
}

// MARK: - Spatial Data Structure for Fast Lookups

final class SpatialIndex {
    private struct GridCell {
        var points: [IndexedPoint] = []
    }
    
    private struct IndexedPoint {
        let point: simd_float3
        let data: Any
        let index: Int
    }
    
    private var grid: [Int: [Int: GridCell]] = [:]
    private let cellSize: Float
    private let lock = NSRecursiveLock()
    
    init(cellSize: Float = 2.0) { // 2m grid cells
        self.cellSize = cellSize
    }
    
    func insert(point: simd_float3, data: Any, index: Int) {
        let gridX = Int(floor(point.x / cellSize))
        let gridZ = Int(floor(point.z / cellSize))
        
        lock.withLock {
            if grid[gridX] == nil {
                grid[gridX] = [:]
            }
            if grid[gridX]![gridZ] == nil {
                grid[gridX]![gridZ] = GridCell()
            }
            
            let indexedPoint = IndexedPoint(point: point, data: data, index: index)
            grid[gridX]![gridZ]!.points.append(indexedPoint)
        }
    }
    
    func findNearby(point: simd_float3, radius: Float) -> [(point: simd_float3, data: Any, distance: Float)] {
        let cellRadius = Int(ceil(radius / cellSize))
        let centerGridX = Int(floor(point.x / cellSize))
        let centerGridZ = Int(floor(point.z / cellSize))
        
        var results: [(point: simd_float3, data: Any, distance: Float)] = []
        
        lock.withLock {
            for x in (centerGridX - cellRadius)...(centerGridX + cellRadius) {
                for z in (centerGridZ - cellRadius)...(centerGridZ + cellRadius) {
                    if let row = grid[x], let cell = row[z] {
                        for indexedPoint in cell.points {
                            let distance = simd_distance(point, indexedPoint.point)
                            if distance <= radius {
                                results.append((
                                    point: indexedPoint.point,
                                    data: indexedPoint.data,
                                    distance: distance
                                ))
                            }
                        }
                    }
                }
            }
        }
        
        return results.sorted { $0.distance < $1.distance }
    }
    
    func clear() {
        lock.withLock {
            grid.removeAll()
        }
    }
    
    var totalPoints: Int {
        lock.withLock {
            return grid.values.flatMap { $0.values }.reduce(0) { $0 + $1.points.count }
        }
    }
}

// MARK: - Optimized Computation Cache

final class ComputationCache<Key: Hashable, Value> {
    private var cache: [Key: CachedValue<Value>] = [:]
    private let lock = NSLock()
    private let maxSize: Int
    private let ttl: TimeInterval // Time to live
    
    private struct CachedValue<V> {
        let value: V
        let timestamp: TimeInterval
    }
    
    init(maxSize: Int = 100, ttl: TimeInterval = 60.0) {
        self.maxSize = maxSize
        self.ttl = ttl
    }
    
    func getValue(for key: Key, compute: () -> Value) -> Value {
        let now = CFAbsoluteTimeGetCurrent()
        
        return lock.withLock {
            // Check if we have a valid cached value
            if let cachedValue = cache[key],
               now - cachedValue.timestamp < ttl {
                return cachedValue.value
            }
            
            // Compute new value
            let newValue = compute()
            
            // Store in cache
            cache[key] = CachedValue(value: newValue, timestamp: now)
            
            // Clean up old entries if needed
            if cache.count > maxSize {
                cleanupOldEntries(currentTime: now)
            }
            
            return newValue
        }
    }
    
    private func cleanupOldEntries(currentTime: TimeInterval) {
        let cutoffTime = currentTime - ttl
        cache = cache.filter { $0.value.timestamp >= cutoffTime }
        
        // If still too many, remove oldest entries
        if cache.count > maxSize {
            let sortedKeys = cache.keys.sorted { cache[$0]!.timestamp < cache[$1]!.timestamp }
            let keysToRemove = sortedKeys.prefix(cache.count - maxSize + 10) // Remove extra for buffer
            for key in keysToRemove {
                cache.removeValue(forKey: key)
            }
        }
    }
    
    func invalidate(key: Key) {
        lock.withLock {
            cache.removeValue(forKey: key)
        }
    }
    
    func clear() {
        lock.withLock {
            cache.removeAll()
        }
    }
}

// MARK: - Batch Processing Utilities

final class BatchProcessor<T> {
    private let batchSize: Int
    private let processingQueue: DispatchQueue
    
    init(batchSize: Int = 50, queue: DispatchQueue = DispatchQueue.global(qos: .utility)) {
        self.batchSize = batchSize
        self.processingQueue = queue
    }
    
    func process<R>(_ items: [T], 
                   transform: @escaping ([T]) -> [R],
                   completion: @escaping ([R]) -> Void) {
        
        processingQueue.async {
            var allResults: [R] = []
            
            // Process in batches
            for i in stride(from: 0, to: items.count, by: self.batchSize) {
                let endIndex = min(i + self.batchSize, items.count)
                let batch = Array(items[i..<endIndex])
                
                let batchResults = transform(batch)
                allResults.append(contentsOf: batchResults)
                
                // Allow other tasks to run between batches
                if i + self.batchSize < items.count {
                    Thread.sleep(forTimeInterval: 0.001) // 1ms pause
                }
            }
            
            DispatchQueue.main.async {
                completion(allResults)
            }
        }
    }
}

// MARK: - Geometry Optimization

struct GeometryOptimizer {
    
    // Fast distance calculation without square root for comparison purposes
    static func distanceSquared(_ a: simd_float3, _ b: simd_float3) -> Float {
        let delta = a - b
        return simd_dot(delta, delta)
    }
    
    // Optimized point-in-polygon test using winding number
    static func isPointInPolygon(_ point: simd_float2, polygon: [simd_float2]) -> Bool {
        guard polygon.count >= 3 else { return false }
        
        var windingNumber = 0
        let n = polygon.count
        
        for i in 0..<n {
            let p1 = polygon[i]
            let p2 = polygon[(i + 1) % n]
            
            if p1.y <= point.y {
                if p2.y > point.y {
                    if isLeftOfLine(point, p1: p1, p2: p2) {
                        windingNumber += 1
                    }
                }
            } else {
                if p2.y <= point.y {
                    if !isLeftOfLine(point, p1: p1, p2: p2) {
                        windingNumber -= 1
                    }
                }
            }
        }
        
        return windingNumber != 0
    }
    
    private static func isLeftOfLine(_ point: simd_float2, p1: simd_float2, p2: simd_float2) -> Bool {
        return ((p2.x - p1.x) * (point.y - p1.y) - (point.x - p1.x) * (p2.y - p1.y)) > 0
    }
    
    // Douglas-Peucker algorithm for polygon simplification
    static func simplifyPolygon(_ points: [simd_float2], tolerance: Float = 0.1) -> [simd_float2] {
        guard points.count > 2 else { return points }
        
        return douglasPeucker(points, tolerance: tolerance)
    }
    
    private static func douglasPeucker(_ points: [simd_float2], tolerance: Float) -> [simd_float2] {
        guard points.count > 2 else { return points }
        
        var maxDistance: Float = 0
        var maxIndex = 0
        let start = points[0]
        let end = points[points.count - 1]
        
        // Find the point with maximum distance from the line
        for i in 1..<(points.count - 1) {
            let distance = perpendicularDistance(points[i], lineStart: start, lineEnd: end)
            if distance > maxDistance {
                maxDistance = distance
                maxIndex = i
            }
        }
        
        // If max distance is greater than tolerance, recursively simplify
        if maxDistance > tolerance {
            let leftPart = douglasPeucker(Array(points[0...maxIndex]), tolerance: tolerance)
            let rightPart = douglasPeucker(Array(points[maxIndex..<points.count]), tolerance: tolerance)
            
            // Combine results, avoiding duplicate middle point
            return leftPart + Array(rightPart.dropFirst())
        } else {
            // All points between start and end can be removed
            return [start, end]
        }
    }
    
    private static func perpendicularDistance(_ point: simd_float2, lineStart: simd_float2, lineEnd: simd_float2) -> Float {
        let lineLength = simd_distance(lineStart, lineEnd)
        if lineLength == 0 {
            return simd_distance(point, lineStart)
        }
        
        let t = max(0, min(1, simd_dot(point - lineStart, lineEnd - lineStart) / (lineLength * lineLength)))
        let projection = lineStart + t * (lineEnd - lineStart)
        
        return simd_distance(point, projection)
    }
}

// MARK: - UI Update Throttling

final class UIUpdateThrottler {
    private var pendingUpdate: DispatchWorkItem?
    private let delay: TimeInterval
    private let queue: DispatchQueue
    
    init(delay: TimeInterval = 0.1, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }
    
    func throttle(_ action: @escaping () -> Void) {
        pendingUpdate?.cancel()
        
        pendingUpdate = DispatchWorkItem { [weak self] in
            action()
            self?.pendingUpdate = nil
        }
        
        queue.asyncAfter(deadline: .now() + delay, execute: pendingUpdate!)
    }
    
    func executeImmediately(_ action: @escaping () -> Void) {
        pendingUpdate?.cancel()
        pendingUpdate = nil
        queue.async(execute: action)
    }
}

// MARK: - Memory-Efficient Data Structures

struct CircularBuffer<T> {
    private var buffer: [T?]
    private var writeIndex = 0
    private var readIndex = 0
    private var count = 0
    private let capacity: Int
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }
    
    mutating func write(_ element: T) {
        buffer[writeIndex] = element
        writeIndex = (writeIndex + 1) % capacity
        
        if count < capacity {
            count += 1
        } else {
            readIndex = (readIndex + 1) % capacity
        }
    }
    
    mutating func read() -> T? {
        guard count > 0 else { return nil }
        
        let element = buffer[readIndex]
        buffer[readIndex] = nil
        readIndex = (readIndex + 1) % capacity
        count -= 1
        
        return element
    }
    
    var isEmpty: Bool {
        return count == 0
    }
    
    var isFull: Bool {
        return count == capacity
    }
    
    func toArray() -> [T] {
        var result: [T] = []
        var index = readIndex
        
        for _ in 0..<count {
            if let element = buffer[index] {
                result.append(element)
            }
            index = (index + 1) % capacity
        }
        
        return result
    }
    
    mutating func clear() {
        buffer = Array(repeating: nil, count: capacity)
        writeIndex = 0
        readIndex = 0
        count = 0
    }
}