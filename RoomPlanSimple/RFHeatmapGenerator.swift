import Foundation
import UIKit
import simd
import CoreGraphics
import Accelerate

// MARK: - RF Heatmap Generator
/// Advanced heatmap generator with multiple interpolation algorithms
class RFHeatmapGenerator {
    
    // MARK: - Enums
    enum InterpolationMethod {
        case nearestNeighbor
        case linear
        case bilinear
        case bicubic
        case idw // Inverse Distance Weighting
        case kriging
        case spline
    }
    
    enum ColorScheme {
        case traditional // Red to Green
        case thermal // Black to White through colors
        case spectrum // Full spectrum
        case grayscale
        case custom(colors: [UIColor])
        
        func colors() -> [UIColor] {
            switch self {
            case .traditional:
                return [
                    UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0), // Red (poor)
                    UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0), // Orange
                    UIColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0), // Yellow
                    UIColor(red: 0.5, green: 1.0, blue: 0.0, alpha: 1.0), // Yellow-green
                    UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)  // Green (excellent)
                ]
            case .thermal:
                return [
                    UIColor.black,
                    UIColor.blue,
                    UIColor.cyan,
                    UIColor.green,
                    UIColor.yellow,
                    UIColor.orange,
                    UIColor.red,
                    UIColor.white
                ]
            case .spectrum:
                return [
                    UIColor(red: 0.5, green: 0.0, blue: 1.0, alpha: 1.0), // Purple
                    UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0), // Blue
                    UIColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1.0), // Cyan
                    UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0), // Green
                    UIColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0), // Yellow
                    UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0), // Orange
                    UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)  // Red
                ]
            case .grayscale:
                return [
                    UIColor(white: 0.0, alpha: 1.0),
                    UIColor(white: 0.25, alpha: 1.0),
                    UIColor(white: 0.5, alpha: 1.0),
                    UIColor(white: 0.75, alpha: 1.0),
                    UIColor(white: 1.0, alpha: 1.0)
                ]
            case .custom(let colors):
                return colors
            }
        }
    }
    
    // MARK: - Properties
    private let propagationModel: RFPropagationModel
    private var colorScheme: ColorScheme = .traditional
    private var interpolationMethod: InterpolationMethod = .idw
    private var resolution: Float = 0.5 // meters per pixel
    private var smoothingFactor: Float = 2.0
    
    // Cache for performance
    private var cachedHeatmapImage: UIImage?
    private var cachedPropagationData: [RFPropagationModel.PropagationPoint]?
    
    // MARK: - Initialization
    init(propagationModel: RFPropagationModel) {
        self.propagationModel = propagationModel
        print("🎨 RF Heatmap Generator initialized")
    }
    
    // MARK: - Configuration
    func setColorScheme(_ scheme: ColorScheme) {
        self.colorScheme = scheme
        invalidateCache()
    }
    
    func setInterpolationMethod(_ method: InterpolationMethod) {
        self.interpolationMethod = method
        invalidateCache()
    }
    
    func setResolution(_ resolution: Float) {
        self.resolution = max(0.1, min(5.0, resolution))
        invalidateCache()
    }
    
    private func invalidateCache() {
        cachedHeatmapImage = nil
        cachedPropagationData = nil
    }
    
    // MARK: - Heatmap Generation
    
    /// Generate 2D heatmap image
    func generateHeatmapImage(size: CGSize, floorHeight: Float = 1.0) -> UIImage? {
        // Check cache
        if let cached = cachedHeatmapImage {
            return cached
        }
        
        // Generate propagation data if needed
        if cachedPropagationData == nil {
            cachedPropagationData = propagationModel.generatePropagationMap(resolution: resolution)
        }
        
        guard let propagationData = cachedPropagationData, !propagationData.isEmpty else {
            print("⚠️ No propagation data available")
            return nil
        }
        
        // Create heatmap grid
        let gridSize = calculateGridSize(for: size)
        var heatmapGrid = createHeatmapGrid(
            propagationData: propagationData,
            gridSize: gridSize,
            floorHeight: floorHeight
        )
        
        // Apply interpolation
        heatmapGrid = applyInterpolation(
            grid: heatmapGrid,
            method: interpolationMethod,
            size: gridSize
        )
        
        // Apply smoothing
        if smoothingFactor > 1.0 {
            heatmapGrid = applyGaussianSmoothing(
                grid: heatmapGrid,
                size: gridSize,
                sigma: smoothingFactor
            )
        }
        
        // Convert to image
        let image = createImage(from: heatmapGrid, size: size)
        cachedHeatmapImage = image
        
        return image
    }
    
    /// Generate 3D heatmap volume data
    func generate3DHeatmapVolume(heightLevels: Int = 5) -> [Float] {
        let volumeData = propagationModel.generate3DPropagationVolume(
            resolution: resolution,
            heightLevels: heightLevels
        )
        
        // Convert to float array for visualization
        return volumeData.map { $0.signalStrength }
    }
    
    // MARK: - Grid Creation
    
    private func calculateGridSize(for imageSize: CGSize) -> (width: Int, height: Int) {
        let width = Int(imageSize.width)
        let height = Int(imageSize.height)
        return (width, height)
    }
    
    private func createHeatmapGrid(
        propagationData: [RFPropagationModel.PropagationPoint],
        gridSize: (width: Int, height: Int),
        floorHeight: Float
    ) -> [[Float]] {
        var grid = Array(repeating: Array(repeating: Float(-100.0), count: gridSize.width), count: gridSize.height)
        
        // Find bounds
        let xValues = propagationData.map { $0.position.x }
        let zValues = propagationData.map { $0.position.z }
        
        guard let minX = xValues.min(), let maxX = xValues.max(),
              let minZ = zValues.min(), let maxZ = zValues.max() else {
            return grid
        }
        
        let xRange = maxX - minX
        let zRange = maxZ - minZ
        
        // Filter points at the specified height
        let heightTolerance: Float = 0.5
        let relevantPoints = propagationData.filter { 
            abs($0.position.y - floorHeight) < heightTolerance
        }
        
        // Map propagation points to grid
        for point in relevantPoints {
            let x = Int(((point.position.x - minX) / xRange) * Float(gridSize.width - 1))
            let z = Int(((point.position.z - minZ) / zRange) * Float(gridSize.height - 1))
            
            if x >= 0 && x < gridSize.width && z >= 0 && z < gridSize.height {
                grid[z][x] = point.signalStrength
            }
        }
        
        return grid
    }
    
    // MARK: - Interpolation Methods
    
    private func applyInterpolation(
        grid: [[Float]],
        method: InterpolationMethod,
        size: (width: Int, height: Int)
    ) -> [[Float]] {
        switch method {
        case .nearestNeighbor:
            return applyNearestNeighborInterpolation(grid: grid, size: size)
        case .linear, .bilinear:
            return applyBilinearInterpolation(grid: grid, size: size)
        case .bicubic:
            return applyBicubicInterpolation(grid: grid, size: size)
        case .idw:
            return applyIDWInterpolation(grid: grid, size: size)
        case .kriging:
            return applyKrigingInterpolation(grid: grid, size: size)
        case .spline:
            return applySplineInterpolation(grid: grid, size: size)
        }
    }
    
    private func applyNearestNeighborInterpolation(
        grid: [[Float]],
        size: (width: Int, height: Int)
    ) -> [[Float]] {
        var interpolated = grid
        
        for y in 0..<size.height {
            for x in 0..<size.width {
                if grid[y][x] == -100.0 {
                    // Find nearest non-empty neighbor
                    var minDistance = Float.infinity
                    var nearestValue: Float = -100.0
                    
                    for dy in -10...10 {
                        for dx in -10...10 {
                            let ny = y + dy
                            let nx = x + dx
                            
                            if ny >= 0 && ny < size.height && nx >= 0 && nx < size.width {
                                if grid[ny][nx] != -100.0 {
                                    let distance = sqrt(Float(dx * dx + dy * dy))
                                    if distance < minDistance {
                                        minDistance = distance
                                        nearestValue = grid[ny][nx]
                                    }
                                }
                            }
                        }
                    }
                    
                    interpolated[y][x] = nearestValue
                }
            }
        }
        
        return interpolated
    }
    
    private func applyBilinearInterpolation(
        grid: [[Float]],
        size: (width: Int, height: Int)
    ) -> [[Float]] {
        var interpolated = grid
        
        // Collect known points
        var knownPoints: [(x: Int, y: Int, value: Float)] = []
        for y in 0..<size.height {
            for x in 0..<size.width {
                if grid[y][x] != -100.0 {
                    knownPoints.append((x, y, grid[y][x]))
                }
            }
        }
        
        // Interpolate unknown points
        for y in 0..<size.height {
            for x in 0..<size.width {
                if grid[y][x] == -100.0 {
                    // Find four nearest points for bilinear interpolation
                    let nearestPoints = findNearestPoints(
                        target: (x, y),
                        points: knownPoints,
                        count: 4
                    )
                    
                    if nearestPoints.count >= 4 {
                        interpolated[y][x] = bilinearInterpolate(
                            target: (x, y),
                            points: nearestPoints
                        )
                    } else if !nearestPoints.isEmpty {
                        // Fall back to weighted average
                        interpolated[y][x] = weightedAverage(
                            target: (x, y),
                            points: nearestPoints
                        )
                    }
                }
            }
        }
        
        return interpolated
    }
    
    private func applyBicubicInterpolation(
        grid: [[Float]],
        size: (width: Int, height: Int)
    ) -> [[Float]] {
        // Simplified bicubic interpolation
        var interpolated = applyBilinearInterpolation(grid: grid, size: size)
        
        // Apply cubic smoothing
        for _ in 0..<2 {
            interpolated = applyGaussianSmoothing(
                grid: interpolated,
                size: size,
                sigma: 1.5
            )
        }
        
        return interpolated
    }
    
    private func applyIDWInterpolation(
        grid: [[Float]],
        size: (width: Int, height: Int)
    ) -> [[Float]] {
        var interpolated = grid
        let power: Float = 2.0 // IDW power parameter
        
        // Collect known points
        var knownPoints: [(x: Int, y: Int, value: Float)] = []
        for y in 0..<size.height {
            for x in 0..<size.width {
                if grid[y][x] != -100.0 {
                    knownPoints.append((x, y, grid[y][x]))
                }
            }
        }
        
        // Interpolate unknown points using IDW
        for y in 0..<size.height {
            for x in 0..<size.width {
                if grid[y][x] == -100.0 {
                    var weightSum: Float = 0
                    var valueSum: Float = 0
                    
                    for point in knownPoints {
                        let dx = Float(x - point.x)
                        let dy = Float(y - point.y)
                        let distance = sqrt(dx * dx + dy * dy)
                        
                        if distance > 0 {
                            let weight = 1.0 / pow(distance, power)
                            weightSum += weight
                            valueSum += weight * point.value
                        } else {
                            // Point coincides with known point
                            interpolated[y][x] = point.value
                            weightSum = 1
                            valueSum = point.value
                            break
                        }
                    }
                    
                    if weightSum > 0 {
                        interpolated[y][x] = valueSum / weightSum
                    }
                }
            }
        }
        
        return interpolated
    }
    
    private func applyKrigingInterpolation(
        grid: [[Float]],
        size: (width: Int, height: Int)
    ) -> [[Float]] {
        // Simplified Kriging - using Gaussian process regression concepts
        // For full implementation, would need variogram modeling
        
        // For now, use IDW with adaptive radius
        return applyIDWInterpolation(grid: grid, size: size)
    }
    
    private func applySplineInterpolation(
        grid: [[Float]],
        size: (width: Int, height: Int)
    ) -> [[Float]] {
        // Simplified spline interpolation
        // Full implementation would use B-splines or thin-plate splines
        
        var interpolated = applyBilinearInterpolation(grid: grid, size: size)
        
        // Apply multiple smoothing passes for spline-like effect
        for _ in 0..<3 {
            interpolated = applyGaussianSmoothing(
                grid: interpolated,
                size: size,
                sigma: 2.0
            )
        }
        
        return interpolated
    }
    
    // MARK: - Smoothing
    
    private func applyGaussianSmoothing(
        grid: [[Float]],
        size: (width: Int, height: Int),
        sigma: Float
    ) -> [[Float]] {
        var smoothed = grid
        
        // Create Gaussian kernel
        let kernelSize = Int(ceil(sigma * 3)) * 2 + 1
        let kernel = createGaussianKernel(size: kernelSize, sigma: sigma)
        
        // Apply convolution
        let halfKernel = kernelSize / 2
        
        for y in halfKernel..<(size.height - halfKernel) {
            for x in halfKernel..<(size.width - halfKernel) {
                var sum: Float = 0
                var weightSum: Float = 0
                
                for ky in 0..<kernelSize {
                    for kx in 0..<kernelSize {
                        let sy = y + ky - halfKernel
                        let sx = x + kx - halfKernel
                        
                        if grid[sy][sx] != -100.0 {
                            let weight = kernel[ky][kx]
                            sum += grid[sy][sx] * weight
                            weightSum += weight
                        }
                    }
                }
                
                if weightSum > 0 {
                    smoothed[y][x] = sum / weightSum
                }
            }
        }
        
        return smoothed
    }
    
    private func createGaussianKernel(size: Int, sigma: Float) -> [[Float]] {
        var kernel = Array(repeating: Array(repeating: Float(0), count: size), count: size)
        let center = size / 2
        var sum: Float = 0
        
        for y in 0..<size {
            for x in 0..<size {
                let dx = Float(x - center)
                let dy = Float(y - center)
                let value = exp(-(dx * dx + dy * dy) / (2 * sigma * sigma))
                kernel[y][x] = value
                sum += value
            }
        }
        
        // Normalize
        for y in 0..<size {
            for x in 0..<size {
                kernel[y][x] /= sum
            }
        }
        
        return kernel
    }
    
    // MARK: - Image Creation
    
    private func createImage(from grid: [[Float]], size: CGSize) -> UIImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        
        // Create bitmap context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        // Draw heatmap
        for y in 0..<min(grid.count, height) {
            for x in 0..<min(grid[y].count, width) {
                let value = grid[y][x]
                let color = signalStrengthToColor(value)
                
                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        
        // Add contour lines
        if shouldDrawContours() {
            drawContourLines(on: context, grid: grid, size: (width, height))
        }
        
        // Create image
        guard let cgImage = context.makeImage() else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func signalStrengthToColor(_ strength: Float) -> UIColor {
        // Normalize signal strength to 0-1 range
        let minSignal: Float = -100.0
        let maxSignal: Float = -30.0
        let normalized = max(0, min(1, (strength - minSignal) / (maxSignal - minSignal)))
        
        // Get color scheme colors
        let colors = colorScheme.colors()
        
        // Interpolate between colors
        let colorIndex = normalized * Float(colors.count - 1)
        let lowerIndex = Int(floor(colorIndex))
        let upperIndex = min(lowerIndex + 1, colors.count - 1)
        let fraction = colorIndex - Float(lowerIndex)
        
        return interpolateColor(
            from: colors[lowerIndex],
            to: colors[upperIndex],
            fraction: CGFloat(fraction)
        )
    }
    
    private func interpolateColor(from: UIColor, to: UIColor, fraction: CGFloat) -> UIColor {
        var fromR: CGFloat = 0, fromG: CGFloat = 0, fromB: CGFloat = 0, fromA: CGFloat = 0
        var toR: CGFloat = 0, toG: CGFloat = 0, toB: CGFloat = 0, toA: CGFloat = 0
        
        from.getRed(&fromR, green: &fromG, blue: &fromB, alpha: &fromA)
        to.getRed(&toR, green: &toG, blue: &toB, alpha: &toA)
        
        let r = fromR + (toR - fromR) * fraction
        let g = fromG + (toG - fromG) * fraction
        let b = fromB + (toB - fromB) * fraction
        let a = fromA + (toA - fromA) * fraction
        
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
    
    // MARK: - Contour Lines
    
    private func shouldDrawContours() -> Bool {
        // Could be made configurable
        return true
    }
    
    private func drawContourLines(
        on context: CGContext,
        grid: [[Float]],
        size: (width: Int, height: Int)
    ) {
        let contourLevels: [Float] = [-80, -70, -60, -50, -40] // dBm levels
        
        context.setLineWidth(0.5)
        context.setAlpha(0.3)
        
        for level in contourLevels {
            context.setStrokeColor(contourColorForLevel(level).cgColor)
            
            // Simple contour detection
            for y in 1..<min(grid.count - 1, size.height - 1) {
                for x in 1..<min(grid[y].count - 1, size.width - 1) {
                    let current = grid[y][x]
                    
                    // Check if contour crosses this cell
                    if current >= level {
                        // Check neighbors
                        if x > 0 && grid[y][x-1] < level {
                            // Vertical line on left
                            context.move(to: CGPoint(x: x, y: y))
                            context.addLine(to: CGPoint(x: x, y: y + 1))
                            context.strokePath()
                        }
                        if y > 0 && grid[y-1][x] < level {
                            // Horizontal line on top
                            context.move(to: CGPoint(x: x, y: y))
                            context.addLine(to: CGPoint(x: x + 1, y: y))
                            context.strokePath()
                        }
                    }
                }
            }
        }
        
        context.setAlpha(1.0)
    }
    
    private func contourColorForLevel(_ level: Float) -> UIColor {
        switch level {
        case -40: return UIColor.green
        case -50: return UIColor.yellow
        case -60: return UIColor.orange
        case -70: return UIColor.red
        case -80: return UIColor.darkGray
        default: return UIColor.black
        }
    }
    
    // MARK: - Helper Methods
    
    private func findNearestPoints(
        target: (x: Int, y: Int),
        points: [(x: Int, y: Int, value: Float)],
        count: Int
    ) -> [(x: Int, y: Int, value: Float)] {
        let sorted = points.sorted { p1, p2 in
            let d1 = pow(Float(p1.x - target.x), 2) + pow(Float(p1.y - target.y), 2)
            let d2 = pow(Float(p2.x - target.x), 2) + pow(Float(p2.y - target.y), 2)
            return d1 < d2
        }
        
        return Array(sorted.prefix(count))
    }
    
    private func bilinearInterpolate(
        target: (x: Int, y: Int),
        points: [(x: Int, y: Int, value: Float)]
    ) -> Float {
        // Simplified bilinear interpolation
        return weightedAverage(target: target, points: points)
    }
    
    private func weightedAverage(
        target: (x: Int, y: Int),
        points: [(x: Int, y: Int, value: Float)]
    ) -> Float {
        var weightSum: Float = 0
        var valueSum: Float = 0
        
        for point in points {
            let dx = Float(target.x - point.x)
            let dy = Float(target.y - point.y)
            let distance = sqrt(dx * dx + dy * dy)
            
            let weight = distance > 0 ? 1.0 / distance : 1.0
            weightSum += weight
            valueSum += weight * point.value
        }
        
        return weightSum > 0 ? valueSum / weightSum : -100.0
    }
    
    // MARK: - Export Methods
    
    /// Export heatmap as data for external processing
    func exportHeatmapData() -> [String: Any] {
        guard let propagationData = cachedPropagationData else {
            return [:]
        }
        
        let data: [String: Any] = [
            "points": propagationData.map { point in
                [
                    "x": point.position.x,
                    "y": point.position.y,
                    "z": point.position.z,
                    "signal": point.signalStrength,
                    "quality": "\(point.quality)"
                ]
            },
            "metadata": [
                "resolution": resolution,
                "interpolation": "\(interpolationMethod)",
                "colorScheme": "\(colorScheme)"
            ]
        ]
        
        return data
    }
}