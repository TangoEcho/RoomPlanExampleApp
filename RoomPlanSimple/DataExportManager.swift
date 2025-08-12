import Foundation
import simd

// MARK: - Data Export Manager for Plume Integration Testing

class DataExportManager {
    
    // MARK: - Export Data Structures
    
    /// Complete export package containing all survey data
    struct SurveyDataExport: Codable {
        let metadata: ExportMetadata
        let roomData: RoomDataExport
        let measurements: [WiFiMeasurementExport]
        let simulatedPlumeData: [PlumeConnectionEvent]
        let exportTimestamp: Date
        let appVersion: String
        
        init(roomAnalyzer: RoomAnalyzer, wifiSurveyManager: WiFiSurveyManager) {
            self.metadata = ExportMetadata()
            self.roomData = RoomDataExport(from: roomAnalyzer)
            self.measurements = wifiSurveyManager.measurements.map { WiFiMeasurementExport(from: $0) }
            self.simulatedPlumeData = Self.generateMockPlumeData(from: wifiSurveyManager.measurements)
            self.exportTimestamp = Date()
            self.appVersion = "1.0.0-plume-integration"
        }
    }
    
    /// Export metadata for context
    struct ExportMetadata: Codable {
        let deviceModel: String
        let osVersion: String
        let exportFormat: String
        let purpose: String
        
        init() {
            self.deviceModel = UIDevice.current.model
            self.osVersion = UIDevice.current.systemVersion
            self.exportFormat = "plume-simulation-v1"
            self.purpose = "Real-world data for Plume API simulation testing"
        }
    }
    
    /// Room data export
    struct RoomDataExport: Codable {
        let rooms: [RoomExport]
        let totalArea: Float
        let scanQuality: Float
        
        init(from roomAnalyzer: RoomAnalyzer) {
            self.rooms = roomAnalyzer.identifiedRooms.map { RoomExport(from: $0) }
            self.totalArea = roomAnalyzer.identifiedRooms.map { $0.area }.reduce(0, +)
            self.scanQuality = roomAnalyzer.identifiedRooms.map { $0.confidence }.reduce(0, +) / Float(max(1, roomAnalyzer.identifiedRooms.count))
        }
        
        struct RoomExport: Codable {
            let type: String
            let area: Float
            let confidence: Float
            let center: LocationExport
            let bounds: [LocationExport]
            
            init(from room: RoomAnalyzer.IdentifiedRoom) {
                self.type = room.type.rawValue
                self.area = room.area
                self.confidence = room.confidence
                self.center = LocationExport(from: room.center)
                self.bounds = room.wallPoints.map { LocationExport(x: $0.x, y: 0, z: $0.y) }
            }
        }
    }
    
    /// WiFi measurement export compatible with Plume format expectations
    struct WiFiMeasurementExport: Codable {
        let location: LocationExport
        let timestamp: Date
        let timestampMillis: Int64
        let signalStrength: Int
        let networkName: String
        let frequency: String
        let speed: Double
        let roomType: String?
        let bandMeasurements: [BandMeasurementExport]
        
        // Additional fields for Plume compatibility
        let deviceMAC: String
        let bssid: String
        let channel: Int
        let snr: Float?
        let noise: Float?
        
        init(from measurement: WiFiMeasurement) {
            self.location = LocationExport(from: measurement.location)
            self.timestamp = measurement.timestamp
            self.timestampMillis = Int64(measurement.timestamp.timeIntervalSince1970 * 1000)
            self.signalStrength = measurement.signalStrength
            self.networkName = measurement.networkName
            self.frequency = measurement.frequency
            self.speed = measurement.speed
            self.roomType = measurement.roomType?.rawValue
            self.bandMeasurements = measurement.bandMeasurements.map { BandMeasurementExport(from: $0) }
            
            // Generate realistic mock values for Plume compatibility
            self.deviceMAC = Self.generateMockMAC()
            self.bssid = Self.generateMockBSSID()
            self.channel = Self.channelFromFrequency(measurement.frequency)
            self.snr = measurement.bandMeasurements.first?.snr
            self.noise = Self.estimateNoise(for: measurement.signalStrength)
        }
        
        static func generateMockMAC() -> String {
            let macComponents = (0..<6).map { _ in String(format: "%02x", Int.random(in: 0...255)) }
            return macComponents.joined(separator: ":")
        }
        
        static func generateMockBSSID() -> String {
            // BSSID format similar to MAC but for router identification
            let bssidComponents = (0..<6).map { _ in String(format: "%02x", Int.random(in: 0...255)) }
            return bssidComponents.joined(separator: ":")
        }
        
        static func channelFromFrequency(_ frequencyString: String) -> Int {
            if frequencyString.contains("2.4") {
                return Int.random(in: 1...11) // 2.4GHz channels
            } else if frequencyString.contains("5") {
                return [36, 40, 44, 48, 149, 153, 157, 161].randomElement() ?? 36 // 5GHz channels
            } else if frequencyString.contains("6") {
                return Int.random(in: 1...93) // 6GHz channels (simplified)
            }
            return 6 // Default channel
        }
        
        static func estimateNoise(for signalStrength: Int) -> Float {
            // Typical noise floor values
            return Float.random(in: -95...(-85))
        }
    }
    
    /// Band measurement export
    struct BandMeasurementExport: Codable {
        let band: String
        let signalStrength: Float
        let frequency: Double
        let snr: Float?
        let channelWidth: Int
        let speed: Float
        let utilization: Float?
        
        init(from bandMeasurement: BandMeasurement) {
            self.band = bandMeasurement.band.rawValue
            self.signalStrength = bandMeasurement.signalStrength
            self.frequency = bandMeasurement.frequency
            self.snr = bandMeasurement.snr
            self.channelWidth = bandMeasurement.channelWidth
            self.speed = bandMeasurement.speed
            self.utilization = bandMeasurement.utilization
        }
    }
    
    /// 3D location export
    struct LocationExport: Codable {
        let x: Float
        let y: Float
        let z: Float
        
        init(from location: simd_float3) {
            self.x = location.x
            self.y = location.y
            self.z = location.z
        }
        
        init(x: Float, y: Float, z: Float) {
            self.x = x
            self.y = y
            self.z = z
        }
    }
    
    // MARK: - Simulated Plume Data Generation
    
    /// Plume API connection event (simulated from real measurements)
    struct PlumeConnectionEvent: Codable {
        let eventId: String
        let timestamp: Date
        let timestampMillis: Int64
        let eventType: String // "connection", "disconnection", "band_change", "roam"
        let deviceMAC: String
        let connectedDevice: PlumeDeviceInfo
        let signalStrength: Int
        let band: String
        let channel: Int
        let location: LocationExport? // Inferred from measurement correlation
        let duration: TimeInterval?
        let reason: String?
        
        struct PlumeDeviceInfo: Codable {
            let deviceId: String
            let deviceType: String // "router", "extender", "pod"
            let model: String
            let firmwareVersion: String
            let location: String? // Room name or description
        }
    }
    
    /// Generate realistic Plume connection events from WiFi measurements
    static func generateMockPlumeData(from measurements: [WiFiMeasurement]) -> [PlumeConnectionEvent] {
        var events: [PlumeConnectionEvent] = []
        
        // Create mock devices (router + extenders)
        let devices = [
            PlumeConnectionEvent.PlumeDeviceInfo(
                deviceId: "plume-router-001",
                deviceType: "router",
                model: "Plume SuperPod",
                firmwareVersion: "3.2.1",
                location: "Living Room"
            ),
            PlumeConnectionEvent.PlumeDeviceInfo(
                deviceId: "plume-extender-001",
                deviceType: "extender", 
                model: "Plume Pod",
                firmwareVersion: "3.2.1",
                location: "Kitchen"
            ),
            PlumeConnectionEvent.PlumeDeviceInfo(
                deviceId: "plume-extender-002",
                deviceType: "extender",
                model: "Plume Pod", 
                firmwareVersion: "3.2.1",
                location: "Bedroom"
            )
        ]
        
        let clientMAC = WiFiMeasurementExport.generateMockMAC()
        var lastConnectedDevice = devices[0]
        var connectionStartTime = measurements.first?.timestamp ?? Date()
        
        for (index, measurement) in measurements.enumerated() {
            // Simulate device roaming based on signal strength and location
            let currentDevice = selectOptimalDevice(for: measurement, devices: devices)
            
            // Generate connection event if device changed
            if currentDevice.deviceId != lastConnectedDevice.deviceId {
                // Disconnection from previous device
                if index > 0 {
                    events.append(PlumeConnectionEvent(
                        eventId: UUID().uuidString,
                        timestamp: measurement.timestamp.addingTimeInterval(-1),
                        timestampMillis: Int64((measurement.timestamp.timeIntervalSince1970 - 1) * 1000),
                        eventType: "disconnection",
                        deviceMAC: clientMAC,
                        connectedDevice: lastConnectedDevice,
                        signalStrength: measurement.signalStrength,
                        band: measurement.frequency,
                        channel: WiFiMeasurementExport.channelFromFrequency(measurement.frequency),
                        location: LocationExport(from: measurement.location),
                        duration: measurement.timestamp.timeIntervalSince(connectionStartTime),
                        reason: "signal_quality"
                    ))
                }
                
                // Connection to new device
                events.append(PlumeConnectionEvent(
                    eventId: UUID().uuidString,
                    timestamp: measurement.timestamp,
                    timestampMillis: Int64(measurement.timestamp.timeIntervalSince1970 * 1000),
                    eventType: "connection",
                    deviceMAC: clientMAC,
                    connectedDevice: currentDevice,
                    signalStrength: measurement.signalStrength,
                    band: measurement.frequency,
                    channel: WiFiMeasurementExport.channelFromFrequency(measurement.frequency),
                    location: LocationExport(from: measurement.location),
                    duration: nil,
                    reason: "optimal_signal"
                ))
                
                lastConnectedDevice = currentDevice
                connectionStartTime = measurement.timestamp
            }
            
            // Generate band change events for multi-band measurements
            for bandMeasurement in measurement.bandMeasurements {
                if bandMeasurement.band.rawValue != measurement.frequency {
                    events.append(PlumeConnectionEvent(
                        eventId: UUID().uuidString,
                        timestamp: measurement.timestamp.addingTimeInterval(0.5),
                        timestampMillis: Int64((measurement.timestamp.timeIntervalSince1970 + 0.5) * 1000),
                        eventType: "band_change",
                        deviceMAC: clientMAC,
                        connectedDevice: currentDevice,
                        signalStrength: Int(bandMeasurement.signalStrength),
                        band: bandMeasurement.band.rawValue,
                        channel: WiFiMeasurementExport.channelFromFrequency(bandMeasurement.band.rawValue),
                        location: LocationExport(from: measurement.location),
                        duration: nil,
                        reason: "band_steering"
                    ))
                }
            }
        }
        
        return events.sorted { $0.timestamp < $1.timestamp }
    }
    
    /// Select optimal Plume device based on location and signal strength
    static func selectOptimalDevice(for measurement: WiFiMeasurement, devices: [PlumeConnectionEvent.PlumeDeviceInfo]) -> PlumeConnectionEvent.PlumeDeviceInfo {
        // Simple logic: stronger signal = closer to router, weaker = prefer extender
        if measurement.signalStrength > -60 {
            return devices.first { $0.deviceType == "router" } ?? devices[0]
        } else {
            return devices.first { $0.deviceType == "extender" } ?? devices[0]
        }
    }
    
    // MARK: - Export Functions
    
    /// Export survey data to JSON file
    func exportSurveyData(roomAnalyzer: RoomAnalyzer, wifiSurveyManager: WiFiSurveyManager) -> URL? {
        let exportData = SurveyDataExport(roomAnalyzer: roomAnalyzer, wifiSurveyManager: wifiSurveyManager)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            let jsonData = try encoder.encode(exportData)
            
            // Save to Documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let timestamp = DateFormatter.fileTimestamp.string(from: Date())
            let filename = "wifi_survey_export_\(timestamp).json"
            let fileURL = documentsPath.appendingPathComponent(filename)
            
            try jsonData.write(to: fileURL)
            
            print("📤 Exported survey data to: \(fileURL.path)")
            print("   - Measurements: \(exportData.measurements.count)")
            print("   - Rooms: \(exportData.roomData.rooms.count)")
            print("   - Simulated Plume events: \(exportData.simulatedPlumeData.count)")
            
            return fileURL
            
        } catch {
            print("❌ Export failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Export only Plume simulation data for testing
    func exportPlumeSimulationData(from measurements: [WiFiMeasurement]) -> URL? {
        let plumeEvents = Self.generateMockPlumeData(from: measurements)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            let jsonData = try encoder.encode(plumeEvents)
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let timestamp = DateFormatter.fileTimestamp.string(from: Date())
            let filename = "plume_simulation_data_\(timestamp).json"
            let fileURL = documentsPath.appendingPathComponent(filename)
            
            try jsonData.write(to: fileURL)
            
            print("📤 Exported Plume simulation data to: \(fileURL.path)")
            print("   - Connection events: \(plumeEvents.count)")
            
            return fileURL
            
        } catch {
            print("❌ Plume export failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Load previously exported data for testing
    func loadExportedData(from url: URL) -> SurveyDataExport? {
        do {
            let jsonData = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let exportData = try decoder.decode(SurveyDataExport.self, from: jsonData)
            
            print("📥 Loaded survey data from: \(url.lastPathComponent)")
            print("   - Measurements: \(exportData.measurements.count)")
            print("   - Plume events: \(exportData.simulatedPlumeData.count)")
            
            return exportData
            
        } catch {
            print("❌ Load failed: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let fileTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}