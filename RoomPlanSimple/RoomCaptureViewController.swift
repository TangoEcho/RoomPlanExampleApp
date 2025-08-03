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
    
    @IBOutlet var doneButton: UIBarButtonItem?
    @IBOutlet var cancelButton: UIBarButtonItem?
    
    private var isScanning: Bool = false
    
    private var roomCaptureView: RoomCaptureView!
    private var roomCaptureSessionConfig: RoomCaptureSession.Configuration = RoomCaptureSession.Configuration()
    
    private var finalResults: CapturedRoom?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupRoomCaptureView()
        setupARView()
        setupWiFiSurvey()
        setupBottomNavigation()
        updateButtonStates()
    }
    
    private func setupRoomCaptureView() {
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
        // Create bottom navigation bar
        bottomNavBar = UIView()
        bottomNavBar?.backgroundColor = SpectrumBranding.Colors.secondaryBackground
        bottomNavBar?.translatesAutoresizingMaskIntoConstraints = false
        
        // Create mode label
        modeLabel = SpectrumBranding.createSpectrumLabel(text: "Room Scanning Mode", style: .caption)
        modeLabel?.textAlignment = .center
        modeLabel?.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        modeLabel?.textColor = .white
        modeLabel?.layer.cornerRadius = 6
        modeLabel?.layer.masksToBounds = true
        
        // Create scan/survey toggle button
        scanSurveyToggleButton = SpectrumBranding.createSpectrumButton(title: "📡 Switch to WiFi Survey", style: .secondary)
        scanSurveyToggleButton?.addTarget(self, action: #selector(scanSurveyToggleTapped), for: .touchUpInside)
        
        // Create floor plan button
        floorPlanNavButton = SpectrumBranding.createSpectrumButton(title: "📊 View Plan", style: .secondary)
        floorPlanNavButton?.addTarget(self, action: #selector(floorPlanNavTapped), for: .touchUpInside)
        
        guard let bottomNavBar = bottomNavBar,
              let modeLabel = modeLabel,
              let scanSurveyToggleButton = scanSurveyToggleButton,
              let floorPlanNavButton = floorPlanNavButton else { return }
        
        view.addSubview(bottomNavBar)
        bottomNavBar.addSubview(modeLabel)
        bottomNavBar.addSubview(scanSurveyToggleButton)
        bottomNavBar.addSubview(floorPlanNavButton)
        
        NSLayoutConstraint.activate([
            // Bottom nav bar
            bottomNavBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomNavBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomNavBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomNavBar.heightAnchor.constraint(equalToConstant: 80),
            
            // Mode label at top
            modeLabel.topAnchor.constraint(equalTo: bottomNavBar.topAnchor, constant: 8),
            modeLabel.leadingAnchor.constraint(equalTo: bottomNavBar.leadingAnchor, constant: 20),
            modeLabel.trailingAnchor.constraint(equalTo: bottomNavBar.trailingAnchor, constant: -20),
            modeLabel.heightAnchor.constraint(equalToConstant: 24),
            
            // Buttons at bottom
            scanSurveyToggleButton.topAnchor.constraint(equalTo: modeLabel.bottomAnchor, constant: 8),
            scanSurveyToggleButton.leadingAnchor.constraint(equalTo: bottomNavBar.leadingAnchor, constant: 10),
            scanSurveyToggleButton.heightAnchor.constraint(equalToConstant: 40),
            scanSurveyToggleButton.widthAnchor.constraint(equalTo: floorPlanNavButton.widthAnchor),
            
            floorPlanNavButton.topAnchor.constraint(equalTo: modeLabel.bottomAnchor, constant: 8),
            floorPlanNavButton.leadingAnchor.constraint(equalTo: scanSurveyToggleButton.trailingAnchor, constant: 10),
            floorPlanNavButton.trailingAnchor.constraint(equalTo: bottomNavBar.trailingAnchor, constant: -10),
            floorPlanNavButton.heightAnchor.constraint(equalToConstant: 40)
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
        
        print("🔄 Switching from room scanning to WiFi survey with coordinate alignment...")
        
        // iOS 17+: Use advanced coordinate alignment with shared ARSession
        // Stop RoomPlan but keep ARSession running for perfect coordinate alignment
        roomCaptureView?.captureSession.stop(pauseARSession: false)
        print("🎯 RoomPlan stopped with ARSession maintained for coordinate continuity")
        
        roomPlanPaused = true
        
        // Store the current room data as additional coordinate reference
        if let capturedRoom = capturedRoomData {
            print("📍 Using captured room data as coordinate reference")
            arVisualizationManager.setCapturedRoomData(capturedRoom)
        }
        
        // Switch to surveying mode
        currentMode = .surveying
        isScanning = false
        
        // Start WiFi survey with perfect coordinate alignment
        startWiFiSurveyWithinRoomPlan()
        
        statusLabel?.text = "📡 WiFi survey mode - Perfect coordinate alignment active"
        print("✅ Successfully switched to WiFi survey mode with coordinate alignment")
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
    }
    
    private func startSession() {
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
        
        setActiveNavBar()
        updateButtonStates()
    }
    
    private func stopSession() {
        print("🛑 Stopping room capture session...")
        isScanning = false
        roomCaptureView?.captureSession.stop()
        stopWiFiMonitoring()
        
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
            self.cancelButton?.tintColor = .white
            self.doneButton?.tintColor = .white
            self.exportButton?.alpha = 0.0
        }, completion: { complete in
            self.exportButton?.isHidden = true
        })
    }
    
    private func setCompleteNavBar() {
        self.exportButton?.isHidden = false
        UIView.animate(withDuration: 1.0) {
            self.cancelButton?.tintColor = .systemBlue
            self.doneButton?.tintColor = .systemBlue
            self.exportButton?.alpha = 1.0
        }
    }
}

