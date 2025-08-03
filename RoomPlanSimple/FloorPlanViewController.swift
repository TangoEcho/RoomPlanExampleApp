import UIKit
import SceneKit
import RoomPlan

protocol FloorPlanInteractionDelegate: AnyObject {
    func didSelectRoom(_ room: RoomAnalyzer.IdentifiedRoom)
    func didSelectMeasurement(_ measurement: WiFiMeasurement)
    func didSelectRouterPlacement(_ placement: simd_float3)
}

class FloorPlanViewController: UIViewController {
    private var floorPlanView: UIView!
    private var heatmapToggle: UISwitch!
    private var legendView: UIView!
    private var exportButton: UIButton!
    private var measurementsList: UITableView!
    
    private var floorPlanRenderer: FloorPlanRenderer!
    private var wifiHeatmapData: WiFiHeatmapData?
    private var roomAnalyzer: RoomAnalyzer?
    private var measurements: [WiFiMeasurement] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupFloorPlanRenderer()
        setupUI()
        setupTableView()
    }
    
    private func setupViews() {
        view.backgroundColor = .systemBackground
        
        // Create main container views
        floorPlanView = UIView()
        floorPlanView.backgroundColor = .systemGray6
        floorPlanView.translatesAutoresizingMaskIntoConstraints = false
        
        heatmapToggle = UISwitch()
        heatmapToggle.translatesAutoresizingMaskIntoConstraints = false
        
        legendView = UIView()
        legendView.backgroundColor = .systemBackground
        legendView.layer.cornerRadius = 8
        legendView.translatesAutoresizingMaskIntoConstraints = false
        
        exportButton = SpectrumBranding.createSpectrumButton(title: "Export Report", style: .primary)
        
        measurementsList = UITableView()
        measurementsList.translatesAutoresizingMaskIntoConstraints = false
        
        // Add to view hierarchy
        view.addSubview(floorPlanView)
        view.addSubview(heatmapToggle)
        view.addSubview(legendView)
        view.addSubview(exportButton)
        view.addSubview(measurementsList)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            floorPlanView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            floorPlanView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            floorPlanView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            floorPlanView.heightAnchor.constraint(equalToConstant: 300),
            
            heatmapToggle.topAnchor.constraint(equalTo: floorPlanView.bottomAnchor, constant: 10),
            heatmapToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            legendView.topAnchor.constraint(equalTo: heatmapToggle.bottomAnchor, constant: 10),
            legendView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            legendView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            legendView.heightAnchor.constraint(equalToConstant: 120),
            
            exportButton.topAnchor.constraint(equalTo: legendView.bottomAnchor, constant: 16),
            exportButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            exportButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            exportButton.heightAnchor.constraint(equalToConstant: 50),
            
            measurementsList.topAnchor.constraint(equalTo: exportButton.bottomAnchor, constant: 10),
            measurementsList.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            measurementsList.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            measurementsList.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    private func setupFloorPlanRenderer() {
        floorPlanRenderer = FloorPlanRenderer(frame: floorPlanView.bounds)
        floorPlanView.addSubview(floorPlanRenderer)
        floorPlanRenderer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            floorPlanRenderer.topAnchor.constraint(equalTo: floorPlanView.topAnchor),
            floorPlanRenderer.leadingAnchor.constraint(equalTo: floorPlanView.leadingAnchor),
            floorPlanRenderer.trailingAnchor.constraint(equalTo: floorPlanView.trailingAnchor),
            floorPlanRenderer.bottomAnchor.constraint(equalTo: floorPlanView.bottomAnchor)
        ])
    }
    
    private func setupUI() {
        title = "Spectrum WiFi Analysis"
        view.backgroundColor = SpectrumBranding.Colors.secondaryBackground
        
        // Configure navigation bar with Spectrum branding
        if let navigationBar = navigationController?.navigationBar {
            SpectrumBranding.configureNavigationBar(navigationBar)
        }
        
        setupLegend()
        
        heatmapToggle.addTarget(self, action: #selector(toggleHeatmap), for: .valueChanged)
        exportButton.addTarget(self, action: #selector(exportReport), for: .touchUpInside)
    }
    
    private func setupTableView() {
        measurementsList.delegate = self
        measurementsList.dataSource = self
        measurementsList.register(UITableViewCell.self, forCellReuseIdentifier: "MeasurementCell")
    }
    
    private func setupLegend() {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        let legendItems = [
            ("Excellent (>-50dBm)", SpectrumBranding.Colors.excellentSignal),
            ("Good (-50 to -70dBm)", SpectrumBranding.Colors.goodSignal),
            ("Fair (-70 to -85dBm)", SpectrumBranding.Colors.fairSignal),
            ("Poor (<-85dBm)", SpectrumBranding.Colors.poorSignal)
        ]
        
        for (label, color) in legendItems {
            let itemView = createLegendItem(label: label, color: color)
            stackView.addArrangedSubview(itemView)
        }
        
        legendView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: legendView.topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: legendView.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: legendView.trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: legendView.bottomAnchor, constant: -8)
        ])
    }
    
    private func createLegendItem(label: String, color: UIColor) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        let colorView = UIView()
        colorView.backgroundColor = color
        colorView.layer.cornerRadius = 6
        colorView.translatesAutoresizingMaskIntoConstraints = false
        
        let labelView = UILabel()
        labelView.text = label
        labelView.font = SpectrumBranding.Typography.captionFont
        labelView.textColor = SpectrumBranding.Colors.textPrimary
        labelView.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(colorView)
        containerView.addSubview(labelView)
        
        NSLayoutConstraint.activate([
            // Set container height
            containerView.heightAnchor.constraint(equalToConstant: 24),
            
            colorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            colorView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            colorView.widthAnchor.constraint(equalToConstant: 16),
            colorView.heightAnchor.constraint(equalToConstant: 16),
            
            labelView.leadingAnchor.constraint(equalTo: colorView.trailingAnchor, constant: 12),
            labelView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            labelView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
        
        return containerView
    }
    
    func updateWithData(heatmapData: WiFiHeatmapData, roomAnalyzer: RoomAnalyzer) {
        self.wifiHeatmapData = heatmapData
        self.roomAnalyzer = roomAnalyzer
        self.measurements = heatmapData.measurements
        
        DispatchQueue.main.async {
            self.floorPlanRenderer.renderFloorPlan(
                rooms: roomAnalyzer.identifiedRooms,
                furniture: roomAnalyzer.furnitureItems,
                heatmapData: heatmapData,
                showHeatmap: self.heatmapToggle.isOn
            )
            self.measurementsList.reloadData()
        }
    }
    
    @objc private func toggleHeatmap() {
        guard let heatmapData = wifiHeatmapData,
              let roomAnalyzer = roomAnalyzer else { return }
        
        floorPlanRenderer.renderFloorPlan(
            rooms: roomAnalyzer.identifiedRooms,
            furniture: roomAnalyzer.furnitureItems,
            heatmapData: heatmapData,
            showHeatmap: heatmapToggle.isOn
        )
    }
    
    @objc private func exportReport() {
        guard let heatmapData = wifiHeatmapData,
              let roomAnalyzer = roomAnalyzer else { return }
        
        let reportGenerator = WiFiReportGenerator()
        let report = reportGenerator.generateReport(
            heatmapData: heatmapData,
            rooms: roomAnalyzer.identifiedRooms,
            furniture: roomAnalyzer.furnitureItems
        )
        
        let activityVC = UIActivityViewController(activityItems: [report], applicationActivities: nil)
        activityVC.modalPresentationStyle = .popover
        
        present(activityVC, animated: true)
        if let popOver = activityVC.popoverPresentationController {
            popOver.sourceView = exportButton
        }
    }
    
    private func signalStrengthColor(_ strength: Int) -> UIColor {
        return SpectrumBranding.signalStrengthColor(for: strength)
    }
}

extension FloorPlanViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return measurements.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MeasurementCell", for: indexPath)
        let measurement = measurements[indexPath.row]
        
        let roomName = measurement.roomType?.rawValue ?? "Unknown"
        cell.textLabel?.text = "\(roomName): \(measurement.signalStrength)dBm, \(String(format: "%.1f", measurement.speed))Mbps"
        cell.detailTextLabel?.text = measurement.frequency
        
        let signalColor = signalStrengthColor(measurement.signalStrength)
        cell.backgroundColor = signalColor.withAlphaComponent(0.3)
        
        return cell
    }
}

class FloorPlanRenderer: UIView {
    private var rooms: [RoomAnalyzer.IdentifiedRoom] = []
    private var furniture: [RoomAnalyzer.FurnitureItem] = []
    private var heatmapData: WiFiHeatmapData?
    private var showHeatmap = false
    
    // Interactive features
    weak var delegate: FloorPlanInteractionDelegate?
    private var selectedRoom: RoomAnalyzer.IdentifiedRoom?
    private var selectedMeasurement: WiFiMeasurement?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupInteraction()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupInteraction()
    }
    
    private func setupInteraction() {
        isUserInteractionEnabled = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let tapLocation = gesture.location(in: self)
        print("🖱️ Tap detected at (\(tapLocation.x), \(tapLocation.y))")
        
        let scale = calculateScale(rect: bounds)
        let offset = calculateOffset(rect: bounds)
        
        // Check if tap hit a room
        if let room = findRoomAtLocation(tapLocation, scale: scale, offset: offset) {
            selectedRoom = room
            delegate?.didSelectRoom(room)
            print("🏠 Selected room: \(room.type.rawValue)")
            setNeedsDisplay() // Redraw to highlight selection
            return
        }
        
        // Check if tap hit a measurement point
        if let heatmapData = heatmapData {
            if let measurement = findMeasurementAtLocation(tapLocation, measurements: heatmapData.measurements, scale: scale, offset: offset) {
                selectedMeasurement = measurement
                delegate?.didSelectMeasurement(measurement)
                print("📍 Selected measurement: \(measurement.signalStrength)dBm")
                setNeedsDisplay() // Redraw to highlight selection
                return
            }
            
            // Check if tap hit a router placement
            if let placement = findRouterPlacementAtLocation(tapLocation, placements: heatmapData.optimalRouterPlacements, scale: scale, offset: offset) {
                delegate?.didSelectRouterPlacement(placement)
                print("📡 Selected router placement")
                return
            }
        }
        
        // Clear selection if nothing hit
        selectedRoom = nil
        selectedMeasurement = nil
        setNeedsDisplay()
        print("✋ Selection cleared")
    }
    
    private func findRoomAtLocation(_ location: CGPoint, scale: CGFloat, offset: CGPoint) -> RoomAnalyzer.IdentifiedRoom? {
        for room in rooms {
            if room.wallPoints.count >= 3 {
                // Check if point is inside room polygon
                let screenPoints = room.wallPoints.map { point in
                    CGPoint(
                        x: CGFloat(point.x) * scale + offset.x,
                        y: CGFloat(point.y) * scale + offset.y
                    )
                }
                
                if isPointInPolygon(location, polygon: screenPoints) {
                    return room
                }
            } else {
                // Check rectangular room
                let roomRect = CGRect(
                    x: CGFloat(room.center.x) * scale + offset.x - CGFloat(room.bounds.dimensions.x) * scale / 2,
                    y: CGFloat(room.center.z) * scale + offset.y - CGFloat(room.bounds.dimensions.z) * scale / 2,
                    width: CGFloat(room.bounds.dimensions.x) * scale,
                    height: CGFloat(room.bounds.dimensions.z) * scale
                )
                
                if roomRect.contains(location) {
                    return room
                }
            }
        }
        return nil
    }
    
    private func findMeasurementAtLocation(_ location: CGPoint, measurements: [WiFiMeasurement], scale: CGFloat, offset: CGPoint) -> WiFiMeasurement? {
        let tapRadius: CGFloat = 15.0 // Increased tap area for easier selection
        
        for measurement in measurements {
            let measurementPoint = CGPoint(
                x: CGFloat(measurement.location.x) * scale + offset.x,
                y: CGFloat(measurement.location.z) * scale + offset.y
            )
            
            let distance = sqrt(pow(location.x - measurementPoint.x, 2) + pow(location.y - measurementPoint.y, 2))
            if distance <= tapRadius {
                return measurement
            }
        }
        return nil
    }
    
    private func findRouterPlacementAtLocation(_ location: CGPoint, placements: [simd_float3], scale: CGFloat, offset: CGPoint) -> simd_float3? {
        let tapRadius: CGFloat = 20.0
        
        for placement in placements {
            let placementPoint = CGPoint(
                x: CGFloat(placement.x) * scale + offset.x,
                y: CGFloat(placement.z) * scale + offset.y
            )
            
            let distance = sqrt(pow(location.x - placementPoint.x, 2) + pow(location.y - placementPoint.y, 2))
            if distance <= tapRadius {
                return placement
            }
        }
        return nil
    }
    
    private func isPointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count > 2 else { return false }
        
        var inside = false
        var j = polygon.count - 1
        
        for i in 0..<polygon.count {
            let xi = polygon[i].x
            let yi = polygon[i].y
            let xj = polygon[j].x
            let yj = polygon[j].y
            
            if ((yi > point.y) != (yj > point.y)) && (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi) {
                inside = !inside
            }
            j = i
        }
        
        return inside
    }
    
    func renderFloorPlan(rooms: [RoomAnalyzer.IdentifiedRoom], 
                        furniture: [RoomAnalyzer.FurnitureItem],
                        heatmapData: WiFiHeatmapData,
                        showHeatmap: Bool) {
        self.rooms = rooms
        self.furniture = furniture
        self.heatmapData = heatmapData
        self.showHeatmap = showHeatmap
        
        // Debug logging
        print("🏠 Rendering floor plan with \(rooms.count) rooms, \(furniture.count) furniture items")
        print("📊 Heatmap data: \(heatmapData.measurements.count) measurements, \(heatmapData.coverageMap.count) coverage points")
        print("   Show heatmap: \(showHeatmap)")
        
        for room in rooms {
            print("   Room: \(room.type.rawValue) at (\(room.center.x), \(room.center.z)) size: \(room.bounds.dimensions.x)x\(room.bounds.dimensions.z)x\(room.bounds.dimensions.y)")
        }
        
        setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        context.setFillColor(UIColor.systemBackground.cgColor)
        context.fill(rect)
        
        drawRooms(context: context, rect: rect)
        drawFurniture(context: context, rect: rect)
        
        if showHeatmap {
            drawHeatmap(context: context, rect: rect)
        }
        
        drawMeasurementPoints(context: context, rect: rect)
        drawOptimalRouterPlacements(context: context, rect: rect)
    }
    
    private func drawRooms(context: CGContext, rect: CGRect) {
        let scale = calculateScale(rect: rect)
        let offset = calculateOffset(rect: rect)
        
        for room in rooms {
            if room.wallPoints.count >= 3 {
                // Draw actual room shape from wall points
                drawRoomShape(context: context, room: room, scale: scale, offset: offset)
            } else {
                // Fallback to rectangular shape
                drawRectangularRoom(context: context, room: room, scale: scale, offset: offset)
            }
            
            // Draw doorways
            drawDoorways(context: context, room: room, scale: scale, offset: offset)
            
            // Draw room label
            drawRoomLabel(context: context, room: room, scale: scale, offset: offset)
        }
    }
    
    private func roomTypeColor(_ roomType: RoomType) -> UIColor {
        switch roomType {
        case .kitchen:
            return UIColor.systemRed
        case .livingRoom:
            return UIColor.systemBlue
        case .bedroom:
            return UIColor.systemGreen
        case .bathroom:
            return UIColor.systemCyan
        case .office:
            return UIColor.systemPurple
        case .diningRoom:
            return UIColor.systemOrange
        case .hallway:
            return UIColor.systemGray
        default:
            return UIColor.systemGray2
        }
    }
    
    private func drawRoomShape(context: CGContext, room: RoomAnalyzer.IdentifiedRoom, scale: CGFloat, offset: CGPoint) {
        guard room.wallPoints.count >= 3 else { 
            print("⚠️ Room \(room.type.rawValue) has insufficient wall points (\(room.wallPoints.count)), using rectangular fallback")
            drawRectangularRoom(context: context, room: room, scale: scale, offset: offset)
            return 
        }
        
        // Validate wall points before rendering
        if !validateWallPointsForRendering(room.wallPoints) {
            print("⚠️ Room \(room.type.rawValue) has invalid wall points, using rectangular fallback")
            drawRectangularRoom(context: context, room: room, scale: scale, offset: offset)
            return
        }
        
        // Convert wall points to screen coordinates
        let screenPoints = room.wallPoints.map { point in
            CGPoint(
                x: CGFloat(point.x) * scale + offset.x,
                y: CGFloat(point.y) * scale + offset.y
            )
        }
        
        // Validate screen coordinates
        guard validateScreenPoints(screenPoints) else {
            print("⚠️ Room \(room.type.rawValue) generated invalid screen coordinates, using rectangular fallback")
            drawRectangularRoom(context: context, room: room, scale: scale, offset: offset)
            return
        }
        
        // Create path from wall points
        let path = CGMutablePath()
        path.move(to: screenPoints[0])
        for i in 1..<screenPoints.count {
            path.addLine(to: screenPoints[i])
        }
        path.closeSubpath()
        
        // Verify path is valid before rendering to prevent assertion failures
        if path.isEmpty || !isValidPathForRendering(path) {
            print("⚠️ Room \(room.type.rawValue) generated invalid path, using rectangular fallback")
            drawRectangularRoom(context: context, room: room, scale: scale, offset: offset)
            return
        }
        
        // Fill the room (highlight if selected)
        let isSelected = selectedRoom?.id == room.id
        let fillAlpha: CGFloat = isSelected ? 0.6 : 0.3
        context.setFillColor(roomTypeColor(room.type).withAlphaComponent(fillAlpha).cgColor)
        context.addPath(path)
        context.fillPath()
        
        // Draw walls (thicker if selected)
        context.setStrokeColor(roomTypeColor(room.type).cgColor)
        context.setLineWidth(isSelected ? 4.0 : 3.0)
        context.addPath(path)
        context.strokePath()
        
        // Add selection indicator
        if isSelected {
            context.setStrokeColor(UIColor.systemBlue.cgColor)
            context.setLineWidth(2.0)
            context.setLineDash(phase: 0, lengths: [5, 3])
            context.addPath(path)
            context.strokePath()
            context.setLineDash(phase: 0, lengths: []) // Reset dash
        }
        
        print("✅ Successfully rendered room \(room.type.rawValue) with \(room.wallPoints.count) wall points")
    }
    
    private func validateWallPointsForRendering(_ wallPoints: [simd_float2]) -> Bool {
        // Check for minimum points
        if wallPoints.count < 3 {
            return false
        }
        
        // Check for valid coordinates (no NaN or infinite values)
        for point in wallPoints {
            if !point.x.isFinite || !point.y.isFinite {
                return false
            }
        }
        
        // Check that points define a reasonable area
        let minX = wallPoints.map { $0.x }.min() ?? 0
        let maxX = wallPoints.map { $0.x }.max() ?? 0
        let minY = wallPoints.map { $0.y }.min() ?? 0
        let maxY = wallPoints.map { $0.y }.max() ?? 0
        
        let width = maxX - minX
        let height = maxY - minY
        
        // Area should be at least 0.25 square meters (0.5m x 0.5m)
        return width > 0.5 && height > 0.5
    }
    
    private func validateScreenPoints(_ points: [CGPoint]) -> Bool {
        // Check for valid screen coordinates
        for point in points {
            if !point.x.isFinite || !point.y.isFinite {
                return false
            }
            // Points should be within reasonable screen bounds
            if point.x < -1000 || point.x > 10000 || point.y < -1000 || point.y > 10000 {
                return false
            }
        }
        
        // Check that points define a visible area on screen
        let minX = points.map { $0.x }.min() ?? 0
        let maxX = points.map { $0.x }.max() ?? 0
        let minY = points.map { $0.y }.min() ?? 0
        let maxY = points.map { $0.y }.max() ?? 0
        
        let width = maxX - minX
        let height = maxY - minY
        
        // Should be at least 1 pixel wide and tall
        return width > 1.0 && height > 1.0
    }
    
    private func isValidPathForRendering(_ path: CGPath) -> Bool {
        // Check if path has valid bounding box to prevent assertion failures
        let boundingBox = path.boundingBox
        
        // Validate bounding box dimensions
        if !boundingBox.width.isFinite || !boundingBox.height.isFinite ||
           boundingBox.width <= 0 || boundingBox.height <= 0 {
            print("⚠️ Path has invalid bounding box: \(boundingBox)")
            return false
        }
        
        // Check for reasonable size limits to prevent memory issues
        if boundingBox.width > 10000 || boundingBox.height > 10000 {
            print("⚠️ Path bounding box too large: \(boundingBox)")
            return false
        }
        
        return true
    }
    
    private func drawRectangularRoom(context: CGContext, room: RoomAnalyzer.IdentifiedRoom, scale: CGFloat, offset: CGPoint) {
        // Ensure minimum room dimensions for visibility
        let minDimension: Float = 0.5
        let roomWidth = max(room.bounds.dimensions.x, minDimension)
        let roomHeight = max(room.bounds.dimensions.z, minDimension)
        
        let roomRect = CGRect(
            x: CGFloat(room.center.x) * scale + offset.x - CGFloat(roomWidth) * scale / 2,
            y: CGFloat(room.center.z) * scale + offset.y - CGFloat(roomHeight) * scale / 2,
            width: CGFloat(roomWidth) * scale,
            height: CGFloat(roomHeight) * scale
        )
        
        // Draw room fill
        context.setFillColor(roomTypeColor(room.type).withAlphaComponent(0.3).cgColor)
        context.addRect(roomRect)
        context.fillPath()
        
        // Draw room walls with thicker lines
        context.setStrokeColor(roomTypeColor(room.type).cgColor)
        context.setLineWidth(3.0)
        context.addRect(roomRect)
        context.strokePath()
    }
    
    private func drawDoorways(context: CGContext, room: RoomAnalyzer.IdentifiedRoom, scale: CGFloat, offset: CGPoint) {
        for doorway in room.doorways {
            let center = CGPoint(
                x: CGFloat(doorway.x) * scale + offset.x,
                y: CGFloat(doorway.y) * scale + offset.y
            )
            
            // Draw architectural door symbol - arc showing door swing
            drawArchitecturalDoor(context: context, at: center, scale: scale)
        }
    }
    
    private func drawArchitecturalDoor(context: CGContext, at center: CGPoint, scale: CGFloat) {
        let doorWidth: CGFloat = 12 * scale / 50 // Scale door size appropriately
        let doorThickness: CGFloat = 2
        
        // Draw door frame (opening in wall)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(doorThickness)
        context.move(to: CGPoint(x: center.x - doorWidth/2, y: center.y))
        context.addLine(to: CGPoint(x: center.x + doorWidth/2, y: center.y))
        context.strokePath()
        
        // Draw door swing arc (architectural convention)
        context.setStrokeColor(UIColor.darkGray.cgColor)
        context.setLineWidth(1.0)
        context.addArc(
            center: CGPoint(x: center.x - doorWidth/2, y: center.y),
            radius: doorWidth,
            startAngle: 0,
            endAngle: .pi/2,
            clockwise: false
        )
        context.strokePath()
        
        // Draw door panel
        context.setStrokeColor(UIColor.darkGray.cgColor)
        context.setLineWidth(1.5)
        context.move(to: CGPoint(x: center.x - doorWidth/2, y: center.y))
        context.addLine(to: CGPoint(x: center.x - doorWidth/2, y: center.y - doorWidth))
        context.strokePath()
    }
    
    private func drawRoomLabel(context: CGContext, room: RoomAnalyzer.IdentifiedRoom, scale: CGFloat, offset: CGPoint) {
        // Create room label with confidence indicator
        let roomLabel = room.type.rawValue
        let confidenceText = String(format: "%.0f%%", room.confidence * 100)
        
        // Use larger, more visible font
        let labelAttributes = [
            NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 16),
            NSAttributedString.Key.foregroundColor: UIColor.black
        ]
        let confidenceAttributes = [
            NSAttributedString.Key.font: UIFont.systemFont(ofSize: 12),
            NSAttributedString.Key.foregroundColor: UIColor.darkGray
        ]
        
        let attributedString = NSMutableAttributedString(string: roomLabel, attributes: labelAttributes)
        attributedString.append(NSAttributedString(string: "\n(\(confidenceText))", attributes: confidenceAttributes))
        
        let textSize = attributedString.size()
        let labelCenter = CGPoint(
            x: CGFloat(room.center.x) * scale + offset.x,
            y: CGFloat(room.center.z) * scale + offset.y
        )
        
        let textRect = CGRect(
            x: labelCenter.x - textSize.width / 2,
            y: labelCenter.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        // Draw background for label
        let backgroundRect = textRect.insetBy(dx: -4, dy: -2)
        context.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        context.setStrokeColor(roomTypeColor(room.type).cgColor)
        context.setLineWidth(1.0)
        let roundedPath = CGPath(roundedRect: backgroundRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(roundedPath)
        context.drawPath(using: .fillStroke)
        
        // Draw the text
        attributedString.draw(in: textRect)
    }
    
    private func drawFurniture(context: CGContext, rect: CGRect) {
        let scale = calculateScale(rect: rect)
        let offset = calculateOffset(rect: rect)
        
        for item in furniture {
            let center = CGPoint(
                x: CGFloat(item.position.x) * scale + offset.x,
                y: CGFloat(item.position.z) * scale + offset.y
            )
            let size = CGSize(
                width: CGFloat(item.dimensions.x) * scale,
                height: CGFloat(item.dimensions.z) * scale
            )
            
            drawArchitecturalFurniture(context: context, item: item, at: center, size: size)
        }
    }
    
    private func drawArchitecturalFurniture(context: CGContext, item: RoomAnalyzer.FurnitureItem, at center: CGPoint, size: CGSize) {
        context.saveGState()
        
        // Draw a subtle background shape first
        drawFurnitureBackground(context: context, at: center, size: size, category: item.category)
        
        // Then draw the emoji icon on top
        let emoji = emojiForFurniture(item.category)
        drawFurnitureEmoji(context: context, emoji: emoji, at: center, size: size)
        
        context.restoreGState()
    }
    
    private func emojiForFurniture(_ category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .bed:
            return "🛏️"
        case .sofa:
            return "🛋️"
        case .table:
            return "🪑" // Using chair emoji to represent table area
        case .chair:
            return "🪑"
        case .refrigerator:
            return "❄️"
        case .oven:
            return "🔥"
        case .sink:
            return "🚿"
        case .toilet:
            return "🚽"
        case .bathtub:
            return "🛁"
        case .television:
            return "📺"
        case .dishwasher:
            return "🧽"
        default:
            return "📦"
        }
    }
    
    private func drawFurnitureBackground(context: CGContext, at center: CGPoint, size: CGSize, category: CapturedRoom.Object.Category) {
        let rect = CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height)
        
        // Choose background color based on category
        let backgroundColor: UIColor
        switch category {
        case .bed, .sofa:
            backgroundColor = UIColor.systemBlue.withAlphaComponent(0.3)
        case .table, .chair:
            backgroundColor = UIColor.systemBrown.withAlphaComponent(0.3)
        case .refrigerator, .oven, .sink, .dishwasher, .stove:
            backgroundColor = UIColor.systemGray.withAlphaComponent(0.3)
        case .toilet, .bathtub:
            backgroundColor = UIColor.systemCyan.withAlphaComponent(0.3)
        case .television:
            backgroundColor = UIColor.systemPurple.withAlphaComponent(0.3)
        default:
            backgroundColor = UIColor.systemYellow.withAlphaComponent(0.3)
        }
        
        // Draw rounded background
        context.setFillColor(backgroundColor.cgColor)
        context.setStrokeColor(backgroundColor.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(1.0)
        
        let roundedPath = CGPath(roundedRect: rect, cornerWidth: min(size.width, size.height) * 0.2, cornerHeight: min(size.width, size.height) * 0.2, transform: nil)
        context.addPath(roundedPath)
        context.drawPath(using: .fillStroke)
    }
    
    private func drawFurnitureEmoji(context: CGContext, emoji: String, at center: CGPoint, size: CGSize) {
        // Calculate emoji size based on furniture size
        let emojiSize = max(min(size.width, size.height) * 0.8, 16) // Minimum 16pt, scale with furniture
        
        let attributes = [
            NSAttributedString.Key.font: UIFont.systemFont(ofSize: emojiSize),
            NSAttributedString.Key.foregroundColor: UIColor.label
        ]
        
        let textSize = emoji.size(withAttributes: attributes)
        let textRect = CGRect(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        emoji.draw(in: textRect, withAttributes: attributes)
    }
    
    // MARK: - Furniture Drawing Methods
    
    private func drawBed(context: CGContext, at center: CGPoint, size: CGSize) {
        let rect = CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height)
        
        // Bed frame
        context.setStrokeColor(UIColor.darkGray.cgColor)
        context.setLineWidth(2.0)
        context.addRect(rect)
        context.strokePath()
        
        // Pillows (smaller rectangles at head)
        let pillowHeight = size.height * 0.2
        let pillowRect = CGRect(x: rect.minX + 2, y: rect.minY + 2, width: rect.width - 4, height: pillowHeight)
        context.setFillColor(UIColor.lightGray.cgColor)
        context.addRect(pillowRect)
        context.fillPath()
        
        // Add "BED" label
        drawFurnitureLabel(context: context, text: "BED", at: center)
    }
    
    private func drawSofa(context: CGContext, at center: CGPoint, size: CGSize) {
        let rect = CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height)
        
        // Sofa body
        context.setFillColor(UIColor.systemGray4.cgColor)
        context.setStrokeColor(UIColor.darkGray.cgColor)
        context.setLineWidth(1.5)
        let roundedPath = CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(roundedPath)
        context.drawPath(using: .fillStroke)
        
        // Cushions (dashed lines)
        context.setLineDash(phase: 0, lengths: [3, 2])
        let cushionWidth = size.width / 3
        for i in 1..<3 {
            let x = rect.minX + CGFloat(i) * cushionWidth
            context.move(to: CGPoint(x: x, y: rect.minY + 2))
            context.addLine(to: CGPoint(x: x, y: rect.maxY - 2))
        }
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
    }
    
    private func drawTable(context: CGContext, at center: CGPoint, size: CGSize) {
        let rect = CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height)
        
        if size.width > size.height * 1.5 || size.height > size.width * 1.5 {
            // Rectangular table
            context.setStrokeColor(UIColor.darkGray.cgColor)
            context.setLineWidth(2.0)
            context.addRect(rect)
            context.strokePath()
        } else {
            // Round table
            context.setStrokeColor(UIColor.darkGray.cgColor)
            context.setLineWidth(2.0)
            context.addEllipse(in: rect)
            context.strokePath()
        }
        
        drawFurnitureLabel(context: context, text: "TABLE", at: center)
    }
    
    private func drawChair(context: CGContext, at center: CGPoint, size: CGSize) {
        let rect = CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height)
        
        // Chair seat
        context.setFillColor(UIColor.systemGray5.cgColor)
        context.setStrokeColor(UIColor.darkGray.cgColor)
        context.setLineWidth(1.0)
        let roundedPath = CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
        context.addPath(roundedPath)
        context.drawPath(using: .fillStroke)
        
        // Chair back (thicker line at one end)
        context.setLineWidth(3.0)
        context.move(to: CGPoint(x: rect.minX, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        context.strokePath()
    }
    
    private func drawRefrigerator(context: CGContext, at center: CGPoint, size: CGSize) {
        let rect = CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height)
        
        // Fridge body
        context.setFillColor(UIColor.systemGray6.cgColor)
        context.setStrokeColor(UIColor.darkGray.cgColor)
        context.setLineWidth(2.0)
        context.addRect(rect)
        context.drawPath(using: .fillStroke)
        
        // Door lines
        let midY = rect.midY
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: rect.minX, y: midY))
        context.addLine(to: CGPoint(x: rect.maxX, y: midY))
        context.strokePath()
        
        drawFurnitureLabel(context: context, text: "REF", at: center)
    }
    
    private func drawSink(context: CGContext, at center: CGPoint, size: CGSize) {
        let rect = CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height)
        
        // Sink basin (oval)
        context.setFillColor(UIColor.systemGray6.cgColor)
        context.setStrokeColor(UIColor.darkGray.cgColor)
        context.setLineWidth(2.0)
        context.addEllipse(in: rect.insetBy(dx: 2, dy: 2))
        context.drawPath(using: .fillStroke)
        
        drawFurnitureLabel(context: context, text: "SINK", at: center)
    }
    
    private func drawToilet(context: CGContext, at center: CGPoint, size: CGSize) {
        let rect = CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height)
        
        // Toilet bowl (oval)
        let bowlRect = CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height/2)
        context.setFillColor(UIColor.systemGray6.cgColor)
        context.setStrokeColor(UIColor.darkGray.cgColor)
        context.setLineWidth(2.0)
        context.addEllipse(in: bowlRect)
        context.drawPath(using: .fillStroke)
        
        // Tank (rectangle at back)
        let tankRect = CGRect(x: rect.minX + rect.width*0.2, y: rect.minY, width: rect.width*0.6, height: rect.height*0.4)
        context.addRect(tankRect)
        context.drawPath(using: .fillStroke)
    }
    
    private func drawBathtub(context: CGContext, at center: CGPoint, size: CGSize) {
        let rect = CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height)
        
        // Tub outline
        context.setFillColor(UIColor.systemGray6.cgColor)
        context.setStrokeColor(UIColor.darkGray.cgColor)
        context.setLineWidth(3.0)
        let roundedPath = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        context.addPath(roundedPath)
        context.drawPath(using: .fillStroke)
        
        drawFurnitureLabel(context: context, text: "TUB", at: center)
    }
    
    private func drawTelevision(context: CGContext, at center: CGPoint, size: CGSize) {
        let rect = CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height)
        
        // TV screen
        context.setFillColor(UIColor.black.cgColor)
        context.setStrokeColor(UIColor.darkGray.cgColor)
        context.setLineWidth(2.0)
        context.addRect(rect)
        context.drawPath(using: .fillStroke)
        
        drawFurnitureLabel(context: context, text: "TV", at: center, textColor: .white)
    }
    
    private func drawOven(context: CGContext, at center: CGPoint, size: CGSize) {
        let rect = CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height)
        
        context.setFillColor(UIColor.systemGray5.cgColor)
        context.setStrokeColor(UIColor.darkGray.cgColor)
        context.setLineWidth(2.0)
        context.addRect(rect)
        context.drawPath(using: .fillStroke)
        
        // Oven door handle
        let handleRect = CGRect(x: rect.maxX - 4, y: rect.midY - rect.height*0.15, width: 2, height: rect.height*0.3)
        context.setFillColor(UIColor.darkGray.cgColor)
        context.addRect(handleRect)
        context.fillPath()
        
        drawFurnitureLabel(context: context, text: "OVEN", at: center)
    }
    
    private func drawDishwasher(context: CGContext, at center: CGPoint, size: CGSize) {
        drawOven(context: context, at: center, size: size) // Similar to oven
        drawFurnitureLabel(context: context, text: "DW", at: center)
    }
    
    private func drawGenericFurniture(context: CGContext, at center: CGPoint, size: CGSize) {
        let rect = CGRect(x: center.x - size.width/2, y: center.y - size.height/2, width: size.width, height: size.height)
        
        context.setFillColor(UIColor.systemGray4.cgColor)
        context.setStrokeColor(UIColor.darkGray.cgColor)
        context.setLineWidth(1.0)
        context.addRect(rect)
        context.drawPath(using: .fillStroke)
    }
    
    private func drawFurnitureLabel(context: CGContext, text: String, at center: CGPoint, textColor: UIColor = .darkGray) {
        let attributes = [
            NSAttributedString.Key.font: UIFont.systemFont(ofSize: 8, weight: .medium),
            NSAttributedString.Key.foregroundColor: textColor
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
    }
    
    private func drawHeatmap(context: CGContext, rect: CGRect) {
        guard let heatmapData = heatmapData else { return }
        
        print("🎨 Drawing enhanced heatmap with \(heatmapData.coverageMap.count) coverage points")
        
        let scale = calculateScale(rect: rect)
        let offset = calculateOffset(rect: rect)
        
        // Create improved heatmap with gradient circles and better coverage representation
        for (position, coverage) in heatmapData.coverageMap {
            let center = CGPoint(
                x: CGFloat(position.x) * scale + offset.x,
                y: CGFloat(position.z) * scale + offset.y
            )
            
            // Calculate signal strength from normalized coverage
            let signalStrength = Int((coverage - 1.0) * 50.0 - 100)
            
            // Adaptive radius based on signal strength (stronger signals cover wider areas)
            let baseRadius: CGFloat = 25.0
            let strengthMultiplier = max(0.3, CGFloat(coverage)) // Minimum 30% radius
            let radius = baseRadius * strengthMultiplier
            
            // Create radial gradient for smooth coverage visualization
            drawGradientCoverage(
                context: context,
                center: center,
                radius: radius,
                coverage: coverage,
                signalStrength: signalStrength
            )
        }
        
        // Add coverage legend
        drawHeatmapLegend(context: context, rect: rect)
        
        print("✅ Heatmap rendered with enhanced gradients and coverage modeling")
    }
    
    private func drawGradientCoverage(context: CGContext, center: CGPoint, radius: CGFloat, coverage: Double, signalStrength: Int) {
        // Create radial gradient from strong signal at center to weak at edges
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        let centerColor = signalStrengthColor(signalStrength).withAlphaComponent(0.7)
        let edgeColor = signalStrengthColor(signalStrength - 20).withAlphaComponent(0.2)
        
        let colors = [centerColor.cgColor, edgeColor.cgColor]
        let locations: [CGFloat] = [0.0, 1.0]
        
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) else {
            // Fallback to simple circle if gradient creation fails
            context.setFillColor(centerColor.cgColor)
            context.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.fillPath()
            return
        }
        
        // Save context state
        context.saveGState()
        
        // Clip to circle
        context.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.clip()
        
        // Draw radial gradient
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: []
        )
        
        // Restore context state
        context.restoreGState()
    }
    
    private func drawHeatmapLegend(context: CGContext, rect: CGRect) {
        // Draw small legend in top-right corner
        let legendWidth: CGFloat = 120
        let legendHeight: CGFloat = 80
        let legendX = rect.maxX - legendWidth - 10
        let legendY = rect.minY + 10
        
        let legendRect = CGRect(x: legendX, y: legendY, width: legendWidth, height: legendHeight)
        
        // Legend background
        context.setFillColor(UIColor.systemBackground.withAlphaComponent(0.9).cgColor)
        context.setStrokeColor(UIColor.systemGray3.cgColor)
        context.setLineWidth(1.0)
        let roundedPath = CGPath(roundedRect: legendRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(roundedPath)
        context.drawPath(using: .fillStroke)
        
        // Legend title
        let titleText = "Signal Strength"
        let titleAttributes = [
            NSAttributedString.Key.font: UIFont.systemFont(ofSize: 12, weight: .medium),
            NSAttributedString.Key.foregroundColor: UIColor.label
        ]
        let titleSize = titleText.size(withAttributes: titleAttributes)
        let titleRect = CGRect(
            x: legendX + (legendWidth - titleSize.width) / 2,
            y: legendY + 5,
            width: titleSize.width,
            height: titleSize.height
        )
        titleText.draw(in: titleRect, withAttributes: titleAttributes)
        
        // Legend items
        let legendItems = [
            (-40, "Excellent"),
            (-60, "Good"),
            (-80, "Fair"),
            (-100, "Poor")
        ]
        
        for (index, (strength, label)) in legendItems.enumerated() {
            let itemY = legendY + 25 + CGFloat(index) * 12
            
            // Color circle
            let circleSize: CGFloat = 8
            let circleRect = CGRect(x: legendX + 8, y: itemY, width: circleSize, height: circleSize)
            context.setFillColor(signalStrengthColor(strength).cgColor)
            context.addEllipse(in: circleRect)
            context.fillPath()
            
            // Label text
            let labelAttributes = [
                NSAttributedString.Key.font: UIFont.systemFont(ofSize: 10),
                NSAttributedString.Key.foregroundColor: UIColor.label
            ]
            label.draw(at: CGPoint(x: legendX + 20, y: itemY - 1), withAttributes: labelAttributes)
        }
    }
    
    private func drawMeasurementPoints(context: CGContext, rect: CGRect) {
        guard let heatmapData = heatmapData else { return }
        
        let scale = calculateScale(rect: rect)
        let offset = calculateOffset(rect: rect)
        
        for measurement in heatmapData.measurements {
            let center = CGPoint(
                x: CGFloat(measurement.location.x) * scale + offset.x,
                y: CGFloat(measurement.location.z) * scale + offset.y
            )
            
            // Check if this measurement is selected
            let isSelected = selectedMeasurement?.location.x == measurement.location.x &&
                           selectedMeasurement?.location.y == measurement.location.y &&
                           selectedMeasurement?.location.z == measurement.location.z
            
            let color = signalStrengthColor(measurement.signalStrength)
            let radius: CGFloat = isSelected ? 6 : 4
            
            // Draw measurement point
            context.setFillColor(color.cgColor)
            context.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.fillPath()
            
            // Add selection indicator
            if isSelected {
                context.setStrokeColor(UIColor.systemBlue.cgColor)
                context.setLineWidth(3.0)
                context.addEllipse(in: CGRect(x: center.x - radius - 2, y: center.y - radius - 2, width: (radius + 2) * 2, height: (radius + 2) * 2))
                context.strokePath()
                
                // Show measurement details
                let detailText = "\(measurement.signalStrength)dBm\n\(String(format: "%.1f", measurement.speed))Mbps"
                drawMeasurementDetail(context: context, text: detailText, at: center)
            }
        }
    }
    
    private func drawMeasurementDetail(context: CGContext, text: String, at center: CGPoint) {
        let attributes = [
            NSAttributedString.Key.font: UIFont.systemFont(ofSize: 10, weight: .medium),
            NSAttributedString.Key.foregroundColor: UIColor.label,
            NSAttributedString.Key.backgroundColor: UIColor.systemBackground
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: center.x + 15,
            y: center.y - textSize.height / 2,
            width: textSize.width + 4,
            height: textSize.height + 2
        )
        
        // Background for text
        context.setFillColor(UIColor.systemBackground.withAlphaComponent(0.9).cgColor)
        context.setStrokeColor(UIColor.systemGray3.cgColor)
        context.setLineWidth(1.0)
        let roundedRect = CGPath(roundedRect: textRect.insetBy(dx: -2, dy: -1), cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(roundedRect)
        context.drawPath(using: .fillStroke)
        
        // Draw text
        text.draw(in: textRect, withAttributes: attributes)
    }
    
    private func drawOptimalRouterPlacements(context: CGContext, rect: CGRect) {
        guard let heatmapData = heatmapData else { return }
        
        let scale = calculateScale(rect: rect)
        let offset = calculateOffset(rect: rect)
        
        for placement in heatmapData.optimalRouterPlacements {
            let center = CGPoint(
                x: CGFloat(placement.x) * scale + offset.x,
                y: CGFloat(placement.z) * scale + offset.y
            )
            
            context.setFillColor(UIColor.systemBlue.cgColor)
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(2.0)
            
            context.addEllipse(in: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16))
            context.drawPath(using: .fillStroke)
            
            let routerLabel = "📡"
            let attributes = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 16)]
            let textSize = routerLabel.size(withAttributes: attributes)
            let textRect = CGRect(
                x: center.x - textSize.width / 2,
                y: center.y - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            routerLabel.draw(in: textRect, withAttributes: attributes)
        }
    }
    
    private func calculateScale(rect: CGRect) -> CGFloat {
        guard !rooms.isEmpty else { return 50.0 }
        
        // Calculate the bounding box of all rooms
        let minX = rooms.map { $0.center.x - $0.bounds.dimensions.x/2 }.min() ?? 0
        let maxX = rooms.map { $0.center.x + $0.bounds.dimensions.x/2 }.max() ?? 1
        let minZ = rooms.map { $0.center.z - $0.bounds.dimensions.z/2 }.min() ?? 0
        let maxZ = rooms.map { $0.center.z + $0.bounds.dimensions.z/2 }.max() ?? 1
        
        let totalWidth = maxX - minX
        let totalHeight = maxZ - minZ
        let maxDimension = max(totalWidth, totalHeight)
        
        let margin: CGFloat = 40
        return min(rect.width - margin, rect.height - margin) / CGFloat(maxDimension)
    }
    
    private func calculateOffset(rect: CGRect) -> CGPoint {
        guard !rooms.isEmpty else { return CGPoint(x: rect.width / 2, y: rect.height / 2) }
        
        // Calculate the center of the bounding box
        let minX = rooms.map { $0.center.x - $0.bounds.dimensions.x/2 }.min() ?? 0
        let maxX = rooms.map { $0.center.x + $0.bounds.dimensions.x/2 }.max() ?? 1
        let minZ = rooms.map { $0.center.z - $0.bounds.dimensions.z/2 }.min() ?? 0
        let maxZ = rooms.map { $0.center.z + $0.bounds.dimensions.z/2 }.max() ?? 1
        
        let centerX = (minX + maxX) / 2
        let centerZ = (minZ + maxZ) / 2
        
        let scale = calculateScale(rect: rect)
        
        return CGPoint(
            x: rect.width / 2 - CGFloat(centerX) * scale,
            y: rect.height / 2 - CGFloat(centerZ) * scale
        )
    }
    
    private func signalStrengthColor(_ strength: Int) -> UIColor {
        return SpectrumBranding.signalStrengthColor(for: strength)
    }
}