import Foundation

/// Centralized runtime config flags for feature toggles and environment settings
enum AppConfig {
    /// Enable simulator/demo behaviors and mock devices
    static let simulationMode: Bool = true
    
    /// Enable Plume integration features (simulation or real depending on simulationMode)
    static let enablePlumeIntegration: Bool = true
    
    /// Enable background network data collection during surveys
    static let enableNetworkDataByDefault: Bool = true
    
    /// Enable periodic speed tests during surveys
    static let enableSpeedTests: Bool = true
    
    /// Use deprecated CaptiveNetwork APIs for SSID/BSSID (will be ignored if not entitled)
    static let useCaptiveNetworkAPIs: Bool = false

    /// Auto-launch demo floor plan on unsupported devices (for demos only)
    static let autoLaunchDemoOnUnsupportedDevices: Bool = false
}


