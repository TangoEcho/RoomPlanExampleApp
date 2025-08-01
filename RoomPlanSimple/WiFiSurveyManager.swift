import Foundation
import Network
import CoreLocation
import simd

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
    
    override init() {
        super.init()
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateNetworkInfo(path: path)
            }
        }
        networkMonitor.start(queue: queue)
    }
    
    private func updateNetworkInfo(path: NWPath) {
        if path.status == .satisfied {
            if let interface = path.availableInterfaces.first(where: { $0.type == .wifi }) {
                currentNetworkName = interface.name
            }
        }
    }
    
    func startSurvey() {
        isRecording = true
        speedTestTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            _ = self?.performSpeedTest()
        }
    }
    
    func stopSurvey() {
        isRecording = false
        speedTestTimer?.invalidate()
        speedTestTimer = nil
    }
    
    func recordMeasurement(at location: simd_float3, roomType: RoomType?) {
        guard isRecording else { return }
        
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
    }
    
    private func performSpeedTest() -> Double {
        return Double.random(in: 10...300)
    }
    
    private func detectFrequency() -> String {
        return ["2.4GHz", "5GHz", "6GHz"].randomElement() ?? "2.4GHz"
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
}