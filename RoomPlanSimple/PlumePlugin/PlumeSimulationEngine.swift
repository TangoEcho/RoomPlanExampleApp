import Foundation
import simd

// MARK: - Plume Simulation Engine

class PlumeSimulationEngine {
    
    private var mockDevices: [PlumeDevice] = []
    private var simulationState: SimulationState
    private var connectionHistory: [SimulatedConnectionEvent] = []
    
    // Simulation parameters
    private let baseSignalStrength: Int = -45
    private let signalVariation: Int = 10
    private let steeringLatency: TimeInterval = 2.0
    private let deviceHandoffLatency: TimeInterval = 3.0
    
    init() {
        self.simulationState = SimulationState()
    }
    
    // MARK: - Setup and Configuration
    
    func setupMockEnvironment(devices: [PlumeDevice]) {
        self.mockDevices = devices
        
        // Initialize simulation state with first device
        if let firstDevice = devices.first {
            simulationState.currentConnection = SimulatedConnection(
                device: firstDevice,
                band: .band5GHz,
                signalStrength: firstDevice.signalStrength,
                connectedSince: Date(),
                location: simd_float3(0, 0, 0) // Default location
            )
        }
        
        print("🎭 Simulation environment setup with \(devices.count) mock devices")
        printDeviceConfiguration()
    }
    
    private func printDeviceConfiguration() {
        print("📋 Mock Device Configuration:")
        for device in mockDevices {
            print("   \(device.type.rawValue): \(device.id)")
            print("     Location: \(device.location ?? "Unknown")")
            print("     Signal: \(device.signalStrength)dBm")
            print("     Bands: \(device.supportedBands.map { $0.displayName }.joined(separator: ", "))")
        }
    }
    
    // MARK: - Device Steering Simulation
    
    func simulateDeviceSteering(to device: PlumeDevice, at location: simd_float3) async throws -> SteeringResult {
        print("🎭 Simulating device steering to \(device.id) at location (\(location.x), \(location.y), \(location.z))")
        
        // Simulate network latency
        try await Task.sleep(nanoseconds: UInt64(deviceHandoffLatency * 1_000_000_000))
        
        // Calculate new signal strength based on location and device
        let newSignalStrength = calculateSimulatedSignalStrength(
            device: device,
            band: simulationState.currentConnection?.band ?? .band5GHz,
            location: location
        )
        
        // Record connection event
        let connectionEvent = SimulatedConnectionEvent(
            eventType: .deviceHandoff,
            timestamp: Date(),
            fromDevice: simulationState.currentConnection?.device,
            toDevice: device,
            fromBand: simulationState.currentConnection?.band,
            toBand: simulationState.currentConnection?.band ?? .band5GHz,
            location: location,
            signalStrength: newSignalStrength
        )
        
        connectionHistory.append(connectionEvent)
        
        // Update simulation state
        simulationState.currentConnection = SimulatedConnection(
            device: device,
            band: simulationState.currentConnection?.band ?? .band5GHz,
            signalStrength: newSignalStrength,
            connectedSince: Date(),
            location: location
        )
        
        return SteeringResult(
            success: true,
            band: simulationState.currentConnection?.band,
            device: device,
            signalStrength: newSignalStrength,
            stabilizationTime: deviceHandoffLatency,
            timestamp: Date()
        )
    }
    
    // MARK: - Band Steering Simulation
    
    func simulateBandSteering(to band: WiFiFrequencyBand, at location: simd_float3) async throws -> SteeringResult {
        guard let currentDevice = simulationState.currentConnection?.device else {
            throw PluginError.steeringNotAvailable
        }
        
        print("🎭 Simulating band steering to \(band.displayName) on \(currentDevice.id)")
        
        // Check if device supports the band
        guard currentDevice.supportedBands.contains(band) else {
            throw PluginError.apiError("Device \(currentDevice.id) does not support \(band.displayName)")
        }
        
        // Simulate network latency
        try await Task.sleep(nanoseconds: UInt64(steeringLatency * 1_000_000_000))
        
        // Calculate new signal strength for the band
        let newSignalStrength = calculateSimulatedSignalStrength(
            device: currentDevice,
            band: band,
            location: location
        )
        
        // Record connection event
        let connectionEvent = SimulatedConnectionEvent(
            eventType: .bandChange,
            timestamp: Date(),
            fromDevice: currentDevice,
            toDevice: currentDevice,
            fromBand: simulationState.currentConnection?.band,
            toBand: band,
            location: location,
            signalStrength: newSignalStrength
        )
        
        connectionHistory.append(connectionEvent)
        
        // Update simulation state
        simulationState.currentConnection?.band = band
        simulationState.currentConnection?.signalStrength = newSignalStrength
        simulationState.currentConnection?.location = location
        
        return SteeringResult(
            success: true,
            band: band,
            device: currentDevice,
            signalStrength: newSignalStrength,
            stabilizationTime: steeringLatency,
            timestamp: Date()
        )
    }
    
    // MARK: - Signal Strength Simulation
    
    private func calculateSimulatedSignalStrength(device: PlumeDevice, 
                                                band: WiFiFrequencyBand, 
                                                location: simd_float3) -> Int {
        
        // Start with device base signal strength
        var signalStrength = device.signalStrength
        
        // Apply band-specific attenuation
        let bandAttenuation = getBandAttenuation(band)
        signalStrength -= bandAttenuation
        
        // Apply distance-based path loss (simplified)
        let distance = simd_length(location)
        let distanceAttenuation = Int(distance * 3) // 3dB per meter
        signalStrength -= distanceAttenuation
        
        // Apply device type modifier
        let deviceModifier = getDeviceTypeModifier(device.type)
        signalStrength += deviceModifier
        
        // Add some random variation for realism
        let variation = Int.random(in: -signalVariation...signalVariation)
        signalStrength += variation
        
        // Apply environmental effects based on location
        let environmentalLoss = calculateEnvironmentalLoss(location)
        signalStrength -= environmentalLoss
        
        // Ensure signal strength stays within realistic bounds
        return max(-90, min(-20, signalStrength))
    }
    
    private func getBandAttenuation(_ band: WiFiFrequencyBand) -> Int {
        switch band {
        case .band2_4GHz: return 0  // Reference band
        case .band5GHz: return 3    // 3dB more attenuation
        case .band6GHz: return 5    // 5dB more attenuation
        }
    }
    
    private func getDeviceTypeModifier(_ deviceType: PlumeDevice.DeviceType) -> Int {
        switch deviceType {
        case .router: return 5      // Routers typically have higher power
        case .extender: return 0    // Reference
        case .pod: return -2        // Pods might be slightly lower power
        }
    }
    
    private func calculateEnvironmentalLoss(_ location: simd_float3) -> Int {
        // Simulate environmental obstacles based on location
        // This is a simplified model - in reality, this would use room data
        
        let x = abs(location.x)
        let z = abs(location.z)
        
        // Assume walls every 5 meters that cause 10dB loss
        let wallsX = Int(x / 5.0)
        let wallsZ = Int(z / 5.0)
        let totalWalls = wallsX + wallsZ
        
        return min(30, totalWalls * 10) // Max 30dB environmental loss
    }
    
    // MARK: - Connection History and Analytics
    
    func getConnectionHistory() -> [SimulatedConnectionEvent] {
        return connectionHistory
    }
    
    func getCurrentSimulationState() -> SimulationState {
        return simulationState
    }
    
    func generateSimulationReport() -> SimulationReport {
        let totalEvents = connectionHistory.count
        let bandChanges = connectionHistory.filter { $0.eventType == .bandChange }.count
        let deviceHandoffs = connectionHistory.filter { $0.eventType == .deviceHandoff }.count
        
        let signalStrengths = connectionHistory.map { $0.signalStrength }
        let averageSignalStrength = signalStrengths.isEmpty ? 0 : 
            signalStrengths.reduce(0, +) / signalStrengths.count
        let minSignalStrength = signalStrengths.min() ?? 0
        let maxSignalStrength = signalStrengths.max() ?? 0
        
        return SimulationReport(
            totalEvents: totalEvents,
            bandChanges: bandChanges,
            deviceHandoffs: deviceHandoffs,
            averageSignalStrength: averageSignalStrength,
            signalRange: (min: minSignalStrength, max: maxSignalStrength),
            simulationDuration: connectionHistory.last?.timestamp.timeIntervalSince(connectionHistory.first?.timestamp ?? Date()) ?? 0
        )
    }
    
    // MARK: - Data Export for Testing
    
    func exportSimulationData() -> [DataExportManager.PlumeConnectionEvent] {
        return connectionHistory.map { event in
            DataExportManager.PlumeConnectionEvent(
                eventId: UUID().uuidString,
                timestamp: event.timestamp,
                timestampMillis: Int64(event.timestamp.timeIntervalSince1970 * 1000),
                eventType: event.eventType.rawValue,
                deviceMAC: "sim:mac:\(UUID().uuidString.prefix(8))",
                connectedDevice: DataExportManager.PlumeConnectionEvent.PlumeDeviceInfo(
                    deviceId: event.toDevice.id,
                    deviceType: event.toDevice.type.rawValue,
                    model: event.toDevice.model,
                    firmwareVersion: "sim-1.0.0",
                    location: event.toDevice.location
                ),
                signalStrength: event.signalStrength,
                band: event.toBand.rawValue,
                channel: channelFromBand(event.toBand),
                location: DataExportManager.LocationExport(from: event.location),
                duration: nil,
                reason: "simulation_\(event.eventType.rawValue)"
            )
        }
    }
    
    private func channelFromBand(_ band: WiFiFrequencyBand) -> Int {
        switch band {
        case .band2_4GHz: return 6
        case .band5GHz: return 36
        case .band6GHz: return 37
        }
    }
}

// MARK: - Simulation Data Structures

struct SimulationState {
    var currentConnection: SimulatedConnection?
    var startTime: Date = Date()
    var totalSteeringOperations: Int = 0
    
    mutating func incrementSteeringOperations() {
        totalSteeringOperations += 1
    }
}

struct SimulatedConnection {
    let device: PlumeDevice
    var band: WiFiFrequencyBand
    var signalStrength: Int
    let connectedSince: Date
    var location: simd_float3
}

struct SimulatedConnectionEvent {
    let eventType: SimulatedEventType
    let timestamp: Date
    let fromDevice: PlumeDevice?
    let toDevice: PlumeDevice
    let fromBand: WiFiFrequencyBand?
    let toBand: WiFiFrequencyBand
    let location: simd_float3
    let signalStrength: Int
}

enum SimulatedEventType: String {
    case bandChange = "band_change"
    case deviceHandoff = "device_handoff"
    case initialConnection = "initial_connection"
}

struct SimulationReport {
    let totalEvents: Int
    let bandChanges: Int
    let deviceHandoffs: Int
    let averageSignalStrength: Int
    let signalRange: (min: Int, max: Int)
    let simulationDuration: TimeInterval
    
    var summary: [String] {
        return [
            "🎭 Simulation Report:",
            "   Total events: \(totalEvents)",
            "   Band changes: \(bandChanges)",
            "   Device handoffs: \(deviceHandoffs)",
            "   Average signal: \(averageSignalStrength)dBm",
            "   Signal range: \(signalRange.min) to \(signalRange.max)dBm",
            "   Duration: \(String(format: "%.1f", simulationDuration))s"
        ]
    }
}