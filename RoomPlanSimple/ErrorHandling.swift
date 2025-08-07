import Foundation
import RoomPlan
import ARKit

// MARK: - Error Definitions

enum RoomPlanError: LocalizedError {
    case roomPlanNotSupported
    case cameraPermissionDenied
    case arSessionFailed(underlying: Error)
    case captureSessionFailed(underlying: Error)
    case roomDataCorrupted
    case exportFailed(reason: String)
    case insufficientData
    
    var errorDescription: String? {
        switch self {
        case .roomPlanNotSupported:
            return "RoomPlan is not supported on this device. Please use a device with an A12 Bionic chip or later."
        case .cameraPermissionDenied:
            return "Camera access is required for room scanning. Please enable camera permissions in Settings."
        case .arSessionFailed(let error):
            return "AR session failed: \(error.localizedDescription)"
        case .captureSessionFailed(let error):
            return "Room capture failed: \(error.localizedDescription)"
        case .roomDataCorrupted:
            return "Room data appears to be corrupted and cannot be processed."
        case .exportFailed(let reason):
            return "Failed to export room data: \(reason)"
        case .insufficientData:
            return "Insufficient room data. Please scan more of the room before proceeding."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .roomPlanNotSupported:
            return "Please use a compatible device with LiDAR scanner for best results."
        case .cameraPermissionDenied:
            return "Go to Settings > Privacy & Security > Camera and enable access for this app."
        case .arSessionFailed, .captureSessionFailed:
            return "Try restarting the app or rebooting your device."
        case .roomDataCorrupted:
            return "Please start a new room scan."
        case .exportFailed:
            return "Check available storage space and try again."
        case .insufficientData:
            return "Continue scanning the room to collect more data."
        }
    }
}

enum WiFiAnalysisError: LocalizedError {
    case networkNotAvailable
    case speedTestFailed(underlying: Error)
    case insufficientMeasurements
    case locationAccessDenied
    case analysisTimeout
    
    var errorDescription: String? {
        switch self {
        case .networkNotAvailable:
            return "No WiFi network available for analysis."
        case .speedTestFailed(let error):
            return "Speed test failed: \(error.localizedDescription)"
        case .insufficientMeasurements:
            return "Not enough measurements for reliable analysis."
        case .locationAccessDenied:
            return "Location access is required for accurate WiFi positioning."
        case .analysisTimeout:
            return "WiFi analysis timed out."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .networkNotAvailable:
            return "Please connect to a WiFi network and try again."
        case .speedTestFailed:
            return "Check your internet connection and try again."
        case .insufficientMeasurements:
            return "Take more WiFi measurements by moving around the room."
        case .locationAccessDenied:
            return "Enable location permissions in Settings for accurate positioning."
        case .analysisTimeout:
            return "Try the analysis again with a stable internet connection."
        }
    }
}

enum ARVisualizationError: LocalizedError {
    case arNotSupported
    case worldTrackingFailed
    case nodeCreationFailed
    case coordinateTransformFailed
    
    var errorDescription: String? {
        switch self {
        case .arNotSupported:
            return "AR features are not supported on this device."
        case .worldTrackingFailed:
            return "AR world tracking failed. Unable to position virtual objects."
        case .nodeCreationFailed:
            return "Failed to create AR visualization nodes."
        case .coordinateTransformFailed:
            return "Failed to transform coordinates between AR and room coordinates."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .arNotSupported:
            return "AR features require iOS 11.0 or later on a compatible device."
        case .worldTrackingFailed:
            return "Try moving to a well-lit area with distinct visual features."
        case .nodeCreationFailed:
            return "Restart the AR session and try again."
        case .coordinateTransformFailed:
            return "Ensure the room scan and AR session are using the same coordinate system."
        }
    }
}

// MARK: - Error Handler Protocol

protocol ErrorHandling {
    func handleError(_ error: Error, context: String?)
    func showError(_ error: LocalizedError, allowRetry: Bool, retryAction: (() -> Void)?)
    func showWarning(_ message: String, context: String?)
}

// MARK: - Error Recovery Actions

enum ErrorRecoveryAction {
    case retry
    case restart
    case skip
    case cancel
    case openSettings
    
    var title: String {
        switch self {
        case .retry: return "Retry"
        case .restart: return "Restart"
        case .skip: return "Skip"
        case .cancel: return "Cancel"
        case .openSettings: return "Open Settings"
        }
    }
}

// MARK: - Error Handler Implementation

final class ErrorHandler: ErrorHandling {
    static let shared = ErrorHandler()
    
    private weak var presentingViewController: UIViewController?
    
    private init() {}
    
    func configure(presentingViewController: UIViewController) {
        self.presentingViewController = presentingViewController
    }
    
    func handleError(_ error: Error, context: String? = nil) {
        print("❌ Error [\(context ?? "Unknown")]: \(error.localizedDescription)")
        
        // Log detailed error information for debugging
        logDetailedError(error, context: context)
        
        // Convert to appropriate typed error if possible
        let typedError: LocalizedError
        if let localizedError = error as? LocalizedError {
            typedError = localizedError
        } else {
            typedError = GenericError(underlying: error)
        }
        
        // Determine recovery actions based on error type
        let recoveryActions = determineRecoveryActions(for: typedError)
        
        // Show error with recovery options
        showError(typedError, recoveryActions: recoveryActions)
    }
    
    func showError(_ error: LocalizedError, allowRetry: Bool = false, retryAction: (() -> Void)? = nil) {
        let recoveryActions: [ErrorRecoveryAction] = allowRetry ? [.retry, .cancel] : [.cancel]
        showError(error, recoveryActions: recoveryActions, retryAction: retryAction)
    }
    
    func showWarning(_ message: String, context: String? = nil) {
        print("⚠️ Warning [\(context ?? "Unknown")]: \(message)")
        
        DispatchQueue.main.async { [weak self] in
            self?.presentAlert(
                title: "Warning",
                message: message,
                actions: [("OK", .cancel, nil)]
            )
        }
    }
    
    private func showError(_ error: LocalizedError, recoveryActions: [ErrorRecoveryAction], retryAction: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            let title = "Error"
            let message = error.localizedDescription + (error.recoverySuggestion.map { "\n\n\($0)" } ?? "")
            
            var actions: [(title: String, style: UIAlertAction.Style, handler: (() -> Void)?)] = []
            
            for action in recoveryActions {
                let handler: (() -> Void)?
                
                switch action {
                case .retry:
                    handler = retryAction
                case .openSettings:
                    handler = {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    }
                case .restart:
                    handler = {
                        // Could implement app restart logic here
                        print("🔄 App restart requested")
                    }
                default:
                    handler = nil
                }
                
                let style: UIAlertAction.Style = action == .cancel ? .cancel : .default
                actions.append((action.title, style, handler))
            }
            
            self?.presentAlert(title: title, message: message, actions: actions)
        }
    }
    
    private func presentAlert(title: String, message: String, actions: [(title: String, style: UIAlertAction.Style, handler: (() -> Void)?)]) {
        guard let presentingViewController = presentingViewController else {
            print("❌ No presenting view controller available for error alert")
            return
        }
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        for (title, style, handler) in actions {
            let action = UIAlertAction(title: title, style: style) { _ in
                handler?()
            }
            alert.addAction(action)
        }
        
        presentingViewController.present(alert, animated: true)
    }
    
    private func determineRecoveryActions(for error: LocalizedError) -> [ErrorRecoveryAction] {
        switch error {
        case is RoomPlanError:
            return determineRoomPlanRecoveryActions(error as! RoomPlanError)
        case is WiFiAnalysisError:
            return determineWiFiRecoveryActions(error as! WiFiAnalysisError)
        case is ARVisualizationError:
            return determineARRecoveryActions(error as! ARVisualizationError)
        default:
            return [.retry, .cancel]
        }
    }
    
    private func determineRoomPlanRecoveryActions(_ error: RoomPlanError) -> [ErrorRecoveryAction] {
        switch error {
        case .roomPlanNotSupported:
            return [.cancel]
        case .cameraPermissionDenied:
            return [.openSettings, .cancel]
        case .arSessionFailed, .captureSessionFailed:
            return [.restart, .retry, .cancel]
        case .roomDataCorrupted:
            return [.restart, .cancel]
        case .exportFailed:
            return [.retry, .cancel]
        case .insufficientData:
            return [.skip, .cancel]
        }
    }
    
    private func determineWiFiRecoveryActions(_ error: WiFiAnalysisError) -> [ErrorRecoveryAction] {
        switch error {
        case .networkNotAvailable:
            return [.retry, .skip, .cancel]
        case .speedTestFailed:
            return [.retry, .skip, .cancel]
        case .insufficientMeasurements:
            return [.skip, .cancel]
        case .locationAccessDenied:
            return [.openSettings, .skip, .cancel]
        case .analysisTimeout:
            return [.retry, .cancel]
        }
    }
    
    private func determineARRecoveryActions(_ error: ARVisualizationError) -> [ErrorRecoveryAction] {
        switch error {
        case .arNotSupported:
            return [.skip, .cancel]
        case .worldTrackingFailed:
            return [.restart, .skip, .cancel]
        case .nodeCreationFailed:
            return [.retry, .skip, .cancel]
        case .coordinateTransformFailed:
            return [.restart, .skip, .cancel]
        }
    }
    
    private func logDetailedError(_ error: Error, context: String?) {
        var logMessage = "🔍 Detailed Error Log\n"
        logMessage += "Context: \(context ?? "Unknown")\n"
        logMessage += "Error Type: \(type(of: error))\n"
        logMessage += "Description: \(error.localizedDescription)\n"
        
        if let nsError = error as NSError? {
            logMessage += "Domain: \(nsError.domain)\n"
            logMessage += "Code: \(nsError.code)\n"
            logMessage += "UserInfo: \(nsError.userInfo)\n"
        }
        
        if let underlyingError = (error as NSError?)?.userInfo[NSUnderlyingErrorKey] as? Error {
            logMessage += "Underlying: \(underlyingError.localizedDescription)\n"
        }
        
        print(logMessage)
    }
}

// MARK: - Generic Error for Non-Typed Errors

struct GenericError: LocalizedError {
    let underlying: Error
    
    var errorDescription: String? {
        return underlying.localizedDescription
    }
    
    var recoverySuggestion: String? {
        return "Please try again or restart the app if the problem persists."
    }
}

// MARK: - Error Handling Extensions

extension Result {
    func handleError(with handler: ErrorHandler, context: String? = nil) {
        if case .failure(let error) = self {
            handler.handleError(error, context: context)
        }
    }
}

// MARK: - Async Error Handling Utilities

func handleAsyncError<T>(_ operation: @escaping () async throws -> T, 
                        errorHandler: ErrorHandler, 
                        context: String? = nil,
                        completion: @escaping (Result<T, Error>) -> Void) {
    Task {
        do {
            let result = try await operation()
            completion(.success(result))
        } catch {
            errorHandler.handleError(error, context: context)
            completion(.failure(error))
        }
    }
}