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
        
        // Create the official Spectrum logo using image rendering
        let logoImageView = UIImageView()
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.contentMode = .scaleAspectFit
        
        // Create the official Spectrum logo image programmatically
        let logoImage = createSpectrumLogoImage()
        logoImageView.image = logoImage
        
        containerView.addSubview(logoImageView)
        
        NSLayoutConstraint.activate([
            logoImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            logoImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            logoImageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            logoImageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        
        return containerView
    }
    
    private func createSpectrumLogoImage() -> UIImage {
        // Official Spectrum logo dimensions and colors - sized to fit well
        let logoSize = CGSize(width: 320, height: 90)
        let spectrumNavy = UIColor(red: 0.094, green: 0.211, blue: 0.314, alpha: 1.0) // #18364F
        let spectrumBlue = UIColor(red: 0.086, green: 0.447, blue: 0.851, alpha: 1.0) // #1672D9
        
        let renderer = UIGraphicsImageRenderer(size: logoSize)
        let logoImage = renderer.image { context in
            let cgContext = context.cgContext
            
            // Draw "Spectrum" text in official navy color
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left
            
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 42, weight: .bold),
                .foregroundColor: spectrumNavy,
                .paragraphStyle: paragraphStyle
            ]
            
            let spectrumText = "Spectrum"
            let textSize = spectrumText.size(withAttributes: textAttributes)
            // Center the entire logo within the canvas
            let totalLogoWidth = textSize.width + 40 // text + spacing + triangle
            let startX = (logoSize.width - totalLogoWidth) / 2
            
            let textRect = CGRect(
                x: startX,
                y: (logoSize.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            spectrumText.draw(in: textRect, withAttributes: textAttributes)
            
            // Draw the blue triangle arrow pointing right
            let triangleStartX = startX + textSize.width + 16
            let triangleCenterY = logoSize.height / 2
            let triangleHeight: CGFloat = 28
            let triangleWidth: CGFloat = 24
            
            cgContext.setFillColor(spectrumBlue.cgColor)
            cgContext.beginPath()
            cgContext.move(to: CGPoint(x: triangleStartX, y: triangleCenterY - triangleHeight/2))
            cgContext.addLine(to: CGPoint(x: triangleStartX + triangleWidth, y: triangleCenterY))
            cgContext.addLine(to: CGPoint(x: triangleStartX, y: triangleCenterY + triangleHeight/2))
            cgContext.closePath()
            cgContext.fillPath()
        }
        
        return logoImage
    }
    
    private func checkDeviceCompatibility() {
        // In simulator, bypass RoomPlan support check for UI testing
        #if targetEnvironment(simulator)
        print("🎭 Running in simulator - bypassing RoomPlan compatibility check")
        #else
        if !RoomCaptureSession.isSupported {
            print("⚠️ Device doesn't support RoomCapture, but continuing anyway")
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
        // Continue even if RoomCapture isn't supported - the view controller will show a placeholder
        print("📱 Transitioning to RoomCaptureViewController")
        #endif
        
        // Create RoomCaptureViewController directly without navigation controller
        if let roomCaptureVC = self.storyboard?.instantiateViewController(
            withIdentifier: "RoomCaptureViewController") as? RoomCaptureViewController {
            roomCaptureVC.modalPresentationStyle = .fullScreen
            present(roomCaptureVC, animated: true)
        }
    }
    
    private func startScanAutomatically() {
        // Continue even if not supported - the RoomCaptureViewController will handle it
        print("📱 Starting scan (will show placeholder if unsupported)")
        
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
        // Continue even if not supported - the RoomCaptureViewController will handle it
        
        if let viewController = self.storyboard?.instantiateViewController(
            withIdentifier: "RoomCaptureViewNavigationController") {
            viewController.modalPresentationStyle = .fullScreen
            present(viewController, animated: true)
        }
    }
}
