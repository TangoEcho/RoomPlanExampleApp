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
    
    private var surveyButton: UIButton?
    private var toggleARButton: UIButton? 
    private var viewResultsButton: UIButton?
    
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
        updateButtonStates()
    }
    
    private func setupRoomCaptureView() {
        roomCaptureView = RoomCaptureView(frame: view.bounds)
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
        
        view.insertSubview(roomCaptureView, at: 0)
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
    }
    
    private func setupSurveyButtons() {
        // Create survey button
        surveyButton = UIButton(type: .system)
        surveyButton?.setTitle("Start WiFi Survey", for: .normal)
        surveyButton?.backgroundColor = .systemBlue
        surveyButton?.setTitleColor(.white, for: .normal)
        surveyButton?.layer.cornerRadius = 8
        surveyButton?.translatesAutoresizingMaskIntoConstraints = false
        surveyButton?.addTarget(self, action: #selector(toggleWiFiSurvey), for: .touchUpInside)
        
        // Create toggle AR button
        toggleARButton = UIButton(type: .system)
        toggleARButton?.setTitle("AR View", for: .normal)
        toggleARButton?.backgroundColor = .systemGreen
        toggleARButton?.setTitleColor(.white, for: .normal)
        toggleARButton?.layer.cornerRadius = 8
        toggleARButton?.translatesAutoresizingMaskIntoConstraints = false
        toggleARButton?.addTarget(self, action: #selector(toggleARMode), for: .touchUpInside)
        
        // Create view results button
        viewResultsButton = UIButton(type: .system)
        viewResultsButton?.setTitle("View Results", for: .normal)
        viewResultsButton?.backgroundColor = .systemOrange
        viewResultsButton?.setTitleColor(.white, for: .normal)
        viewResultsButton?.layer.cornerRadius = 8
        viewResultsButton?.translatesAutoresizingMaskIntoConstraints = false
        viewResultsButton?.addTarget(self, action: #selector(viewResults), for: .touchUpInside)
        
        // Add buttons to view
        guard let surveyButton = surveyButton,
              let toggleARButton = toggleARButton,
              let viewResultsButton = viewResultsButton else { return }
        
        view.addSubview(surveyButton)
        view.addSubview(toggleARButton)
        view.addSubview(viewResultsButton)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            surveyButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            surveyButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            surveyButton.heightAnchor.constraint(equalToConstant: 44),
            surveyButton.widthAnchor.constraint(equalToConstant: 120),
            
            toggleARButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toggleARButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            toggleARButton.heightAnchor.constraint(equalToConstant: 44),
            toggleARButton.widthAnchor.constraint(equalToConstant: 100),
            
            viewResultsButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            viewResultsButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            viewResultsButton.heightAnchor.constraint(equalToConstant: 44),
            viewResultsButton.widthAnchor.constraint(equalToConstant: 120)
        ])
    }
    
    private func updateButtonStates() {
        surveyButton?.setTitle(wifiSurveyManager.isRecording ? "Stop Survey" : "Start WiFi Survey", for: .normal)
        toggleARButton?.setTitle(isARMode ? "Room Scan" : "AR View", for: .normal)
        viewResultsButton?.isEnabled = capturedRoomData != nil && !wifiSurveyManager.measurements.isEmpty
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
    }
    
    override func viewWillDisappear(_ flag: Bool) {
        super.viewWillDisappear(flag)
        stopSession()
    }
    
    private func startSession() {
        isScanning = true
        roomCaptureView?.captureSession.run(configuration: roomCaptureSessionConfig)
        
        setActiveNavBar()
    }
    
    private func stopSession() {
        isScanning = false
        roomCaptureView?.captureSession.stop()
        
        setCompleteNavBar()
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
        updateButtonStates()
    }
    
    @IBAction func doneScanning(_ sender: UIBarButtonItem) {
        if isScanning { 
            stopSession() 
        } else { 
            if wifiSurveyManager.isRecording {
                wifiSurveyManager.stopSurvey()
            }
            cancelScanning(sender) 
        }
    }
    
    @objc private func toggleWiFiSurvey() {
        if wifiSurveyManager.isRecording {
            wifiSurveyManager.stopSurvey()
            if isARMode {
                arVisualizationManager.stopARSession()
                switchToRoomCapture()
            }
        } else {
            guard capturedRoomData != nil else {
                showAlert(title: "Room Scan Required", message: "Please complete room scanning before starting WiFi survey.")
                return
            }
            
            wifiSurveyManager.startSurvey()
            switchToARMode()
        }
        updateButtonStates()
    }
    
    @objc private func toggleARMode() {
        if isARMode {
            switchToRoomCapture()
        } else {
            switchToARMode()
        }
    }
    
    @objc private func viewResults() {
        guard let capturedRoom = capturedRoomData else { return }
        
        let heatmapData = wifiSurveyManager.generateHeatmapData()
        
        let floorPlanVC = FloorPlanViewController()
        floorPlanVC.updateWithData(heatmapData: heatmapData, roomAnalyzer: roomAnalyzer)
        navigationController?.pushViewController(floorPlanVC, animated: true)
    }
    
    private func switchToARMode() {
        isARMode = true
        roomCaptureView.isHidden = true
        arSceneView.isHidden = false
        updateButtonStates()
    }
    
    private func switchToRoomCapture() {
        isARMode = false
        roomCaptureView.isHidden = false
        arSceneView.isHidden = true
        updateButtonStates()
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @IBAction func cancelScanning(_ sender: UIBarButtonItem) {
        navigationController?.dismiss(animated: true)
    }
    
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

