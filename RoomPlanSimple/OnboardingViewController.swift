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
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        let titleLabel = SpectrumBranding.createSpectrumLabel(text: "Spectrum", style: .title)
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: 48, weight: .bold)

        let subtitleLabel = SpectrumBranding.createSpectrumLabel(text: "WiFi Analyzer", style: .headline)
        subtitleLabel.textAlignment = .center
        subtitleLabel.font = UIFont.systemFont(ofSize: 24, weight: .medium)

        let newSessionButton = SpectrumBranding.createSpectrumButton(title: "Start New Session", style: .primary)
        newSessionButton.addTarget(self, action: #selector(startNewSessionTapped), for: .touchUpInside)
        newSessionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let loadButton = SpectrumBranding.createSpectrumButton(title: "Load Previous Session", style: .secondary)
        loadButton.addTarget(self, action: #selector(loadPreviousTapped), for: .touchUpInside)
        loadButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            subtitleLabel,
            createSpacer(height: 40),
            newSessionButton,
            loadButton
        ])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stackView)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 40),
            container.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40),

            stackView.topAnchor.constraint(equalTo: container.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
    
    private func createSpacer(height: CGFloat) -> UIView {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        return spacer
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
        // Do nothing; wait for user to select New or Load
    }
    
    private func transitionToRoomCapture() {
        #if !targetEnvironment(simulator)
        guard RoomCaptureSession.isSupported else {
            showUnsupportedDeviceAlert()
            return
        }
        #endif
        
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
    
    @objc private func startNewSessionTapped() {
        transitionToRoomCapture()
    }
    
    @objc private func loadPreviousTapped() {
        let list = SessionListViewController()
        let nav = UINavigationController(rootViewController: list)
        list.onSelect = { [weak self] saved in
            self?.presentSavedSession(saved)
        }
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }
    
    private func presentSavedSession(_ saved: SavedSession) {
        guard let roomCaptureVC = self.storyboard?.instantiateViewController(
            withIdentifier: "RoomCaptureViewController") as? RoomCaptureViewController else { return }
        roomCaptureVC.modalPresentationStyle = .fullScreen
        roomCaptureVC.applySavedSession(saved)
        present(roomCaptureVC, animated: true)
    }
}
