import UIKit
import RoomPlan
import simd
import CoreGraphics

// MARK: - Improved Floor Plan Generator
/// Advanced floor plan generator with RF propagation visualization
class ImprovedFloorPlanGenerator {
    
    // MARK: - Enums
    enum RenderStyle {
        case blueprint
        case architectural
        case modern
        case minimal
        case detailed
    }
    
    enum LayerType {
        case walls
        case doors
        case windows
        case furniture
        case dimensions
        case labels
        case grid
        case rfPropagation
        case networkDevices
    }
    
    // MARK: - Properties
    private var capturedRoom: CapturedRoom?
    private var rooms: [RoomAnalyzer.IdentifiedRoom] = []
    private var renderStyle: RenderStyle = .modern
    private var enabledLayers: Set<LayerType> = [.walls, .doors, .windows, .labels, .rfPropagation]
    private var scale: CGFloat = 50.0 // pixels per meter
    private var propagationModel: RFPropagationModel?
    private var heatmapGenerator: RFHeatmapGenerator?
    
    // Style configuration
    private var wallThickness: CGFloat = 4.0
    private var doorWidth: CGFloat = 0.9 // meters
    private var windowWidth: CGFloat = 1.2 // meters
    
    // Colors for different styles
    private var styleColors: [RenderStyle: StyleColorPalette] = [
        .blueprint: StyleColorPalette(
            background: UIColor(red: 0.0, green: 0.1, blue: 0.3, alpha: 1.0),
            walls: UIColor.white,
            doors: UIColor(red: 0.8, green: 0.8, blue: 1.0, alpha: 1.0),
            windows: UIColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 1.0),
            furniture: UIColor(red: 0.7, green: 0.7, blue: 0.9, alpha: 1.0),
            text: UIColor.white,
            grid: UIColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 0.3)
        ),
        .architectural: StyleColorPalette(
            background: UIColor.white,
            walls: UIColor.black,
            doors: UIColor.darkGray,
            windows: UIColor.gray,
            furniture: UIColor.lightGray,
            text: UIColor.black,
            grid: UIColor(white: 0.9, alpha: 1.0)
        ),
        .modern: StyleColorPalette(
            background: UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0),
            walls: UIColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 1.0),
            doors: UIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0),
            windows: UIColor(red: 0.5, green: 0.7, blue: 0.9, alpha: 1.0),
            furniture: UIColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1.0),
            text: UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0),
            grid: UIColor(white: 0.85, alpha: 0.5)
        ),
        .minimal: StyleColorPalette(
            background: UIColor.white,
            walls: UIColor(white: 0.2, alpha: 1.0),
            doors: UIColor(white: 0.5, alpha: 1.0),
            windows: UIColor(white: 0.6, alpha: 1.0),
            furniture: UIColor(white: 0.8, alpha: 1.0),
            text: UIColor(white: 0.3, alpha: 1.0),
            grid: UIColor.clear
        ),
        .detailed: StyleColorPalette(
            background: UIColor(red: 0.95, green: 0.95, blue: 0.92, alpha: 1.0),
            walls: UIColor(red: 0.3, green: 0.25, blue: 0.2, alpha: 1.0),
            doors: UIColor(red: 0.55, green: 0.35, blue: 0.15, alpha: 1.0),
            windows: UIColor(red: 0.4, green: 0.6, blue: 0.8, alpha: 0.8),
            furniture: UIColor(red: 0.6, green: 0.5, blue: 0.4, alpha: 1.0),
            text: UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0),
            grid: UIColor(red: 0.8, green: 0.8, blue: 0.75, alpha: 0.3)
        )
    ]
    
    struct StyleColorPalette {
        let background: UIColor
        let walls: UIColor
        let doors: UIColor
        let windows: UIColor
        let furniture: UIColor
        let text: UIColor
        let grid: UIColor
    }
    
    // MARK: - Initialization
    init() {
        print("🏗 Improved Floor Plan Generator initialized")
    }
    
    // MARK: - Configuration
    func configure(with capturedRoom: CapturedRoom?, rooms: [RoomAnalyzer.IdentifiedRoom]) {
        self.capturedRoom = capturedRoom
        self.rooms = rooms
        print("📐 Configured with \(rooms.count) rooms")
    }
    
    func setRenderStyle(_ style: RenderStyle) {
        self.renderStyle = style
    }
    
    func setEnabledLayers(_ layers: Set<LayerType>) {
        self.enabledLayers = layers
    }
    
    func setScale(_ scale: CGFloat) {
        self.scale = max(10, min(200, scale))
    }
    
    func setPropagationModel(_ model: RFPropagationModel) {
        self.propagationModel = model
        self.heatmapGenerator = RFHeatmapGenerator(propagationModel: model)
    }
    
    // MARK: - Floor Plan Generation
    
    /// Generate complete floor plan image
    func generateFloorPlan(size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, true, 0.0)
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        
        // Get style colors
        let colors = styleColors[renderStyle] ?? styleColors[.modern]!
        
        // Draw background
        drawBackground(context: context, size: size, color: colors.background)
        
        // Draw grid if enabled
        if enabledLayers.contains(.grid) {
            drawGrid(context: context, size: size, color: colors.grid)
        }
        
        // Calculate transform for centering and scaling
        let transform = calculateTransform(for: size)
        context.concatenate(transform)
        
        // Draw RF propagation heatmap if enabled (underneath floor plan)
        if enabledLayers.contains(.rfPropagation), let heatmapGen = heatmapGenerator {
            drawRFPropagation(context: context, generator: heatmapGen, transform: transform, size: size)
        }
        
        // Draw floor plan layers
        if enabledLayers.contains(.walls) {
            drawWalls(context: context, color: colors.walls)
        }
        
        if enabledLayers.contains(.doors) {
            drawDoors(context: context, color: colors.doors)
        }
        
        if enabledLayers.contains(.windows) {
            drawWindows(context: context, color: colors.windows)
        }
        
        if enabledLayers.contains(.furniture) {
            drawFurniture(context: context, color: colors.furniture)
        }
        
        if enabledLayers.contains(.networkDevices) {
            drawNetworkDevices(context: context)
        }
        
        // Reset transform for UI elements
        context.concatenate(transform.inverted())
        
        if enabledLayers.contains(.labels) {
            drawRoomLabels(context: context, transform: transform, color: colors.text)
        }
        
        if enabledLayers.contains(.dimensions) {
            drawDimensions(context: context, transform: transform, color: colors.text)
        }
        
        // Draw legend
        drawLegend(context: context, size: size, colors: colors)
        
        // Draw scale
        drawScale(context: context, size: size, color: colors.text)
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image
    }
    
    // MARK: - Drawing Methods
    
    private func drawBackground(context: CGContext, size: CGSize, color: UIColor) {
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
    }
    
    private func drawGrid(context: CGContext, size: CGSize, color: UIColor) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(0.5)
        
        let gridSpacing: CGFloat = scale // 1 meter grid
        
        // Vertical lines
        var x: CGFloat = 0
        while x < size.width {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: size.height))
            x += gridSpacing
        }
        
        // Horizontal lines
        var y: CGFloat = 0
        while y < size.height {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: size.width, y: y))
            y += gridSpacing
        }
        
        context.strokePath()
    }
    
    private func drawWalls(context: CGContext, color: UIColor) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(wallThickness)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // Draw walls from captured room data if available
        if let room = capturedRoom {
            for surface in room.walls {
                drawSurface(context: context, surface: surface)
            }
        }
        
        // Draw walls from analyzed rooms
        for room in rooms {
            drawRoomWalls(context: context, room: room)
        }
        
        context.strokePath()
    }
    
    private func drawRoomWalls(context: CGContext, room: RoomAnalyzer.IdentifiedRoom) {
        let points = room.wallPoints
        guard points.count >= 3 else { return }
        
        context.beginPath()
        
        // Convert 3D points to 2D and scale
        let scaledPoints = points.map { point in
            CGPoint(x: CGFloat(point.x) * scale, y: CGFloat(point.z) * scale)
        }
        
        // Draw walls
        context.move(to: scaledPoints[0])
        for i in 1..<scaledPoints.count {
            context.addLine(to: scaledPoints[i])
        }
        context.closePath()
        context.strokePath()
    }
    
    private func drawDoors(context: CGContext, color: UIColor) {
        guard let room = capturedRoom else { return }
        
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2.0)
        
        for door in room.doors {
            drawDoorSymbol(context: context, door: door)
        }
    }
    
    private func drawDoorSymbol(context: CGContext, door: CapturedRoom.Surface) {
        let center = door.transform.position
        let scaledCenter = CGPoint(x: CGFloat(center.x) * scale, y: CGFloat(center.z) * scale)
        
        // Draw door arc
        let doorRadius = CGFloat(doorWidth) * scale / 2
        
        context.saveGState()
        context.translateBy(x: scaledCenter.x, y: scaledCenter.y)
        
        // Draw door swing arc
        context.setLineDash(phase: 0, lengths: [2, 2])
        context.addArc(center: .zero, radius: doorRadius, startAngle: 0, endAngle: .pi / 2, clockwise: false)
        context.strokePath()
        
        // Draw door panel
        context.setLineDash(phase: 0, lengths: [])
        context.move(to: CGPoint(x: -doorRadius, y: 0))
        context.addLine(to: CGPoint(x: doorRadius, y: 0))
        context.strokePath()
        
        context.restoreGState()
    }
    
    private func drawWindows(context: CGContext, color: UIColor) {
        guard let room = capturedRoom else { return }
        
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(3.0)
        
        for window in room.windows {
            drawWindowSymbol(context: context, window: window)
        }
    }
    
    private func drawWindowSymbol(context: CGContext, window: CapturedRoom.Surface) {
        let center = window.transform.position
        let scaledCenter = CGPoint(x: CGFloat(center.x) * scale, y: CGFloat(center.z) * scale)
        let windowHalfWidth = CGFloat(windowWidth) * scale / 2
        
        // Draw window with double lines
        context.saveGState()
        context.translateBy(x: scaledCenter.x, y: scaledCenter.y)
        
        // Outer line
        context.move(to: CGPoint(x: -windowHalfWidth, y: -2))
        context.addLine(to: CGPoint(x: windowHalfWidth, y: -2))
        
        // Inner line
        context.move(to: CGPoint(x: -windowHalfWidth, y: 2))
        context.addLine(to: CGPoint(x: windowHalfWidth, y: 2))
        
        context.strokePath()
        context.restoreGState()
    }
    
    private func drawFurniture(context: CGContext, color: UIColor) {
        guard let room = capturedRoom else { return }
        
        context.setFillColor(color.cgColor)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.0)
        
        for object in room.objects {
            drawFurnitureObject(context: context, object: object)
        }
    }
    
    private func drawFurnitureObject(context: CGContext, object: CapturedRoom.Object) {
        let position = object.transform.position
        let scaledPosition = CGPoint(x: CGFloat(position.x) * scale, y: CGFloat(position.z) * scale)
        let size = object.dimensions
        let scaledSize = CGSize(width: CGFloat(size.x) * scale, height: CGFloat(size.z) * scale)
        
        // Draw furniture as rectangles with rounded corners
        let rect = CGRect(
            x: scaledPosition.x - scaledSize.width / 2,
            y: scaledPosition.y - scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
        
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 2.0)
        context.addPath(path.cgPath)
        context.fillPath()
        
        // Add outline
        context.addPath(path.cgPath)
        context.strokePath()
    }
    
    private func drawRFPropagation(context: CGContext, generator: RFHeatmapGenerator, transform: CGAffineTransform, size: CGSize) {
        // Generate heatmap image
        if let heatmapImage = generator.generateHeatmapImage(size: size) {
            context.saveGState()
            
            // Reset transform to draw heatmap in screen coordinates
            context.concatenate(transform.inverted())
            
            // Set blend mode for overlay
            context.setBlendMode(.multiply)
            context.setAlpha(0.6)
            
            // Draw heatmap
            if let cgImage = heatmapImage.cgImage {
                context.draw(cgImage, in: CGRect(origin: .zero, size: size))
            }
            
            context.restoreGState()
        }
    }
    
    private func drawNetworkDevices(context: CGContext) {
        guard let model = propagationModel else { return }
        
        // This would draw access points and network devices
        // Implementation would depend on network device data structure
    }
    
    private func drawRoomLabels(context: CGContext, transform: CGAffineTransform, color: UIColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: color
        ]
        
        for room in rooms {
            // Calculate room center
            let center = calculateRoomCenter(room: room)
            let transformedCenter = center.applying(transform)
            
            // Draw room type label
            let label = room.type.rawValue
            let size = label.size(withAttributes: attributes)
            let rect = CGRect(
                x: transformedCenter.x - size.width / 2,
                y: transformedCenter.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            
            label.draw(in: rect, withAttributes: attributes)
            
            // Draw room area if available
            if room.floorArea > 0 {
                let areaLabel = String(format: "%.1f m²", room.floorArea)
                let areaAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11),
                    .foregroundColor: color.withAlphaComponent(0.7)
                ]
                
                let areaSize = areaLabel.size(withAttributes: areaAttributes)
                let areaRect = CGRect(
                    x: transformedCenter.x - areaSize.width / 2,
                    y: transformedCenter.y + size.height / 2 + 2,
                    width: areaSize.width,
                    height: areaSize.height
                )
                
                areaLabel.draw(in: areaRect, withAttributes: areaAttributes)
            }
        }
    }
    
    private func drawDimensions(context: CGContext, transform: CGAffineTransform, color: UIColor) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(0.5)
        
        // Draw dimension lines for rooms
        for room in rooms {
            drawRoomDimensions(context: context, room: room, transform: transform, color: color)
        }
    }
    
    private func drawRoomDimensions(context: CGContext, room: RoomAnalyzer.IdentifiedRoom, transform: CGAffineTransform, color: UIColor) {
        let points = room.wallPoints
        guard points.count >= 2 else { return }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: color
        ]
        
        // Draw dimensions for each wall
        for i in 0..<points.count {
            let start = points[i]
            let end = points[(i + 1) % points.count]
            
            let startPoint = CGPoint(x: CGFloat(start.x) * scale, y: CGFloat(start.z) * scale).applying(transform)
            let endPoint = CGPoint(x: CGFloat(end.x) * scale, y: CGFloat(end.z) * scale).applying(transform)
            
            let distance = simd_distance(start, end)
            let label = String(format: "%.2fm", distance)
            
            // Calculate midpoint
            let midPoint = CGPoint(
                x: (startPoint.x + endPoint.x) / 2,
                y: (startPoint.y + endPoint.y) / 2
            )
            
            // Draw dimension line
            context.saveGState()
            context.setLineDash(phase: 0, lengths: [2, 2])
            context.move(to: startPoint)
            context.addLine(to: endPoint)
            context.strokePath()
            context.restoreGState()
            
            // Draw dimension text
            let size = label.size(withAttributes: attributes)
            let rect = CGRect(
                x: midPoint.x - size.width / 2,
                y: midPoint.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            
            // Add white background for readability
            context.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor)
            context.fill(rect.insetBy(dx: -2, dy: -1))
            
            label.draw(in: rect, withAttributes: attributes)
        }
    }
    
    private func drawLegend(context: CGContext, size: CGSize, colors: StyleColorPalette) {
        if !enabledLayers.contains(.rfPropagation) { return }
        
        let legendWidth: CGFloat = 150
        let legendHeight: CGFloat = 100
        let margin: CGFloat = 20
        
        let legendRect = CGRect(
            x: size.width - legendWidth - margin,
            y: margin,
            width: legendWidth,
            height: legendHeight
        )
        
        // Draw legend background
        context.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        context.fill(legendRect)
        context.setStrokeColor(colors.text.cgColor)
        context.setLineWidth(1.0)
        context.stroke(legendRect)
        
        // Draw legend title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: colors.text
        ]
        
        let title = "Signal Strength"
        title.draw(at: CGPoint(x: legendRect.minX + 10, y: legendRect.minY + 5), withAttributes: titleAttributes)
        
        // Draw color gradient
        let gradientRect = CGRect(
            x: legendRect.minX + 10,
            y: legendRect.minY + 25,
            width: 20,
            height: 60
        )
        
        drawSignalGradient(context: context, rect: gradientRect)
        
        // Draw labels
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: colors.text
        ]
        
        let labels = [
            ("Excellent", "-30 dBm"),
            ("Good", "-50 dBm"),
            ("Fair", "-70 dBm"),
            ("Poor", "-85 dBm")
        ]
        
        for (index, (quality, strength)) in labels.enumerated() {
            let y = gradientRect.minY + CGFloat(index) * 15
            quality.draw(at: CGPoint(x: gradientRect.maxX + 5, y: y), withAttributes: labelAttributes)
            strength.draw(at: CGPoint(x: gradientRect.maxX + 50, y: y), withAttributes: labelAttributes)
        }
    }
    
    private func drawSignalGradient(context: CGContext, rect: CGRect) {
        let colors = [
            UIColor.green.cgColor,
            UIColor.yellow.cgColor,
            UIColor.orange.cgColor,
            UIColor.red.cgColor
        ]
        
        let locations: [CGFloat] = [0.0, 0.33, 0.66, 1.0]
        
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: locations
        ) else { return }
        
        context.saveGState()
        context.addRect(rect)
        context.clip()
        
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
        
        context.restoreGState()
    }
    
    private func drawScale(context: CGContext, size: CGSize, color: UIColor) {
        let scaleLength: CGFloat = 100
        let margin: CGFloat = 20
        
        let startPoint = CGPoint(x: margin, y: size.height - margin)
        let endPoint = CGPoint(x: margin + scaleLength, y: size.height - margin)
        
        // Draw scale line
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2.0)
        context.move(to: startPoint)
        context.addLine(to: endPoint)
        context.strokePath()
        
        // Draw end caps
        context.move(to: CGPoint(x: startPoint.x, y: startPoint.y - 5))
        context.addLine(to: CGPoint(x: startPoint.x, y: startPoint.y + 5))
        context.move(to: CGPoint(x: endPoint.x, y: endPoint.y - 5))
        context.addLine(to: CGPoint(x: endPoint.x, y: endPoint.y + 5))
        context.strokePath()
        
        // Draw scale label
        let meters = scaleLength / scale
        let label = String(format: "%.1f m", meters)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: color
        ]
        
        let labelSize = label.size(withAttributes: attributes)
        let labelPoint = CGPoint(
            x: startPoint.x + (scaleLength - labelSize.width) / 2,
            y: startPoint.y - labelSize.height - 5
        )
        
        label.draw(at: labelPoint, withAttributes: attributes)
    }
    
    // MARK: - Helper Methods
    
    private func calculateTransform(for size: CGSize) -> CGAffineTransform {
        guard !rooms.isEmpty else {
            return CGAffineTransform.identity
        }
        
        // Calculate bounds
        let allPoints = rooms.flatMap { $0.wallPoints }
        guard !allPoints.isEmpty else {
            return CGAffineTransform.identity
        }
        
        let xValues = allPoints.map { CGFloat($0.x) * scale }
        let zValues = allPoints.map { CGFloat($0.z) * scale }
        
        let minX = xValues.min() ?? 0
        let maxX = xValues.max() ?? 0
        let minZ = zValues.min() ?? 0
        let maxZ = zValues.max() ?? 0
        
        let floorPlanWidth = maxX - minX
        let floorPlanHeight = maxZ - minZ
        
        // Calculate scale to fit
        let scaleX = (size.width - 100) / max(floorPlanWidth, 1)
        let scaleY = (size.height - 100) / max(floorPlanHeight, 1)
        let fitScale = min(scaleX, scaleY, 1.0)
        
        // Calculate translation to center
        let centerX = size.width / 2
        let centerY = size.height / 2
        let floorPlanCenterX = (minX + maxX) / 2
        let floorPlanCenterY = (minZ + maxZ) / 2
        
        // Create transform
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: centerX, y: centerY)
        transform = transform.scaledBy(x: fitScale, y: fitScale)
        transform = transform.translatedBy(x: -floorPlanCenterX, y: -floorPlanCenterY)
        
        return transform
    }
    
    private func calculateRoomCenter(room: RoomAnalyzer.IdentifiedRoom) -> CGPoint {
        let points = room.wallPoints
        guard !points.isEmpty else {
            return .zero
        }
        
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumZ = points.reduce(0) { $0 + $1.z }
        
        return CGPoint(
            x: CGFloat(sumX / Float(points.count)) * scale,
            y: CGFloat(sumZ / Float(points.count)) * scale
        )
    }
    
    private func drawSurface(context: CGContext, surface: CapturedRoom.Surface) {
        // Convert surface to path
        let transform = surface.transform
        let dimensions = surface.dimensions
        
        let position = transform.position
        let scaledPosition = CGPoint(x: CGFloat(position.x) * scale, y: CGFloat(position.z) * scale)
        
        // Draw surface outline
        let rect = CGRect(
            x: scaledPosition.x - CGFloat(dimensions.x) * scale / 2,
            y: scaledPosition.y - CGFloat(dimensions.y) * scale / 2,
            width: CGFloat(dimensions.x) * scale,
            height: CGFloat(dimensions.y) * scale
        )
        
        context.addRect(rect)
    }
    
    // MARK: - Export Methods
    
    /// Export floor plan as PDF
    func exportAsPDF(size: CGSize) -> Data? {
        let pdfData = NSMutableData()
        
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return nil
        }
        
        pdfContext.beginPDFPage(nil)
        
        // Draw floor plan to PDF context
        if let floorPlanImage = generateFloorPlan(size: size),
           let cgImage = floorPlanImage.cgImage {
            pdfContext.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }
        
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        
        return pdfData as Data
    }
    
    /// Export floor plan as SVG
    func exportAsSVG(size: CGSize) -> String {
        var svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg width="\(size.width)" height="\(size.height)" xmlns="http://www.w3.org/2000/svg">
        """
        
        // Add background
        let colors = styleColors[renderStyle] ?? styleColors[.modern]!
        svg += """
        <rect width="\(size.width)" height="\(size.height)" fill="\(colors.background.hexString)"/>
        """
        
        // Add walls
        for room in rooms {
            svg += createSVGPath(for: room, color: colors.walls)
        }
        
        svg += "</svg>"
        
        return svg
    }
    
    private func createSVGPath(for room: RoomAnalyzer.IdentifiedRoom, color: UIColor) -> String {
        let points = room.wallPoints
        guard !points.isEmpty else { return "" }
        
        var path = "<path d=\""
        
        for (index, point) in points.enumerated() {
            let x = CGFloat(point.x) * scale
            let y = CGFloat(point.z) * scale
            
            if index == 0 {
                path += "M \(x) \(y) "
            } else {
                path += "L \(x) \(y) "
            }
        }
        
        path += "Z\" stroke=\"\(color.hexString)\" stroke-width=\"\(wallThickness)\" fill=\"none\"/>"
        
        return path
    }
}

// MARK: - UIColor Extension
extension UIColor {
    var hexString: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        getRed(&r, green: &g, blue: &b, alpha: &a)
        
        return String(format: "#%02X%02X%02X", 
                     Int(r * 255), 
                     Int(g * 255), 
                     Int(b * 255))
    }
}