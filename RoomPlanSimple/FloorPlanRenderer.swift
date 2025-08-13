import UIKit
import simd

class FloorPlanRenderer: UIView {
    
    // MARK: - Properties
    private var rooms: [RoomAnalyzer.IdentifiedRoom] = []
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
        self.rooms = rooms.filter { room in
            guard room.wallPoints.count >= 3 else {
                print("⚠️ FloorPlanRenderer: Skipping room with insufficient boundary points (\(room.wallPoints.count))")
                return false
            }
            return true
        }
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
        
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        context.clear(rect)
        
        drawRooms(in: context, rect: rect)
        
        if showHeatmap, let heatmapData = heatmapData {
            drawHeatmap(heatmapData, in: context, rect: rect)
        }
        
        drawNetworkDevices(in: context, rect: rect)
    }
    
    private func drawRooms(in context: CGContext, rect: CGRect) {
        guard !rooms.isEmpty else {
            drawPlaceholderRoom(in: context, rect: rect)
            return
        }
        
        let allPoints = rooms.flatMap { $0.wallPoints }
        guard !allPoints.isEmpty else { return }
        
        let minX = allPoints.map { $0.x }.min() ?? 0
        let maxX = allPoints.map { $0.x }.max() ?? 0
        let minY = allPoints.map { $0.y }.min() ?? 0
        let maxY = allPoints.map { $0.y }.max() ?? 0
        
        let roomWidth = maxX - minX
        let roomHeight = maxY - minY
        
        guard roomWidth > 0 && roomHeight > 0 else {
            drawPlaceholderRoom(in: context, rect: rect)
            return
        }
        
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
        
        for (index, room) in rooms.enumerated() {
            drawRoom(room, in: context, scale: scale, offsetX: offsetX, offsetY: offsetY, roomIndex: index)
        }
    }
    
    private func drawRoom(_ room: RoomAnalyzer.IdentifiedRoom, in context: CGContext, scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat, roomIndex: Int) {
        guard room.wallPoints.count >= 3 else { return }
        
        let viewPoints = room.wallPoints.map { point in
            CGPoint(x: CGFloat(point.x) * scale + offsetX,
                   y: CGFloat(point.y) * scale + offsetY)
        }
        
        let path = CGMutablePath()
        if let firstPoint = viewPoints.first {
            path.move(to: firstPoint)
            for i in 1..<viewPoints.count {
                path.addLine(to: viewPoints[i])
            }
            if viewPoints.count > 2 { path.closeSubpath() }
        }
        
        context.setFillColor(UIColor.systemGray5.withAlphaComponent(0.3).cgColor)
        context.addPath(path)
        context.fillPath()
        
        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setLineWidth(roomStrokeWidth)
        context.addPath(path)
        context.strokePath()
        
        if let centerPoint = calculateRoomCenter(viewPoints) {
            drawRoomLabel(room.type.rawValue, at: centerPoint, in: context)
        }
    }
    
    private func drawPlaceholderRoom(in context: CGContext, rect: CGRect) {
        let padding: CGFloat = 40
        let roomRect = rect.insetBy(dx: padding, dy: padding)
        
        let path = CGMutablePath()
        path.addRect(roomRect)
        
        context.setFillColor(UIColor.systemGray5.withAlphaComponent(0.3).cgColor)
        context.addPath(path)
        context.fillPath()
        
        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setLineWidth(roomStrokeWidth)
        context.addPath(path)
        context.strokePath()
        
        let center = CGPoint(x: roomRect.midX, y: roomRect.midY)
        drawRoomLabel("Room", at: center, in: context)
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
    
    private func drawHeatmap(_ data: WiFiHeatmapData, in context: CGContext, rect: CGRect) {
        let hasCoverageTiles = !data.coverageMap.isEmpty
        let minX: Float
        let maxX: Float
        let minY: Float
        let maxY: Float
        if hasCoverageTiles {
            let points = data.coverageMap.keys.map { simd_float2($0.x, $0.z) }
            minX = points.map { $0.x }.min() ?? 0
            maxX = points.map { $0.x }.max() ?? 0
            minY = points.map { $0.y }.min() ?? 0
            maxY = points.map { $0.y }.max() ?? 0
        } else {
            guard !data.measurements.isEmpty else { return }
            let points = data.measurements.map { simd_float2($0.location.x, $0.location.z) }
            minX = points.map { $0.x }.min() ?? 0
            maxX = points.map { $0.x }.max() ?? 0
            minY = points.map { $0.y }.min() ?? 0
            maxY = points.map { $0.y }.max() ?? 0
        }
        let roomWidth = maxX - minX
        let roomHeight = maxY - minY
        guard roomWidth > 0 && roomHeight > 0 else { return }
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

        if hasCoverageTiles {
            for (position, normalized) in data.coverageMap {
                let viewPoint = CGPoint(
                    x: CGFloat(position.x) * scale + offsetX,
                    y: CGFloat(position.z) * scale + offsetY
                )
                let tileSizeMeters: CGFloat = 0.5
                let tileSize = tileSizeMeters * scale
                let rectTile = CGRect(x: viewPoint.x - tileSize/2, y: viewPoint.y - tileSize/2, width: tileSize, height: tileSize)
                let rssi = Int(normalized * 100.0 - 100.0)
                let color = SpectrumBranding.signalStrengthColor(for: rssi)
                context.setFillColor(color.withAlphaComponent(heatmapAlpha).cgColor)
                context.fill(rectTile)
            }
        } else {
            for measurement in data.measurements {
                let viewPoint = CGPoint(
                    x: CGFloat(measurement.location.x) * scale + offsetX,
                    y: CGFloat(measurement.location.z) * scale + offsetY
                )
                let color = colorForSignalStrength(Float(measurement.signalStrength))
                drawMeasurementPoint(at: viewPoint, color: color, in: context)
            }
        }
    }
    
    private func drawNetworkDevices(in context: CGContext, rect: CGRect) {
        // Draw router and extender positions if available
        for device in networkDevices {
            let viewPoint = CGPoint(x: rect.midX, y: rect.midY)
            
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
    
    private func drawMeasurementPoint(at point: CGPoint, color: UIColor, in context: CGContext) {
        let radius: CGFloat = 8
        let rect = CGRect(x: point.x - radius, y: point.y - radius, 
                         width: radius * 2, height: radius * 2)
        
        context.setFillColor(color.withAlphaComponent(heatmapAlpha).cgColor)
        context.fillEllipse(in: rect)
        
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: rect)
    }
    
    private func drawDeviceIcon(_ type: NetworkDevice.DeviceType, at point: CGPoint, color: UIColor, in context: CGContext) {
        let size: CGFloat = 12
        let rect = CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size)
        
        context.setFillColor(color.cgColor)
        context.fill(rect)
        
        let text = type == .router ? "R" : "E"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: UIColor.white
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        let textRect = CGRect(x: point.x - textSize.width/2, 
                             y: point.y - textSize.height/2,
                             width: textSize.width, 
                             height: textSize.height)
        
        attributedString.draw(in: textRect)
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