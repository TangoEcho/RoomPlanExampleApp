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
    
    private var floorPlanRenderer: FloorPlanRenderer!
    private var wifiHeatmapData: WiFiHeatmapData?
    private var roomAnalyzer: RoomAnalyzer?
    private var networkDeviceManager: NetworkDeviceManager?
    private var measurements: [WiFiMeasurement] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupFloorPlanRenderer()
        setupUI()
        setupConstraints()
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
        
        heatmapLabel = SpectrumBranding.createSpectrumLabel(text: "Show WiFi Heatmap", style: .body)
        heatmapLabel.textAlignment = .right
        
        legendView = UIView()
        legendView.backgroundColor = .systemBackground
        legendView.layer.cornerRadius = 8
        legendView.translatesAutoresizingMaskIntoConstraints = false
        
        exportButton = SpectrumBranding.createSpectrumButton(title: "Export Report", style: .accent)
        // Remove white border for better readability - accent style already has good contrast
        exportButton.layer.borderWidth = 0
        exportButton.layer.borderColor = UIColor.clear.cgColor
        
        measurementsList = UITableView()
        measurementsList.translatesAutoresizingMaskIntoConstraints = false
        
        // Add to view hierarchy
        view.addSubview(floorPlanView)
        view.addSubview(heatmapToggle)
        view.addSubview(heatmapLabel)
        view.addSubview(legendView)
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
            floorPlanView.heightAnchor.constraint(equalToConstant: 300),
            
            heatmapToggle.topAnchor.constraint(equalTo: floorPlanView.bottomAnchor, constant: 10),
            heatmapToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            heatmapLabel.centerYAnchor.constraint(equalTo: heatmapToggle.centerYAnchor),
            heatmapLabel.trailingAnchor.constraint(equalTo: heatmapToggle.leadingAnchor, constant: -10),
            heatmapLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            
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
        
        let newScanButton = SpectrumBranding.createSpectrumButton(title: "New Scan", style: .primary)
        // Use primary style for better contrast on blue header background
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
    
    func updateWithData(heatmapData: WiFiHeatmapData, roomAnalyzer: RoomAnalyzer, networkDeviceManager: NetworkDeviceManager? = nil) {
        self.wifiHeatmapData = heatmapData
        self.roomAnalyzer = roomAnalyzer
        self.networkDeviceManager = networkDeviceManager
        self.measurements = heatmapData.measurements
        
        DispatchQueue.main.async {
            // Update the renderer with the new data
            self.floorPlanRenderer.updateRooms(roomAnalyzer.identifiedRooms)
            self.floorPlanRenderer.updateFurniture(roomAnalyzer.furnitureItems)
            self.floorPlanRenderer.updateHeatmap(heatmapData)
            if let devices = self.networkDeviceManager?.getAllDevices() {
                // Convert NetworkDeviceManager.NetworkDevice to our NetworkDevice type
                let convertedDevices = devices.compactMap { device -> NetworkDevice? in
                    let type: NetworkDevice.DeviceType = device.type == .router ? .router : .extender
                    return NetworkDevice(type: type, position: device.position)
                }
                self.floorPlanRenderer.updateNetworkDevices(convertedDevices)
            }
            self.floorPlanRenderer.setShowHeatmap(self.heatmapToggle.isOn)
            self.measurementsList.reloadData()
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
