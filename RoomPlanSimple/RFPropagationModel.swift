import Foundation
import simd

final class RFPropagationModel {
    struct Parameters {
        let frequencyGHz: Double
        let txPowerAt1mDbm: Double
        let pathLossExponent: Double
        let wallAttenuationDb: Double
        let doorAttenuationDb: Double
        let maxDistanceMeters: Double
        let gridResolutionMeters: Float
        static let `default` = Parameters(
            frequencyGHz: 5.18,
            txPowerAt1mDbm: -30.0, // reference RSSI at 1m
            pathLossExponent: 2.0,
            wallAttenuationDb: 5.0,
            doorAttenuationDb: 2.0,
            maxDistanceMeters: 30.0,
            gridResolutionMeters: 0.5
        )
    }

    static func generatePropagationMap(
        rooms: [RoomAnalyzer.IdentifiedRoom],
        routers: [simd_float3],
        parameters: Parameters = .default
    ) -> [simd_float3: Double] {
        guard !rooms.isEmpty, !routers.isEmpty else { return [:] }

        // Compute overall bounds from room wall points
        let allPoints: [simd_float2] = rooms.flatMap { $0.wallPoints }
        guard !allPoints.isEmpty else { return [:] }

        let minX = allPoints.map { $0.x }.min() ?? 0
        let maxX = allPoints.map { $0.x }.max() ?? 0
        let minZ = allPoints.map { $0.y }.min() ?? 0
        let maxZ = allPoints.map { $0.y }.max() ?? 0

        let gridResolution = parameters.gridResolutionMeters
        let widthCount = Int(ceil((maxX - minX) / gridResolution))
        let depthCount = Int(ceil((maxZ - minZ) / gridResolution))

        // Precompute wall segments
        let wallSegments = buildWallSegments(from: rooms)

        var coverageMap: [simd_float3: Double] = [:]
        for ix in 0...widthCount {
            for iz in 0...depthCount {
                let x = minX + Float(ix) * gridResolution
                let z = minZ + Float(iz) * gridResolution
                let p2D = simd_float2(x, z)

                // Skip if point not inside any room polygon
                guard rooms.contains(where: { isPointInPolygon(p2D, polygon: $0.wallPoints) }) else { continue }

                // Evaluate RSSI from all routers; take max (best signal)
                var bestRssi: Double = -150
                for router in routers {
                    let rssi = predictRSSI(at: simd_float3(x, 0, z), from: router, wallSegments: wallSegments, parameters: parameters)
                    if rssi > bestRssi { bestRssi = rssi }
                }

                // Normalize to 0..1 similar to existing convention: (RSSI + 100) / 100
                let normalized = max(0.0, min(1.0, (bestRssi + 100.0) / 100.0))
                coverageMap[simd_float3(x, 0, z)] = normalized
            }
        }

        return coverageMap
    }

    static func mergePredictedWithMeasured(
        predicted: [simd_float3: Double],
        measured: [WiFiMeasurement],
        influenceRadiusMeters: Float = 2.0
    ) -> [simd_float3: Double] {
        guard !predicted.isEmpty else { return [:] }
        guard !measured.isEmpty else { return predicted }

        var merged: [simd_float3: Double] = [:]
        for (point, predVal) in predicted {
            // Find nearby measurements
            let nearby = measured.filter { simd_distance(point, $0.location) <= influenceRadiusMeters }
            if nearby.isEmpty {
                merged[point] = predVal
            } else {
                // Weighted blend: closer measurements weigh more
                var totalWeight: Double = 0
                var weightedVal: Double = 0
                for m in nearby {
                    let d = Double(simd_distance(point, m.location))
                    let w = d < 0.1 ? 1000.0 : 1.0 / (d * d)
                    let mNorm = (Double(m.signalStrength) + 100.0) / 100.0
                    totalWeight += w
                    weightedVal += w * mNorm
                }
                let measuredVal = totalWeight > 0 ? (weightedVal / totalWeight) : predVal
                // Blend measured more heavily where available
                let alpha = 0.7
                merged[point] = alpha * measuredVal + (1 - alpha) * predVal
            }
        }
        return merged
    }

    // MARK: - Internals

    private struct WallSegment { let a: simd_float2; let b: simd_float2 }

    private static func buildWallSegments(from rooms: [RoomAnalyzer.IdentifiedRoom]) -> [WallSegment] {
        var segments: [WallSegment] = []
        for room in rooms {
            let pts = room.wallPoints
            guard pts.count >= 2 else { continue }
            for i in 0..<pts.count {
                let a = pts[i]
                let b = pts[(i + 1) % pts.count]
                segments.append(WallSegment(a: a, b: b))
            }
        }
        return segments
    }

    private static func predictRSSI(
        at point: simd_float3,
        from router: simd_float3,
        wallSegments: [WallSegment],
        parameters: Parameters
    ) -> Double {
        let dx = Double(point.x - router.x)
        let dz = Double(point.z - router.z)
        let distance = max(0.1, sqrt(dx * dx + dz * dz))
        if distance > parameters.maxDistanceMeters { return -120.0 }

        // Free-space/path-loss model
        // FSPL(dB) ~= 20 log10(f) + 10 n log10(d) + C (we fold constants into txPowerAt1mDbm)
        let fspl = 10.0 * parameters.pathLossExponent * log10(distance)

        // Count wall crossings between router and point
        let crossings = countWallCrossings(from: simd_float2(router.x, router.z), to: simd_float2(point.x, point.z), segments: wallSegments)
        let wallLoss = Double(crossings.walls) * parameters.wallAttenuationDb + Double(crossings.doors) * parameters.doorAttenuationDb

        let rssi = parameters.txPowerAt1mDbm - fspl - wallLoss
        return max(-120.0, min(-20.0, rssi))
    }

    private static func countWallCrossings(
        from p0: simd_float2,
        to p1: simd_float2,
        segments: [WallSegment]
    ) -> (walls: Int, doors: Int) {
        // Currently no door segmentation; count all as walls
        var count = 0
        for seg in segments {
            if segmentsIntersect(p0, p1, seg.a, seg.b) {
                count += 1
            }
        }
        return (count, 0)
    }

    private static func isPointInPolygon(_ point: simd_float2, polygon: [simd_float2]) -> Bool {
        guard polygon.count > 2 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let xi = polygon[i].x
            let yi = polygon[i].y
            let xj = polygon[j].x
            let yj = polygon[j].y
            if ((yi > point.y) != (yj > point.y)) && (point.x < (xj - xi) * (point.y - yi) / (yj - yi + 1e-6) + xi) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private static func segmentsIntersect(_ p1: simd_float2, _ p2: simd_float2, _ q1: simd_float2, _ q2: simd_float2) -> Bool {
        func orientation(_ a: simd_float2, _ b: simd_float2, _ c: simd_float2) -> Float {
            return (b.y - a.y) * (c.x - b.x) - (b.x - a.x) * (c.y - b.y)
        }
        func onSegment(_ a: simd_float2, _ b: simd_float2, _ c: simd_float2) -> Bool {
            return min(a.x, b.x) - 1e-4 <= c.x && c.x <= max(a.x, b.x) + 1e-4 &&
                   min(a.y, b.y) - 1e-4 <= c.y && c.y <= max(a.y, b.y) + 1e-4
        }
        let o1 = orientation(p1, p2, q1)
        let o2 = orientation(p1, p2, q2)
        let o3 = orientation(q1, q2, p1)
        let o4 = orientation(q1, q2, p2)
        if o1 == 0 && onSegment(p1, p2, q1) { return true }
        if o2 == 0 && onSegment(p1, p2, q2) { return true }
        if o3 == 0 && onSegment(q1, q2, p1) { return true }
        if o4 == 0 && onSegment(q1, q2, p2) { return true }
        return (o1 > 0) != (o2 > 0) && (o3 > 0) != (o4 > 0)
    }
}