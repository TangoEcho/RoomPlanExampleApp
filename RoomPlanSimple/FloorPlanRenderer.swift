import UIKit
import simd
import RoomPlan

// MARK: - UIColor Extension
extension UIColor {
    func darker(by percentage: CGFloat = 0.3) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        self.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        return UIColor(
            red: max(red - percentage, 0),
            green: max(green - percentage, 0),
            blue: max(blue - percentage, 0),
            alpha: alpha
        )
    }
}

class FloorPlanRenderer: UIView {
    
    // MARK: - Properties
    private var rooms: [RoomAnalyzer.IdentifiedRoom] = []
    private var furnitureItems: [RoomAnalyzer.FurnitureItem] = []
    private var heatmapData: WiFiHeatmapData?
    private var networkDevices: [NetworkDevice] = []
    private var showHeatmap = false
    
    // Drawing properties
    private let roomStrokeWidth: CGFloat = 2.0
    private let heatmapAlpha: CGFloat = 0.6
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = UIColor.systemGray6
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = UIColor.systemGray4.cgColor
    }
    
    // MARK: - Public Methods
    
    func updateRooms(_ rooms: [RoomAnalyzer.IdentifiedRoom]) {
        print("🏠 FloorPlanRenderer: Received \(rooms.count) rooms for rendering")
        
        // Validate room boundaries before storing
        self.rooms = rooms.filter { room in
            print("   Room \(room.type.rawValue): \(room.wallPoints.count) wall points")
            guard room.wallPoints.count >= 3 else {
                print("⚠️ FloorPlanRenderer: Skipping room with insufficient boundary points (\(room.wallPoints.count))")
                return false
            }
            return true
        }
        
        print("✅ FloorPlanRenderer: Filtered to \(self.rooms.count) valid rooms")
        setNeedsDisplay()
    }
    
    func updateFurniture(_ furniture: [RoomAnalyzer.FurnitureItem]) {
        self.furnitureItems = furniture
        setNeedsDisplay()
    }
    
    func updateHeatmap(_ data: WiFiHeatmapData?) {
        self.heatmapData = data
        if showHeatmap {
            setNeedsDisplay()
        }
    }
    
    func updateNetworkDevices(_ devices: [NetworkDevice]) {
        self.networkDevices = devices
        setNeedsDisplay()
    }
    
    func setShowHeatmap(_ show: Bool) {
        self.showHeatmap = show
        setNeedsDisplay()
    }
    
    // MARK: - Drawing
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        print("🎨 FloorPlanRenderer: draw() called - \(rooms.count) rooms, \(furnitureItems.count) furniture")
        print("🎨 FloorPlanRenderer: View frame: \(frame), bounds: \(bounds)")
        print("🎨 FloorPlanRenderer: Draw rect: \(rect)")
        print("🎨 FloorPlanRenderer: Background color: \(backgroundColor?.description ?? "nil")")
        print("🎨 FloorPlanRenderer: IsHidden: \(isHidden), Alpha: \(alpha)")
        
        guard let context = UIGraphicsGetCurrentContext() else { 
            print("❌ FloorPlanRenderer: No graphics context available!")
            return 
        }
        
        // Clear the context with a visible background for debugging
        context.clear(rect)
        
        // Fill with background color to make sure the view is visible
        if let bgColor = backgroundColor {
            context.setFillColor(bgColor.cgColor)
            context.fill(rect)
        }
        
        
        // Draw rooms
        drawRooms(in: context, rect: rect)
        
        // Draw furniture items
        drawFurniture(in: context, rect: rect)
        
        // Always draw WiFi test points if heatmap data exists
        if let heatmapData = heatmapData {
            drawWiFiTestPoints(heatmapData, in: context, rect: rect)
        }
        
        // Draw heatmap overlay if enabled
        if showHeatmap, let heatmapData = heatmapData {
            drawHeatmapOverlay(heatmapData, in: context, rect: rect)
        }
        
        // Draw network devices
        drawNetworkDevices(in: context, rect: rect)
    }
    
    private func drawRooms(in context: CGContext, rect: CGRect) {
        print("🎨 FloorPlanRenderer: Drawing \(rooms.count) rooms")
        
        // Always draw placeholder room when no rooms available or in simulator
        if rooms.isEmpty {
            print("⚠️ FloorPlanRenderer: No rooms to draw, showing placeholder")
            drawPlaceholderRoom(in: context, rect: rect)
            return
        }
        
        // Calculate bounds for all rooms to fit them in the view
        let allPoints = rooms.flatMap { $0.wallPoints }
        guard !allPoints.isEmpty else { return }
        
        let minX = allPoints.map { $0.x }.min() ?? 0
        let maxX = allPoints.map { $0.x }.max() ?? 0
        let minY = allPoints.map { $0.y }.min() ?? 0
        let maxY = allPoints.map { $0.y }.max() ?? 0
        
        let roomWidth = maxX - minX
        let roomHeight = maxY - minY
        
        // Prevent division by zero
        guard roomWidth > 0 && roomHeight > 0 else {
            drawPlaceholderRoom(in: context, rect: rect)
            return
        }
        
        // Calculate scale to fit room in view with padding
        let padding: CGFloat = 20
        let availableWidth = rect.width - (padding * 2)
        let availableHeight = rect.height - (padding * 2)
        
        let scaleX = availableWidth / CGFloat(roomWidth)
        let scaleY = availableHeight / CGFloat(roomHeight)
        let scale = min(scaleX, scaleY)
        
        // Calculate offset to center the room
        let scaledRoomWidth = CGFloat(roomWidth) * scale
        let scaledRoomHeight = CGFloat(roomHeight) * scale
        let offsetX = (rect.width - scaledRoomWidth) / 2 - CGFloat(minX) * scale
        let offsetY = (rect.height - scaledRoomHeight) / 2 - CGFloat(minY) * scale
        
        // Draw each room
        for (index, room) in rooms.enumerated() {
            drawRoom(room, in: context, scale: scale, offsetX: offsetX, offsetY: offsetY, roomIndex: index)
        }
    }
    
    private func drawRoom(_ room: RoomAnalyzer.IdentifiedRoom, in context: CGContext, scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat, roomIndex: Int) {
        // Ensure we have enough points to draw a room
        guard room.wallPoints.count >= 3 else {
            print("⚠️ FloorPlanRenderer: Cannot draw room with \(room.wallPoints.count) points")
            return
        }
        
        // Debug: Print raw room data
        print("🔍 FloorPlanRenderer: Drawing room '\(room.type.rawValue)' with \(room.wallPoints.count) wall points:")
        for (i, point) in room.wallPoints.enumerated() {
            print("   Point \(i): (\(point.x), \(point.y))")
        }
        
        // Sort wall points in counterclockwise order to ensure proper room boundary
        let sortedPoints = sortWallPointsCounterclockwise(room.wallPoints)
        
        // Additional validation to prevent boundary assertion errors
        let uniquePoints = sortedPoints.reduce(into: [simd_float2]()) { result, point in
            if !result.contains(where: { abs($0.x - point.x) < 0.01 && abs($0.y - point.y) < 0.01 }) {
                result.append(point)
            }
        }
        
        guard uniquePoints.count >= 3 else {
            print("⚠️ FloorPlanRenderer: Room has insufficient unique points after deduplication (\(uniquePoints.count))")
            return
        }
        
        print("🔍 FloorPlanRenderer: Using \(uniquePoints.count) unique points after sorting and deduplication")
        print("🔍 FloorPlanRenderer: Transform - scale: \(scale), offsetX: \(offsetX), offsetY: \(offsetY)")
        
        // Convert room points to view coordinates using unique points
        let viewPoints = uniquePoints.map { point in
            CGPoint(x: CGFloat(point.x) * scale + offsetX,
                   y: CGFloat(point.y) * scale + offsetY)
        }
        
        print("🔍 FloorPlanRenderer: Transformed view points:")
        for (i, point) in viewPoints.enumerated() {
            print("   ViewPoint \(i): (\(point.x), \(point.y))")
        }
        
        // Create path for room boundary - using safe path creation
        let path = CGMutablePath()
        if let firstPoint = viewPoints.first {
            path.move(to: firstPoint)
            
            // Add lines to subsequent points
            for i in 1..<viewPoints.count {
                path.addLine(to: viewPoints[i])
            }
            
            // Close the path only if we have more than 2 points
            if viewPoints.count > 2 {
                path.closeSubpath()
            }
        }
        
        // Use different colors for different room types to distinguish overlaps
        let (fillColor, strokeColor) = getRoomColors(for: room.type, roomIndex: roomIndex)
        
        // Set room fill color with room-specific transparency
        context.setFillColor(fillColor.withAlphaComponent(0.2).cgColor)
        context.addPath(path)
        context.fillPath()
        
        // Draw room boundary with room-specific color
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(roomStrokeWidth)
        context.addPath(path)
        context.strokePath()
        
        // Draw room label if there's space
        if let centerPoint = calculateRoomCenter(viewPoints) {
            drawRoomLabel(room.type.rawValue, at: centerPoint, in: context)
        }
    }
    
    private func sortWallPointsCounterclockwise(_ points: [simd_float2]) -> [simd_float2] {
        // Calculate the centroid
        let centroidX = points.map { $0.x }.reduce(0, +) / Float(points.count)
        let centroidY = points.map { $0.y }.reduce(0, +) / Float(points.count)
        let centroid = simd_float2(centroidX, centroidY)
        
        // Sort points by angle from centroid
        let sortedPoints = points.sorted { point1, point2 in
            let angle1 = atan2(point1.y - centroid.y, point1.x - centroid.x)
            let angle2 = atan2(point2.y - centroid.y, point2.x - centroid.x)
            return angle1 < angle2
        }
        
        print("🔧 Sorted \(points.count) wall points counterclockwise around centroid (\(centroidX), \(centroidY))")
        return sortedPoints
    }
    
    private func getRoomColors(for roomType: RoomType, roomIndex: Int) -> (fill: UIColor, stroke: UIColor) {
        switch roomType {
        case .kitchen:
            return (.systemOrange, .systemRed)
        case .livingRoom:
            return (.systemBlue, .systemBlue)
        case .bedroom:
            return (.systemPink, .systemRed)
        case .bathroom:
            return (.systemCyan, .systemBlue)
        case .diningRoom:
            return (.systemPurple, .systemPurple)
        case .office:
            return (.systemGreen, .systemGreen)
        case .hallway:
            return (.systemGray, .systemGray2)
        case .closet:
            return (.systemBrown, .systemBrown)
        case .laundryRoom:
            return (.systemTeal, .systemBlue)
        case .garage:
            return (.systemIndigo, .systemPurple)
        case .unknown:
            // Use different colors for different room indices to help distinguish overlapping rooms
            let colors: [(UIColor, UIColor)] = [
                (.systemYellow, .systemOrange),
                (.systemMint, .systemGreen), 
                (.systemGray4, .systemGray2),
                (.systemOrange, .systemRed),
                (.systemYellow, .systemOrange),
                (.systemPink, .systemRed)
            ]
            return colors[roomIndex % colors.count]
        }
    }
    
    private func drawPlaceholderRoom(in context: CGContext, rect: CGRect) {
        print("🎨 FloorPlanRenderer: Drawing placeholder room in rect: \(rect)")
        
        // Draw a more visible placeholder room
        let padding: CGFloat = 40
        let roomRect = rect.insetBy(dx: padding, dy: padding)
        
        let path = CGMutablePath()
        path.addRect(roomRect)
        
        // Fill with more visible color
        context.setFillColor(UIColor.systemGray4.withAlphaComponent(0.6).cgColor)
        context.addPath(path)
        context.fillPath()
        
        // Border with thicker line
        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setLineWidth(3.0)
        context.addPath(path)
        context.strokePath()
        
        // Add some furniture placeholder
        let furnitureRect = CGRect(x: roomRect.midX - 30, y: roomRect.midY - 15, width: 60, height: 30)
        context.setFillColor(UIColor.systemBrown.withAlphaComponent(0.7).cgColor)
        context.fill(furnitureRect)
        context.setStrokeColor(UIColor.systemBrown.cgColor)
        context.setLineWidth(2.0)
        context.stroke(furnitureRect)
        
        // Label
        let center = CGPoint(x: roomRect.midX, y: roomRect.midY + 50)
        drawRoomLabel("Sample Room Layout", at: center, in: context)
        
        // Add WiFi points placeholder
        let wifiPoint1 = CGPoint(x: roomRect.minX + 60, y: roomRect.minY + 60)
        let wifiPoint2 = CGPoint(x: roomRect.maxX - 60, y: roomRect.minY + 60)
        let wifiPoint3 = CGPoint(x: roomRect.midX, y: roomRect.maxY - 60)
        
        for point in [wifiPoint1, wifiPoint2, wifiPoint3] {
            drawMeasurementPoint(at: point, color: UIColor.systemGreen, in: context)
        }
    }
    
    private func calculateRoomCenter(_ points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        
        return CGPoint(x: sumX / CGFloat(points.count),
                      y: sumY / CGFloat(points.count))
    }
    
    private func drawRoomLabel(_ text: String, at point: CGPoint, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.label
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let size = attributedString.size()
        
        let rect = CGRect(x: point.x - size.width / 2,
                         y: point.y - size.height / 2,
                         width: size.width,
                         height: size.height)
        
        attributedString.draw(in: rect)
    }
    
    private func drawWiFiTestPoints(_ data: WiFiHeatmapData, in context: CGContext, rect: CGRect) {
        // Draw WiFi test points as colored circles - always visible
        guard !data.measurements.isEmpty else { return }
        
        // Use the SAME coordinate transform as rooms for consistency
        let transform = calculateRoomCoordinateTransform(in: rect)
        guard let transform = transform else { 
            print("⚠️ FloorPlanRenderer: No coordinate transform available for WiFi points")
            return 
        }
        
        print("📍 FloorPlanRenderer: Drawing \(data.measurements.count) WiFi measurements with room coordinate system")
        
        // Draw measurement points using room coordinate system
        for measurement in data.measurements {
            let viewPoint = CGPoint(
                x: CGFloat(measurement.location.x) * transform.scale + transform.offsetX,
                y: CGFloat(measurement.location.z) * transform.scale + transform.offsetY
            )
            
            print("   WiFi Point: (\(measurement.location.x), \(measurement.location.z)) -> View: (\(viewPoint.x), \(viewPoint.y))")
            
            let color = colorForSignalStrength(Float(measurement.signalStrength))
            drawMeasurementPoint(at: viewPoint, color: color, in: context, alpha: 1.0)
        }
    }
    
    private func drawHeatmapOverlay(_ data: WiFiHeatmapData, in context: CGContext, rect: CGRect) {
        // Draw heatmap overlay with transparency - only when heatmap toggle is on
        guard !data.measurements.isEmpty else { return }
        
        // Use the SAME coordinate transform as rooms for consistency
        let transform = calculateRoomCoordinateTransform(in: rect)
        guard let transform = transform else { return }
        
        // Draw semi-transparent heatmap overlay
        for measurement in data.measurements {
            let viewPoint = CGPoint(
                x: CGFloat(measurement.location.x) * transform.scale + transform.offsetX,
                y: CGFloat(measurement.location.z) * transform.scale + transform.offsetY
            )
            
            let color = colorForSignalStrength(Float(measurement.signalStrength))
            drawHeatmapArea(at: viewPoint, color: color, in: context, radius: 30)
        }
    }
    
    private struct CoordinateTransform {
        let scale: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
    }
    
    private func calculateRoomCoordinateTransform(in rect: CGRect) -> CoordinateTransform? {
        // Use room wall points if available, otherwise fallback to reasonable defaults
        if !rooms.isEmpty {
            // Calculate bounds from all room wall points
            let allPoints = rooms.flatMap { $0.wallPoints }
            let minX = allPoints.map { $0.x }.min() ?? 0
            let maxX = allPoints.map { $0.x }.max() ?? 0
            let minY = allPoints.map { $0.y }.min() ?? 0
            let maxY = allPoints.map { $0.y }.max() ?? 0
            
            let roomWidth = maxX - minX
            let roomHeight = maxY - minY
            
            guard roomWidth > 0 && roomHeight > 0 else { return nil }
            
            let padding: CGFloat = 20
            let availableWidth = rect.width - (padding * 2)
            let availableHeight = rect.height - (padding * 2)
            
            let scaleX = availableWidth / CGFloat(roomWidth)
            let scaleY = availableHeight / CGFloat(roomHeight)
            let scale = min(scaleX, scaleY)
            
            let scaledRoomWidth = CGFloat(roomWidth) * scale
            let scaledRoomHeight = CGFloat(roomHeight) * scale
            let offsetX = (rect.width - scaledRoomWidth) / 2 - CGFloat(minX) * scale
            let offsetY = (rect.height - scaledRoomHeight) / 2 - CGFloat(minY) * scale
            
            print("🔧 Room coordinate transform - scale: \(scale), offsetX: \(offsetX), offsetY: \(offsetY)")
            print("   Room bounds: (\(minX), \(minY)) to (\(maxX), \(maxY))")
            
            return CoordinateTransform(scale: scale, offsetX: offsetX, offsetY: offsetY)
        } else {
            // Fallback for when no rooms are available - use default coordinate space
            let defaultScale: CGFloat = 30.0  // pixels per unit
            let centerX = rect.width / 2
            let centerY = rect.height / 2
            
            print("🔧 Using fallback coordinate transform - scale: \(defaultScale)")
            
            return CoordinateTransform(scale: defaultScale, offsetX: centerX, offsetY: centerY)
        }
    }
    
    private func calculateCoordinateTransform(for measurements: [WiFiMeasurement], in rect: CGRect) -> CoordinateTransform? {
        // Deprecated - use calculateRoomCoordinateTransform instead for consistency
        return calculateRoomCoordinateTransform(in: rect)
    }
    
    private func drawNetworkDevices(in context: CGContext, rect: CGRect) {
        guard !networkDevices.isEmpty else { return }
        
        // Use the SAME coordinate transform as rooms for consistency
        let transform = calculateRoomCoordinateTransform(in: rect)
        guard let transform = transform else { return }
        
        // Draw each network device
        for device in networkDevices {
            let viewPoint = CGPoint(
                x: CGFloat(device.position.x) * transform.scale + transform.offsetX,
                y: CGFloat(device.position.z) * transform.scale + transform.offsetY // Use Z for Y in top-down view
            )
            
            let color = device.type == .router ? UIColor.systemRed : UIColor.systemOrange
            drawDeviceIcon(device.type, at: viewPoint, color: color, in: context)
        }
    }
    
    private func colorForSignalStrength(_ strength: Float) -> UIColor {
        switch strength {
        case Float(-50.0)...:
            return SpectrumBranding.Colors.excellentSignal
        case Float(-70.0)..<Float(-50.0):
            return SpectrumBranding.Colors.goodSignal  
        case Float(-85.0)..<Float(-70.0):
            return SpectrumBranding.Colors.fairSignal
        default:
            return SpectrumBranding.Colors.poorSignal
        }
    }
    
    private func drawMeasurementPoint(at point: CGPoint, color: UIColor, in context: CGContext, alpha: CGFloat = 1.0) {
        let radius: CGFloat = 8
        let rect = CGRect(x: point.x - radius, y: point.y - radius, 
                         width: radius * 2, height: radius * 2)
        
        // Fill with specified alpha
        context.setFillColor(color.withAlphaComponent(alpha * 0.8).cgColor)
        context.fillEllipse(in: rect)
        
        // Stroke with solid color for better visibility
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: rect)
    }
    
    private func drawHeatmapArea(at point: CGPoint, color: UIColor, in context: CGContext, radius: CGFloat) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius, 
                         width: radius * 2, height: radius * 2)
        
        // Draw transparent heatmap area
        context.setFillColor(color.withAlphaComponent(heatmapAlpha * 0.3).cgColor)
        context.fillEllipse(in: rect)
    }
    
    private func drawDeviceIcon(_ type: NetworkDevice.DeviceType, at point: CGPoint, color: UIColor, in context: CGContext) {
        let outerSize: CGFloat = 24
        let innerSize: CGFloat = 20
        
        // Draw outer circle with glow effect
        let glowRect = CGRect(x: point.x - outerSize/2, y: point.y - outerSize/2, width: outerSize, height: outerSize)
        context.setFillColor(color.withAlphaComponent(0.3).cgColor)
        context.fillEllipse(in: glowRect)
        
        // Draw main device circle
        let mainRect = CGRect(x: point.x - innerSize/2, y: point.y - innerSize/2, width: innerSize, height: innerSize)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: mainRect)
        
        // Draw white border
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: mainRect)
        
        // Draw device emoji
        let emoji = type == .router ? "📡" : "📡"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.white
        ]
        
        let attributedString = NSAttributedString(string: emoji, attributes: attributes)
        let textSize = attributedString.size()
        let textRect = CGRect(x: point.x - textSize.width/2, 
                             y: point.y - textSize.height/2,
                             width: textSize.width, 
                             height: textSize.height)
        
        attributedString.draw(in: textRect)
        
        // Draw device type label below
        let labelText = type == .router ? "Router" : "Extender"
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: color,
            .backgroundColor: UIColor.systemBackground.withAlphaComponent(0.8)
        ]
        
        let labelString = NSAttributedString(string: labelText, attributes: labelAttributes)
        let labelSize = labelString.size()
        let labelRect = CGRect(x: point.x - labelSize.width/2,
                              y: point.y + outerSize/2 + 2,
                              width: labelSize.width,
                              height: labelSize.height)
        
        // Draw background for label
        context.setFillColor(UIColor.systemBackground.withAlphaComponent(0.8).cgColor)
        let paddedRect = labelRect.insetBy(dx: -4, dy: -2)
        let path = UIBezierPath(roundedRect: paddedRect, cornerRadius: 4)
        context.addPath(path.cgPath)
        context.fillPath()
        
        labelString.draw(in: labelRect)
    }
    
    private func drawFurniture(in context: CGContext, rect: CGRect) {
        guard !furnitureItems.isEmpty else { 
            print("🏠 No furniture items to draw")
            return 
        }
        
        print("🏠 Drawing \(furnitureItems.count) furniture items")
        
        // Use the SAME coordinate transform as rooms for consistency
        let transform = calculateRoomCoordinateTransform(in: rect)
        guard let transform = transform else { 
            print("⚠️ No coordinate transform available for furniture rendering")
            return 
        }
        
        print("📏 Using transform - scale: \(transform.scale), offset: (\(transform.offsetX), \(transform.offsetY))")
        
        // Group furniture by type for better visualization
        let beds = furnitureItems.filter { $0.category == .bed }
        let tables = furnitureItems.filter { $0.category == .table }
        let storage = furnitureItems.filter { $0.category == .storage }
        let other = furnitureItems.filter { ![.bed, .table, .storage].contains($0.category) }
        
        // Draw in order: beds first (largest), then storage, tables, other
        let drawOrder = beds + storage + tables + other
        
        for (index, furniture) in drawOrder.enumerated() {
            print("   Drawing furniture \(index + 1): \(furniture.category) at (\(String(format: "%.3f", furniture.position.x)), \(String(format: "%.3f", furniture.position.z)))")
            drawFurnitureItem(furniture, in: context, scale: transform.scale, offsetX: transform.offsetX, offsetY: transform.offsetY)
        }
    }
    
    private func drawFurnitureItem(_ furniture: RoomAnalyzer.FurnitureItem, in context: CGContext, scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        // Convert furniture position to view coordinates
        let viewX = CGFloat(furniture.position.x) * scale + offsetX
        let viewY = CGFloat(furniture.position.z) * scale + offsetY // Use Z for Y in top-down view
        
        // Calculate furniture dimensions in view coordinates
        let width = CGFloat(furniture.dimensions.x) * scale
        let height = CGFloat(furniture.dimensions.z) * scale // Use Z for depth in top-down view
        
        // IMPROVED: Ensure minimum visible size for furniture
        let minSize: CGFloat = 8.0
        let adjustedWidth = max(width, minSize)
        let adjustedHeight = max(height, minSize)
        
        let furnitureRect = CGRect(
            x: viewX - adjustedWidth/2,
            y: viewY - adjustedHeight/2,
            width: adjustedWidth,
            height: adjustedHeight
        )
        
        print("🏠 Drawing \(furniture.category) at view pos (\(String(format: "%.1f", viewX)), \(String(format: "%.1f", viewY))) size \(String(format: "%.1fx%.1f", adjustedWidth, adjustedHeight))")
        print("   World position: (\(String(format: "%.3f", furniture.position.x)), \(String(format: "%.3f", furniture.position.z))) -> View: (\(String(format: "%.1f", viewX)), \(String(format: "%.1f", viewY)))")
        
        // Choose color and style based on furniture category
        let (fillColor, strokeColor, shouldDrawAsOval) = styleForFurnitureCategory(furniture.category)
        
        // Create path based on furniture type
        let path = CGMutablePath()
        if shouldDrawAsOval {
            // Draw round furniture (tables, chairs) as ovals
            path.addEllipse(in: furnitureRect)
        } else {
            // Draw rectangular furniture with appropriate corner radius
            let cornerRadius = min(adjustedWidth, adjustedHeight) * 0.1
            path.addRoundedRect(in: furnitureRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
        }
        
        // Fill furniture with appropriate transparency
        let alpha: CGFloat = furniture.category == .bed ? 0.8 : 0.7
        context.setFillColor(fillColor.withAlphaComponent(alpha).cgColor)
        context.addPath(path)
        context.fillPath()
        
        // Stroke furniture outline
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(furniture.category == .bed ? 2.0 : 1.5)
        context.addPath(path)
        context.strokePath()
        
        // Add furniture label if there's space
        if adjustedWidth > 20 && adjustedHeight > 15 {
            let emoji = emojiForFurnitureCategory(furniture.category)
            drawFurnitureLabel(emoji, at: CGPoint(x: furnitureRect.midX, y: furnitureRect.midY), in: context)
            
            // Add size debugging label for beds and large furniture
            if furniture.category == .bed {
                let sizeLabel = "\(String(format: "%.1f", furniture.dimensions.x))×\(String(format: "%.1f", furniture.dimensions.z))m"
                drawFurnitureSizeLabel(sizeLabel, at: CGPoint(x: furnitureRect.midX, y: furnitureRect.maxY + 5), in: context)
            }
        }
    }
    
    private func styleForFurnitureCategory(_ category: CapturedRoom.Object.Category) -> (fill: UIColor, stroke: UIColor, oval: Bool) {
        switch category {
        case .table:
            return (.systemBrown, .systemBrown.darker(by: 0.3), true) // Round tables
        case .sofa:
            return (.systemIndigo, .systemIndigo.darker(by: 0.3), false)
        case .bed:
            return (.systemPink, .systemPink.darker(by: 0.3), false)
        case .storage:
            return (.systemGreen, .systemGreen.darker(by: 0.3), false)
        case .chair:
            return (.systemOrange, .systemOrange.darker(by: 0.3), true) // Round chairs
        default:
            return (.systemGray2, .systemGray, false)
        }
    }
    
    private func drawFurnitureSizeLabel(_ text: String, at point: CGPoint, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let size = attributedString.size()
        
        let rect = CGRect(x: point.x - size.width / 2,
                         y: point.y,
                         width: size.width,
                         height: size.height)
        
        attributedString.draw(in: rect)
    }
    
    private func colorForFurnitureCategory(_ category: CapturedRoom.Object.Category) -> UIColor {
        switch category {
        case .table:
            return UIColor.systemBrown
        case .sofa:
            return UIColor.systemIndigo
        case .bed:
            return UIColor.systemPink
        case .storage:
            return UIColor.systemGreen
        default:
            return UIColor.systemGray2
        }
    }
    
    private func emojiForFurnitureCategory(_ category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .table:
            return "📋"
        case .sofa:
            return "🛋️"
        case .bed:
            return "🛏️"
        case .storage:
            return "📦"
        default:
            return "🔲"
        }
    }
    
    private func drawFurnitureLabel(_ text: String, at point: CGPoint, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.label
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let size = attributedString.size()
        
        let rect = CGRect(x: point.x - size.width / 2,
                         y: point.y - size.height / 2,
                         width: size.width,
                         height: size.height)
        
        attributedString.draw(in: rect)
    }
}

// MARK: - Supporting Types


struct NetworkDevice {
    enum DeviceType {
        case router
        case extender
    }
    
    let type: DeviceType
    let position: simd_float3
}