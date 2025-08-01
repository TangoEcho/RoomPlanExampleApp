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
        
        exportButton = UIButton(type: .system)
        exportButton.setTitle("Export Report", for: .normal)
        exportButton.backgroundColor = .systemBlue
        exportButton.setTitleColor(.white, for: .normal)
        exportButton.layer.cornerRadius = 8
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        
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
        title = "WiFi Coverage Analysis"
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
            ("Excellent (>-50dBm)", UIColor.green),
            ("Good (-50 to -70dBm)", UIColor.yellow),
            ("Fair (-70 to -85dBm)", UIColor.orange),
            ("Poor (<-85dBm)", UIColor.red)
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
        switch strength {
        case -50...0:
            return UIColor.green
        case -70..<(-50):
            return UIColor.yellow
        case -85..<(-70):
            return UIColor.orange
        default:
            return UIColor.red
        }
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
            let roomRect = CGRect(
                x: CGFloat(room.center.x) * scale + offset.x - CGFloat(room.bounds.dimensions.x) * scale / 2,
                y: CGFloat(room.center.z) * scale + offset.y - CGFloat(room.bounds.dimensions.z) * scale / 2,
                width: CGFloat(room.bounds.dimensions.x) * scale,
                height: CGFloat(room.bounds.dimensions.z) * scale
            )
            
            context.setFillColor(roomTypeColor(room.type).withAlphaComponent(0.3).cgColor)
            context.setStrokeColor(roomTypeColor(room.type).cgColor)
            context.setLineWidth(2.0)
            
            context.addRect(roomRect)
            context.drawPath(using: .fillStroke)
            
            let roomLabel = room.type.rawValue
            let attributes = [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 14)]
            let textSize = roomLabel.size(withAttributes: attributes)
            let textRect = CGRect(
                x: roomRect.midX - textSize.width / 2,
                y: roomRect.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            roomLabel.draw(in: textRect, withAttributes: attributes)
        }
    }
    
    private func drawFurniture(context: CGContext, rect: CGRect) {
        let scale = calculateScale(rect: rect)
        let offset = calculateOffset(rect: rect)
        
        for item in furniture {
            let furnitureRect = CGRect(
                x: CGFloat(item.position.x) * scale + offset.x - CGFloat(item.dimensions.x) * scale / 2,
                y: CGFloat(item.position.z) * scale + offset.y - CGFloat(item.dimensions.z) * scale / 2,
                width: CGFloat(item.dimensions.x) * scale,
                height: CGFloat(item.dimensions.z) * scale
            )
            
            context.setFillColor(UIColor.gray.withAlphaComponent(0.5).cgColor)
            context.setStrokeColor(UIColor.darkGray.cgColor)
            context.setLineWidth(1.0)
            
            context.addRect(furnitureRect)
            context.drawPath(using: .fillStroke)
        }
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
        let maxDimension = max(
            rooms.map { $0.bounds.dimensions.x }.max() ?? 1.0,
            rooms.map { $0.bounds.dimensions.z }.max() ?? 1.0
        )
        
        let margin: CGFloat = 40
        return min(rect.width - margin, rect.height - margin) / CGFloat(maxDimension)
    }
    
    private func calculateOffset(rect: CGRect) -> CGPoint {
        return CGPoint(x: rect.width / 2, y: rect.height / 2)
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
        switch strength {
        case -50...0:
            return UIColor.green
        case -70..<(-50):
            return UIColor.yellow
        case -85..<(-70):
            return UIColor.orange
        default:
            return UIColor.red
        }
    }
}