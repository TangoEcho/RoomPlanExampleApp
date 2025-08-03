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
    
    private var primaryActionButton: UIButton?
    private var viewResultsButton: UIButton?
    private var statusLabel: UILabel?
    private var progressIndicator: UIProgressView?
    private var speedTestProgressView: UIProgressView?
    private var speedTestLabel: UILabel?
    
    // Bottom navigation
    private var bottomNavBar: UIView?
    private var roomScanNavButton: UIButton?
    private var wifiSurveyNavButton: UIButton?
    private var floorPlanNavButton: UIButton?
    
    private var isARMode = false
    private var capturedRoomData: CapturedRoom?
    
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
        print("🔧 Setting up RoomCaptureView...")
        
        // Remove existing room capture view if any
        roomCaptureView?.removeFromSuperview()
        
        roomCaptureView = RoomCaptureView(frame: view.bounds)
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
        arSceneView = ARSCNView(frame: view.bounds)
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
        
        // Create navigation buttons
        roomScanNavButton = SpectrumBranding.createSpectrumButton(title: "Room Scan", style: .secondary)
        roomScanNavButton?.addTarget(self, action: #selector(roomScanNavTapped), for: .touchUpInside)
        
        wifiSurveyNavButton = SpectrumBranding.createSpectrumButton(title: "WiFi Survey", style: .secondary)
        wifiSurveyNavButton?.addTarget(self, action: #selector(wifiSurveyNavTapped), for: .touchUpInside)
        
        floorPlanNavButton = SpectrumBranding.createSpectrumButton(title: "Floor Plan", style: .secondary)
        floorPlanNavButton?.addTarget(self, action: #selector(floorPlanNavTapped), for: .touchUpInside)
        
        guard let bottomNavBar = bottomNavBar,
              let roomScanNavButton = roomScanNavButton,
              let wifiSurveyNavButton = wifiSurveyNavButton,
              let floorPlanNavButton = floorPlanNavButton else { return }
        
        view.addSubview(bottomNavBar)
        bottomNavBar.addSubview(roomScanNavButton)
        bottomNavBar.addSubview(wifiSurveyNavButton)
        bottomNavBar.addSubview(floorPlanNavButton)
        
        NSLayoutConstraint.activate([
            // Bottom nav bar
            bottomNavBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomNavBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomNavBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomNavBar.heightAnchor.constraint(equalToConstant: 60),
            
            // Navigation buttons - equal width
            roomScanNavButton.leadingAnchor.constraint(equalTo: bottomNavBar.leadingAnchor, constant: 10),
            roomScanNavButton.centerYAnchor.constraint(equalTo: bottomNavBar.centerYAnchor),
            roomScanNavButton.heightAnchor.constraint(equalToConstant: 40),
            roomScanNavButton.widthAnchor.constraint(equalTo: wifiSurveyNavButton.widthAnchor),
            
            wifiSurveyNavButton.leadingAnchor.constraint(equalTo: roomScanNavButton.trailingAnchor, constant: 10),
            wifiSurveyNavButton.centerYAnchor.constraint(equalTo: bottomNavBar.centerYAnchor),
            wifiSurveyNavButton.heightAnchor.constraint(equalToConstant: 40),
            wifiSurveyNavButton.widthAnchor.constraint(equalTo: floorPlanNavButton.widthAnchor),
            
            floorPlanNavButton.leadingAnchor.constraint(equalTo: wifiSurveyNavButton.trailingAnchor, constant: 10),
            floorPlanNavButton.trailingAnchor.constraint(equalTo: bottomNavBar.trailingAnchor, constant: -10),
            floorPlanNavButton.centerYAnchor.constraint(equalTo: bottomNavBar.centerYAnchor),
            floorPlanNavButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        updateBottomNavigation()
    }
    
    @objc private func roomScanNavTapped() {
        if !isScanning && capturedRoomData == nil {
            startSession()
        } else if isScanning {
            stopSession()
        }
        updateBottomNavigation()
    }
    
    @objc private func wifiSurveyNavTapped() {
        if capturedRoomData != nil {
            if !wifiSurveyManager.isRecording && wifiSurveyManager.measurements.isEmpty {
                startWiFiSurvey()
            } else if wifiSurveyManager.isRecording {
                stopWiFiSurvey()
            }
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
    
    private func updateBottomNavigation() {
        // Room Scan button
        if isScanning {
            roomScanNavButton?.setTitle("🛑 Stop", for: .normal)
            roomScanNavButton?.backgroundColor = SpectrumBranding.Colors.spectrumRed
            roomScanNavButton?.isEnabled = true
        } else if capturedRoomData == nil {
            roomScanNavButton?.setTitle("📱 Scan", for: .normal)
            roomScanNavButton?.backgroundColor = SpectrumBranding.Colors.spectrumBlue
            roomScanNavButton?.isEnabled = true
        } else {
            roomScanNavButton?.setTitle("✅ Done", for: .normal)
            roomScanNavButton?.backgroundColor = SpectrumBranding.Colors.spectrumGreen
            roomScanNavButton?.isEnabled = false
        }
        
        // WiFi Survey button
        if capturedRoomData == nil {
            wifiSurveyNavButton?.setTitle("📡 WiFi", for: .normal)
            wifiSurveyNavButton?.backgroundColor = SpectrumBranding.Colors.spectrumSilver
            wifiSurveyNavButton?.isEnabled = false
        } else if wifiSurveyManager.isRecording {
            wifiSurveyNavButton?.setTitle("🛑 Stop", for: .normal)
            wifiSurveyNavButton?.backgroundColor = SpectrumBranding.Colors.spectrumRed
            wifiSurveyNavButton?.isEnabled = true
        } else if wifiSurveyManager.measurements.isEmpty {
            wifiSurveyNavButton?.setTitle("📡 Start", for: .normal)
            wifiSurveyNavButton?.backgroundColor = SpectrumBranding.Colors.spectrumGreen
            wifiSurveyNavButton?.isEnabled = true
        } else {
            wifiSurveyNavButton?.setTitle("✅ Done", for: .normal)
            wifiSurveyNavButton?.backgroundColor = SpectrumBranding.Colors.spectrumGreen
            wifiSurveyNavButton?.isEnabled = false
        }
        
        // Floor Plan button - allow access after room scan, enhanced if WiFi data available
        let hasRoomData = capturedRoomData != nil
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
        var statusText = "Ready to start room scanning"
        var backgroundColor = UIColor.black.withAlphaComponent(0.7)
        
        if isScanning {
            statusText = "📱 Move around to capture room - Tap 'Stop' when satisfied"
            backgroundColor = UIColor.systemBlue.withAlphaComponent(0.9)
        } else if isScanning == false && capturedRoomData == nil {
            statusText = "🔄 Ready to start scanning - Move device to capture room layout"
            backgroundColor = UIColor.systemGray.withAlphaComponent(0.9)
        } else if capturedRoomData != nil && !wifiSurveyManager.isRecording && wifiSurveyManager.measurements.isEmpty {
            statusText = "✅ Room captured! Found \(roomAnalyzer.identifiedRooms.count) rooms - Ready for WiFi survey"
            backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
        } else if wifiSurveyManager.isRecording {
            statusText = "📡 Recording WiFi (\(wifiSurveyManager.measurements.count) points) - Move around room"
            backgroundColor = UIColor.systemOrange.withAlphaComponent(0.9)
        } else if capturedRoomData != nil && !wifiSurveyManager.measurements.isEmpty {
            statusText = "🎉 WiFi survey complete - View detailed results"
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
        
        if #available(iOS 17.0, *) {
            roomAnalyzer.analyzeCapturedRoom(processedResult)
        }
        
        // Pass room data to AR visualization manager
        arVisualizationManager.setCapturedRoomData(processedResult)
        
        updateButtonStates()
    }
    
    // Removed Done/Cancel actions - using bottom navigation instead
    
    private func startWiFiSurvey() {
        guard capturedRoomData != nil else {
            showAlert(title: "Room Scan Required", message: "Please complete room scanning first.")
            return
        }
        
        // Check network connectivity before starting survey
        guard isNetworkAvailable() else {
            showAlert(title: "Network Required", message: "Please connect to a WiFi network to perform speed tests.")
            return
        }
        
        wifiSurveyManager.startSurvey()
        switchToARMode()
        statusLabel?.text = "Starting WiFi survey..."
        
        // Start a timer to update status with measurement count
        startStatusUpdateTimer()
        updateButtonStates()
    }
    
    private func stopWiFiSurvey() {
        print("🛑 Stopping WiFi survey...")
        
        // Stop survey first
        wifiSurveyManager.stopSurvey()
        
        // Stop AR session with proper cleanup
        arVisualizationManager.stopARSession()
        
        // Switch back to room capture view
        switchToRoomCapture()
        
        // Update UI
        statusLabel?.text = "WiFi survey completed - \\(wifiSurveyManager.measurements.count) measurements recorded"
        stopStatusUpdateTimer()
        updateButtonStates()
        
        print("✅ WiFi survey stopped successfully")
        
        // Ensure results button is enabled after survey completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateButtonStates()
        }
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

