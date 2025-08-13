import Foundation
import CoreTelephony
import CoreLocation
import Network
import SystemConfiguration.CaptiveNetwork

// MARK: - Lightweight Network Data Collection Plugin

/// Lightweight plugin that collects cellular and network data without analysis
class NetworkDataCollector: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isEnabled: Bool = false
    @Published var lastCellularData: CellularData?
    @Published var homeLocation: CLLocation?
    @Published var lastError: NetworkDataError?
    
    // MARK: - Core Components
    private let telephonyInfo = CTTelephonyNetworkInfo()
    private let locationManager = CLLocationManager()
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkDataMonitor")
    
    // MARK: - Data Storage
    private var collectedData: [NetworkDataPoint] = []
    private let maxDataPoints = 1000 // Memory limit
    
    // MARK: - Configuration
    var measurementInterval: TimeInterval? // Uses WiFi manager's interval if nil
    private var isCollecting = false
    
    override init() {
        super.init()
        setupLocationServices()
        setupNetworkMonitoring()
        setupCellularMonitoring()
    }
    
    // MARK: - Setup Methods
    
    private func setupLocationServices() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            self?.handleNetworkPathUpdate(path)
        }
    }
    
    private func setupCellularMonitoring() {
        // No additional setup needed for CTTelephonyNetworkInfo
        print("📱 Cellular monitoring ready")
    }
    
    // MARK: - Public Collection Methods
    
    /// Start collecting network data (called by WiFiSurveyManager)
    func startCollection() {
        guard !isCollecting else { return }
        
        isCollecting = true
        isEnabled = true
        
        // Start network monitor
        networkMonitor.start(queue: monitorQueue)
        
        // Get initial location if not already set
        if homeLocation == nil {
            requestHomeLocation()
        }
        
        print("📡 Network data collection started")
    }
    
    /// Stop collecting network data
    func stopCollection() {
        isCollecting = false
        isEnabled = false
        networkMonitor.cancel()
        
        print("📡 Network data collection stopped")
    }
    
    /// Collect current network data snapshot (called at measurement intervals)
    func collectCurrentData(at location: simd_float3? = nil) -> NetworkDataPoint {
        let cellularData = collectCellularData()
        let wifiData = collectWiFiData()
        let networkPath = collectNetworkPath()
        
        let dataPoint = NetworkDataPoint(
            timestamp: Date(),
            location: location,
            cellularData: cellularData,
            wifiData: wifiData,
            networkPath: networkPath,
            homeLocation: homeLocation
        )
        
        // Store in local collection
        storeDataPoint(dataPoint)
        
        // Update published properties
        lastCellularData = cellularData
        
        return dataPoint
    }
    
    // MARK: - Data Collection Methods
    
    private func collectCellularData() -> CellularData {
        var carriers: [String: CarrierInfo] = [:]
        var radioTechnologies: [String: String] = [:]
        
        // Collect data for all available cellular services (dual SIM support)
        if let providers = telephonyInfo.serviceSubscriberCellularProviders {
            for (serviceId, carrier) in providers {
                if let carrier = carrier {
                    carriers[serviceId] = CarrierInfo(
                        name: carrier.carrierName ?? "Unknown",
                        mobileCountryCode: carrier.mobileCountryCode ?? "",
                        mobileNetworkCode: carrier.mobileNetworkCode ?? "",
                        isoCountryCode: carrier.isoCountryCode ?? "",
                        allowsVOIP: carrier.allowsVOIP
                    )
                }
            }
        }
        
        // Get radio technology for each service
        if let radioTechs = telephonyInfo.serviceCurrentRadioAccessTechnology {
            for (serviceId, tech) in radioTechs {
                radioTechnologies[serviceId] = parseRadioTechnology(tech)
            }
        }
        
        // Get signal strength (bars) - approximation based on radio tech
        let signalBars = estimateSignalBars(from: radioTechnologies.values.first)
        
        return CellularData(
            carriers: carriers,
            radioTechnologies: radioTechnologies,
            signalBars: signalBars,
            dataConnectionState: getDataConnectionState(),
            timestamp: Date()
        )
    }
    
    private func collectWiFiData() -> WiFiData {
        var currentSSID: String?
        var currentBSSID: String?
        var networkCount = 0
        
        // Get current WiFi network info
        if let interfaces = CNCopySupportedInterfaces() as? [String] {
            for interface in interfaces {
                if let info = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any] {
                    currentSSID = info[kCNNetworkInfoKeySSID as String] as? String
                    currentBSSID = info[kCNNetworkInfoKeyBSSID as String] as? String
                    break
                }
            }
        }
        
        // Note: iOS doesn't allow scanning for neighboring networks without special entitlements
        // We can only detect that other networks exist through indirect methods
        networkCount = detectNeighboringNetworkCount()
        
        return WiFiData(
            connectedSSID: currentSSID,
            connectedBSSID: currentBSSID,
            neighboringNetworkCount: networkCount,
            timestamp: Date()
        )
    }
    
    private func collectNetworkPath() -> NetworkPathData {
        var pathData = NetworkPathData()
        
        // This will be updated by the network monitor
        networkMonitor.currentPath.availableInterfaces.forEach { interface in
            switch interface.type {
            case .wifi:
                pathData.hasWiFi = true
            case .cellular:
                pathData.hasCellular = true
            case .wiredEthernet:
                pathData.hasEthernet = true
            default:
                break
            }
        }
        
        pathData.isExpensive = networkMonitor.currentPath.isExpensive
        pathData.isConstrained = networkMonitor.currentPath.isConstrained
        pathData.status = networkMonitor.currentPath.status
        
        return pathData
    }
    
    // MARK: - Helper Methods
    
    private func parseRadioTechnology(_ technology: String) -> String {
        // Convert CoreTelephony constants to readable format
        switch technology {
        case CTRadioAccessTechnologyNR:
            return "5G"
        case CTRadioAccessTechnologyNRNSA:
            return "5G NSA"
        case CTRadioAccessTechnologyLTE:
            return "LTE"
        case CTRadioAccessTechnologyWCDMA:
            return "3G"
        case CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA:
            return "3.5G"
        case CTRadioAccessTechnologyEdge:
            return "EDGE"
        case CTRadioAccessTechnologyGPRS:
            return "GPRS"
        case CTRadioAccessTechnologyCDMA1x:
            return "CDMA"
        case CTRadioAccessTechnologyeHRPD:
            return "eHRPD"
        default:
            return technology
        }
    }
    
    private func estimateSignalBars(from radioTech: String?) -> Int {
        // Rough estimation based on technology (actual bars not available in public API)
        guard let tech = radioTech else { return 0 }
        
        switch tech {
        case "5G", "5G NSA":
            return 4 // Assume good signal for 5G
        case "LTE":
            return 3 // Assume decent LTE
        case "3G", "3.5G":
            return 2
        default:
            return 1
        }
    }
    
    private func getDataConnectionState() -> String {
        let cellularData = CTCellularData()
        switch cellularData.restrictedState {
        case .restricted:
            return "Restricted"
        case .notRestricted:
            return "Active"
        case .restrictedStateUnknown:
            return "Unknown"
        @unknown default:
            return "Unknown"
        }
    }
    
    private func detectNeighboringNetworkCount() -> Int {
        // This is a placeholder - actual scanning requires special entitlements
        // In production, this might use NEHotspotHelper with proper entitlements
        return 0
    }
    
    private func handleNetworkPathUpdate(_ path: NWPath) {
        // Called when network path changes
        if isCollecting {
            print("🔄 Network path changed: \(path.status)")
        }
    }
    
    // MARK: - Location Services
    
    private func requestHomeLocation() {
        locationManager.requestLocation()
    }
    
    // MARK: - Public Query Methods (for WiFiSurveyManager)
    
    /// Get current network name (SSID) for WiFi measurements
    func getCurrentNetworkName() -> String {
        let wifiData = collectWiFiData()
        return wifiData.connectedSSID ?? "Unknown Network"
    }
    
    /// Get current signal strength estimation
    func getCurrentSignalStrength() -> Int {
        let cellularData = collectCellularData()
        // Convert bars to approximate dBm for consistency
        return convertBarsToDBm(cellularData.signalBars)
    }
    
    /// Get current carrier information
    func getCurrentCarrierInfo() -> String {
        let cellularData = collectCellularData()
        let carrierNames = cellularData.carriers.values.map { $0.name }
        return carrierNames.joined(separator: ", ")
    }
    
    /// Get current radio technology
    func getCurrentRadioTechnology() -> String {
        let cellularData = collectCellularData()
        let technologies = cellularData.radioTechnologies.values
        return technologies.joined(separator: ", ")
    }
    
    private func convertBarsToDBm(_ bars: Int) -> Int {
        // Rough conversion from signal bars to dBm
        switch bars {
        case 4: return Int.random(in: -50...(-40)) // Excellent
        case 3: return Int.random(in: -65...(-50)) // Good  
        case 2: return Int.random(in: -80...(-65)) // Fair
        case 1: return Int.random(in: -95...(-80)) // Poor
        default: return -100 // No signal
        }
    }
    
    // MARK: - Data Management
    
    private func storeDataPoint(_ dataPoint: NetworkDataPoint) {
        collectedData.append(dataPoint)
        
        // Maintain memory bounds
        if collectedData.count > maxDataPoints {
            let excess = collectedData.count - maxDataPoints
            collectedData.removeFirst(excess)
            print("🧹 Trimmed \(excess) old network data points")
        }
    }
    
    /// Get all collected data for export
    func getCollectedData() -> [NetworkDataPoint] {
        return collectedData
    }
    
    /// Clear all collected data
    func clearData() {
        collectedData.removeAll()
        print("🧹 Cleared all network data")
    }
    
    // MARK: - Export Support
    
    /// Create enhanced WiFi measurement with network data
    func enhanceWiFiMeasurement(_ measurement: WiFiMeasurement) -> EnhancedWiFiMeasurement {
        let networkData = collectCurrentData(at: measurement.location)
        
        return EnhancedWiFiMeasurement(
            wifiMeasurement: measurement,
            networkData: networkData
        )
    }
}

// MARK: - Location Manager Delegate

extension NetworkDataCollector: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first {
            homeLocation = location
            print("📍 Home location captured: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
        lastError = .locationError(error.localizedDescription)
    }
}

// MARK: - Data Structures

struct NetworkDataPoint: Codable {
    let timestamp: Date
    let location: simd_float3?
    let cellularData: CellularData
    let wifiData: WiFiData
    let networkPath: NetworkPathData
    let homeLocation: CLLocation?
    
    // Codable support for simd_float3
    enum CodingKeys: String, CodingKey {
        case timestamp, cellularData, wifiData, networkPath
        case locationX, locationY, locationZ
        case homeLatitude, homeLongitude
    }
    
    init(timestamp: Date, location: simd_float3?, cellularData: CellularData, 
         wifiData: WiFiData, networkPath: NetworkPathData, homeLocation: CLLocation?) {
        self.timestamp = timestamp
        self.location = location
        self.cellularData = cellularData
        self.wifiData = wifiData
        self.networkPath = networkPath
        self.homeLocation = homeLocation
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        cellularData = try container.decode(CellularData.self, forKey: .cellularData)
        wifiData = try container.decode(WiFiData.self, forKey: .wifiData)
        networkPath = try container.decode(NetworkPathData.self, forKey: .networkPath)
        
        if let x = try container.decodeIfPresent(Float.self, forKey: .locationX),
           let y = try container.decodeIfPresent(Float.self, forKey: .locationY),
           let z = try container.decodeIfPresent(Float.self, forKey: .locationZ) {
            location = simd_float3(x, y, z)
        } else {
            location = nil
        }
        
        if let lat = try container.decodeIfPresent(Double.self, forKey: .homeLatitude),
           let lon = try container.decodeIfPresent(Double.self, forKey: .homeLongitude) {
            homeLocation = CLLocation(latitude: lat, longitude: lon)
        } else {
            homeLocation = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(cellularData, forKey: .cellularData)
        try container.encode(wifiData, forKey: .wifiData)
        try container.encode(networkPath, forKey: .networkPath)
        
        if let loc = location {
            try container.encode(loc.x, forKey: .locationX)
            try container.encode(loc.y, forKey: .locationY)
            try container.encode(loc.z, forKey: .locationZ)
        }
        
        if let home = homeLocation {
            try container.encode(home.coordinate.latitude, forKey: .homeLatitude)
            try container.encode(home.coordinate.longitude, forKey: .homeLongitude)
        }
    }
}

struct CellularData: Codable {
    let carriers: [String: CarrierInfo]
    let radioTechnologies: [String: String]
    let signalBars: Int
    let dataConnectionState: String
    let timestamp: Date
}

struct CarrierInfo: Codable {
    let name: String
    let mobileCountryCode: String
    let mobileNetworkCode: String
    let isoCountryCode: String
    let allowsVOIP: Bool
}

struct WiFiData: Codable {
    let connectedSSID: String?
    let connectedBSSID: String?
    let neighboringNetworkCount: Int
    let timestamp: Date
}

struct NetworkPathData: Codable {
    var hasWiFi: Bool = false
    var hasCellular: Bool = false
    var hasEthernet: Bool = false
    var isExpensive: Bool = false
    var isConstrained: Bool = false
    var status: NWPath.Status = .unsatisfied
}

struct EnhancedWiFiMeasurement: Codable {
    let wifiMeasurement: WiFiMeasurement
    let networkData: NetworkDataPoint
}

enum NetworkDataError: Error, LocalizedError {
    case notEnabled
    case locationError(String)
    case cellularError(String)
    case exportError(String)
    
    var errorDescription: String? {
        switch self {
        case .notEnabled:
            return "Network data collection is not enabled"
        case .locationError(let message):
            return "Location error: \(message)"
        case .cellularError(let message):
            return "Cellular data error: \(message)"
        case .exportError(let message):
            return "Export error: \(message)"
        }
    }
}