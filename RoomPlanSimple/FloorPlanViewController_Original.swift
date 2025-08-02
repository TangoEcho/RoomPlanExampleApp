import UIKit
import SceneKit
import RoomPlan

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
            
            exportButton.topAnchor.constraint(equalTo: legendView.bottomAnchor, constant: 10),
            exportButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            exportButton.widthAnchor.constraint(equalToConstant: 150),
            exportButton.heightAnchor.constraint(equalToConstant: 44),
            
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
        
        let colorView = UIView()
        colorView.backgroundColor = color
        colorView.layer.cornerRadius = 6
        colorView.translatesAutoresizingMaskIntoConstraints = false
        
        let labelView = UILabel()
        labelView.text = label
        labelView.font = UIFont.systemFont(ofSize: 12)
        labelView.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(colorView)
        containerView.addSubview(labelView)
        
        NSLayoutConstraint.activate([
            colorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            colorView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            colorView.widthAnchor.constraint(equalToConstant: 12),
            colorView.heightAnchor.constraint(equalToConstant: 12),
            
            labelView.leadingAnchor.constraint(equalTo: colorView.trailingAnchor, constant: 8),
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
    
    private func signalStrengthColor(_ strength: Int) -> UIColor {
        return SpectrumBranding.signalStrengthColor(for: strength)
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
        guard room.wallPoints.count >= 3 else { return }
        
        // Convert wall points to screen coordinates
        let screenPoints = room.wallPoints.map { point in
            CGPoint(
                x: CGFloat(point.x) * scale + offset.x,
                y: CGFloat(point.y) * scale + offset.y
            )
        }
        
        // Create path from wall points
        let path = CGMutablePath()
        path.move(to: screenPoints[0])
        for i in 1..<screenPoints.count {
            path.addLine(to: screenPoints[i])
        }
        path.closeSubpath()
        
        // Fill the room
        context.setFillColor(roomTypeColor(room.type).withAlphaComponent(0.3).cgColor)
        context.addPath(path)
        context.fillPath()
        
        // Draw walls
        context.setStrokeColor(roomTypeColor(room.type).cgColor)
        context.setLineWidth(3.0)
        context.addPath(path)
        context.strokePath()
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
}

class FloorPlanRenderer: UIView {
    private var rooms: [RoomAnalyzer.IdentifiedRoom] = []
    private var furniture: [RoomAnalyzer.FurnitureItem] = []
    private var heatmapData: WiFiHeatmapData?
    private var showHeatmap = false
    
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
        
        switch item.category {
        case .bed:
            drawBed(context: context, at: center, size: size)
        case .sofa:
            drawSofa(context: context, at: center, size: size)
        case .table:
            drawTable(context: context, at: center, size: size)
        case .chair:
            drawChair(context: context, at: center, size: size)
        case .refrigerator:
            drawRefrigerator(context: context, at: center, size: size)
        case .oven:
            drawOven(context: context, at: center, size: size)
        case .sink:
            drawSink(context: context, at: center, size: size)
        case .toilet:
            drawToilet(context: context, at: center, size: size)
        case .bathtub:
            drawBathtub(context: context, at: center, size: size)
        case .television:
            drawTelevision(context: context, at: center, size: size)
        case .dishwasher:
            drawDishwasher(context: context, at: center, size: size)
        default:
            drawGenericFurniture(context: context, at: center, size: size)
        }
        
        context.restoreGState()
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
        
        let scale = calculateScale(rect: rect)
        let offset = calculateOffset(rect: rect)
        
        for (position, coverage) in heatmapData.coverageMap {
            let center = CGPoint(
                x: CGFloat(position.x) * scale + offset.x,
                y: CGFloat(position.z) * scale + offset.y
            )
            
            let radius = 30.0 * CGFloat(coverage)
            let signalStrength = Int((coverage - 1.0) * 50.0 - 100)
            let color = signalStrengthColor(signalStrength).withAlphaComponent(0.4)
            
            context.setFillColor(color.cgColor)
            context.addEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.fillPath()
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
            
            let color = signalStrengthColor(measurement.signalStrength)
            context.setFillColor(color.cgColor)
            context.addEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            context.fillPath()
        }
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
    
    private func signalStrengthColor(_ strength: Int) -> UIColor {
        return SpectrumBranding.signalStrengthColor(for: strength)
    }
}