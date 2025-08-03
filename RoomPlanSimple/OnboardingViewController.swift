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
        title = "Spectrum WiFi Analyzer"
        view.backgroundColor = SpectrumBranding.Colors.secondaryBackground
        
        // Configure navigation bar with Spectrum branding
        if let navigationBar = navigationController?.navigationBar {
            SpectrumBranding.configureNavigationBar(navigationBar)
        }
        
        // Create and setup features programmatically to avoid storyboard connection issues
        setupSpectrumBrandedView()
    }
    
    private func setupSpectrumBrandedView() {
        // Create main logo container
        let logoContainer = UIView()
        logoContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logoContainer)
        
        // Spectrum logo/title section
        let titleLabel = SpectrumBranding.createSpectrumLabel(text: "Spectrum", style: .title)
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: 48, weight: .bold)
        
        let subtitleLabel = SpectrumBranding.createSpectrumLabel(text: "WiFi Analyzer", style: .headline)
        subtitleLabel.textAlignment = .center
        subtitleLabel.font = UIFont.systemFont(ofSize: 24, weight: .medium)
        
        let loadingLabel = SpectrumBranding.createSpectrumLabel(text: "Loading...", style: .body)
        loadingLabel.textAlignment = .center
        loadingLabel.alpha = 0.7
        
        // Create activity indicator
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.color = SpectrumBranding.Colors.spectrumBlue
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        
        // Stack view for centered content
        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            subtitleLabel,
            createSpacer(height: 40),
            activityIndicator,
            createSpacer(height: 16),
            loadingLabel
        ])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        logoContainer.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            // Logo container centered
            logoContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            logoContainer.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 40),
            logoContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40),
            
            // Stack view fills container
            stackView.topAnchor.constraint(equalTo: logoContainer.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: logoContainer.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: logoContainer.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: logoContainer.bottomAnchor),
            
            // Activity indicator size
            activityIndicator.widthAnchor.constraint(equalToConstant: 40),
            activityIndicator.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    private func createSpacer(height: CGFloat) -> UIView {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        return spacer
    }
    
    private func checkDeviceCompatibility() {
        if !RoomCaptureSession.isSupported {
            showUnsupportedDeviceAlert()
        }
        // Auto-start will be triggered after view appears
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Reduce splash screen delay to improve perceived loading time
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.transitionToRoomCapture()
        }
    }
    
    private func transitionToRoomCapture() {
        guard RoomCaptureSession.isSupported else {
            showUnsupportedDeviceAlert()
            return
        }
        
        // Create RoomCaptureViewController directly without navigation controller
        if let roomCaptureVC = self.storyboard?.instantiateViewController(
            withIdentifier: "RoomCaptureViewController") as? RoomCaptureViewController {
            roomCaptureVC.modalPresentationStyle = .fullScreen
            present(roomCaptureVC, animated: true)
        }
    }
    
    private func startScanAutomatically() {
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
