/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The sample app's main view controller that manages the scanning process.
*/

import UIKit
import RoomPlan
import ARKit
import SceneKit
import Combine
import CoreLocation

class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    
    private var roomAnalyzer = RoomAnalyzer()
    private var wifiSurveyManager = WiFiSurveyManager()
    private var arVisualizationManager = ARVisualizationManager()
    private var networkDeviceManager = NetworkDeviceManager()
    // Room accuracy validation disabled for build compatibility
    private var arSceneView: ARSCNView!
    
    // iOS 17+ Custom ARSession for perfect coordinate alignment
    private lazy var sharedARSession: ARSession = {
        let session = ARSession()
        return session
    }()
    
    // Helper to check if iOS 17+ features are available
    private var isIOS17Available: Bool {
        if #available(iOS 17.0, *) { return true }
        return false
    }
    
    private var primaryActionButton: UIButton?
    private var viewResultsButton: UIButton?
    private var statusLabel: UILabel?
    private var progressIndicator: UIProgressView?
    private var speedTestProgressView: UIProgressView?
    private var speedTestLabel: UILabel?
    private var speedTestSpinner: UIActivityIndicatorView?
    
    // Bottom navigation
    private var bottomNavBar: UIView?
    private var scanSurveyToggleButton: UIButton?
    private var floorPlanNavButton: UIButton?
    private var routerPlacementButton: UIButton?
    private var modeLabel: UILabel?
    
    // Plume integration and data export controls
    private var plumeControlsContainer: UIView?
    private var plumeToggleButton: UIButton?
    private var exportDataButton: UIButton?
    private var plumeStatusLabel: UILabel?
    
    private var isARMode = false
    private var capturedRoomData: CapturedRoom?
    
    // Unified scan/survey workflow
    private var currentMode: CaptureMode = .scanning
    private var roomPlanPaused = false
    
    enum CaptureMode {
        case scanning    // Room scanning active
        case surveying   // WiFi surveying (RoomPlan paused)
        case completed   // Both complete
    }
    
    @IBOutlet var exportButton: UIButton?
    
    // Removed unused Done/Cancel buttons - using corner controls instead
    
    private var isScanning: Bool = false
    
    private var roomCaptureView: RoomCaptureView!
    private var roomCaptureSessionConfig: RoomCaptureSession.Configuration = RoomCaptureSession.Configuration()
    
    private var finalResults: CapturedRoom?
    
    // Haptic feedback generators
    private var lightHapticGenerator = UIImpactFeedbackGenerator(style: .light)
    private var mediumHapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    private var heavyHapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    
    // Tracking for haptic feedback throttling
    private var lastSurfaceHapticTime: Date = Date.distantPast
    private var lastObjectHapticTime: Date = Date.distantPast
    private let hapticThrottleInterval: TimeInterval = 0.5 // Minimum time between haptics
    
    // Progress scanning haptic timer
    private var scanningProgressTimer: Timer?
    private let progressHapticInterval: TimeInterval = 1.5 // Every 1.5 seconds while scanning
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupRoomCaptureView()
        setupARView()
        setupWiFiSurvey()
        setupBottomNavigation()
        setupPlumeControls()
        setupHapticFeedback()
        updateButtonStates()
    }
    
    private func setupRoomCaptureView() {
        
        print("🔧 Setting up RoomCaptureView with shared ARSession for optimal coordinate alignment...")
        
        // Check if RoomCapture is supported
        guard RoomCaptureSession.isSupported else {
            print("⚠️ RoomCapture not supported on this device - showing placeholder")
            setupPlaceholderView()
            return
        }
        
        // Remove existing room capture view if any
        roomCaptureView?.removeFromSuperview()
        
        // iOS 17+: Use custom ARSession for perfect coordinate alignment
        roomCaptureView = RoomCaptureView(frame: view.bounds, arSession: sharedARSession)
        print("✅ Using iOS 17+ custom ARSession for coordinate alignment")
        
        roomCaptureView?.captureSession.delegate = self
        roomCaptureView?.delegate = self
        roomCaptureView?.translatesAutoresizingMaskIntoConstraints = false
        
        // Insert at index 0 to be behind all UI elements
        view.insertSubview(roomCaptureView!, at: 0)
        
        // Add constraints to ensure it fills the entire view
        NSLayoutConstraint.activate([
            roomCaptureView!.topAnchor.constraint(equalTo: view.topAnchor),
            roomCaptureView!.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            roomCaptureView!.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            roomCaptureView!.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        print("✅ RoomCaptureView setup complete")
    }
    
    private func setupPlaceholderView() {
        // Create a red placeholder view for unsupported devices
        let placeholderView = UIView(frame: view.bounds)
        placeholderView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.3)
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add a label explaining the limitation
        let messageLabel = UILabel()
        messageLabel.text = "Room Capture not supported\n\nOther features are still available:\n• WiFi Analysis\n• Floor Plan View\n• Report Generation"
        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 18, weight: .medium)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add demo button
        let demoButton = UIButton(type: .system)
        demoButton.setTitle("📊 View Floor Plan Demo", for: .normal)
        demoButton.backgroundColor = SpectrumBranding.Colors.spectrumBlue
        demoButton.setTitleColor(.white, for: .normal)
        demoButton.layer.cornerRadius = 12
        demoButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        demoButton.translatesAutoresizingMaskIntoConstraints = false
        demoButton.addTarget(self, action: #selector(showFloorPlanDemo), for: .touchUpInside)
        
        placeholderView.addSubview(messageLabel)
        placeholderView.addSubview(demoButton)
        view.insertSubview(placeholderView, at: 0)
        
        // Auto-launch demo disabled by default; enable via feature flag if needed
        if false {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                print("🎯 Auto-launching Floor Plan Demo")
                self.showFloorPlanDemo()
            }
        }
        
        NSLayoutConstraint.activate([
            placeholderView.topAnchor.constraint(equalTo: view.topAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            messageLabel.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: placeholderView.centerYAnchor, constant: -60),
            messageLabel.leadingAnchor.constraint(equalTo: placeholderView.leadingAnchor, constant: 40),
            messageLabel.trailingAnchor.constraint(equalTo: placeholderView.trailingAnchor, constant: -40),
            
            demoButton.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
            demoButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 40),
            demoButton.widthAnchor.constraint(equalToConstant: 220),
            demoButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    @objc private func showFloorPlanDemo() {
        print("📊 Showing Floor Plan Demo")
        let floorPlanVC = FloorPlanViewController()
        floorPlanVC.modalPresentationStyle = .fullScreen
        present(floorPlanVC, animated: true)
    }
    
    
    private func setupARView() {
        // iOS 17+: Use shared ARSession for perfect coordinate alignment
        if isIOS17Available {
            arSceneView = ARSCNView(frame: view.bounds)
            arSceneView.session = sharedARSession  // Share the same ARSession
            print("✅ AR view configured with shared ARSession for perfect coordinate alignment")
        } else {
            arSceneView = ARSCNView(frame: view.bounds)
            print("⚠️ AR view using separate ARSession (iOS 16)")
        }
        
        arSceneView.isHidden = true
        view.insertSubview(arSceneView, at: 1)
        
        arVisualizationManager.configure(
            sceneView: arSceneView,
            wifiManager: wifiSurveyManager,
            roomAnalyzer: roomAnalyzer
        )
        
        // Setup network device management integration
        arVisualizationManager.setNetworkDeviceManager(networkDeviceManager)
        
        // Add tap gesture for router placement
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleARTap(_:)))
        arSceneView.addGestureRecognizer(tapGesture)
    }
    
    private func setupWiFiSurvey() {
        // Create buttons programmatically for now to avoid storyboard connection issues
        setupSurveyButtons()
        
        // Setup speed test progress handler
        wifiSurveyManager.speedTestProgressHandler = { [weak self] progress, message in
            DispatchQueue.main.async {
                self?.updateSpeedTestProgress(progress: progress, message: message)
            }
        }
    }
    
    private func setupSurveyButtons() {
        // Create status label
        statusLabel = SpectrumBranding.createSpectrumLabel(text: "Starting room scan...", style: .caption)
        statusLabel?.textAlignment = .center
        statusLabel?.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        statusLabel?.textColor = .white
        statusLabel?.layer.cornerRadius = 8
        statusLabel?.layer.masksToBounds = true
        
        // Create progress indicator
        progressIndicator = UIProgressView(progressViewStyle: .default)
        progressIndicator?.progressTintColor = SpectrumBranding.Colors.spectrumBlue
        progressIndicator?.trackTintColor = SpectrumBranding.Colors.spectrumSilver
        progressIndicator?.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator?.isHidden = true
        
        // Create speed test progress view
        speedTestProgressView = UIProgressView(progressViewStyle: .default)
        speedTestProgressView?.progressTintColor = SpectrumBranding.Colors.spectrumGreen
        speedTestProgressView?.trackTintColor = SpectrumBranding.Colors.spectrumSilver
        speedTestProgressView?.translatesAutoresizingMaskIntoConstraints = false
        speedTestProgressView?.isHidden = true
        
        // Create speed test label
        speedTestLabel = SpectrumBranding.createSpectrumLabel(text: "Running speed test...", style: .caption)
        // Create speed test spinner
        speedTestSpinner = UIActivityIndicatorView(style: .medium)
        speedTestSpinner?.translatesAutoresizingMaskIntoConstraints = false
        speedTestSpinner?.hidesWhenStopped = true

        speedTestLabel?.textAlignment = .center
        speedTestLabel?.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.9)
        speedTestLabel?.textColor = .white
        speedTestLabel?.layer.cornerRadius = 8
        speedTestLabel?.layer.masksToBounds = true
        speedTestLabel?.translatesAutoresizingMaskIntoConstraints = false
        speedTestLabel?.isHidden = true
        
        // Add UI elements to view
        guard let statusLabel = statusLabel,
              let progressIndicator = progressIndicator,
              let speedTestProgressView = speedTestProgressView,
              let speedTestLabel = speedTestLabel else { return }
        
        view.addSubview(statusLabel)
        view.addSubview(progressIndicator)
        view.addSubview(speedTestProgressView)
        view.addSubview(speedTestLabel)
        if let speedTestSpinner = speedTestSpinner { view.addSubview(speedTestSpinner) }
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Status label at top
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            statusLabel.heightAnchor.constraint(equalToConstant: 32),
            
            // Progress indicator below status
            progressIndicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            progressIndicator.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            progressIndicator.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            progressIndicator.heightAnchor.constraint(equalToConstant: 4),
            
            // Speed test label and progress (center of screen)
            speedTestLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            speedTestLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            speedTestLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            speedTestLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            speedTestLabel.heightAnchor.constraint(equalToConstant: 40),
            
            speedTestProgressView.topAnchor.constraint(equalTo: speedTestLabel.bottomAnchor, constant: 8),
            speedTestProgressView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 40),
            speedTestProgressView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40),
            speedTestProgressView.heightAnchor.constraint(equalToConstant: 6)
        ])

        if let spinner = speedTestSpinner {
            NSLayoutConstraint.activate([
                spinner.trailingAnchor.constraint(equalTo: speedTestLabel.leadingAnchor, constant: -8),
                spinner.centerYAnchor.constraint(equalTo: speedTestLabel.centerYAnchor)
            ])
        }
    }
    
    private func setupBottomNavigation() {
        // Create mode label in top-left corner
        modeLabel = SpectrumBranding.createSpectrumLabel(text: "Room Scanning Mode", style: .caption)
        modeLabel?.textAlignment = .left
        modeLabel?.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        modeLabel?.textColor = .white
        modeLabel?.layer.cornerRadius = 8
        modeLabel?.layer.masksToBounds = true
        modeLabel?.translatesAutoresizingMaskIntoConstraints = false
        
        // Bottom toolbar layout
        let toolbar = UIStackView()
        toolbar.axis = .horizontal
        toolbar.alignment = .fill
        toolbar.distribution = .fillEqually
        toolbar.spacing = 12
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        // Create scan/survey toggle button
        scanSurveyToggleButton = UIButton(type: .system)
        scanSurveyToggleButton?.setTitle("📡 Switch to WiFi Survey", for: .normal)
        scanSurveyToggleButton?.setTitleColor(.white, for: .normal)
        scanSurveyToggleButton?.titleLabel?.font = UIFont.boldSystemFont(ofSize: 15)
        scanSurveyToggleButton?.backgroundColor = SpectrumBranding.Colors.spectrumGreen
        scanSurveyToggleButton?.addTarget(self, action: #selector(scanSurveyToggleTapped), for: .touchUpInside)
        scanSurveyToggleButton?.translatesAutoresizingMaskIntoConstraints = false
        scanSurveyToggleButton?.layer.cornerRadius = 8
        scanSurveyToggleButton?.titleLabel?.adjustsFontSizeToFitWidth = true
        scanSurveyToggleButton?.titleLabel?.minimumScaleFactor = 0.8
        
        // Create floor plan button
        floorPlanNavButton = UIButton(type: .system)
        floorPlanNavButton?.setTitle("📊 View Plan", for: .normal)
        floorPlanNavButton?.setTitleColor(.white, for: .normal)
        floorPlanNavButton?.titleLabel?.font = UIFont.boldSystemFont(ofSize: 15)
        floorPlanNavButton?.backgroundColor = SpectrumBranding.Colors.spectrumBlue
        floorPlanNavButton?.addTarget(self, action: #selector(floorPlanNavTapped), for: .touchUpInside)
        floorPlanNavButton?.translatesAutoresizingMaskIntoConstraints = false
        floorPlanNavButton?.layer.cornerRadius = 8
        
        // Create router placement button
        routerPlacementButton = UIButton(type: .system)
        routerPlacementButton?.setTitle("📡 Place Router", for: .normal)
        routerPlacementButton?.setTitleColor(.white, for: .normal)
        routerPlacementButton?.titleLabel?.font = UIFont.boldSystemFont(ofSize: 15)
        routerPlacementButton?.backgroundColor = SpectrumBranding.Colors.spectrumRed
        routerPlacementButton?.addTarget(self, action: #selector(routerPlacementTapped), for: .touchUpInside)
        routerPlacementButton?.translatesAutoresizingMaskIntoConstraints = false
        routerPlacementButton?.layer.cornerRadius = 8
        routerPlacementButton?.isHidden = true // Initially hidden
        
        guard let modeLabel = modeLabel,
              let scanSurveyToggleButton = scanSurveyToggleButton,
              let floorPlanNavButton = floorPlanNavButton,
              let routerPlacementButton = routerPlacementButton else { return }

        view.addSubview(modeLabel)
        view.addSubview(toolbar)
        toolbar.addArrangedSubview(scanSurveyToggleButton)
        toolbar.addArrangedSubview(routerPlacementButton)
        toolbar.addArrangedSubview(floorPlanNavButton)
        
        NSLayoutConstraint.activate([
            // Mode label in top-left corner
            modeLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80), // Below status label
            modeLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            modeLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            modeLabel.heightAnchor.constraint(equalToConstant: 32),
            
            // Bottom toolbar
            toolbar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            toolbar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            toolbar.heightAnchor.constraint(equalToConstant: 48)
        ])
        
        updateBottomNavigation()
    }
    
    private func setupPlumeControls() {
        // Create container for Plume controls
        plumeControlsContainer = UIView()
        plumeControlsContainer?.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        plumeControlsContainer?.layer.cornerRadius = 12
        plumeControlsContainer?.layer.masksToBounds = true
        plumeControlsContainer?.translatesAutoresizingMaskIntoConstraints = false
        
        // Create Plume toggle button
        plumeToggleButton = UIButton(type: .system)
        plumeToggleButton?.setTitle("🔌 Enable Plume", for: .normal)
        plumeToggleButton?.setTitleColor(.white, for: .normal)
        plumeToggleButton?.titleLabel?.font = UIFont.boldSystemFont(ofSize: 14)
        plumeToggleButton?.backgroundColor = SpectrumBranding.Colors.spectrumBlue
        plumeToggleButton?.addTarget(self, action: #selector(plumeToggleTapped), for: .touchUpInside)
        plumeToggleButton?.translatesAutoresizingMaskIntoConstraints = false
        plumeToggleButton?.layer.cornerRadius = 6
        
        // Create export data button
        exportDataButton = UIButton(type: .system)
        exportDataButton?.setTitle("📤 Export Data", for: .normal)
        exportDataButton?.setTitleColor(.white, for: .normal)
        exportDataButton?.titleLabel?.font = UIFont.boldSystemFont(ofSize: 14)
        exportDataButton?.backgroundColor = SpectrumBranding.Colors.spectrumGreen
        exportDataButton?.addTarget(self, action: #selector(exportDataTapped), for: .touchUpInside)
        exportDataButton?.translatesAutoresizingMaskIntoConstraints = false
        exportDataButton?.layer.cornerRadius = 6
        
        // Create Plume status label
        plumeStatusLabel = UILabel()
        plumeStatusLabel?.text = "Plume: Initializing..."
        plumeStatusLabel?.textColor = .white
        plumeStatusLabel?.font = UIFont.systemFont(ofSize: 11)
        plumeStatusLabel?.textAlignment = .center
        plumeStatusLabel?.translatesAutoresizingMaskIntoConstraints = false
        
        // Add network data status (no toggle needed - auto-enabled)
        let networkStatusLabel = UILabel()
        networkStatusLabel.text = "📱 Network Data: Active"
        networkStatusLabel.textColor = .white
        networkStatusLabel.font = UIFont.systemFont(ofSize: 11)
        networkStatusLabel.textAlignment = .center
        networkStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        guard let container = plumeControlsContainer,
              let toggleButton = plumeToggleButton,
              let exportButton = exportDataButton,
              let statusLabel = plumeStatusLabel else { return }
        
        container.addSubview(toggleButton)
        container.addSubview(exportButton)
        container.addSubview(statusLabel)
        container.addSubview(networkStatusLabel)
        view.addSubview(container)
        
        NSLayoutConstraint.activate([
            // Container in top-right corner
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            container.widthAnchor.constraint(equalToConstant: 160),
            container.heightAnchor.constraint(equalToConstant: 120),
            
            // Plume toggle button
            toggleButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            toggleButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            toggleButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            toggleButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Export button
            exportButton.topAnchor.constraint(equalTo: toggleButton.bottomAnchor, constant: 4),
            exportButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            exportButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            exportButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Plume status label
            statusLabel.topAnchor.constraint(equalTo: exportButton.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            statusLabel.heightAnchor.constraint(equalToConstant: 16),
            
            // Network status label
            networkStatusLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 2),
            networkStatusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            networkStatusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            networkStatusLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        
        // Update Plume status periodically
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updatePlumeStatus()
        }
    }
    
    @objc private func plumeToggleTapped() {
        let currentlyEnabled = wifiSurveyManager.isPlumeEnabled
        wifiSurveyManager.enablePlumeIntegration(!currentlyEnabled)
        
        let newTitle = wifiSurveyManager.isPlumeEnabled ? "🔌 Disable Plume" : "🔌 Enable Plume"
        plumeToggleButton?.setTitle(newTitle, for: .normal)
        
        updatePlumeStatus()
        
        print("🔌 Plume integration toggled: \(wifiSurveyManager.isPlumeEnabled)")
    }
    
    @objc private func exportDataTapped() {
        guard wifiSurveyManager.measurements.count > 0 else {
            showAlert(title: "No Data", message: "No measurements available to export. Please complete a WiFi survey first.")
            return
        }
        
        // Export data with room information if available
        let exportURL = wifiSurveyManager.exportMeasurementData(roomAnalyzer: roomAnalyzer)
        
        if let url = exportURL {
            // Show share sheet
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activityVC.popoverPresentationController?.sourceView = exportDataButton
            present(activityVC, animated: true)
            
            let networkDataCount = wifiSurveyManager.networkDataCollector?.getCollectedData().count ?? 0
            showAlert(title: "Export Complete", 
                     message: "Survey data exported successfully!\n\nFile: \(url.lastPathComponent)\n\nMeasurements: \(wifiSurveyManager.measurements.count)\nNetwork data points: \(networkDataCount)\nPlume enabled: \(wifiSurveyManager.isPlumeEnabled)")
        } else {
            showAlert(title: "Export Failed", message: "Failed to export survey data. Please try again.")
        }
    }
    
    private func updatePlumeStatus() {
        if wifiSurveyManager.isPlumeEnabled {
            let correlationStatus = wifiSurveyManager.getPlumeCorrelationStatus()
            let steeringStatus = wifiSurveyManager.plumeSteeringActive ? " 🎯" : ""
            plumeStatusLabel?.text = "Plume: \(correlationStatus)\(steeringStatus)"
        } else {
            plumeStatusLabel?.text = "Plume: Disabled"
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    @objc private func scanSurveyToggleTapped() {
        switch currentMode {
        case .scanning:
            if isScanning {
                // Switch from scanning to surveying
                switchToWiFiSurvey()
            } else {
                // Start scanning
                startSession()
            }
            
        case .surveying:
            if wifiSurveyManager.isRecording {
                // Stop WiFi survey and return to scanning
                switchBackToScanning()
            } else {
                // Resume WiFi survey
                resumeWiFiSurvey()
            }
            
        case .completed:
            // Restart the entire session from the beginning
            restartCompleteSession()
        }
        
        updateBottomNavigation()
    }
    
    @objc private func floorPlanNavTapped() {
        // Only allow floor plan access after both room scan and WiFi survey are completed
        let hasRoomData = capturedRoomData != nil || roomPlanPaused
        let hasWifiData = !wifiSurveyManager.measurements.isEmpty
        
        if hasRoomData && hasWifiData {
            viewResults()
        } else if !hasRoomData {
            showAlert(title: "Room Scan Required", message: "Please complete room scanning first, then WiFi survey to view results.")
        } else if !hasWifiData {
            showAlert(title: "WiFi Survey Required", message: "Please complete WiFi survey after room scanning to view results.")
        }
    }
    
    @objc private func routerPlacementTapped() {
        if networkDeviceManager.isRouterPlacementMode {
            // Cancel placement mode
            networkDeviceManager.disableRouterPlacementMode()
            routerPlacementButton?.setTitle("📡 Place Router", for: .normal)
            routerPlacementButton?.backgroundColor = SpectrumBranding.Colors.spectrumRed
            routerPlacementButton?.setTitleColor(.white, for: .normal)
        } else {
            // Enter placement mode
            guard isARMode else {
                showAlert(title: "AR Mode Required", message: "Switch to WiFi Survey mode to place router in AR.")
                return
            }
            
            networkDeviceManager.enableRouterPlacementMode()
            routerPlacementButton?.setTitle("❌ Cancel", for: .normal)
            routerPlacementButton?.backgroundColor = UIColor.systemGray
            routerPlacementButton?.setTitleColor(.white, for: .normal)
            
            // Show instruction message
            statusLabel?.text = "📡 Tap anywhere in AR to place router"
            statusLabel?.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
        }
    }
    
    @objc private func handleARTap(_ gesture: UITapGestureRecognizer) {
        guard networkDeviceManager.isRouterPlacementMode else { return }
        
        let location = gesture.location(in: arSceneView)
        
        // Perform raycast to find a surface
        guard let query = arSceneView.raycastQuery(from: location, allowing: .existingPlaneGeometry, alignment: .horizontal) else { return }
        let raycastResults = arSceneView.session.raycast(query)
        
        if let raycastResult = raycastResults.first {
            let position = raycastResult.worldTransform.columns.3
            let routerPosition = simd_float3(position.x, position.y, position.z)
            
            // Handle router placement through AR visualization manager
            if arVisualizationManager.handleDeviceTap(at: routerPosition) {
                // Router was placed successfully
                routerPlacementButton?.setTitle("📡 Place Router", for: .normal)
                routerPlacementButton?.backgroundColor = SpectrumBranding.Colors.spectrumRed
                
                // Update AR visualization with the router
                if let router = networkDeviceManager.router {
                    arVisualizationManager.addNetworkDevice(router)
                }
                
                // Trigger extender placement after router is placed
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.placeExtenderOnBestSurface()
                }
                
                updateBottomNavigation()
            }
        }
    }
    
    private func placeExtenderOnBestSurface() {
        guard networkDeviceManager.router != nil else { return }
        
        // Place extender on best available surface
        if let extender = networkDeviceManager.placeExtenderOnBestSurface() {
            arVisualizationManager.addNetworkDevice(extender)
            print("📶 Extender automatically placed on suitable surface")
            
            // Show success message
            statusLabel?.text = "✅ Router and extender placed! Network optimized."
            statusLabel?.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
        } else {
            // No suitable surfaces found
            statusLabel?.text = "⚠️ Router placed, but no suitable surfaces found for extender"
            statusLabel?.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.9)
        }
    }
    
    private func switchToWiFiSurvey() {
        guard isScanning else { return }
        
        print("🔄 Switching from room scanning to WiFi survey...")
        
        // iOS 17+: Use advanced coordinate alignment with shared ARSession
        // Stop RoomPlan but keep ARSession running for perfect coordinate alignment
        roomCaptureView?.captureSession.stop(pauseARSession: false)
        print("🎯 RoomPlan stopped with ARSession maintained for coordinate continuity")
        
        // Store the current room data as additional coordinate reference
        if let capturedRoom = capturedRoomData {
            print("📍 Using captured room data as coordinate reference")
            arVisualizationManager.setCapturedRoomData(capturedRoom)
        }
        
        roomPlanPaused = true
        
        // Switch to surveying mode
        currentMode = .surveying
        isScanning = false
        
        // Start WiFi survey
        startWiFiSurveyWithinRoomPlan()
        
        statusLabel?.text = "📡 WiFi survey mode - Perfect coordinate alignment active"
        print("✅ Successfully switched to WiFi survey mode")
    }
    
    private func switchBackToScanning() {
        print("🔄 Switching back to room scanning with coordinate preservation...")
        
        // Stop WiFi survey but preserve coordinate system
        wifiSurveyManager.stopSurvey()
        
        // Disable shared session mode when returning to scanning
        arVisualizationManager.setSharedARSessionMode(false)
        
        // iOS 17+: Don't stop the shared ARSession to maintain coordinates
        if isIOS17Available {
            print("🎯 Preserving shared ARSession for coordinate continuity")
            // ARSession remains active, perfect for resuming room scanning
        } else {
            // iOS 16: Stop AR session
            arVisualizationManager.stopARSession()
        }
        
        // Check if we should complete or continue scanning
        let hasRoomData = capturedRoomData != nil
        let hasWifiData = !wifiSurveyManager.measurements.isEmpty
        
        if hasRoomData && hasWifiData {
            // Both data collected - but user decides when to view results
            print("📊 Room scan and WiFi survey data collected - awaiting user action")
        } else if hasRoomData {
            // Room scanning already complete, show room view but don't mark as completed
            switchToRoomCapture()
            print("✅ Room scan complete, WiFi data available - awaiting user action")
        } else {
            // Resume room scanning with same coordinate system
            roomPlanPaused = false
            currentMode = .scanning
            
            // Switch back to room capture view
            switchToRoomCapture()
            
            // Resume scanning with coordinate continuity
            if isIOS17Available {
                // iOS 17+: Resume with same ARSession for perfect coordinate alignment
                roomCaptureView?.captureSession.run(configuration: roomCaptureSessionConfig)
                isScanning = true
                statusLabel?.text = "📱 Room scanning resumed - Same coordinate system maintained"
                print("✅ Room scanning resumed with coordinate continuity")
            } else {
                // iOS 16: Restart session
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startSession()
                }
                statusLabel?.text = "Restarting room scan - Move around to capture room"
                print("✅ Restarting room scanning session")
            }
        }
    }
    
    private func restartCompleteSession() {
        print("🔄 Restarting complete session - clearing all data...")
        
        // Stop any active sessions
        stopSession()
        
        // Clear all data
        capturedRoomData = nil
        finalResults = nil
        currentMode = .scanning
        isScanning = false
        
        // Clear WiFi survey data
        wifiSurveyManager.clearMeasurementData()
        
        // Clear AR visualization
        arVisualizationManager.clearAllVisualizations()
        
        // Clear network device data
        networkDeviceManager.clearAllDevices()
        
        // Clear any room analysis
        roomAnalyzer.identifiedRooms.removeAll()
        
        // Reset status
        statusLabel?.text = "📱 Ready to scan room - Tap to start"
        statusLabel?.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
        
        // Update UI
        updateBottomNavigation()
        
        print("✅ Complete session restart - ready for new scan")
    }
    
    private func resumeWiFiSurvey() {
        print("▶️ Resuming WiFi survey...")
        startWiFiSurveyWithinRoomPlan()
    }
    
    private func startWiFiSurveyWithinRoomPlan() {
        // Clear any existing test point markers from previous survey
        arVisualizationManager.clearTestPointMarkers()
        
        // Start WiFi survey 
        wifiSurveyManager.startSurvey()
        
        // iOS 17+: Set shared session mode BEFORE switching to AR mode to preserve coordinates
        if isIOS17Available {
            print("🎯 Enabling shared ARSession mode for perfect coordinate alignment")
            arVisualizationManager.setSharedARSessionMode(true)
        } else {
            // iOS 16: Disable shared session mode
            arVisualizationManager.setSharedARSessionMode(false)
            print("⚠️ Using separate ARSession (iOS 16)")
        }
        
        // Add async dispatch to prevent UI freezing during AR mode switch
        DispatchQueue.main.async {
            // Switch to AR mode for WiFi visualization (this will respect shared session mode)
            self.switchToARMode()
            
            // If we have room data, use it for additional reference
            if let capturedRoom = self.capturedRoomData {
                print("📍 Using captured room data as additional coordinate reference")
                self.arVisualizationManager.setCapturedRoomData(capturedRoom)
            }
            
            self.statusLabel?.text = "📡 WiFi survey active - Perfect coordinate alignment"
        }
    }
    
    private func updateBottomNavigation() {
        // Update mode label and buttons based on current state
        switch currentMode {
        case .scanning:
            if isScanning {
                modeLabel?.text = "🔍 Room Scanning Active"
                modeLabel?.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
                scanSurveyToggleButton?.setTitle("📡 Switch to WiFi Survey", for: .normal)
                scanSurveyToggleButton?.backgroundColor = SpectrumBranding.Colors.spectrumGreen
                scanSurveyToggleButton?.setTitleColor(.white, for: .normal)
                scanSurveyToggleButton?.isEnabled = true
            } else {
                modeLabel?.text = "📱 Ready to Scan Room"
                modeLabel?.backgroundColor = UIColor.systemGray.withAlphaComponent(0.9)
                scanSurveyToggleButton?.setTitle("📱 Start Room Scan", for: .normal)
                scanSurveyToggleButton?.backgroundColor = SpectrumBranding.Colors.spectrumBlue
                scanSurveyToggleButton?.setTitleColor(.white, for: .normal)
                scanSurveyToggleButton?.isEnabled = true
            }
            
        case .surveying:
            if wifiSurveyManager.isRecording {
                modeLabel?.text = "📡 WiFi Survey Active (\(wifiSurveyManager.measurements.count) points)"
                modeLabel?.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.9)
                scanSurveyToggleButton?.setTitle("📱 Back to Room Scan", for: .normal)
                scanSurveyToggleButton?.backgroundColor = SpectrumBranding.Colors.spectrumBlue
                scanSurveyToggleButton?.setTitleColor(.white, for: .normal)
                scanSurveyToggleButton?.isEnabled = true
            } else {
                modeLabel?.text = "📡 WiFi Survey Ready"
                modeLabel?.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
                scanSurveyToggleButton?.setTitle("📡 Resume WiFi Survey", for: .normal)
                scanSurveyToggleButton?.backgroundColor = SpectrumBranding.Colors.spectrumGreen
                scanSurveyToggleButton?.setTitleColor(.white, for: .normal)
                scanSurveyToggleButton?.isEnabled = true
            }
            
        case .completed:
            modeLabel?.text = "📊 Ready for Results"
            modeLabel?.backgroundColor = UIColor.systemPurple.withAlphaComponent(0.9)
            scanSurveyToggleButton?.setTitle("🔄 Restart", for: .normal)
            scanSurveyToggleButton?.backgroundColor = UIColor.systemGray
            scanSurveyToggleButton?.setTitleColor(.white, for: .normal)
            scanSurveyToggleButton?.isEnabled = true
        }
        
        // Floor Plan button - only show after survey mode has been opened at least once
        let hasRoomData = capturedRoomData != nil || roomPlanPaused
        let hasWifiData = !wifiSurveyManager.measurements.isEmpty
        let hasSurveyBeenOpened = currentMode == .surveying || currentMode == .completed || hasWifiData
        
        if hasRoomData && hasSurveyBeenOpened {
            // Room scan completed and survey opened - show Results button
            if hasWifiData {
                floorPlanNavButton?.setTitle("📊 Results", for: .normal)
            } else {
                floorPlanNavButton?.setTitle("📊 Floor Plan", for: .normal)
            }
            floorPlanNavButton?.backgroundColor = SpectrumBranding.Colors.spectrumBlue
            floorPlanNavButton?.setTitleColor(.white, for: .normal)
            floorPlanNavButton?.isEnabled = true
            floorPlanNavButton?.isHidden = false
        } else {
            // Hide button until survey mode is opened
            floorPlanNavButton?.isHidden = true
        }
        
        // Router placement button - show in AR/surveying mode when room data exists
        let showRouterButton = isARMode && hasRoomData && !networkDeviceManager.suitableSurfaces.isEmpty
        routerPlacementButton?.isHidden = !showRouterButton
        
        // Update button text based on placement status
        if networkDeviceManager.router != nil {
            routerPlacementButton?.setTitle("📡 Router Placed", for: .normal)
            routerPlacementButton?.backgroundColor = SpectrumBranding.Colors.spectrumGreen
            routerPlacementButton?.setTitleColor(.white, for: .normal)
            routerPlacementButton?.isEnabled = false
        } else if networkDeviceManager.isRouterPlacementMode {
            routerPlacementButton?.setTitle("❌ Cancel", for: .normal)
            routerPlacementButton?.backgroundColor = UIColor.systemGray
            routerPlacementButton?.setTitleColor(.white, for: .normal)
            routerPlacementButton?.isEnabled = true
        } else {
            routerPlacementButton?.setTitle("📡 Place Router", for: .normal)
            routerPlacementButton?.backgroundColor = SpectrumBranding.Colors.spectrumRed
            routerPlacementButton?.setTitleColor(.white, for: .normal)
            routerPlacementButton?.isEnabled = true
        }
    }
    
    private func updateButtonStates() {
        print("🔄 Updating button states - isScanning: \(isScanning), capturedRoomData: \(capturedRoomData != nil), wifiRecording: \(wifiSurveyManager.isRecording), measurements: \(wifiSurveyManager.measurements.count)")
        
        // Update status label
        updateStatusLabel()
        
        // Update progress indicator
        updateProgressIndicator()
        
        // Update bottom navigation
        updateBottomNavigation()
    }
    
    private func updateStatusLabel() {
        var statusText = "Ready to start scanning"
        var backgroundColor = UIColor.black.withAlphaComponent(0.7)
        
        switch currentMode {
        case .scanning:
            if isScanning {
                statusText = "📱 Move around to capture room - Tap 'Switch to WiFi Survey' when ready"
                backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
            } else if capturedRoomData == nil && !roomPlanPaused {
                statusText = "🎯 Tap 'Start Room Scan' to begin mapping your space"
                backgroundColor = UIColor.systemGray.withAlphaComponent(0.9)
            } else {
                statusText = "✅ Room scan paused - Use toggle to switch modes"
                backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
            }
            
        case .surveying:
            if wifiSurveyManager.isRecording {
                let roomCount = roomAnalyzer.identifiedRooms.count
                let roomText = roomCount > 0 ? " across \(roomCount) rooms" : ""
                statusText = "📡 Recording WiFi (\(wifiSurveyManager.measurements.count) points\(roomText)) - Walk to test coverage"
                backgroundColor = UIColor.systemOrange.withAlphaComponent(0.9)
            } else {
                statusText = "📡 WiFi survey ready - Move around to collect signal data"
                backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
            }
            
        case .completed:
            // Never show automatic completion - user must explicitly decide when ready
            statusText = "📊 Data available - Use 'Results' button when you're ready to view analysis"
            backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
        }
        
        statusLabel?.text = statusText
        statusLabel?.backgroundColor = backgroundColor
    }
    
    private func updateProgressIndicator() {
        let hasRoomData = capturedRoomData != nil
        let hasMeasurements = !wifiSurveyManager.measurements.isEmpty
        
        if !hasRoomData {
            progressIndicator?.progress = 0.0
            progressIndicator?.isHidden = !isScanning
        } else if !hasMeasurements {
            progressIndicator?.progress = 0.5
            progressIndicator?.isHidden = false
        } else {
            progressIndicator?.progress = 1.0
            progressIndicator?.isHidden = false
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        print("🎬 RoomCaptureViewController viewDidAppear - starting preview")
        
        // Ensure the room capture view is properly configured
        setupRoomCaptureViewIfNeeded()
        
        // Start the camera preview (but not scanning) so user can see the feed
        startCameraPreview()
        
        // Auto-start scanning immediately since we bypassed the instruction screen
        if !isScanning && capturedRoomData == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("🚀 Auto-starting room scan...")
                self.startSession()
            }
        }
        
        updateButtonStates()
    }
    
    private func setupRoomCaptureViewIfNeeded() {
        guard roomCaptureView == nil else { return }
        
        print("⚠️ RoomCaptureView was nil, recreating...")
        setupRoomCaptureView()
    }
    
    private func startCameraPreview() {
        guard let roomCaptureView = roomCaptureView else {
            print("❌ Cannot start camera preview: roomCaptureView is nil")
            return
        }
        
        if !isScanning {
            print("📹 Starting camera preview...")
            roomCaptureView.captureSession.run(configuration: roomCaptureSessionConfig)
        } else {
            print("📹 Already scanning, camera should be active")
        }
    }
    
    override func viewWillDisappear(_ flag: Bool) {
        super.viewWillDisappear(flag)
        stopSession()
        
        // Ensure all timers are stopped
        stopTrackingStateMonitoring()
        stopStatusUpdateTimer()
        stopScanningProgressHaptics()
        
        // Clean up haptic generators to free memory
        cleanupHapticGenerators()
    }
    
    deinit {
        // Final cleanup to ensure no memory leaks
        print("🧹 RoomCaptureViewController deallocating - performing final cleanup")
        cleanupHapticGenerators()
        stopTrackingStateMonitoring()
        stopStatusUpdateTimer()
        stopScanningProgressHaptics()
        
        // Clean up measurement data to prevent memory leaks
        wifiSurveyManager.clearMeasurementData()
    }
    
    private func startSession() {
        
        guard RoomCaptureSession.isSupported else {
            print("❌ Cannot start session: RoomCaptureSession not supported")
            // Don't show alert - just log and return
            return
        }
        
        guard let roomCaptureView = roomCaptureView else {
            print("❌ Cannot start session: roomCaptureView is nil")
            return
        }
        
        print("🚀 Starting room capture session...")
        
        isScanning = true
        
        // Configure and start the session
        roomCaptureView.captureSession.run(configuration: roomCaptureSessionConfig)
        print("✅ Room capture session started successfully")
        
        // Start monitoring WiFi network info during room scanning
        startWiFiMonitoring()
        
        // Start tracking state monitoring for better user experience
        startTrackingStateMonitoring()
        
        // Start periodic scanning progress haptics
        startScanningProgressHaptics()
        
        setActiveNavBar()
        updateButtonStates()
    }
    
    
    
    
    
    private func stopSession() {
        print("🛑 Stopping room capture session...")
        isScanning = false
        
        roomCaptureView?.captureSession.stop()
        stopTrackingStateMonitoring()
        
        stopWiFiMonitoring()
        
        // Stop scanning progress haptics
        stopScanningProgressHaptics()
        
        setCompleteNavBar()
        updateButtonStates()
        
        print("✅ Room capture session stopped")
    }
    
    private func startWiFiMonitoring() {
        // Start basic WiFi network monitoring during room scan
        // Minimal logging using collector (if available)
        let name = wifiSurveyManager.currentNetworkName
        if !name.isEmpty { print("📶 Connected to WiFi: \(name)") }
    }
    
    private func stopWiFiMonitoring() {
        // Stop any ongoing WiFi monitoring
    }
    
    // Decide to post-process and show the final results.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return true
    }
    
    // Access the final post-processed results.
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        finalResults = processedResult
        capturedRoomData = processedResult
        
        print("🏠 Room capture completed - processing room data...")
        
        // Trigger major discovery haptic for room completion
        triggerMajorDiscoveryHaptic()
        
        // Trigger object detection haptics for discovered furniture
        let objectCount = processedResult.objects.count
        if objectCount > 0 {
            print("📦 Discovered \(objectCount) objects - triggering object haptics")
            
            // Stagger haptic feedback for multiple objects to create scanning sensation
            for i in 0..<min(objectCount, 5) { // Limit to first 5 objects to avoid overwhelming
                DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(i) * 0.2) {
                    self.triggerObjectDetectionHaptic()
                }
            }
        }
        
        roomAnalyzer.analyzeCapturedRoom(processedResult)
        
        // Analyze suitable surfaces for network device placement
        networkDeviceManager.analyzeSuitableSurfaces(from: roomAnalyzer.furnitureItems)
        
        // Pass room data to AR visualization manager
        arVisualizationManager.setCapturedRoomData(processedResult)
        
        // Perform accuracy validation after room analysis
        // performAccuracyValidation(capturedRoom: processedResult) // Disabled for build compatibility
        
        // Check if both room and WiFi data exist (but don't auto-complete)
        if !wifiSurveyManager.measurements.isEmpty {
            print("✅ Both room scan and WiFi survey data available - user can view results when ready")
        }
        
        updateButtonStates()
    }
    
    // Removed Done/Cancel actions - using bottom navigation instead
    
    // Legacy methods - replaced by unified scan/survey workflow
    private func startWiFiSurvey() {
        // This method is now handled by switchToWiFiSurvey()
        // Keeping for compatibility but redirecting to new workflow
        switchToWiFiSurvey()
    }
    
    private func stopWiFiSurvey() {
        // This method is now handled by switchBackToScanning()
        // Keeping for compatibility but redirecting to new workflow
        switchBackToScanning()
    }
    
    private func isNetworkAvailable() -> Bool {
        // Simple network check - in a real app you'd use NWPathMonitor
        return true // For now, assume network is available
    }
    
    private var statusUpdateTimer: Timer?
    
    private func startStatusUpdateTimer() {
        statusUpdateTimer?.invalidate()
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusLabel()
            }
        }
    }
    
    private func stopStatusUpdateTimer() {
        statusUpdateTimer?.invalidate()
        statusUpdateTimer = nil
    }
    
    private func updateSpeedTestProgress(progress: Float, message: String) {
        if progress > 0 && !message.isEmpty {
            // Show speed test UI
            speedTestLabel?.text = "📊 \(message)"
            speedTestLabel?.isHidden = false
            speedTestProgressView?.isHidden = false
            speedTestProgressView?.progress = progress
            
            // Make the speed test more visible by temporarily changing status
            if wifiSurveyManager.isRecording {
                statusLabel?.text = "📊 \(message) - \(wifiSurveyManager.measurements.count) measurements"
                statusLabel?.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.9)
            }
        } else {
            // Hide speed test UI
            speedTestLabel?.isHidden = true
            speedTestProgressView?.isHidden = true
            
            // Restore normal status
            if wifiSurveyManager.isRecording {
                updateStatusLabel()
            }
        }
    }
    
    
    @objc private func viewResults() {
        // User has explicitly chosen to view results - now we can set completed mode
        currentMode = .completed
        print("📊 User requested results view - setting completed mode")
        
        // In simulator mode, allow viewing results with mock data even without captured room data
        
        guard capturedRoomData != nil else {
            currentMode = .scanning // Reset if no data
            showAlert(title: "No Room Data", message: "Please complete room scanning first.")
            return
        }
        
        let hasWifiData = !wifiSurveyManager.measurements.isEmpty
        
        if hasWifiData {
            print("📊 Generating results for \(wifiSurveyManager.measurements.count) measurements...")
            
            // Show loading indicator
            statusLabel?.text = "Generating analysis results..."
            
            // Generate heatmap data in background to prevent UI freezing
            DispatchQueue.global(qos: .userInitiated).async {
                let heatmapData = self.wifiSurveyManager.generateHeatmapData()
                
                DispatchQueue.main.async {
                    print("✅ Results generated, navigating to floor plan...")
                    
                    let floorPlanVC = FloorPlanViewController()
                    floorPlanVC.updateWithData(heatmapData: heatmapData, roomAnalyzer: self.roomAnalyzer, networkDeviceManager: self.networkDeviceManager, validationResults: nil)
                    floorPlanVC.modalPresentationStyle = .fullScreen
                    self.present(floorPlanVC, animated: true)
                    
                    // Reset status
                    self.statusLabel?.text = "Analysis complete"
                }
            }
        } else {
            print("📊 Showing floor plan without WiFi data...")
            
            // Show basic floor plan without WiFi heatmap
            statusLabel?.text = "Loading floor plan..."
            
            DispatchQueue.main.async {
                let floorPlanVC = FloorPlanViewController()
                // Create empty heatmap data for basic floor plan view
                let emptyHeatmapData = WiFiHeatmapData(
                    measurements: [],
                    coverageMap: [:],
                    optimalRouterPlacements: []
                )
                floorPlanVC.updateWithData(heatmapData: emptyHeatmapData, roomAnalyzer: self.roomAnalyzer, networkDeviceManager: self.networkDeviceManager, validationResults: nil)
                floorPlanVC.modalPresentationStyle = .fullScreen
                self.present(floorPlanVC, animated: true)
                
                // Reset status
                self.statusLabel?.text = "Floor plan loaded"
            }
        }
    }
    
    
    private func switchToARMode() {
        isARMode = true
        roomCaptureView.isHidden = true
        arSceneView.isHidden = false
        
        // Start AR session when switching to AR mode
        // (ARVisualizationManager will handle shared session mode appropriately)
        arVisualizationManager.startARSession()
        
        updateButtonStates()
    }
    
    private func switchToRoomCapture() {
        isARMode = false
        roomCaptureView.isHidden = false
        arSceneView.isHidden = true
        updateButtonStates()
    }
    
    private func showAlert(title: String, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        if let completion = completion {
            alert.addAction(UIAlertAction(title: "Yes", style: .default) { _ in
                completion()
            })
            alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
        } else {
            alert.addAction(UIAlertAction(title: "OK", style: .default))
        }
        
        present(alert, animated: true)
    }

    // Removed cancel action - navigation handled by bottom nav
    
    // Export the USDZ output by specifying the `.parametric` export option.
    // Alternatively, `.mesh` exports a nonparametric file and `.all`
    // exports both in a single USDZ.
    @IBAction func exportResults(_ sender: UIButton) {
        print("📊 Export Results button tapped - showing WiFi analysis results...")
        
        // Check if we have WiFi measurements
        if wifiSurveyManager.measurements.count > 0 {
            print("📊 Found \(wifiSurveyManager.measurements.count) WiFi measurements")
            showAnalysisResults()
        } else if roomAnalyzer.identifiedRooms.count > 0 {
            print("📊 No WiFi measurements found, showing basic floor plan...")
            // Show basic floor plan without WiFi data
            let floorPlanVC = FloorPlanViewController()
            let emptyHeatmapData = WiFiHeatmapData(
                measurements: [],
                coverageMap: [:],
                optimalRouterPlacements: []
            )
            floorPlanVC.updateWithData(heatmapData: emptyHeatmapData, roomAnalyzer: roomAnalyzer, networkDeviceManager: networkDeviceManager)
            floorPlanVC.modalPresentationStyle = .fullScreen
            present(floorPlanVC, animated: true)
        } else {
            print("⚠️ No room data available to show results")
            let alert = UIAlertController(title: "No Data", message: "Please complete a room scan first", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
    
    private func showAnalysisResults() {
        print("📊 Showing WiFi analysis results...")
        
        // Generate heatmap data from measurements
        let heatmapData = WiFiHeatmapData(
            measurements: wifiSurveyManager.measurements,
            coverageMap: [:], // Could be calculated if needed
            optimalRouterPlacements: [] // Could be calculated if needed
        )
        
        // Present the floor plan view controller
        let floorPlanVC = FloorPlanViewController()
        floorPlanVC.updateWithData(
            heatmapData: heatmapData,
            roomAnalyzer: roomAnalyzer,
            networkDeviceManager: networkDeviceManager
        )
        floorPlanVC.modalPresentationStyle = .fullScreen
        present(floorPlanVC, animated: true)
    }
    
    private func setActiveNavBar() {
        UIView.animate(withDuration: 1.0, animations: {
            self.exportButton?.alpha = 0.0
        }, completion: { complete in
            self.exportButton?.isHidden = true
        })
    }
    
    private func setCompleteNavBar() {
        self.exportButton?.isHidden = false
        UIView.animate(withDuration: 1.0) {
            self.exportButton?.alpha = 1.0
        }
    }
    
    // MARK: - Accuracy Validation
    
    /*
    private func performAccuracyValidation(capturedRoom: CapturedRoom) {
        print("🎯 Performing room accuracy validation...")
        
        // Run validation in background to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            let validationResults = self.roomAccuracyValidator.validateRoomAccuracy(
                capturedRoom: capturedRoom,
                roomAnalyzer: self.roomAnalyzer
            )
            
            DispatchQueue.main.async {
                self.handleValidationResults(validationResults)
            }
        }
    }
    */
    
    // MARK: - Room Accuracy Validation (Disabled for Build Compatibility)
    /*
    private func handleValidationResults(_ results: RoomAccuracyValidator.ValidationResults) {
        print("📊 Accuracy validation completed:")
        print("   Overall accuracy: \(String(format: "%.1f", results.overallAccuracyScore * 100))%")
        print("   Wall matching: \(String(format: "%.1f", results.comparisonResults.wallAccuracy.wallMatchingRate * 100))%")
        print("   Furniture matching: \(String(format: "%.1f", results.comparisonResults.furnitureAccuracy.furnitureMatchingRate * 100))%")
        print("   Recommendations: \(roomAccuracyValidator.recommendations.count)")
        
        // Update status label with accuracy information
        let accuracyText = String(format: "%.0f", results.overallAccuracyScore * 100)
        statusLabel?.text = "✅ Room scanned with \(accuracyText)% accuracy - Tap 'View Plan' to see results"
        
        // Change status color based on accuracy
        if results.overallAccuracyScore >= 0.8 {
            statusLabel?.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
        } else if results.overallAccuracyScore >= 0.6 {
            statusLabel?.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.9)
        } else {
            statusLabel?.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.9)
        }
        
        // Show alert for significant accuracy issues
        if results.overallAccuracyScore < 0.6 && !roomAccuracyValidator.recommendations.isEmpty {
            showAccuracyAlert(results: results)
        }
        
        // Log detailed recommendations
        for recommendation in roomAccuracyValidator.recommendations {
            print("   \(recommendation.severity.color) \(recommendation.type): \(recommendation.issue)")
            print("     → \(recommendation.recommendation)")
        }
    }
    
    private func showAccuracyAlert(results: RoomAccuracyValidator.ValidationResults) {
        let accuracyPercent = String(format: "%.0f", results.overallAccuracyScore * 100)
        let criticalIssues = roomAccuracyValidator.recommendations.filter { $0.severity == .critical || $0.severity == .high }
        
        let title = "Room Accuracy Issues Detected"
        var message = "Floor plan accuracy: \(accuracyPercent)%\n\n"
        
        if !criticalIssues.isEmpty {
            message += "Key issues found:\n"
            for issue in criticalIssues.prefix(3) {
                message += "• \(issue.issue)\n"
            }
        }
        
        message += "\nYou can still proceed with the current results or rescan for better accuracy."
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "View Detailed Report", style: .default) { _ in
            self.showDetailedAccuracyReport(results)
        })
        
        alert.addAction(UIAlertAction(title: "Continue", style: .default))
        alert.addAction(UIAlertAction(title: "Rescan Room", style: .cancel) { _ in
            self.retryRoomCapture()
        })
        
        present(alert, animated: true)
    }
    
    private func showDetailedAccuracyReport(_ results: RoomAccuracyValidator.ValidationResults) {
        let reportText = results.validationSummary + "\n\n" + 
            roomAccuracyValidator.recommendations.map { rec in
                "\(rec.severity.color) \(rec.issue)\n→ \(rec.recommendation)\n"
            }.joined(separator: "\n")
        
        let alert = UIAlertController(
            title: "Room Accuracy Report",
            message: reportText,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    */
    
    // MARK: - Navigation Methods
    
    private func navigateToFloorPlan() {
        // Allow floor plan access if room data exists, even without WiFi measurements
        if capturedRoomData != nil {
            viewResults()
        } else {
            showAlert(title: "Room Scan Required", message: "Please complete room scanning first to view the floor plan.")
        }
    }
    
    private func switchToRoomMode() {
        isARMode = false
        roomCaptureView.isHidden = false
        arSceneView.isHidden = true
        updateButtonStates()
    }
    
    // MARK: - Tracking State Management
    
    private var trackingStateTimer: Timer?
    private var poorTrackingStartTime: Date?
    private let poorTrackingThreshold: TimeInterval = 3.0 // seconds
    
    private func startTrackingStateMonitoring() {
        stopTrackingStateMonitoring()
        
        trackingStateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.monitorTrackingState()
        }
        
        print("📱 Started real-time tracking state monitoring")
    }
    
    private func stopTrackingStateMonitoring() {
        trackingStateTimer?.invalidate()
        trackingStateTimer = nil
        poorTrackingStartTime = nil
        print("📱 Stopped tracking state monitoring")
    }
    
    private func monitorTrackingState() {
        guard isScanning else { return }
        
        let trackingGood = isTrackingStateGood()
        let currentTime = Date()
        
        if !trackingGood {
            if poorTrackingStartTime == nil {
                poorTrackingStartTime = currentTime
            } else if let startTime = poorTrackingStartTime,
                      currentTime.timeIntervalSince(startTime) > poorTrackingThreshold {
                // Poor tracking for too long - show guidance
                handlePoorTracking()
                poorTrackingStartTime = currentTime // Reset timer
            }
        } else {
            // Good tracking - reset timer
            poorTrackingStartTime = nil
        }
    }
    
    private func handlePoorTracking() {
        guard isScanning else { return }
        
        print("⚠️ Poor tracking detected - providing user guidance")
        
        // Get specific tracking issue
        let trackingMessage = getTrackingStateMessage()
        
        // Show contextual guidance without stopping the session
        statusLabel?.text = "⚠️ \(trackingMessage)"
        statusLabel?.backgroundColor = UIColor.systemRed.withAlphaComponent(0.9)
        
        // Optionally show alert for severe issues
        let alert = UIAlertController(
            title: "Camera Tracking Issues",
            message: trackingMessage + "\n\nTip: If your phone is lying flat, pick it up and point the camera toward the room.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Continue", style: .default))
        alert.addAction(UIAlertAction(title: "Restart Scan", style: .default) { _ in
            self.restartScanWithGuidance()
        })
        
        present(alert, animated: true)
    }
    
    private func getTrackingStateMessage() -> String {
        guard let arSession = roomCaptureView?.captureSession.arSession,
              let trackingState = arSession.currentFrame?.camera.trackingState else {
            return "Unable to determine camera tracking state"
        }
        
        switch trackingState {
        case .normal:
            return "Camera tracking is working well"
        case .limited(.initializing):
            return "Camera is initializing - move device slowly"
        case .limited(.relocalizing):
            return "Camera lost tracking - return to a previously scanned area"
        case .limited(.excessiveMotion):
            return "Moving too fast - slow down your movements"  
        case .limited(.insufficientFeatures):
            return "Not enough visual detail - point camera at walls/furniture"
        case .notAvailable:
            return "Camera tracking unavailable - check device orientation"
        default:
            return "Camera tracking needs attention"
        }
    }
    
    private func restartScanWithGuidance() {
        print("🔄 Restarting scan with user guidance...")
        
        // Stop current session
        stopSession()
        
        // Show enhanced guidance
        showEnhancedTrackingGuidance()
    }
    
    private func showEnhancedTrackingGuidance() {
        let alert = UIAlertController(
            title: "Optimal Camera Setup",
            message: "For successful room scanning:\n\n📱 Hold phone upright (not flat)\n👀 Point camera toward room surfaces\n🚶‍♂️ Walk slowly around the space\n💡 Ensure good lighting\n🏠 Start from a corner or wall\n\nThis will ensure the best scanning results.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Start Scanning", style: .default) { _ in
            // Wait a moment for user to position phone correctly
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startSession()
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func isTrackingStateGood() -> Bool {
        // In simulator mode, simulate good tracking most of the time
        
        guard let arSession = roomCaptureView?.captureSession.arSession else { return false }
        
        switch arSession.currentFrame?.camera.trackingState {
        case .normal:
            return true
        case .limited(.initializing), .limited(.relocalizing):
            return false
        case .limited(.excessiveMotion), .limited(.insufficientFeatures):
            return false
        case .notAvailable:
            return false
        default:
            return false
        }
    }
    
    private func showTrackingGuidance() {
        showEnhancedTrackingGuidance()
    }
    
    
    
}

// MARK: - RoomCaptureSessionDelegate

extension RoomCaptureViewController {
    
    func captureSession(_ session: RoomCaptureSession, didFailWithError error: Error) {
        print("❌ Room capture session failed with error: \(error.localizedDescription)")
        
        // Handle specific error types
        if let roomCaptureError = error as? RoomCaptureSession.CaptureError {
            handleCaptureError(roomCaptureError)
        } else {
            // Generic error handling
            handleGenericCaptureError(error)
        }
    }
    
    func captureSession(_ session: RoomCaptureSession, didAdd room: CapturedRoom.Surface) {
        print("📐 Added room surface: \(room)")
        
        // Trigger scanning haptic for new surface detection
        triggerSurfaceDetectionHaptic()
        
        // Update progress indicator as surfaces are detected
        DispatchQueue.main.async {
            self.updateButtonStates()
        }
    }
    
    func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom.Surface) {
        print("📐 Updated room surface: \(room)")
        
        // Trigger lighter haptic for surface updates (less frequent)
        let now = Date()
        if now.timeIntervalSince(lastSurfaceHapticTime) >= hapticThrottleInterval * 2 {
            triggerScanningPattern(intensity: .light, duration: .short)
            lastSurfaceHapticTime = now
        }
        
        DispatchQueue.main.async {
            self.updateButtonStates()
        }
    }
    
    func captureSession(_ session: RoomCaptureSession, didRemove room: CapturedRoom.Surface) {
        print("📐 Removed room surface: \(room)")
        
        DispatchQueue.main.async {
            self.updateButtonStates()
        }
    }
    
    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        print("🏁 Room capture session ended")
        
        if let error = error {
            print("⚠️ Session ended with error: \(error.localizedDescription)")
            handleSessionEndError(error)
        } else {
            print("✅ Session ended successfully with data")
            // Continue with normal processing
        }
    }
    
    // MARK: - Error Handling
    
    private func handleCaptureError(_ error: RoomCaptureSession.CaptureError) {
        DispatchQueue.main.async {
            // Handle all RoomCaptureSession errors generically since
            // the specific enum cases may vary by iOS version
            self.handleGenericCaptureError(error)
        }
    }
    
    private func handleGenericCaptureError(_ error: Error) {
        print("⚠️ Capture error: \(error.localizedDescription)")
        
        statusLabel?.text = "⚠️ Scanning error - Tap restart to try again"
        statusLabel?.backgroundColor = UIColor.systemRed.withAlphaComponent(0.9)
        
        // Check if this looks like a tracking issue (common with phone positioning problems)
        let errorDescription = error.localizedDescription.lowercased()
        let isTrackingError = errorDescription.contains("tracking") || 
                             errorDescription.contains("motion") || 
                             errorDescription.contains("features")
        
        let alert = UIAlertController(
            title: isTrackingError ? "Camera Tracking Issues" : "Scanning Error",
            message: isTrackingError ? 
                "Camera tracking failed. This often happens when:\n\n• Phone is lying flat or facing down\n• Moving too quickly\n• Poor lighting conditions\n• Not enough visual detail\n\nWould you like guidance on positioning?" :
                "There was an issue with room scanning: \(error.localizedDescription)\n\nWould you like to try again?",
            preferredStyle: .alert
        )
        
        if isTrackingError {
            alert.addAction(UIAlertAction(title: "Get Positioning Help", style: .default) { _ in
                self.retryWithGuidance()
            })
        }
        
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in
            self.retryRoomCapture()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func handleSessionEndError(_ error: Error) {
        print("⚠️ Session end error: \(error.localizedDescription)")
        
        DispatchQueue.main.async {
            self.statusLabel?.text = "⚠️ Session ended with issues"
            self.statusLabel?.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.9)
            
            let alert = UIAlertController(
                title: "Scanning Incomplete",
                message: "The room scan ended with issues: \(error.localizedDescription)\n\nYou can try scanning again or proceed with the current results.",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Retry Scan", style: .default) { _ in
                self.retryRoomCapture()
            })
            
            alert.addAction(UIAlertAction(title: "Use Current Results", style: .default) { _ in
                // Continue with whatever data we have
                self.updateButtonStates()
            })
            
            self.present(alert, animated: true)
        }
    }
    
    // MARK: - Retry Logic
    
    private func retryRoomCapture() {
        print("🔄 Retrying room capture...")
        
        // Stop current session cleanly
        if isScanning {
            stopSession()
        }
        
        // Wait a moment for cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.statusLabel?.text = "🔄 Restarting room scan..."
            self.statusLabel?.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
            
            // Clear any previous data to start fresh
            self.capturedRoomData = nil
            self.finalResults = nil
            
            // Restart the session
            self.startSession()
        }
    }
    
    private func retryWithGuidance() {
        print("🔄 Retrying room capture with user guidance...")
        
        // Stop current session cleanly
        if isScanning {
            stopSession()
        }
        
        // Clear any previous data
        capturedRoomData = nil
        finalResults = nil
        
        // Show enhanced guidance before retrying
        showEnhancedTrackingGuidance()
    }
    
    // MARK: - Haptic Feedback Setup
    
    private func setupHapticFeedback() {
        // Prepare haptic generators for faster response
        lightHapticGenerator.prepare()
        mediumHapticGenerator.prepare()
        heavyHapticGenerator.prepare()
        
        print("📳 Haptic feedback system initialized")
    }
    
    private func cleanupHapticGenerators() {
        // Release haptic generators to free memory
        // Note: UIImpactFeedbackGenerator doesn't have an explicit cleanup method,
        // but setting them to new instances releases the old prepared state
        lightHapticGenerator = UIImpactFeedbackGenerator(style: .light)
        mediumHapticGenerator = UIImpactFeedbackGenerator(style: .medium)
        heavyHapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
        
        // Reset throttling timestamps
        lastSurfaceHapticTime = Date.distantPast
        lastObjectHapticTime = Date.distantPast
        
        print("🧹 Haptic generators cleaned up and reset")
    }
    
    private func ensureHapticGeneratorsReady() {
        // Re-prepare generators if they were cleaned up (lazy re-initialization)
        lightHapticGenerator.prepare()
        mediumHapticGenerator.prepare()  
        heavyHapticGenerator.prepare()
    }
    
    private func triggerSurfaceDetectionHaptic() {
        let now = Date()
        
        // Throttle haptic feedback to prevent overwhelming vibration
        guard now.timeIntervalSince(lastSurfaceHapticTime) >= hapticThrottleInterval else {
            return
        }
        
        lastSurfaceHapticTime = now
        
        // Skip haptics in simulator mode
        
        // Ensure generators are ready
        ensureHapticGeneratorsReady()
        
        // Create scanning sensation for wall/surface detection
        triggerScanningPattern(intensity: .light, duration: .short)
        print("📳 Scanning haptic triggered for surface detection")
    }
    
    private func triggerObjectDetectionHaptic() {
        let now = Date()
        
        // Throttle haptic feedback
        guard now.timeIntervalSince(lastObjectHapticTime) >= hapticThrottleInterval else {
            return
        }
        
        lastObjectHapticTime = now
        
        // Skip haptics in simulator mode
        
        // Create more detailed scanning sensation for objects
        triggerScanningPattern(intensity: .medium, duration: .medium)
        print("📳 Scanning haptic triggered for object detection")
    }
    
    private func triggerMajorDiscoveryHaptic() {
        // Skip haptics in simulator mode
        
        // Create discovery confirmation pattern
        triggerDiscoveryPattern()
        print("📳 Discovery haptic triggered for major discovery")
    }
    
    // MARK: - Scanner-like Haptic Patterns
    
    private enum ScanIntensity {
        case light, medium, heavy
    }
    
    private enum ScanDuration {
        case short, medium, long
    }
    
    private func triggerScanningPattern(intensity: ScanIntensity, duration: ScanDuration) {
        let generator: UIImpactFeedbackGenerator
        let pulseCount: Int
        let pulseInterval: TimeInterval
        
        switch intensity {
        case .light:
            generator = lightHapticGenerator
        case .medium:
            generator = mediumHapticGenerator
        case .heavy:
            generator = heavyHapticGenerator
        }
        
        switch duration {
        case .short:
            pulseCount = 2
            pulseInterval = 0.08 // Quick double-tap like scanner beam
        case .medium:
            pulseCount = 3
            pulseInterval = 0.06 // Rapid triple pulse like scanning over object
        case .long:
            pulseCount = 4
            pulseInterval = 0.05 // Extended scanning sensation
        }
        
        // Create scanning pulse pattern
        for i in 0..<pulseCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(i) * pulseInterval) {
                generator.impactOccurred()
            }
        }
    }
    
    private func triggerDiscoveryPattern() {
        // Success pattern: medium -> pause -> heavy (like scanner confirmation)
        mediumHapticGenerator.impactOccurred()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.heavyHapticGenerator.impactOccurred()
        }
    }
    
    private func triggerActiveScanningFeedback() {
        // Continuous subtle feedback while actively scanning
        // Very light, rhythmic pulse to indicate scanning is active
        
        // Ensure generators are ready
        ensureHapticGeneratorsReady()
        
        let generator = lightHapticGenerator
        
        // Gentle rhythmic pulse - triple micro-pulse pattern
        let pulsePattern = [0.0, 0.05, 0.1] // Triple micro-pulse
        
        for delay in pulsePattern {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                generator.impactOccurred() // Very subtle using light generator
            }
        }
        
        print("📳 Progress scanning haptic triggered")
    }
    
    // MARK: - Scanning Progress Haptics
    
    private func startScanningProgressHaptics() {
        // Stop any existing timer
        stopScanningProgressHaptics()
        
        // Start periodic subtle haptics to indicate ongoing scanning
        scanningProgressTimer = Timer.scheduledTimer(withTimeInterval: progressHapticInterval, repeats: true) { [weak self] _ in
            self?.triggerActiveScanningFeedback()
        }
        
        print("📳 Started scanning progress haptics (every \(progressHapticInterval)s)")
    }
    
    private func stopScanningProgressHaptics() {
        scanningProgressTimer?.invalidate()
        scanningProgressTimer = nil
        print("📳 Stopped scanning progress haptics")
    }
    
}

