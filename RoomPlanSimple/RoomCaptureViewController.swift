/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The sample app's main view controller that manages the scanning process.
*/

import UIKit
import RoomPlan
import ARKit
import SceneKit

class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    
    private var roomAnalyzer = RoomAnalyzer()
    private var wifiSurveyManager = WiFiSurveyManager()
    private var arVisualizationManager = ARVisualizationManager()
    private var arSceneView: ARSCNView!
    
    // iOS 17+ Custom ARSession for perfect coordinate alignment
    private lazy var sharedARSession: ARSession = {
        let session = ARSession()
        return session
    }()
    
    // Helper to check if iOS 17+ features are available
    private var isIOS17Available: Bool {
        return true
    }
    
    private var primaryActionButton: UIButton?
    private var viewResultsButton: UIButton?
    private var statusLabel: UILabel?
    private var progressIndicator: UIProgressView?
    private var speedTestProgressView: UIProgressView?
    private var speedTestLabel: UILabel?
    
    // Bottom navigation
    private var bottomNavBar: UIView?
    private var scanSurveyToggleButton: UIButton?
    private var floorPlanNavButton: UIButton?
    private var modeLabel: UILabel?
    
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
    private var isSimulatorMode: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
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
    private let progressHapticInterval: TimeInterval = 3.0 // Every 3 seconds while scanning
    
    // Simulator mode properties
    private var simulatorTimer: Timer?
    private var simulatorProgress: Float = 0.0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupRoomCaptureView()
        setupARView()
        setupWiFiSurvey()
        setupBottomNavigation()
        setupHapticFeedback()
        updateButtonStates()
    }
    
    private func setupRoomCaptureView() {
        if isSimulatorMode {
            print("🎭 Simulator: Setting up mock camera view")
            setupMockCameraView()
            return
        }
        
        print("🔧 Setting up RoomCaptureView with shared ARSession for optimal coordinate alignment...")
        
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
    
    private func setupMockCameraView() {
        // Create a mock camera background for simulator
        let mockCameraView = UIView(frame: view.bounds)
        mockCameraView.backgroundColor = UIColor.systemGray
        mockCameraView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add a label to indicate simulator mode
        let simulatorLabel = UILabel()
        simulatorLabel.text = "📱 SIMULATOR MODE\nMock Camera Feed\n\nUI Testing Environment"
        simulatorLabel.textAlignment = .center
        simulatorLabel.numberOfLines = 0
        simulatorLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        simulatorLabel.textColor = .white
        simulatorLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        simulatorLabel.layer.cornerRadius = 12
        simulatorLabel.layer.masksToBounds = true
        simulatorLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Insert mock view at index 0 to be behind all UI elements
        view.insertSubview(mockCameraView, at: 0)
        view.addSubview(simulatorLabel)
        
        NSLayoutConstraint.activate([
            mockCameraView.topAnchor.constraint(equalTo: view.topAnchor),
            mockCameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mockCameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mockCameraView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            simulatorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            simulatorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            simulatorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            simulatorLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40)
        ])
        
        print("✅ Mock camera view setup complete")
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
        
        // Create scan/survey toggle button in bottom-left corner
        scanSurveyToggleButton = SpectrumBranding.createSpectrumButton(title: "📡 Switch to WiFi Survey", style: .secondary)
        scanSurveyToggleButton?.addTarget(self, action: #selector(scanSurveyToggleTapped), for: .touchUpInside)
        scanSurveyToggleButton?.translatesAutoresizingMaskIntoConstraints = false
        scanSurveyToggleButton?.layer.cornerRadius = 8
        
        // Create floor plan button in bottom-right corner
        floorPlanNavButton = SpectrumBranding.createSpectrumButton(title: "📊 View Plan", style: .secondary)
        floorPlanNavButton?.addTarget(self, action: #selector(floorPlanNavTapped), for: .touchUpInside)
        floorPlanNavButton?.translatesAutoresizingMaskIntoConstraints = false
        floorPlanNavButton?.layer.cornerRadius = 8
        
        guard let modeLabel = modeLabel,
              let scanSurveyToggleButton = scanSurveyToggleButton,
              let floorPlanNavButton = floorPlanNavButton else { return }
        
        view.addSubview(modeLabel)
        view.addSubview(scanSurveyToggleButton)
        view.addSubview(floorPlanNavButton)
        
        NSLayoutConstraint.activate([
            // Mode label in top-left corner
            modeLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80), // Below status label
            modeLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            modeLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            modeLabel.heightAnchor.constraint(equalToConstant: 32),
            
            // Scan/survey toggle in bottom-left corner
            scanSurveyToggleButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            scanSurveyToggleButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            scanSurveyToggleButton.widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            scanSurveyToggleButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Floor plan button in bottom-right corner
            floorPlanNavButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            floorPlanNavButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            floorPlanNavButton.widthAnchor.constraint(equalToConstant: 100),
            floorPlanNavButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        updateBottomNavigation()
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
            // Allow viewing results or restarting
            break
        }
        
        updateBottomNavigation()
    }
    
    @objc private func floorPlanNavTapped() {
        // Allow floor plan access if room data exists, even without WiFi measurements
        if capturedRoomData != nil {
            viewResults()
        } else {
            showAlert(title: "Room Scan Required", message: "Please complete room scanning first to view the floor plan.")
        }
    }
    
    private func switchToWiFiSurvey() {
        guard isScanning else { return }
        
        print("🔄 Switching from room scanning to WiFi survey...")
        
        if isSimulatorMode {
            // Simulator mode - load mock WiFi data
            print("🎭 Loading mock WiFi survey data")
            let mockMeasurements = createMockWiFiMeasurements()
            wifiSurveyManager.measurements = mockMeasurements
            print("🎭 Loaded \(mockMeasurements.count) mock WiFi measurements")
        } else {
            // iOS 17+: Use advanced coordinate alignment with shared ARSession
            // Stop RoomPlan but keep ARSession running for perfect coordinate alignment
            roomCaptureView?.captureSession.stop(pauseARSession: false)
            print("🎯 RoomPlan stopped with ARSession maintained for coordinate continuity")
            
            // Store the current room data as additional coordinate reference
            if let capturedRoom = capturedRoomData {
                print("📍 Using captured room data as coordinate reference")
                arVisualizationManager.setCapturedRoomData(capturedRoom)
            }
        }
        
        roomPlanPaused = true
        
        // Switch to surveying mode
        currentMode = .surveying
        isScanning = false
        
        // Start WiFi survey
        startWiFiSurveyWithinRoomPlan()
        
        statusLabel?.text = isSimulatorMode ? 
            "📡 Mock WiFi survey mode - UI testing" : 
            "📡 WiFi survey mode - Perfect coordinate alignment active"
        print("✅ Successfully switched to WiFi survey mode")
    }
    
    private func switchBackToScanning() {
        print("🔄 Switching back to room scanning with coordinate preservation...")
        
        // Stop WiFi survey but preserve coordinate system
        wifiSurveyManager.stopSurvey()
        
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
            // Both completed - set to completed mode
            currentMode = .completed
            statusLabel?.text = "✅ Scan and survey complete - View your results"
            print("🎉 Both room scan and WiFi survey complete")
        } else if hasRoomData {
            // Room scanning already complete, just show room view
            currentMode = .completed
            switchToRoomCapture()
            statusLabel?.text = "Room scan complete - WiFi survey data collected"
            print("✅ Room scan complete, WiFi data available")
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
    
    private func resumeWiFiSurvey() {
        print("▶️ Resuming WiFi survey...")
        startWiFiSurveyWithinRoomPlan()
    }
    
    private func startWiFiSurveyWithinRoomPlan() {
        // Start WiFi survey 
        wifiSurveyManager.startSurvey()
        
        // Switch to AR mode for WiFi visualization
        switchToARMode()
        
        // iOS 17+: AR is already using the shared session, perfect alignment!
        if isIOS17Available {
            print("🎯 WiFi survey using shared ARSession - Perfect coordinate alignment active")
            arVisualizationManager.setSharedARSessionMode(true)
        } else {
            // iOS 16: Start separate AR session
            arVisualizationManager.startARSession()
            print("⚠️ WiFi survey using separate ARSession (iOS 16)")
        }
        
        // If we have room data, use it for additional reference
        if let capturedRoom = capturedRoomData {
            print("📍 Using captured room data as additional coordinate reference")
            arVisualizationManager.setCapturedRoomData(capturedRoom)
        }
        
        statusLabel?.text = "📡 WiFi survey active - Perfect coordinate alignment"
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
                scanSurveyToggleButton?.isEnabled = true
            } else {
                modeLabel?.text = "📱 Ready to Scan Room"
                modeLabel?.backgroundColor = UIColor.systemGray.withAlphaComponent(0.9)
                scanSurveyToggleButton?.setTitle("📱 Start Room Scan", for: .normal)
                scanSurveyToggleButton?.backgroundColor = SpectrumBranding.Colors.spectrumBlue
                scanSurveyToggleButton?.isEnabled = true
            }
            
        case .surveying:
            if wifiSurveyManager.isRecording {
                modeLabel?.text = "📡 WiFi Survey Active (\(wifiSurveyManager.measurements.count) points)"
                modeLabel?.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.9)
                scanSurveyToggleButton?.setTitle("📱 Back to Room Scan", for: .normal)
                scanSurveyToggleButton?.backgroundColor = SpectrumBranding.Colors.spectrumBlue
                scanSurveyToggleButton?.isEnabled = true
            } else {
                modeLabel?.text = "📡 WiFi Survey Ready"
                modeLabel?.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
                scanSurveyToggleButton?.setTitle("📡 Resume WiFi Survey", for: .normal)
                scanSurveyToggleButton?.backgroundColor = SpectrumBranding.Colors.spectrumGreen
                scanSurveyToggleButton?.isEnabled = true
            }
            
        case .completed:
            modeLabel?.text = "✅ Scan & Survey Complete"
            modeLabel?.backgroundColor = UIColor.systemPurple.withAlphaComponent(0.9)
            scanSurveyToggleButton?.setTitle("🔄 Restart", for: .normal)
            scanSurveyToggleButton?.backgroundColor = SpectrumBranding.Colors.spectrumSilver
            scanSurveyToggleButton?.isEnabled = true
        }
        
        // Floor Plan button
        let hasRoomData = capturedRoomData != nil || roomPlanPaused
        let hasWifiData = !wifiSurveyManager.measurements.isEmpty
        
        if hasRoomData {
            if hasWifiData {
                floorPlanNavButton?.setTitle("📊 Results", for: .normal)
                floorPlanNavButton?.backgroundColor = SpectrumBranding.Colors.spectrumBlue
            } else {
                floorPlanNavButton?.setTitle("📊 Plan", for: .normal)
                floorPlanNavButton?.backgroundColor = SpectrumBranding.Colors.spectrumGreen
            }
            floorPlanNavButton?.isEnabled = true
        } else {
            floorPlanNavButton?.setTitle("📊 Plan", for: .normal)
            floorPlanNavButton?.backgroundColor = SpectrumBranding.Colors.spectrumSilver
            floorPlanNavButton?.isEnabled = false
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
            let roomCount = roomAnalyzer.identifiedRooms.count
            let measurementCount = wifiSurveyManager.measurements.count
            statusText = "🎉 Complete! \(roomCount) rooms mapped, \(measurementCount) WiFi points - View Results"
            backgroundColor = UIColor.systemPurple.withAlphaComponent(0.9)
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
        simulatorTimer?.invalidate()
        simulatorTimer = nil
        
        // Clean up measurement data to prevent memory leaks
        wifiSurveyManager.clearMeasurementData()
    }
    
    private func startSession() {
        if isSimulatorMode {
            startSimulatorSession()
            return
        }
        
        guard let roomCaptureView = roomCaptureView else {
            print("❌ Cannot start session: roomCaptureView is nil")
            return
        }
        
        guard RoomCaptureSession.isSupported else {
            print("❌ Cannot start session: RoomCaptureSession not supported")
            showAlert(title: "Device Not Supported", message: "This device does not support room capture.")
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
    
    private func startSimulatorSession() {
        print("🎭 Starting simulator mock session...")
        
        isScanning = true
        simulatorProgress = 0.0
        
        // Start mock room scanning progress
        simulatorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            self?.updateSimulatorProgress()
        }
        
        // Load mock room data
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.loadMockRoomData()
        }
        
        setActiveNavBar()
        updateButtonStates()
        
        print("✅ Simulator session started")
    }
    
    private func updateSimulatorProgress() {
        simulatorProgress += 0.05
        
        // Update status with mock scanning progress
        statusLabel?.text = "📱 Mock Room Scanning... \(Int(simulatorProgress * 100))%"
        statusLabel?.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
        
        // Simulate completion after reaching 100%
        if simulatorProgress >= 1.0 {
            simulatorTimer?.invalidate()
            simulatorTimer = nil
            completeSimulatorScanning()
        }
    }
    
    private func loadMockRoomData() {
        // Simulate room analysis with mock data
        let mockRooms = createMockRoomAnalysis()
        roomAnalyzer.identifiedRooms = mockRooms
        
        print("🎭 Loaded \(mockRooms.count) mock rooms for testing")
        
        // Update UI to reflect mock room data
        updateButtonStates()
    }
    
    private func completeSimulatorScanning() {
        print("🎭 Simulator room scanning completed")
        
        // Simulate a successful room capture
        isScanning = false
        
        // Mock captured room data (set a flag to indicate mock data exists)
        capturedRoomData = nil // We'll use the room analyzer data instead
        
        statusLabel?.text = "✅ Mock Room Scan Complete - \(roomAnalyzer.identifiedRooms.count) rooms detected"
        statusLabel?.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
        
        updateButtonStates()
    }
    
    private func stopSession() {
        print("🛑 Stopping room capture session...")
        isScanning = false
        
        if isSimulatorMode {
            // Stop simulator timers
            simulatorTimer?.invalidate()
            simulatorTimer = nil
        } else {
            roomCaptureView?.captureSession.stop()
            stopTrackingStateMonitoring()
        }
        
        stopWiFiMonitoring()
        
        // Stop scanning progress haptics
        stopScanningProgressHaptics()
        
        setCompleteNavBar()
        updateButtonStates()
        
        print("✅ Room capture session stopped")
    }
    
    private func startWiFiMonitoring() {
        // Start basic WiFi network monitoring during room scan
        let networkInfo = wifiSurveyManager.getCurrentNetworkInfo()
        if let ssid = networkInfo.ssid, !ssid.isEmpty {
            print("📶 Connected to WiFi: \(ssid)")
        }
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
        
        // Pass room data to AR visualization manager
        arVisualizationManager.setCapturedRoomData(processedResult)
        
        // Update mode to completed if both room and WiFi data exist
        if !wifiSurveyManager.measurements.isEmpty {
            currentMode = .completed
            print("✅ Both room scan and WiFi survey complete")
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
        // In simulator mode, allow viewing results with mock data even without captured room data
        if isSimulatorMode {
            viewSimulatorResults()
            return
        }
        
        guard capturedRoomData != nil else {
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
                    floorPlanVC.updateWithData(heatmapData: heatmapData, roomAnalyzer: self.roomAnalyzer)
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
                floorPlanVC.updateWithData(heatmapData: emptyHeatmapData, roomAnalyzer: self.roomAnalyzer)
                floorPlanVC.modalPresentationStyle = .fullScreen
                self.present(floorPlanVC, animated: true)
                
                // Reset status
                self.statusLabel?.text = "Floor plan loaded"
            }
        }
    }
    
    private func viewSimulatorResults() {
        print("🎭 Showing simulator results with mock data...")
        
        statusLabel?.text = "📊 Loading mock analysis results..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Use mock heatmap data
            let mockHeatmapData = self.createMockHeatmapData()
            
            DispatchQueue.main.async {
                print("✅ Mock results generated, navigating to floor plan...")
                
                let floorPlanVC = FloorPlanViewController()
                floorPlanVC.updateWithData(heatmapData: mockHeatmapData, roomAnalyzer: self.roomAnalyzer)
                floorPlanVC.modalPresentationStyle = .fullScreen
                self.present(floorPlanVC, animated: true)
                
                // Reset status
                self.statusLabel?.text = "Mock analysis complete"
            }
        }
    }
    
    private func switchToARMode() {
        isARMode = true
        roomCaptureView.isHidden = true
        arSceneView.isHidden = false
        
        // Start AR session when switching to AR mode
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
        let destinationURL = FileManager.default.temporaryDirectory.appending(path: "Room.usdz")
        do {
            try finalResults?.export(to: destinationURL, exportOptions: .parametric)
            
            let activityVC = UIActivityViewController(activityItems: [destinationURL], applicationActivities: nil)
            activityVC.modalPresentationStyle = .popover
            
            present(activityVC, animated: true, completion: nil)
            if let popOver = activityVC.popoverPresentationController {
                popOver.sourceView = self.exportButton
            }
        } catch {
            print("Error = \(error)")
        }
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
        if isSimulatorMode {
            return true // For UI testing, assume good tracking
        }
        
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
    
    // MARK: - Mock Data for Simulator
    
    private func createMockRoomAnalysis() -> [RoomAnalyzer.IdentifiedRoom] {
        // Note: This is a simplified mock - will need to match actual RoomAnalyzer.IdentifiedRoom structure
        // For now, we'll just set an empty array and let the real room analyzer work
        return []
    }
    
    private func createMockWiFiMeasurements() -> [WiFiMeasurement] {
        var measurements: [WiFiMeasurement] = []
        
        // Living room measurements (good signal near router)
        measurements.append(contentsOf: [
            WiFiMeasurement(
                location: simd_float3(2.0, 0, 1.0),
                timestamp: Date().addingTimeInterval(-300),
                signalStrength: -35,
                networkName: "SpectrumSetup-A7",
                speed: 450.0,
                frequency: "5.18 GHz",
                roomType: .livingRoom
            ),
            WiFiMeasurement(
                location: simd_float3(4.0, 0, 2.0),
                timestamp: Date().addingTimeInterval(-280),
                signalStrength: -42,
                networkName: "SpectrumSetup-A7",
                speed: 380.0,
                frequency: "5.18 GHz",
                roomType: .livingRoom
            ),
            WiFiMeasurement(
                location: simd_float3(3.5, 0, 3.0),
                timestamp: Date().addingTimeInterval(-260),
                signalStrength: -38,
                networkName: "SpectrumSetup-A7",
                speed: 420.0,
                frequency: "5.18 GHz",
                roomType: .livingRoom
            )
        ])
        
        // Kitchen measurements (moderate signal)
        measurements.append(contentsOf: [
            WiFiMeasurement(
                location: simd_float3(-1.0, 0, 1.5),
                timestamp: Date().addingTimeInterval(-240),
                signalStrength: -58,
                networkName: "SpectrumSetup-A7",
                speed: 180.0,
                frequency: "5.18 GHz",
                roomType: .kitchen
            ),
            WiFiMeasurement(
                location: simd_float3(-2.5, 0, 2.5),
                timestamp: Date().addingTimeInterval(-220),
                signalStrength: -65,
                networkName: "SpectrumSetup-A7",
                speed: 120.0,
                frequency: "5.18 GHz",
                roomType: .kitchen
            )
        ])
        
        // Bedroom measurements (weaker signal)
        measurements.append(contentsOf: [
            WiFiMeasurement(
                location: simd_float3(2.5, 0, -2.0),
                timestamp: Date().addingTimeInterval(-200),
                signalStrength: -72,
                networkName: "SpectrumSetup-A7",
                speed: 85.0,
                frequency: "5.18 GHz",
                roomType: .bedroom
            ),
            WiFiMeasurement(
                location: simd_float3(4.0, 0, -3.5),
                timestamp: Date().addingTimeInterval(-180),
                signalStrength: -78,
                networkName: "SpectrumSetup-A7",
                speed: 45.0,
                frequency: "5.18 GHz",
                roomType: .bedroom
            )
        ])
        
        return measurements
    }
    
    private func createMockHeatmapData() -> WiFiHeatmapData {
        let measurements = createMockWiFiMeasurements()
        
        // Generate interpolated coverage map
        var coverageMap: [simd_float3: Double] = [:]
        
        // Create a grid covering the mock room area
        for x in stride(from: -4.0, through: 6.0, by: 0.5) {
            for z in stride(from: -5.0, through: 4.0, by: 0.5) {
                let point = simd_float3(Float(x), 0, Float(z))
                
                // Calculate interpolated signal strength based on distance from measurements
                var totalWeight: Float = 0
                var weightedSignal: Float = 0
                
                for measurement in measurements {
                    let distance = simd_distance(point, measurement.location)
                    let weight = 1.0 / (distance + 0.1) // Avoid division by zero
                    
                    totalWeight += weight
                    weightedSignal += weight * Float(measurement.signalStrength)
                }
                
                if totalWeight > 0 {
                    let interpolatedStrength = weightedSignal / totalWeight
                    let normalizedSignal = Double(interpolatedStrength + 100) / 100.0
                    
                    if interpolatedStrength > -120 {
                        coverageMap[point] = max(0, min(1, normalizedSignal))
                    }
                }
            }
        }
        
        // Mock optimal router placements (simplified as coordinates)
        let optimalPlacements = [
            simd_float3(1.0, 1.5, 0.5),
            simd_float3(0.0, 1.5, 1.0)
        ]
        
        return WiFiHeatmapData(
            measurements: measurements,
            coverageMap: coverageMap,
            optimalRouterPlacements: optimalPlacements
        )
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
        guard !isSimulatorMode else {
            print("📳 [Simulator] Would trigger scanning haptic for surface detection")
            return
        }
        
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
        guard !isSimulatorMode else {
            print("📳 [Simulator] Would trigger scanning haptic for object detection")
            return
        }
        
        // Create more detailed scanning sensation for objects
        triggerScanningPattern(intensity: .medium, duration: .medium)
        print("📳 Scanning haptic triggered for object detection")
    }
    
    private func triggerMajorDiscoveryHaptic() {
        // Skip haptics in simulator mode
        guard !isSimulatorMode else {
            print("📳 [Simulator] Would trigger discovery haptic for major discovery")
            return
        }
        
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
        guard !isSimulatorMode else { 
            print("📳 [Simulator] Would trigger active scanning feedback")
            return 
        }
        
        // Ensure generators are ready
        ensureHapticGeneratorsReady()
        
        let generator = lightHapticGenerator
        
        // Gentle rhythmic pulse - triple micro-pulse pattern
        let pulsePattern = [0.0, 0.05, 0.1] // Triple micro-pulse
        
        for delay in pulsePattern {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                generator.impactOccurred(intensity: 0.3) // Very subtle
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

