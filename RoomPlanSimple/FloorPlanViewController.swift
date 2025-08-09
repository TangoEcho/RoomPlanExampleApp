import UIKit
import RoomPlan

class FloorPlanViewController: UIViewController {
    
    // MARK: - Properties
    
    private var floorPlanRenderer: FloorPlanRenderer!
    // Accuracy debug renderer disabled for build compatibility
    private var legendView: UIView!
    private var measurementsList: UITableView!
    private var heatmapToggle: UISwitch!
    private var heatmapLabel: UILabel!
    private var debugToggle: UISwitch!
    private var debugLabel: UILabel!
    private var confidenceToggle: UISwitch!
    private var confidenceLabel: UILabel!
    private var exportButton: UIButton!
    private var compareButton: UIButton!
    private var closeButton: UIButton!
    
    private var wifiHeatmapData: WiFiHeatmapData?
    private var roomAnalyzer: RoomAnalyzer?
    private var networkDeviceManager: NetworkDeviceManager?
    // Validation results disabled for build compatibility
    private var measurements: [WiFiMeasurement] = []
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        // Test RF propagation models integration
        let wifiSurveyManager = WiFiSurveyManager()
        wifiSurveyManager.testRFPropagationModels()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("📊 FloorPlanViewController appeared with frame: \(view.frame)")
        
        // Force layout update
        view.setNeedsLayout()
        view.layoutIfNeeded()
        
        // Log renderer frame
        if let renderer = floorPlanRenderer {
            print("📊 FloorPlanRenderer frame: \(renderer.frame), bounds: \(renderer.bounds)")
        }
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Create all views first
        createViews()
        
        // Add all views to hierarchy
        addSubviews()
        
        // Setup constraints
        setupConstraints()
        
        // Configure views
        configureViews()
        
        // Setup legend content
        setupLegend()
    }
    
    private func createViews() {
        // Floor plan renderer
        floorPlanRenderer = FloorPlanRenderer()
        floorPlanRenderer.translatesAutoresizingMaskIntoConstraints = false
        floorPlanRenderer.backgroundColor = .systemGray6
        floorPlanRenderer.layer.cornerRadius = 12
        floorPlanRenderer.layer.borderWidth = 1
        floorPlanRenderer.layer.borderColor = UIColor.systemGray4.cgColor
        
        // Accuracy debug renderer
        // Accuracy debug renderer setup disabled for build compatibility
        /*
        accuracyDebugRenderer = AccuracyDebugRenderer()
        accuracyDebugRenderer.translatesAutoresizingMaskIntoConstraints = false
        accuracyDebugRenderer.backgroundColor = .systemGray6
        accuracyDebugRenderer.layer.cornerRadius = 12
        accuracyDebugRenderer.layer.borderWidth = 1
        accuracyDebugRenderer.layer.borderColor = UIColor.systemGray4.cgColor
        accuracyDebugRenderer.isHidden = true
        */
        
        // Heatmap controls
        heatmapLabel = UILabel()
        heatmapLabel.translatesAutoresizingMaskIntoConstraints = false
        heatmapLabel.text = "Show WiFi Heatmap"
        heatmapLabel.font = .systemFont(ofSize: 16, weight: .medium)
        
        heatmapToggle = UISwitch()
        heatmapToggle.translatesAutoresizingMaskIntoConstraints = false
        heatmapToggle.addTarget(self, action: #selector(toggleHeatmap), for: .valueChanged)
        
        // Debug controls
        debugLabel = UILabel()
        debugLabel.translatesAutoresizingMaskIntoConstraints = false
        debugLabel.text = "Show Debug Overlay"
        debugLabel.font = .systemFont(ofSize: 16, weight: .medium)
        
        debugToggle = UISwitch()
        debugToggle.translatesAutoresizingMaskIntoConstraints = false
        debugToggle.addTarget(self, action: #selector(toggleDebugView), for: .valueChanged)
        
        // Confidence visualization controls
        confidenceLabel = UILabel()
        confidenceLabel.translatesAutoresizingMaskIntoConstraints = false
        confidenceLabel.text = "Show Coverage Confidence"
        confidenceLabel.font = .systemFont(ofSize: 16, weight: .medium)
        
        confidenceToggle = UISwitch()
        confidenceToggle.translatesAutoresizingMaskIntoConstraints = false
        confidenceToggle.addTarget(self, action: #selector(toggleConfidenceView), for: .valueChanged)
        
        // Legend
        legendView = UIView()
        legendView.translatesAutoresizingMaskIntoConstraints = false
        legendView.backgroundColor = .secondarySystemBackground
        legendView.layer.cornerRadius = 12
        
        // Measurements table
        measurementsList = UITableView()
        measurementsList.translatesAutoresizingMaskIntoConstraints = false
        measurementsList.delegate = self
        measurementsList.dataSource = self
        measurementsList.register(UITableViewCell.self, forCellReuseIdentifier: "MeasurementCell")
        measurementsList.backgroundColor = .systemBackground
        measurementsList.layer.cornerRadius = 12
        
        // Buttons
        exportButton = UIButton(type: .system)
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        exportButton.setTitle("Export Report", for: .normal)
        exportButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        exportButton.backgroundColor = .systemBlue
        exportButton.setTitleColor(.white, for: .normal)
        exportButton.layer.cornerRadius = 12
        exportButton.addTarget(self, action: #selector(exportReport), for: .touchUpInside)
        
        compareButton = UIButton(type: .system)
        compareButton.translatesAutoresizingMaskIntoConstraints = false
        compareButton.setTitle("📊 View Coverage Comparison", for: .normal)
        compareButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        compareButton.backgroundColor = SpectrumBranding.Colors.accent
        compareButton.setTitleColor(.white, for: .normal)
        compareButton.layer.cornerRadius = 12
        compareButton.addTarget(self, action: #selector(showCoverageComparison), for: .touchUpInside)
        
        closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("Close", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
    }
    
    private func addSubviews() {
        view.addSubview(closeButton)
        view.addSubview(floorPlanRenderer)
        // view.addSubview(accuracyDebugRenderer) // Disabled
        view.addSubview(heatmapLabel)
        view.addSubview(heatmapToggle)
        view.addSubview(debugLabel)
        view.addSubview(debugToggle)
        view.addSubview(confidenceLabel)
        view.addSubview(confidenceToggle)
        view.addSubview(legendView)
        view.addSubview(measurementsList)
        view.addSubview(exportButton)
        view.addSubview(compareButton)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Close button
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Floor plan renderer - fixed height
            floorPlanRenderer.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 16),
            floorPlanRenderer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            floorPlanRenderer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            floorPlanRenderer.heightAnchor.constraint(equalToConstant: 300),
            
            // Accuracy debug renderer - same position as floor plan renderer
            // Accuracy debug renderer constraints disabled
            /*
            accuracyDebugRenderer.topAnchor.constraint(equalTo: floorPlanRenderer.topAnchor),
            accuracyDebugRenderer.leadingAnchor.constraint(equalTo: floorPlanRenderer.leadingAnchor),
            accuracyDebugRenderer.trailingAnchor.constraint(equalTo: floorPlanRenderer.trailingAnchor),
            accuracyDebugRenderer.bottomAnchor.constraint(equalTo: floorPlanRenderer.bottomAnchor),
            */
            
            // Heatmap toggle and label
            heatmapToggle.topAnchor.constraint(equalTo: floorPlanRenderer.bottomAnchor, constant: 16),
            heatmapToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            heatmapLabel.centerYAnchor.constraint(equalTo: heatmapToggle.centerYAnchor),
            heatmapLabel.trailingAnchor.constraint(equalTo: heatmapToggle.leadingAnchor, constant: -8),
            
            // Debug toggle and label
            debugToggle.topAnchor.constraint(equalTo: heatmapToggle.bottomAnchor, constant: 8),
            debugToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            debugLabel.centerYAnchor.constraint(equalTo: debugToggle.centerYAnchor),
            debugLabel.trailingAnchor.constraint(equalTo: debugToggle.leadingAnchor, constant: -8),
            
            // Confidence toggle and label
            confidenceToggle.topAnchor.constraint(equalTo: debugToggle.bottomAnchor, constant: 8),
            confidenceToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            confidenceLabel.centerYAnchor.constraint(equalTo: confidenceToggle.centerYAnchor),
            confidenceLabel.trailingAnchor.constraint(equalTo: confidenceToggle.leadingAnchor, constant: -8),
            
            // Legend
            legendView.topAnchor.constraint(equalTo: confidenceToggle.bottomAnchor, constant: 16),
            legendView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            legendView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            legendView.heightAnchor.constraint(equalToConstant: 140),
            
            // Export button
            exportButton.topAnchor.constraint(equalTo: legendView.bottomAnchor, constant: 16),
            exportButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            exportButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            exportButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Compare button
            compareButton.topAnchor.constraint(equalTo: exportButton.bottomAnchor, constant: 12),
            compareButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            compareButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            compareButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Measurements list
            measurementsList.topAnchor.constraint(equalTo: compareButton.bottomAnchor, constant: 16),
            measurementsList.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            measurementsList.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            measurementsList.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }
    
    private func configureViews() {
        // Add title
        title = "WiFi Analysis Results"
        
        // Configure navigation bar if in navigation controller
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(closeButtonTapped)
        )
    }
    
    private func setupLegend() {
        // Clear existing subviews
        legendView.subviews.forEach { $0.removeFromSuperview() }
        
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.distribution = .fillEqually
        
        let legendItems = [
            ("Excellent (>-50 dBm)", UIColor.systemGreen),
            ("Good (-50 to -70 dBm)", UIColor.systemYellow),
            ("Fair (-70 to -85 dBm)", UIColor.systemOrange),
            ("Poor (<-85 dBm)", UIColor.systemRed),
            ("High Confidence (>80%)", UIColor.systemBlue),
            ("Medium Confidence (50-80%)", UIColor.systemPurple),
            ("Low Confidence (<50%)", UIColor.systemGray)
        ]
        
        // Show different legend based on confidence mode
        let filteredItems = confidenceToggle.isOn ? 
            Array(legendItems.suffix(3)) : // Show confidence legend
            Array(legendItems.prefix(4))   // Show signal strength legend
        
        for (text, color) in filteredItems {
            let itemView = createLegendItem(text: text, color: color)
            stackView.addArrangedSubview(itemView)
        }
        
        legendView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: legendView.topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: legendView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: legendView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: legendView.bottomAnchor, constant: -12)
        ])
    }
    
    private func createLegendItem(text: String, color: UIColor) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let colorView = UIView()
        colorView.translatesAutoresizingMaskIntoConstraints = false
        colorView.backgroundColor = color
        colorView.layer.cornerRadius = 6
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = .systemFont(ofSize: 14)
        label.textColor = .label
        
        container.addSubview(colorView)
        container.addSubview(label)
        
        NSLayoutConstraint.activate([
            colorView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            colorView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            colorView.widthAnchor.constraint(equalToConstant: 20),
            colorView.heightAnchor.constraint(equalToConstant: 20),
            
            label.leadingAnchor.constraint(equalTo: colorView.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        
        return container
    }
    
    // MARK: - Public Methods
    
    func updateWithData(heatmapData: WiFiHeatmapData, roomAnalyzer: RoomAnalyzer, networkDeviceManager: NetworkDeviceManager? = nil, validationResults: Any? = nil) {
        self.wifiHeatmapData = heatmapData
        self.roomAnalyzer = roomAnalyzer
        self.networkDeviceManager = networkDeviceManager
        // validationResults assignment disabled for build compatibility
        self.measurements = heatmapData.measurements
        
        print("📊 FloorPlanViewController: Received data update")
        print("   Rooms: \(roomAnalyzer.identifiedRooms.count)")
        print("   Measurements: \(measurements.count)")
        if validationResults != nil {
            print("   Validation results received (details disabled for build compatibility)")
        }
        
        // Update the renderer
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.floorPlanRenderer.updateRooms(roomAnalyzer.identifiedRooms)
            self.floorPlanRenderer.updateFurniture(roomAnalyzer.furnitureItems)
            self.floorPlanRenderer.updateHeatmap(heatmapData)
            
            if let devices = networkDeviceManager?.getAllDevices() {
                let convertedDevices = devices.map { device in
                    NetworkDevice(
                        type: device.type == .router ? .router : .extender,
                        position: device.position
                    )
                }
                self.floorPlanRenderer.updateNetworkDevices(convertedDevices)
            }
            
            // Enable debug and confidence toggles for enhanced visualization modes
            self.debugToggle.isEnabled = !heatmapData.measurements.isEmpty
            self.confidenceToggle.isEnabled = !heatmapData.measurements.isEmpty
            
            self.floorPlanRenderer.setShowHeatmap(self.heatmapToggle.isOn)
            self.floorPlanRenderer.setShowConfidence(self.confidenceToggle.isOn)
            self.measurementsList.reloadData()
        }
    }
    
    // MARK: - Actions
    
    @objc private func toggleHeatmap() {
        floorPlanRenderer.setShowHeatmap(heatmapToggle.isOn)
    }
    
    @objc private func toggleDebugView() {
        // Enhanced debug mode: force heatmap overlay and detailed view
        if debugToggle.isOn {
            // Debug mode: Force heatmap on and enhanced visualization
            floorPlanRenderer.setShowHeatmap(true)
            floorPlanRenderer.setDebugMode(true)
            heatmapToggle.isEnabled = false // Lock heatmap on in debug mode
            print("🔬 Debug visualization mode enabled")
        } else {
            // Normal mode: restore user's heatmap preference
            floorPlanRenderer.setShowHeatmap(heatmapToggle.isOn)
            floorPlanRenderer.setDebugMode(false)
            heatmapToggle.isEnabled = true
            print("🔬 Debug visualization mode disabled")
        }
    }
    
    @objc private func toggleConfidenceView() {
        floorPlanRenderer.setShowConfidence(confidenceToggle.isOn)
        // Update legend to show confidence scale or signal strength scale
        setupLegend()
        if confidenceToggle.isOn {
            print("📊 Coverage confidence visualization enabled")
        } else {
            print("📊 Coverage confidence visualization disabled")
        }
    }
    
    @objc private func exportReport() {
        guard let heatmapData = wifiHeatmapData,
              let roomAnalyzer = roomAnalyzer else {
            print("⚠️ No data available for export")
            return
        }
        
        let reportGenerator = WiFiReportGenerator()
        let reportURL = reportGenerator.generateReport(
            heatmapData: heatmapData,
            rooms: roomAnalyzer.identifiedRooms,
            furniture: roomAnalyzer.furnitureItems,
            networkDeviceManager: networkDeviceManager
        )
        
        let activityVC = UIActivityViewController(
            activityItems: [reportURL],
            applicationActivities: nil
        )
        
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = exportButton
            popover.sourceRect = exportButton.bounds
        }
        
        present(activityVC, animated: true)
    }
    
    @objc private func showCoverageComparison() {
        print("📊 Coverage comparison feature temporarily disabled during integration")
        
        let alert = UIAlertController(
            title: "Coverage Comparison",
            message: "This feature is being enhanced and will be available soon.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
}

// MARK: - UITableViewDataSource

extension FloorPlanViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return measurements.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MeasurementCell", for: indexPath)
        let measurement = measurements[indexPath.row]
        
        let roomName = measurement.roomType?.rawValue ?? "Unknown"
        let signalText = "\(measurement.signalStrength) dBm"
        let speedText = "\(Int(measurement.speed)) Mbps"
        
        cell.textLabel?.text = "\(roomName): \(signalText), \(speedText)"
        cell.textLabel?.font = .systemFont(ofSize: 14)
        
        // Set background color based on signal strength
        let signalColor = colorForSignalStrength(Float(measurement.signalStrength))
        cell.backgroundColor = signalColor.withAlphaComponent(0.2)
        
        return cell
    }
    
    private func colorForSignalStrength(_ strength: Float) -> UIColor {
        switch strength {
        case -50...Float.greatestFiniteMagnitude:
            return .systemGreen
        case -70..<(-50):
            return .systemYellow
        case -85..<(-70):
            return .systemOrange
        default:
            return .systemRed
        }
    }
}

// MARK: - UITableViewDelegate

extension FloorPlanViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }
}