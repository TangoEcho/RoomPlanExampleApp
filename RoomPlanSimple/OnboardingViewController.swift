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
        
        // Official Spectrum logo - using bundled asset for offline support
        let logoView = createSpectrumLogoView()
        logoView.translatesAutoresizingMaskIntoConstraints = false
        
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
            logoView,
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
            activityIndicator.heightAnchor.constraint(equalToConstant: 40),
            
            // Logo view size
            logoView.heightAnchor.constraint(equalToConstant: 80),
            logoView.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        ])
    }
    
    private func createSpacer(height: CGFloat) -> UIView {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        return spacer
    }
    
    private func createSpectrumLogoView() -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Official Spectrum colors (metallic gray and sky blue)
        let spectrumGray = UIColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1.0)
        let spectrumBlue = UIColor(red: 0.0, green: 0.64, blue: 1.0, alpha: 1.0)
        
        // Create "SPECTRUM" text with official styling
        let textLabel = UILabel()
        textLabel.text = "SPECTRUM"
        // Use system font that matches the official sans-serif rounded look
        textLabel.font = UIFont.systemFont(ofSize: 28, weight: .medium)
        textLabel.textColor = spectrumGray
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.adjustsFontSizeToFitWidth = true
        textLabel.minimumScaleFactor = 0.5
        
        // Create blue triangle pointing right
        let triangleView = UIView()
        triangleView.translatesAutoresizingMaskIntoConstraints = false
        triangleView.backgroundColor = .clear
        
        // Draw custom triangle
        let triangleLayer = CAShapeLayer()
        let trianglePath = UIBezierPath()
        trianglePath.move(to: CGPoint(x: 0, y: 0))
        trianglePath.addLine(to: CGPoint(x: 16, y: 8))
        trianglePath.addLine(to: CGPoint(x: 0, y: 16))
        trianglePath.close()
        triangleLayer.path = trianglePath.cgPath
        triangleLayer.fillColor = spectrumBlue.cgColor
        triangleView.layer.addSublayer(triangleLayer)
        
        containerView.addSubview(textLabel)
        containerView.addSubview(triangleView)
        
        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            textLabel.topAnchor.constraint(equalTo: containerView.topAnchor),
            textLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            triangleView.leadingAnchor.constraint(equalTo: textLabel.trailingAnchor, constant: 12),
            triangleView.centerYAnchor.constraint(equalTo: textLabel.centerYAnchor),
            triangleView.widthAnchor.constraint(equalToConstant: 16),
            triangleView.heightAnchor.constraint(equalToConstant: 16),
            triangleView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
        
        return containerView
    }
    
    private func checkDeviceCompatibility() {
        // In simulator, bypass RoomPlan support check for UI testing
        #if targetEnvironment(simulator)
        print("🎭 Running in simulator - bypassing RoomPlan compatibility check")
        #else
        if !RoomCaptureSession.isSupported {
            showUnsupportedDeviceAlert()
        }
        #endif
        // Auto-start will be triggered after view appears
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Display Spectrum logo prominently for 3 seconds before transitioning
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.transitionToRoomCapture()
        }
    }
    
    private func transitionToRoomCapture() {
        #if targetEnvironment(simulator)
        print("🎭 Simulator: Transitioning to RoomCaptureViewController with mock data")
        #else
        guard RoomCaptureSession.isSupported else {
            showUnsupportedDeviceAlert()
            return
        }
        #endif
        
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
