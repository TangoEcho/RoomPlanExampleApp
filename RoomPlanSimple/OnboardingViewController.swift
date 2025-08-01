/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller for the app's first screen that explains what to do.
*/

import UIKit
import RoomPlan

class OnboardingViewController: UIViewController {
    @IBOutlet var existingScanView: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        checkDeviceCompatibility()
    }
    
    private func setupUI() {
        title = "Interspectrum WiFi Analyzer"
        
        // Create and setup features programmatically to avoid storyboard connection issues
        setupFeaturesView()
    }
    
    private func setupFeaturesView() {
        let features = [
            "🏠 3D Room Mapping with RoomPlan",
            "📡 WiFi Coverage Analysis", 
            "🗺️ AR Visualization Overlay",
            "📊 Speed Testing & Heatmaps",
            "📋 Detailed Coverage Reports",
            "🎯 Optimal Router Placement"
        ]
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        for feature in features {
            let label = UILabel()
            label.text = feature
            label.font = UIFont.systemFont(ofSize: 16)
            label.numberOfLines = 0
            stackView.addArrangedSubview(label)
        }
        
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 40),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50)
        ])
    }
    
    private func checkDeviceCompatibility() {
        if !RoomCaptureSession.isSupported {
            showUnsupportedDeviceAlert()
        }
    }
    
    private func showUnsupportedDeviceAlert() {
        let alert = UIAlertController(
            title: "Device Not Supported",
            message: "This app requires a device with LiDAR sensor (iPhone 12 Pro and later, iPad Pro 2020 and later).",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    @IBAction func startScan(_ sender: UIButton) {
        guard RoomCaptureSession.isSupported else {
            showUnsupportedDeviceAlert()
            return
        }
        
        if let viewController = self.storyboard?.instantiateViewController(
            withIdentifier: "RoomCaptureViewNavigationController") {
            viewController.modalPresentationStyle = .fullScreen
            present(viewController, animated: true)
        }
    }
}
