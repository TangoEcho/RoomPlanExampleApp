import UIKit
import RoomPlan
import simd

class FloorPlanViewController: UIViewController {
    
    // MARK: - Properties
    
    private var floorPlanRenderer: FloorPlanRenderer!
    // Accuracy debug renderer disabled for build compatibility
    private var legendView: UIView!
    private var scrollView: UIScrollView!
    private var contentView: UIView!
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
    
    // Sample data properties
    private var rooms: [RoomAnalyzer.IdentifiedRoom] = []
    private var furniture: [RoomAnalyzer.FurnitureItem] = []
    private var heatmapData: WiFiHeatmapData?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        // Test RF propagation models integration
        let wifiSurveyManager = WiFiSurveyManager()
        wifiSurveyManager.testRFPropagationModels()
        
        // Load sample data for demonstration
        loadSampleData()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("📊 FloorPlanViewController appeared with frame: \(view.frame)")
        
        // Force layout update
        view.setNeedsLayout()
        view.layoutIfNeeded()
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()
        contentView.setNeedsLayout()
        contentView.layoutIfNeeded()
        
        // Log all view frames
        print("📊 ScrollView frame: \(scrollView.frame)")
        print("📊 ContentView frame: \(contentView.frame)")
        if let renderer = floorPlanRenderer {
            print("📊 FloorPlanRenderer frame: \(renderer.frame), bounds: \(renderer.bounds)")
            print("📊 FloorPlanRenderer superview: \(renderer.superview?.description ?? "nil")")
            // Force the renderer to redraw
            renderer.setNeedsDisplay()
        }
        
        // Show sample data if available
        if !rooms.isEmpty {
            updateVisualization()
        } else {
            print("📊 No rooms available, forcing renderer to draw placeholder")
            floorPlanRenderer.setNeedsDisplay()
        }
    }
    
    // MARK: - Sample Data
    
    private func loadSampleData() {
        print("📊 Loading sample data for demonstration")
        
        // Create sample rooms (a typical house layout)
        let livingRoom = RoomAnalyzer.IdentifiedRoom(
            type: .livingRoom,
            bounds: createMockSurface(width: 6.0, height: 5.0, centerX: 0, centerY: -2.5),
            center: simd_float3(0, 0, -2.5),
            area: 30.0,
            confidence: 0.9,
            wallPoints: [
                simd_float2(-3, 0), simd_float2(3, 0), simd_float2(3, -5), simd_float2(-3, -5)
            ],
            doorways: [simd_float2(1.5, 0), simd_float2(-3, -1.5)]
        )
        
        let kitchen = RoomAnalyzer.IdentifiedRoom(
            type: .kitchen,
            bounds: createMockSurface(width: 4.0, height: 3.0, centerX: 2, centerY: 1.5),
            center: simd_float3(2, 0, 1.5),
            area: 12.0,
            confidence: 0.85,
            wallPoints: [
                simd_float2(0, 3), simd_float2(4, 3), simd_float2(4, 0), simd_float2(0, 0)
            ],
            doorways: [simd_float2(1, 0)]
        )
        
        let bedroom = RoomAnalyzer.IdentifiedRoom(
            type: .bedroom,
            bounds: createMockSurface(width: 4.0, height: 3.5, centerX: -2, centerY: 1.75),
            center: simd_float3(-2, 0, 1.75),
            area: 14.0,
            confidence: 0.88,
            wallPoints: [
                simd_float2(-4, 3.5), simd_float2(0, 3.5), simd_float2(0, 0), simd_float2(-4, 0)
            ],
            doorways: [simd_float2(-2, 0)]
        )
        
        rooms = [livingRoom, kitchen, bedroom]
        
        // Create sample furniture
        furniture = [
            RoomAnalyzer.FurnitureItem(
                category: .sofa,
                position: simd_float3(-1, 0.4, -3),
                dimensions: simd_float3(2.0, 0.8, 0.9),
                roomId: livingRoom.id,
                confidence: 0.9
            ),
            RoomAnalyzer.FurnitureItem(
                category: .table,
                position: simd_float3(1, 0.4, -2),
                dimensions: simd_float3(1.2, 0.8, 0.8),
                roomId: livingRoom.id,
                confidence: 0.85
            ),
            RoomAnalyzer.FurnitureItem(
                category: .refrigerator,
                position: simd_float3(3.5, 0.9, 2.8),
                dimensions: simd_float3(0.7, 1.8, 0.7),
                roomId: kitchen.id,
                confidence: 0.95
            ),
            RoomAnalyzer.FurnitureItem(
                category: .bed,
                position: simd_float3(-3, 0.3, 2.5),
                dimensions: simd_float3(1.4, 0.6, 2.0),
                roomId: bedroom.id,
                confidence: 0.92
            )
        ]
        
        // Create sample WiFi measurements with multi-band data
        let sampleMeasurements = createSampleWiFiMeasurements()
        measurements = sampleMeasurements
        
        // Create basic heatmap data from measurements  
        let basicCoverageMap = createCoverageMap(from: measurements)
        heatmapData = WiFiHeatmapData(
            measurements: measurements,
            coverageMap: basicCoverageMap,
            optimalRouterPlacements: [simd_float3(0, 0.5, 0)] // Center of living room
        )
        
        print("📊 Sample data loaded: \(rooms.count) rooms, \(furniture.count) furniture items, \(measurements.count) WiFi measurements")
    }
    
    private func createMockSurface(width: Float, height: Float, centerX: Float, centerY: Float) -> CapturedRoom.Surface? {
        // This is a simplified mock - in reality this would be more complex RoomPlan data
        // For now, we'll return nil and use our wall points instead of RoomPlan geometry
        return nil
    }
    
    private func createSampleWiFiMeasurements() -> [WiFiMeasurement] {
        var measurements: [WiFiMeasurement] = []
        
        // Create measurements positioned within the actual room boundaries
        // Living room: center=(0,0,-2.5), bounds=(-3,0) to (3,-5)
        // Kitchen: center=(2,0,1.5), bounds=(0,0) to (4,3) 
        // Bedroom: center=(-2,0,1.75), bounds=(-4,0) to (0,3.5)
        let positions = [
            // Living room measurements (good signal - close to router) - within bounds (-3,0) to (3,-5)
            (simd_float3(-1.5, 0, -1.5), RoomType.livingRoom, -45, 180.0),
            (simd_float3(0, 0, -2.5), RoomType.livingRoom, -42, 195.0),
            (simd_float3(1.5, 0, -3.5), RoomType.livingRoom, -48, 165.0),
            (simd_float3(-1, 0, -4), RoomType.livingRoom, -40, 210.0),
            
            // Kitchen measurements (moderate signal) - within bounds (0,0) to (4,3)
            (simd_float3(1.5, 0, 1.5), RoomType.kitchen, -55, 120.0),
            (simd_float3(3, 0, 2.5), RoomType.kitchen, -58, 95.0),
            (simd_float3(2.5, 0, 1), RoomType.kitchen, -60, 85.0),
            
            // Bedroom measurements (weaker signal - far from router) - within bounds (-4,0) to (0,3.5)
            (simd_float3(-3, 0, 1.5), RoomType.bedroom, -68, 45.0),
            (simd_float3(-1.5, 0, 2.5), RoomType.bedroom, -72, 35.0),
            (simd_float3(-2.5, 0, 3), RoomType.bedroom, -65, 55.0),
        ]
        
        for (index, (position, roomType, signalStrength, speed)) in positions.enumerated() {
            // Create multi-band measurements for WiFi 7
            let bandMeasurements = [
                BandMeasurement(
                    band: .band2_4GHz,
                    signalStrength: Float(signalStrength + 5), // 2.4GHz typically stronger
                    snr: 25.0,
                    channelWidth: 20,
                    speed: Float(speed * 0.3), // 2.4GHz slower
                    utilization: 0.6
                ),
                BandMeasurement(
                    band: .band5GHz,
                    signalStrength: Float(signalStrength),
                    snr: 28.0,
                    channelWidth: 80,
                    speed: Float(speed),
                    utilization: 0.3
                ),
                BandMeasurement(
                    band: .band6GHz,
                    signalStrength: Float(signalStrength - 3), // 6GHz typically weaker but less congested
                    snr: 32.0,
                    channelWidth: 160,
                    speed: Float(speed * 1.5), // 6GHz faster when available
                    utilization: 0.1
                )
            ]
            
            let measurement = WiFiMeasurement(
                location: position,
                timestamp: Date().addingTimeInterval(TimeInterval(index * 30)),
                signalStrength: signalStrength,
                networkName: "Spectrum-WiFi7-Demo",
                speed: speed,
                frequency: "Multi-band",
                roomType: roomType,
                bandMeasurements: bandMeasurements
            )
            
            measurements.append(measurement)
        }
        
        return measurements
    }
    
    private func createCoverageMap(from measurements: [WiFiMeasurement]) -> [simd_float3: Double] {
        var coverageMap: [simd_float3: Double] = [:]
        
        for measurement in measurements {
            // Convert signal strength to coverage percentage
            let coverage: Double
            switch measurement.signalStrength {
            case -50...0: coverage = 1.0
            case -65..<(-50): coverage = 0.8
            case -75..<(-65): coverage = 0.6
            case -85..<(-75): coverage = 0.4
            default: coverage = 0.2
            }
            
            coverageMap[measurement.location] = coverage
        }
        
        return coverageMap
    }
    
    private func updateVisualization() {
        guard let heatmapData = heatmapData else { return }
        
        // Update floor plan renderer with sample data
        floorPlanRenderer.updateRooms(rooms)
        floorPlanRenderer.updateFurniture(furniture)
        floorPlanRenderer.updateHeatmap(heatmapData)
        
        print("📊 Updated visualization with sample data")
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
        // Scroll view and content view
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = true
        
        contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
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
        heatmapLabel.text = "Show WiFi Heatmap"
        heatmapLabel.font = .systemFont(ofSize: 16, weight: .medium)
        heatmapLabel.textAlignment = .left
        heatmapLabel.setContentHuggingPriority(.required, for: .horizontal)
        // heatmapLabel.backgroundColor = .clear  // Removed debug color
        heatmapLabel.translatesAutoresizingMaskIntoConstraints = false
        
        heatmapToggle = UISwitch()
        heatmapToggle.addTarget(self, action: #selector(toggleHeatmap), for: .valueChanged)
        heatmapToggle.setContentHuggingPriority(.required, for: .horizontal)
        heatmapToggle.translatesAutoresizingMaskIntoConstraints = false
        
        // Debug controls
        debugLabel = UILabel()
        debugLabel.text = "Show Debug Overlay"
        debugLabel.font = .systemFont(ofSize: 16, weight: .medium)
        debugLabel.textAlignment = .left
        debugLabel.setContentHuggingPriority(.required, for: .horizontal)
        debugLabel.translatesAutoresizingMaskIntoConstraints = false
        
        debugToggle = UISwitch()
        debugToggle.addTarget(self, action: #selector(toggleDebugView), for: .valueChanged)
        debugToggle.setContentHuggingPriority(.required, for: .horizontal)
        debugToggle.translatesAutoresizingMaskIntoConstraints = false
        
        // Confidence visualization controls
        confidenceLabel = UILabel()
        confidenceLabel.text = "Show Coverage Confidence"
        confidenceLabel.font = .systemFont(ofSize: 16, weight: .medium)
        confidenceLabel.textAlignment = .left
        confidenceLabel.setContentHuggingPriority(.required, for: .horizontal)
        confidenceLabel.translatesAutoresizingMaskIntoConstraints = false
        
        confidenceToggle = UISwitch()
        confidenceToggle.addTarget(self, action: #selector(toggleConfidenceView), for: .valueChanged)
        confidenceToggle.setContentHuggingPriority(.required, for: .horizontal)
        confidenceToggle.translatesAutoresizingMaskIntoConstraints = false
        
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
        // Add main views to view controller
        view.addSubview(closeButton)
        view.addSubview(scrollView)
        
        // Add content view to scroll view
        scrollView.addSubview(contentView)
        
        // Add all content to content view
        contentView.addSubview(floorPlanRenderer)
        contentView.addSubview(heatmapLabel)
        contentView.addSubview(heatmapToggle)
        contentView.addSubview(debugLabel)
        contentView.addSubview(debugToggle)
        contentView.addSubview(confidenceLabel)
        contentView.addSubview(confidenceToggle)
        contentView.addSubview(legendView)
        contentView.addSubview(exportButton)
        contentView.addSubview(compareButton)
        contentView.addSubview(measurementsList)
        
        print("📊 Added all subviews to content view")
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Close button
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            // Content view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Floor plan renderer - fixed height
            floorPlanRenderer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            floorPlanRenderer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            floorPlanRenderer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            floorPlanRenderer.heightAnchor.constraint(equalToConstant: 300),
            
            // Accuracy debug renderer - same position as floor plan renderer
            // Accuracy debug renderer constraints disabled
            /*
            accuracyDebugRenderer.topAnchor.constraint(equalTo: floorPlanRenderer.topAnchor),
            accuracyDebugRenderer.leadingAnchor.constraint(equalTo: floorPlanRenderer.leadingAnchor),
            accuracyDebugRenderer.trailingAnchor.constraint(equalTo: floorPlanRenderer.trailingAnchor),
            accuracyDebugRenderer.bottomAnchor.constraint(equalTo: floorPlanRenderer.bottomAnchor),
            */
            
            // Heatmap toggle and label - better alignment
            heatmapToggle.topAnchor.constraint(equalTo: floorPlanRenderer.bottomAnchor, constant: 20),
            heatmapToggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            heatmapLabel.centerYAnchor.constraint(equalTo: heatmapToggle.centerYAnchor),
            heatmapLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            heatmapLabel.trailingAnchor.constraint(lessThanOrEqualTo: heatmapToggle.leadingAnchor, constant: -12),
            
            // Debug toggle and label - consistent alignment
            debugToggle.topAnchor.constraint(equalTo: heatmapToggle.bottomAnchor, constant: 12),
            debugToggle.trailingAnchor.constraint(equalTo: heatmapToggle.trailingAnchor),
            
            debugLabel.centerYAnchor.constraint(equalTo: debugToggle.centerYAnchor),
            debugLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            debugLabel.trailingAnchor.constraint(lessThanOrEqualTo: debugToggle.leadingAnchor, constant: -12),
            
            // Confidence toggle and label - consistent alignment
            confidenceToggle.topAnchor.constraint(equalTo: debugToggle.bottomAnchor, constant: 12),
            confidenceToggle.trailingAnchor.constraint(equalTo: heatmapToggle.trailingAnchor),
            
            confidenceLabel.centerYAnchor.constraint(equalTo: confidenceToggle.centerYAnchor),
            confidenceLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            confidenceLabel.trailingAnchor.constraint(lessThanOrEqualTo: confidenceToggle.leadingAnchor, constant: -12),
            
            // Legend - better spacing
            legendView.topAnchor.constraint(equalTo: confidenceToggle.bottomAnchor, constant: 20),
            legendView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            legendView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            legendView.heightAnchor.constraint(equalToConstant: 120),
            
            // Export button - consistent spacing
            exportButton.topAnchor.constraint(equalTo: legendView.bottomAnchor, constant: 20),
            exportButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            exportButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            exportButton.heightAnchor.constraint(equalToConstant: 48),
            
            // Compare button - consistent spacing
            compareButton.topAnchor.constraint(equalTo: exportButton.bottomAnchor, constant: 12),
            compareButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            compareButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            compareButton.heightAnchor.constraint(equalToConstant: 48),
            
            // Measurements list - fixed height with bottom constraint to contentView
            measurementsList.topAnchor.constraint(equalTo: compareButton.bottomAnchor, constant: 20),
            measurementsList.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            measurementsList.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            measurementsList.heightAnchor.constraint(equalToConstant: 200),
            measurementsList.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
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