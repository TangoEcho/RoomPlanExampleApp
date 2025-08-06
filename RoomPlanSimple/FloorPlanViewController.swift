import UIKit
import SceneKit
import RoomPlan

protocol FloorPlanInteractionDelegate: AnyObject {
    func didSelectRoom(_ room: RoomAnalyzer.IdentifiedRoom)
    func didSelectMeasurement(_ measurement: WiFiMeasurement)
    func didSelectRouterPlacement(_ placement: simd_float3)
}

class FloorPlanViewController: UIViewController {
    private var customHeaderView: UIView!
    private var floorPlanView: UIView!
    private var heatmapToggle: UISwitch!
    private var heatmapLabel: UILabel!
    private var legendView: UIView!
    private var exportButton: UIButton!
    private var measurementsList: UITableView!
    private var devicePlacementButton: UIButton!
    private var deviceStatusLabel: UILabel!
    
    private var floorPlanRenderer: FloorPlanRenderer!
    private var wifiHeatmapData: WiFiHeatmapData?
    private var roomAnalyzer: RoomAnalyzer?
    private var networkDeviceManager: NetworkDeviceManager?
    private var measurements: [WiFiMeasurement] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupUI()
        setupConstraints()
        setupTableView()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if floorPlanRenderer == nil {
            setupFloorPlanRenderer()
        }
    }
    
    private func setupViews() {
        view.backgroundColor = .systemBackground
        
        // Create main container views
        floorPlanView = UIView()
        floorPlanView.backgroundColor = .systemGray6
        floorPlanView.translatesAutoresizingMaskIntoConstraints = false
        
        heatmapToggle = UISwitch()
        heatmapToggle.translatesAutoresizingMaskIntoConstraints = false
        
        heatmapLabel = SpectrumBranding.createSpectrumLabel(text: "Show WiFi Heatmap", style: .body)
        heatmapLabel.textAlignment = .right
        
        legendView = UIView()
        legendView.backgroundColor = .systemBackground
        legendView.layer.cornerRadius = 8
        legendView.translatesAutoresizingMaskIntoConstraints = false
        
        exportButton = UIButton(type: .system)
        exportButton.setTitle("Export Report", for: .normal)
        exportButton.setTitleColor(.white, for: .normal)
        exportButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        exportButton.backgroundColor = SpectrumBranding.Colors.spectrumBlue
        exportButton.layer.cornerRadius = 8
        exportButton.layer.shadowColor = UIColor.black.cgColor
        exportButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        exportButton.layer.shadowOpacity = 0.2
        exportButton.layer.shadowRadius = 4
        
        measurementsList = UITableView()
        measurementsList.translatesAutoresizingMaskIntoConstraints = false
        
        devicePlacementButton = UIButton(type: .system)
        devicePlacementButton.setTitle("📡 Show Network Devices", for: .normal)
        devicePlacementButton.setTitleColor(.white, for: .normal)
        devicePlacementButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        devicePlacementButton.backgroundColor = SpectrumBranding.Colors.spectrumGreen
        devicePlacementButton.layer.cornerRadius = 8
        devicePlacementButton.addTarget(self, action: #selector(toggleDevicePlacement), for: .touchUpInside)
        
        deviceStatusLabel = SpectrumBranding.createSpectrumLabel(text: "", style: .caption)
        deviceStatusLabel.textAlignment = .center
        deviceStatusLabel.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        deviceStatusLabel.layer.cornerRadius = 8
        deviceStatusLabel.layer.masksToBounds = true
        deviceStatusLabel.isHidden = true
        
        // Add to view hierarchy
        view.addSubview(floorPlanView)
        view.addSubview(heatmapToggle)
        view.addSubview(heatmapLabel)
        view.addSubview(legendView)
        view.addSubview(devicePlacementButton)
        view.addSubview(deviceStatusLabel)
        view.addSubview(exportButton)
        view.addSubview(measurementsList)
    }
    
    private func setupConstraints() {
        let topConstraint: NSLayoutConstraint
        if customHeaderView != nil {
            topConstraint = floorPlanView.topAnchor.constraint(equalTo: customHeaderView.bottomAnchor, constant: 10)
        } else {
            topConstraint = floorPlanView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10)
        }
        
        NSLayoutConstraint.activate([
            topConstraint,
            floorPlanView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            floorPlanView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            floorPlanView.heightAnchor.constraint(equalToConstant: 500),
            
            heatmapToggle.topAnchor.constraint(equalTo: floorPlanView.bottomAnchor, constant: 10),
            heatmapToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            heatmapLabel.centerYAnchor.constraint(equalTo: heatmapToggle.centerYAnchor),
            heatmapLabel.trailingAnchor.constraint(equalTo: heatmapToggle.leadingAnchor, constant: -10),
            heatmapLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            
            legendView.topAnchor.constraint(equalTo: heatmapToggle.bottomAnchor, constant: 10),
            legendView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            legendView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            legendView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            
            devicePlacementButton.topAnchor.constraint(equalTo: legendView.bottomAnchor, constant: 10),
            devicePlacementButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            devicePlacementButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            devicePlacementButton.heightAnchor.constraint(equalToConstant: 44),
            
            deviceStatusLabel.topAnchor.constraint(equalTo: devicePlacementButton.bottomAnchor, constant: 8),
            deviceStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            deviceStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            deviceStatusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            
            exportButton.topAnchor.constraint(equalTo: devicePlacementButton.bottomAnchor, constant: 60),
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
        
        // Apply any pending data now that renderer is ready
        if let roomAnalyzer = self.roomAnalyzer, let heatmapData = self.wifiHeatmapData {
            floorPlanRenderer.updateRooms(roomAnalyzer.identifiedRooms)
            floorPlanRenderer.updateFurniture(roomAnalyzer.furnitureItems)
            floorPlanRenderer.updateHeatmap(heatmapData)
            if let devices = self.networkDeviceManager?.getAllDevices() {
                let convertedDevices = devices.compactMap { device -> NetworkDevice? in
                    let type: NetworkDevice.DeviceType = device.type == .router ? .router : .extender
                    return NetworkDevice(type: type, position: device.position)
                }
                floorPlanRenderer.updateNetworkDevices(convertedDevices)
            }
            floorPlanRenderer.setShowHeatmap(self.heatmapToggle.isOn)
            print("✅ Applied pending data to FloorPlanRenderer")
        }
    }
    
    private func setupUI() {
        title = "Spectrum WiFi Analysis"
        view.backgroundColor = SpectrumBranding.Colors.secondaryBackground
        
        // Configure navigation bar with Spectrum branding
        if let navigationBar = navigationController?.navigationBar {
            SpectrumBranding.configureNavigationBar(navigationBar)
        } else {
            // Add custom header with navigation for modal presentation
            setupCustomHeader()
        }
        
        setupLegend()
        
        heatmapToggle.addTarget(self, action: #selector(toggleHeatmap), for: .valueChanged)
        exportButton.addTarget(self, action: #selector(exportReport), for: .touchUpInside)
    }
    
    private func setupCustomHeader() {
        customHeaderView = UIView()
        customHeaderView.backgroundColor = SpectrumBranding.Colors.spectrumBlue
        customHeaderView.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = SpectrumBranding.createSpectrumLabel(text: "Spectrum WiFi Analysis", style: .headline)
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
        
        let newScanButton = UIButton(type: .system)
        newScanButton.setTitle("New Scan", for: .normal)
        newScanButton.setTitleColor(.white, for: .normal)
        newScanButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        newScanButton.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        newScanButton.layer.cornerRadius = 8
        newScanButton.layer.borderWidth = 1
        newScanButton.layer.borderColor = UIColor.white.cgColor
        newScanButton.addTarget(self, action: #selector(startNewScan), for: .touchUpInside)
        
        view.addSubview(customHeaderView)
        customHeaderView.addSubview(titleLabel)
        customHeaderView.addSubview(newScanButton)
        
        NSLayoutConstraint.activate([
            customHeaderView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            customHeaderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customHeaderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            customHeaderView.heightAnchor.constraint(equalToConstant: 60),
            
            titleLabel.centerXAnchor.constraint(equalTo: customHeaderView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: customHeaderView.centerYAnchor),
            
            newScanButton.trailingAnchor.constraint(equalTo: customHeaderView.trailingAnchor, constant: -16),
            newScanButton.centerYAnchor.constraint(equalTo: customHeaderView.centerYAnchor),
            newScanButton.widthAnchor.constraint(equalToConstant: 80),
            newScanButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }
    
    @objc private func startNewScan() {
        dismiss(animated: true, completion: nil)
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
            colorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            colorView.topAnchor.constraint(equalTo: containerView.topAnchor),
            colorView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            colorView.widthAnchor.constraint(equalToConstant: 16),
            colorView.heightAnchor.constraint(equalToConstant: 16),
            
            labelView.leadingAnchor.constraint(equalTo: colorView.trailingAnchor, constant: 12),
            labelView.centerYAnchor.constraint(equalTo: colorView.centerYAnchor),
            labelView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            labelView.topAnchor.constraint(greaterThanOrEqualTo: containerView.topAnchor),
            labelView.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor)
        ])
        
        return containerView
    }
    
    func updateWithData(heatmapData: WiFiHeatmapData, roomAnalyzer: RoomAnalyzer, networkDeviceManager: NetworkDeviceManager? = nil) {
        self.wifiHeatmapData = heatmapData
        self.roomAnalyzer = roomAnalyzer
        self.networkDeviceManager = networkDeviceManager
        self.measurements = heatmapData.measurements
        
        DispatchQueue.main.async {
            // Update the renderer with the new data (if it exists)
            if let renderer = self.floorPlanRenderer {
                renderer.updateRooms(roomAnalyzer.identifiedRooms)
                renderer.updateFurniture(roomAnalyzer.furnitureItems)
                renderer.updateHeatmap(heatmapData)
                if let devices = self.networkDeviceManager?.getAllDevices() {
                    // Convert NetworkDeviceManager.NetworkDevice to our NetworkDevice type
                    let convertedDevices = devices.compactMap { device -> NetworkDevice? in
                        let type: NetworkDevice.DeviceType = device.type == .router ? .router : .extender
                        return NetworkDevice(type: type, position: device.position)
                    }
                    renderer.updateNetworkDevices(convertedDevices)
                }
                renderer.setShowHeatmap(self.heatmapToggle.isOn)
            } else {
                // Renderer not ready yet, will be updated in setupFloorPlanRenderer
                print("⚠️ FloorPlanRenderer not ready yet, data will be applied when renderer is created")
            }
            self.measurementsList.reloadData()
            self.updateDeviceStatus()
        }
    }
    
    @objc private func toggleHeatmap() {
        floorPlanRenderer.setShowHeatmap(heatmapToggle.isOn)
    }
    
    @objc private func exportReport() {
        guard let heatmapData = wifiHeatmapData,
              let roomAnalyzer = roomAnalyzer else { return }
        
        let reportGenerator = WiFiReportGenerator()
        let reportURL = reportGenerator.generateReport(
            heatmapData: heatmapData,
            rooms: roomAnalyzer.identifiedRooms,
            furniture: roomAnalyzer.furnitureItems
        )
        
        let activityVC = UIActivityViewController(activityItems: [reportURL], applicationActivities: nil)
        activityVC.modalPresentationStyle = .popover
        
        present(activityVC, animated: true)
        if let popOver = activityVC.popoverPresentationController {
            popOver.sourceView = exportButton
        }
    }
    
    private func signalStrengthColor(_ strength: Float) -> UIColor {
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
    
    @objc private func toggleDevicePlacement() {
        guard let networkDeviceManager = networkDeviceManager else { return }
        
        let hasDevices = networkDeviceManager.router != nil || !networkDeviceManager.extenders.isEmpty
        
        if hasDevices {
            // Show device information
            showDeviceInfo()
        } else {
            // Show placement recommendations
            showPlacementRecommendations()
        }
    }
    
    private func showDeviceInfo() {
        guard let networkDeviceManager = networkDeviceManager else { return }
        
        var message = "Current Network Setup:\n\n"
        
        if let router = networkDeviceManager.router {
            message += "📡 Router: Placed\n"
            message += "Position: (\(String(format: "%.1f", router.position.x)), \(String(format: "%.1f", router.position.z)))\n\n"
        } else {
            message += "📡 Router: Not placed\n\n"
        }
        
        if !networkDeviceManager.extenders.isEmpty {
            message += "📡 Extenders: \(networkDeviceManager.extenders.count)\n"
            for (index, extender) in networkDeviceManager.extenders.enumerated() {
                message += "  \(index + 1). Position: (\(String(format: "%.1f", extender.position.x)), \(String(format: "%.1f", extender.position.z)))\n"
            }
        } else {
            message += "📡 Extenders: None\n"
        }
        
        message += "\n\(networkDeviceManager.suitableSurfaces.count) suitable surfaces found for placement"
        
        let alert = UIAlertController(title: "Network Device Status", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showPlacementRecommendations() {
        guard let networkDeviceManager = networkDeviceManager else { return }
        
        var message = "Network Device Placement Guide:\n\n"
        
        if networkDeviceManager.suitableSurfaces.isEmpty {
            message += "⚠️ No suitable surfaces found for device placement.\n\n"
            message += "Tips:\n"
            message += "• Ensure room scanning captured furniture\n"
            message += "• Tables and elevated surfaces work best\n"
            message += "• Avoid floor-level placement\n"
        } else {
            message += "✅ Found \(networkDeviceManager.suitableSurfaces.count) suitable surfaces:\n\n"
            
            for (index, surface) in networkDeviceManager.suitableSurfaces.prefix(3).enumerated() {
                let emoji = surface.furnitureItem.category == .table ? "📋" : "🛋️"
                message += "\(index + 1). \(emoji) \(surface.furnitureItem.category) "
                message += "(Score: \(String(format: "%.1f", surface.suitabilityScore * 100))%)\n"
            }
            
            message += "\nTo place devices:\n"
            message += "1. Return to AR scanning mode\n"
            message += "2. Switch to WiFi Survey\n"
            message += "3. Use '📡 Place Router' button\n"
        }
        
        let alert = UIAlertController(title: "Device Placement Guide", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func updateDeviceStatus() {
        guard let networkDeviceManager = networkDeviceManager else {
            deviceStatusLabel.isHidden = true
            return
        }
        
        let deviceCount = networkDeviceManager.getDeviceCount()
        let surfaceCount = networkDeviceManager.suitableSurfaces.count
        
        if deviceCount.routers > 0 || deviceCount.extenders > 0 {
            devicePlacementButton.setTitle("📡 View Network Devices", for: .normal)
            deviceStatusLabel.text = "\(deviceCount.routers) router, \(deviceCount.extenders) extender(s) placed"
            deviceStatusLabel.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
            deviceStatusLabel.isHidden = false
        } else if surfaceCount > 0 {
            devicePlacementButton.setTitle("📡 View Placement Options", for: .normal)
            deviceStatusLabel.text = "\(surfaceCount) suitable surfaces found for device placement"
            deviceStatusLabel.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
            deviceStatusLabel.isHidden = false
        } else {
            devicePlacementButton.setTitle("📡 Network Device Info", for: .normal)
            deviceStatusLabel.isHidden = true
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
        cell.textLabel?.text = "\(roomName): \(measurement.signalStrength)dBm, \(Int(round(measurement.speed)))Mbps"
        cell.detailTextLabel?.text = measurement.frequency
        
        let signalColor = signalStrengthColor(Float(measurement.signalStrength))
        cell.backgroundColor = signalColor.withAlphaComponent(0.3)
        
        return cell
    }
}
