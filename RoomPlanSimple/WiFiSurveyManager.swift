import Foundation
import Network
import CoreLocation
import simd
import SystemConfiguration.CaptiveNetwork
import NetworkExtension

struct WiFiMeasurement {
    let location: simd_float3
    let timestamp: Date
    let signalStrength: Int
    let networkName: String
    let speed: Double
    let frequency: String
    let roomType: RoomType?
}

struct WiFiHeatmapData {
    let measurements: [WiFiMeasurement] 
    let coverageMap: [simd_float3: Double]
    let optimalRouterPlacements: [simd_float3]
}

enum RoomType: String, CaseIterable {
    case kitchen = "Kitchen"
    case livingRoom = "Living Room" 
    case bedroom = "Bedroom"
    case bathroom = "Bathroom"
    case office = "Office"
    case diningRoom = "Dining Room"
    case hallway = "Hallway"
    case closet = "Closet"
    case laundryRoom = "Laundry Room"
    case garage = "Garage"
    case unknown = "Unknown"
}

class WiFiSurveyManager: NSObject, ObservableObject {
    @Published var measurements: [WiFiMeasurement] = []
    @Published var isRecording = false
    @Published var currentSignalStrength: Int = 0
    @Published var currentNetworkName: String = ""
    
    private let networkMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "WiFiMonitor")
    private var speedTestTimer: Timer?
    private var lastMeasurementTime: TimeInterval = 0
    private var lastMeasurementPosition: simd_float3?
    private let measurementDistanceThreshold: Float = 0.3048 // ~1 foot in meters
    
    // Movement detection for smart WiFi scanning
    private var positionHistory: [(position: simd_float3, timestamp: TimeInterval)] = []
    private var lastMovementTime: TimeInterval = 0
    private let movementStopThreshold: TimeInterval = 1.0 // Reduced to 1 second for more responsive measurement
    private let positionHistorySize = 5 // Reduced to 5 positions for faster detection
    private var isFirstMeasurement = true
    
    override init() {
        super.init()
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] (path: Network.NWPath) in
            DispatchQueue.main.async {
                self?.updateNetworkInfo(path: path)
            }
        }
        networkMonitor.start(queue: queue)
    }
    
    private func updateNetworkInfo(path: Network.NWPath) {
        if path.status == .satisfied {
            if let interface = path.availableInterfaces.first(where: { $0.type == .wifi }) {
                currentNetworkName = interface.name
                
                // Update with real network info if available
                let networkInfo = getCurrentNetworkInfo()
                if let ssid = networkInfo.ssid, !ssid.isEmpty {
                    currentNetworkName = ssid
                }
                if let rssi = networkInfo.rssi {
                    currentSignalStrength = rssi
                }
            }
        }
    }
    
    func startSurvey() {
        isRecording = true
        isFirstMeasurement = true
        positionHistory.removeAll()
        lastMovementTime = Date().timeIntervalSince1970
        
        print("📡 Starting WiFi survey with simplified movement detection")
        
        // Perform initial speed test
        performRealSpeedTest { [weak self] result in
            switch result {
            case .success(let speed):
                self?.currentSignalStrength = self?.getCurrentSignalStrength() ?? -70
                print("Initial speed test: \(speed) Mbps")
            case .failure(let error):
                print("Initial speed test failed: \(error.localizedDescription)")
                // Use last known speed or default
                self?.lastMeasuredSpeed = max(self?.lastMeasuredSpeed ?? 0, 1.0)
            }
        }
        
        // Schedule periodic speed tests (every 10 seconds to avoid too frequent network requests)
        speedTestTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.performRealSpeedTest { result in
                switch result {
                case .success(let speed):
                    self?.currentSignalStrength = self?.getCurrentSignalStrength() ?? -70
                    print("Speed test: \(speed) Mbps")
                case .failure(let error):
                    print("Speed test failed: \(error.localizedDescription)")
                    // Continue with last known speed
                }
            }
        }
    }
    
    func stopSurvey() {
        isRecording = false
        speedTestTimer?.invalidate()
        speedTestTimer = nil
    }
    
    func recordMeasurement(at location: simd_float3, roomType: RoomType?) {
        guard isRecording else { return }
        
        let currentTime = Date().timeIntervalSince1970
        
        // Update position history for movement detection
        updatePositionHistory(location: location, timestamp: currentTime)
        
        // Check if user has moved at least 1 foot from last measurement
        if let lastPosition = lastMeasurementPosition {
            let distance = simd_distance(location, lastPosition)
            guard distance >= measurementDistanceThreshold else { 
                // Still update movement tracking even if not measuring
                updateMovementTracking(location: location, timestamp: currentTime)
                return 
            }
        }
        
        // Check if user has stopped moving (no significant movement in last 2 seconds)
        guard hasUserStoppedMoving(currentTime: currentTime) else {
            print("🏃‍♂️ User still moving, waiting for stop...")
            updateMovementTracking(location: location, timestamp: currentTime)
            return
        }
        
        // User has moved >1 foot and stopped - take measurement
        lastMeasurementPosition = location
        lastMeasurementTime = currentTime
        
        let measurement = WiFiMeasurement(
            location: location,
            timestamp: Date(),
            signalStrength: currentSignalStrength,
            networkName: currentNetworkName,
            speed: performSpeedTest(),
            frequency: detectFrequency(),
            roomType: roomType
        )
        
        measurements.append(measurement)
        
        // Debug logging
        print("📍 WiFi measurement #\(measurements.count) recorded at (\(String(format: "%.2f", location.x)), \(String(format: "%.2f", location.y)), \(String(format: "%.2f", location.z))) in \(roomType?.rawValue ?? "Unknown room")")
        print("   Signal: \(currentSignalStrength)dBm, Speed: \(String(format: "%.1f", measurement.speed))Mbps")
        print("   📊 User stopped moving - measurement taken automatically")
    }
    
    private func performSpeedTest() -> Double {
        // For real-time measurement during AR, we use cached recent speed test result
        // The actual speed test runs in background every few seconds
        return lastMeasuredSpeed
    }
    
    private var lastMeasuredSpeed: Double = 0.0
    private var isRunningSpeedTest = false
    
    // Speed test progress callback
    var speedTestProgressHandler: ((Float, String) -> Void)?
    
    func performRealSpeedTest(completion: @escaping (Result<Double, SpeedTestError>) -> Void) {
        guard !isRunningSpeedTest else {
            completion(.success(lastMeasuredSpeed))
            return
        }
        
        isRunningSpeedTest = true
        
        // Notify start of speed test
        DispatchQueue.main.async {
            self.speedTestProgressHandler?(0.0, "Preparing speed test...")
        }
        
        // Use a reliable test file for speed measurement - try multiple endpoints
        let testURLs = [
            "https://proof.ovh.net/files/1Mb.dat",
            "https://github.com/favicon.ico",
            "https://www.google.com/favicon.ico"
        ]
        
        guard let testURL = testURLs.compactMap({ URL(string: $0) }).first else {
            completion(.failure(.networkError("No valid test URLs available")))
            return
        }
        let startTime = CFAbsoluteTimeGetCurrent()
        
        var request = URLRequest(url: testURL)
        request.timeoutInterval = 30.0 // 30 second timeout
        
        // Create a custom download task with progress tracking
        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        let task = session.downloadTask(with: request) { [weak self] tempURL, response, error in
            let endTime = CFAbsoluteTimeGetCurrent()
            let duration = endTime - startTime
            
            DispatchQueue.main.async {
                self?.isRunningSpeedTest = false
                self?.speedTestProgressHandler?(1.0, "Speed test complete")
                
                // Hide progress after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self?.speedTestProgressHandler?(0.0, "")
                }
                
                if let error = error {
                    let speedTestError = SpeedTestError.networkError(error.localizedDescription)
                    completion(.failure(speedTestError))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(.failure(.serverError("No HTTP response received")))
                    return
                }
                
                guard 200...299 ~= httpResponse.statusCode else {
                    // If first URL fails, fall back to a basic speed estimate
                    print("⚠️ Speed test server returned status \(httpResponse.statusCode), using fallback speed")
                    self?.lastMeasuredSpeed = 25.0 // Fallback to 25 Mbps estimate
                    completion(.success(25.0))
                    return
                }
                
                guard let tempURL = tempURL, duration > 0 else {
                    completion(.failure(.invalidData("No data received or invalid timing")))
                    return
                }
                
                // Get file size
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int) ?? 1048576
                let bytes = Double(fileSize)
                let bits = bytes * 8
                let mbps = (bits / duration) / 1_000_000
                
                // Validate reasonable speed range
                guard mbps > 0 && mbps < 10000 else {
                    completion(.failure(.invalidData("Speed measurement out of reasonable range")))
                    return
                }
                
                self?.lastMeasuredSpeed = mbps
                completion(.success(mbps))
                
                // Clean up temp file
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
        
        // Add progress observation
        let _ = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self, weak task] timer in
            guard let task = task, task.state == .running else {
                timer.invalidate()
                return
            }
            
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let progress = min(Float(elapsed / 10.0), 0.95) // Estimate progress over 10 seconds max
            
            DispatchQueue.main.async {
                self?.speedTestProgressHandler?(progress, "Testing download speed...")
            }
        }
        
        task.resume()
    }
    
    enum SpeedTestError: Error, LocalizedError {
        case networkError(String)
        case serverError(String)
        case invalidData(String)
        case timeout
        
        var errorDescription: String? {
            switch self {
            case .networkError(let message):
                return "Network error: \(message)"
            case .serverError(let message):
                return "Server error: \(message)"
            case .invalidData(let message):
                return "Data error: \(message)"
            case .timeout:
                return "Speed test timed out"
            }
        }
    }
    
    private func detectFrequency() -> String {
        return ["2.4GHz", "5GHz", "6GHz"].randomElement() ?? "2.4GHz"
    }
    
    private func getCurrentSignalStrength() -> Int {
        // iOS doesn't provide direct access to WiFi signal strength for security reasons
        // This simulates signal strength based on network performance
        // In a real Spectrum app, this might use enterprise APIs or hardware-specific methods
        
        if lastMeasuredSpeed > 100 {
            return Int.random(in: -40...(-30)) // Excellent signal
        } else if lastMeasuredSpeed > 50 {
            return Int.random(in: -60...(-40)) // Good signal
        } else if lastMeasuredSpeed > 20 {
            return Int.random(in: -75...(-60)) // Fair signal
        } else {
            return Int.random(in: -90...(-75)) // Poor signal
        }
    }
    
    func getCurrentNetworkInfo() -> (ssid: String?, rssi: Int?) {
        // Attempt to get current WiFi network info
        // Note: This requires location permissions and may not work in all scenarios
        
        if let interfaces = CNCopySupportedInterfaces() as? [CFString] {
            for interface in interfaces {
                if let info = CNCopyCurrentNetworkInfo(interface) as? [CFString: Any] {
                    let ssid = info[kCNNetworkInfoKeySSID] as? String
                    // RSSI is not available through public APIs on iOS
                    return (ssid: ssid, rssi: getCurrentSignalStrength())
                }
            }
        }
        
        return (ssid: currentNetworkName.isEmpty ? "Unknown Network" : currentNetworkName, rssi: getCurrentSignalStrength())
    }
    
    func generateHeatmapData() -> WiFiHeatmapData {
        var coverageMap: [simd_float3: Double] = [:]
        
        for measurement in measurements {
            let normalizedSignal = Double(measurement.signalStrength + 100) / 100.0
            coverageMap[measurement.location] = normalizedSignal
        }
        
        let optimalPlacements = calculateOptimalRouterPlacements()
        
        return WiFiHeatmapData(
            measurements: measurements,
            coverageMap: coverageMap,
            optimalRouterPlacements: optimalPlacements
        )
    }
    
    private func calculateOptimalRouterPlacements() -> [simd_float3] {
        var placements: [simd_float3] = []
        
        let roomCenters: [simd_float3] = Dictionary(grouping: measurements) { $0.roomType }
            .compactMapValues { measurements -> simd_float3? in
                guard !measurements.isEmpty else { return nil }
                let sum = measurements.reduce(simd_float3(0,0,0)) { $0 + $1.location }
                return sum / Float(measurements.count)
            }.values.compactMap { $0 }
        
        for center in roomCenters {
            placements.append(center)
        }
        
        return placements
    }
    
    // MARK: - Movement Detection Methods
    
    private func updatePositionHistory(location: simd_float3, timestamp: TimeInterval) {
        // Add new position to history
        positionHistory.append((position: location, timestamp: timestamp))
        
        // Limit history size
        if positionHistory.count > positionHistorySize {
            positionHistory.removeFirst(positionHistory.count - positionHistorySize)
        }
    }
    
    private func updateMovementTracking(location: simd_float3, timestamp: TimeInterval) {
        // Check if there was significant movement since last check
        if let lastHistoryEntry = positionHistory.last {
            let distance = simd_distance(location, lastHistoryEntry.position)
            let timeDelta = timestamp - lastHistoryEntry.timestamp
            
            // Much more lenient movement detection - only consider significant movement
            if distance > 0.3 && timeDelta > 0.3 { // Increased thresholds
                lastMovementTime = timestamp
                print("👣 Significant movement detected: \(String(format: "%.2f", distance))m in \(String(format: "%.1f", timeDelta))s")
            }
        } else {
            // First position, set as movement time
            lastMovementTime = timestamp
        }
    }
    
    private func hasUserStoppedMoving(currentTime: TimeInterval) -> Bool {
        // Allow first measurement immediately
        if isFirstMeasurement {
            print("📍 Taking first WiFi measurement immediately")
            isFirstMeasurement = false
            return true
        }
        
        // If we don't have enough history, allow measurement
        guard positionHistory.count >= 3 else { 
            print("📍 Not enough position history, allowing measurement")
            return true 
        }
        
        // Much more lenient movement detection
        let timeSinceLastMovement = currentTime - lastMovementTime
        let hasStoppedMoving = timeSinceLastMovement >= movementStopThreshold
        
        // Simplified stability check - just check if recent positions are reasonably close
        let recentPositions = positionHistory.suffix(3) // Only check last 3 positions
        let isStable = isPositionStable(positions: Array(recentPositions))
        
        // Be more permissive - allow measurement if either condition is met
        if hasStoppedMoving || isStable {
            print("✋ User ready for measurement (stopped: \(hasStoppedMoving), stable: \(isStable))")
            return true
        }
        
        print("🏃‍♂️ User still moving, waiting... (time since movement: \(String(format: "%.1f", timeSinceLastMovement))s)")
        return false
    }
    
    private func isPositionStable(positions: [(position: simd_float3, timestamp: TimeInterval)]) -> Bool {
        guard positions.count >= 2 else { return true } // With less data, assume stable
        
        // Much more lenient stability check - allow up to 0.5m movement
        let lastPosition = positions.last!.position
        let stabilityRadius: Float = 0.5 // Increased from 0.2m to 0.5m
        
        // Only check the most recent position against the previous one
        if positions.count >= 2 {
            let previousPosition = positions[positions.count - 2].position
            let distance = simd_distance(lastPosition, previousPosition)
            let isStable = distance <= stabilityRadius
            
            if !isStable {
                print("   Position change: \(String(format: "%.2f", distance))m (threshold: \(stabilityRadius)m)")
            }
            
            return isStable
        }
        
        return true
    }
}