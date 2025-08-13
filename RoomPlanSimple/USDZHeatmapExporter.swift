import Foundation
import simd
import UIKit
import ModelIO

final class USDZHeatmapExporter {
    static func exportRoomWithHeatmap(
        capturedRoom: CapturedRoom,
        coverageMap: [simd_float3: Double],
        destinationURL: URL
    ) throws {
        // 1) Export the base RoomPlan USDZ to a temp location
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent("Room_Base_\(UUID().uuidString).usdz")
        try capturedRoom.export(to: baseURL, exportOptions: .parametric)

        // 2) Load as MDLAsset
        let asset = MDLAsset(url: baseURL)

        // 3) Build heatmap image from coverage
        guard let heatmapImage = renderHeatmapImage(coverageMap: coverageMap) else {
            // If rendering fails, just re-export the original asset
            _ = try? asset.export(to: destinationURL)
            return
        }

        // 4) Create a plane mesh that spans the coverage bounds
        guard let (center, size) = coverageBounds(coverageMap: coverageMap) else {
            _ = try? asset.export(to: destinationURL)
            return
        }

        let extent = vector_float3(size.width, 0.0, size.height) // XZ plane
        let mesh = MDLMesh(planeWithExtent: extent, segments: vector_uint2(1, 1), geometryType: .triangles, allocator: nil)

        // Position: MDLMesh plane is centered at origin in local space. We'll wrap it in a transform node to position/raise it
        let transform = MDLTransform()
        transform.translation = vector_float3(center.x, 0.02, center.z) // Slightly above floor to avoid z-fighting

        let meshObject = MDLObject()
        meshObject.transform = transform
        meshObject.addChild(mesh)

        // 5) Apply material with heatmap texture (with alpha)
        let material = MDLMaterial(name: "HeatmapMaterial", scatteringFunction: MDLScatteringFunction())
        let textureProp = MDLMaterialProperty(name: MDLMaterialSemantic.baseColor.rawValue, semantic: .baseColor, textureSampler: textureSampler(from: heatmapImage))
        material.setProperty(textureProp)
        // Slight emissive to make it visible regardless of lighting
        let emissiveProp = MDLMaterialProperty(name: MDLMaterialSemantic.emission.rawValue, semantic: .emission, textureSampler: textureSampler(from: heatmapImage))
        material.setProperty(emissiveProp)

        mesh.submeshes?.forEach { sub in
            (sub as? MDLSubmesh)?.material = material
        }

        // 6) Add to asset and export new USDZ
        asset.add(meshObject)
        try asset.export(to: destinationURL)

        // Cleanup
        try? FileManager.default.removeItem(at: baseURL)
    }

    // MARK: - Helpers

    private static func coverageBounds(coverageMap: [simd_float3: Double]) -> (center: simd_float3, size: (width: Float, height: Float))? {
        guard !coverageMap.isEmpty else { return nil }
        let xs = coverageMap.keys.map { $0.x }
        let zs = coverageMap.keys.map { $0.z }
        guard let minX = xs.min(), let maxX = xs.max(), let minZ = zs.min(), let maxZ = zs.max() else { return nil }
        let center = simd_float3((minX + maxX) / 2, 0, (minZ + maxZ) / 2)
        let size = (width: max(0.1, maxX - minX), height: max(0.1, maxZ - minZ))
        return (center, size)
    }

    private static func textureSampler(from image: UIImage) -> MDLTextureSampler {
        let sampler = MDLTextureSampler()
        if let cg = image.cgImage {
            let texture = MDLTexture(cgImage: cg, name: "HeatmapTexture", isSRGB: true)
            sampler.texture = texture
        }
        sampler.tiling = .repeat
        return sampler
    }

    private static func renderHeatmapImage(coverageMap: [simd_float3: Double]) -> UIImage? {
        guard !coverageMap.isEmpty else { return nil }

        // Determine bounds and grid
        guard let (center, size) = coverageBounds(coverageMap: coverageMap) else { return nil }
        let minX = center.x - size.width / 2
        let minZ = center.z - size.height / 2

        // Render at reasonable resolution
        let pixelsPerMeter: CGFloat = 64 // 64 px per meter
        let widthPx = max(64, Int(ceil(CGFloat(size.width) * pixelsPerMeter)))
        let heightPx = max(64, Int(ceil(CGFloat(size.height) * pixelsPerMeter)))

        UIGraphicsBeginImageContextWithOptions(CGSize(width: widthPx, height: heightPx), false, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }

        // Transparent background
        ctx.setFillColor(UIColor.clear.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: widthPx, height: heightPx))

        // Draw each coverage point as a small square
        for (pos, norm) in coverageMap {
            // Map world pos -> image coords
            let xMeters = CGFloat(pos.x - minX)
            let zMeters = CGFloat(pos.z - minZ)
            let px = xMeters * pixelsPerMeter
            let pz = zMeters * pixelsPerMeter

            let color = colorForCoverage(norm)
            ctx.setFillColor(color.withAlphaComponent(0.55).cgColor)
            // Tile size ~ half meter cells
            let tileSize: CGFloat = max(2, pixelsPerMeter * 0.5)
            let rect = CGRect(x: px - tileSize/2, y: CGFloat(heightPx) - (pz + tileSize/2), width: tileSize, height: tileSize)
            ctx.fill(rect)
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }

    private static func colorForCoverage(_ normalized: Double) -> UIColor {
        // Map 0..1 -> colors similar to app scheme
        // Convert to approx RSSI for reuse of palette
        let rssi = Int(normalized * 100.0 - 100.0)
        return SpectrumBranding.signalStrengthColor(for: rssi)
    }
}