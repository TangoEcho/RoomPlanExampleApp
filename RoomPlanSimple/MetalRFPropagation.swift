import Foundation
import Metal
import simd

final class MetalRFPropagation {
    struct GPUParameters {
        let minX: Float
        let minZ: Float
        let gridResolution: Float
        let width: UInt32
        let height: UInt32
        let txPowerAt1mDbm: Float
        let pathLossExponent: Float
        let wallAttenuationDb: Float
        let maxDistanceMeters: Float
    }

    struct WallSegmentGPU { var ax: Float; var az: Float; var bx: Float; var bz: Float }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    init?() {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let q = dev.makeCommandQueue() else { return nil }
        device = dev
        queue = q
        do {
            let library = try device.makeDefaultLibrary(bundle: .main)
            guard let function = library.makeFunction(name: "rf_propagation_kernel") else { return nil }
            pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            return nil
        }
    }

    func generateCoverage(
        rooms: [RoomAnalyzer.IdentifiedRoom],
        routers: [simd_float3],
        parameters: RFPropagationModel.Parameters = .default
    ) -> [simd_float3: Double]? {
        guard !rooms.isEmpty, !routers.isEmpty else { return [:] }

        // Bounds from room polygons
        let allPoints: [simd_float2] = rooms.flatMap { $0.wallPoints }
        guard !allPoints.isEmpty else { return [:] }
        let minX = allPoints.map { $0.x }.min() ?? 0
        let maxX = allPoints.map { $0.x }.max() ?? 0
        let minZ = allPoints.map { $0.y }.min() ?? 0
        let maxZ = allPoints.map { $0.y }.max() ?? 0

        let gridRes = parameters.gridResolutionMeters
        let widthCount = max(1, Int(ceil((maxX - minX) / gridRes)))
        let heightCount = max(1, Int(ceil((maxZ - minZ) / gridRes)))

        // Prepare segments
        let segments = MetalRFPropagation.buildWallSegments(from: rooms)
        let segCount = segments.count
        if segCount == 0 { return nil }

        // Prepare buffers
        guard let segBuffer = device.makeBuffer(length: MemoryLayout<WallSegmentGPU>.stride * segCount, options: .storageModeShared),
              let routerBuffer = device.makeBuffer(length: MemoryLayout<SIMD2<Float>>.stride * routers.count, options: .storageModeShared),
              let outBuffer = device.makeBuffer(length: MemoryLayout<Float>.stride * widthCount * heightCount, options: .storageModeShared)
        else { return nil }

        // Fill segments
        var segPtr = segBuffer.contents().bindMemory(to: WallSegmentGPU.self, capacity: segCount)
        for s in segments {
            segPtr.pointee = WallSegmentGPU(ax: s.a.x, az: s.a.y, bx: s.b.x, bz: s.b.y)
            segPtr = segPtr.advanced(by: 1)
        }
        // Fill routers (x,z only)
        var rPtr = routerBuffer.contents().bindMemory(to: SIMD2<Float>.self, capacity: routers.count)
        for r in routers { rPtr.pointee = SIMD2<Float>(r.x, r.z); rPtr = rPtr.advanced(by: 1) }

        // Params
        var gpuParams = GPUParameters(
            minX: minX,
            minZ: minZ,
            gridResolution: gridRes,
            width: UInt32(widthCount),
            height: UInt32(heightCount),
            txPowerAt1mDbm: Float(parameters.txPowerAt1mDbm),
            pathLossExponent: Float(parameters.pathLossExponent),
            wallAttenuationDb: Float(parameters.wallAttenuationDb),
            maxDistanceMeters: Float(parameters.maxDistanceMeters)
        )
        guard let paramsBuffer = device.makeBuffer(bytes: &gpuParams, length: MemoryLayout<GPUParameters>.stride, options: .storageModeShared) else { return nil }

        // Counts
        var segCountU = UInt32(segCount)
        var routerCountU = UInt32(routers.count)
        guard let segCountBuf = device.makeBuffer(bytes: &segCountU, length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let routerCountBuf = device.makeBuffer(bytes: &routerCountU, length: MemoryLayout<UInt32>.stride, options: .storageModeShared) else { return nil }

        // Encode
        guard let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else { return nil }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(segBuffer, offset: 0, index: 0)
        encoder.setBuffer(segCountBuf, offset: 0, index: 1)
        encoder.setBuffer(routerBuffer, offset: 0, index: 2)
        encoder.setBuffer(routerCountBuf, offset: 0, index: 3)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 4)
        encoder.setBuffer(outBuffer, offset: 0, index: 5)

        // Threadgrid
        let w = widthCount
        let h = heightCount
        let tgW = min(pipeline.threadExecutionWidth, 16)
        let tgH = max(1, min(pipeline.maxTotalThreadsPerThreadgroup / tgW, 16))
        let threadsPerThreadgroup = MTLSize(width: tgW, height: tgH, depth: 1)
        let threadsPerGrid = MTLSize(width: w, height: h, depth: 1)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()

        // Read back
        let outPtr = outBuffer.contents().bindMemory(to: Float.self, capacity: w * h)
        var result: [simd_float3: Double] = [:]
        for iy in 0..<h {
            for ix in 0..<w {
                let idx = iy * w + ix
                let norm = Double(outPtr[idx])
                let x = minX + Float(ix) * gridRes
                let z = minZ + Float(iy) * gridRes
                result[simd_float3(x, 0, z)] = norm
            }
        }
        return result
    }

    // MARK: - Helpers

    private struct WallSeg2D { let a: simd_float2; let b: simd_float2 }

    private static func buildWallSegments(from rooms: [RoomAnalyzer.IdentifiedRoom]) -> [WallSeg2D] {
        var segments: [WallSeg2D] = []
        for room in rooms {
            let pts = room.wallPoints
            guard pts.count >= 2 else { continue }
            for i in 0..<pts.count {
                let a = pts[i]
                let b = pts[(i + 1) % pts.count]
                segments.append(WallSeg2D(a: a, b: b))
            }
        }
        return segments
    }
}