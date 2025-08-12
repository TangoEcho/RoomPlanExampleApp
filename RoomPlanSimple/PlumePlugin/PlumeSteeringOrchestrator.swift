import Foundation
import simd

// MARK: - Plume Steering Orchestrator

class PlumeSteeringOrchestrator {
    private let apiManager: PlumeAPIManager
    private var currentSequence: SteeringSequence?
    private let steeringHistory: SteeringHistory
    
    // Configuration
    private let stabilizationDelay: TimeInterval = 5.0 // Wait for signal to stabilize
    private let maxRetries: Int = 3
    private let sequenceTimeout: TimeInterval = 120.0 // 2 minutes max per sequence
    
    init(apiManager: PlumeAPIManager) {
        self.apiManager = apiManager
        self.steeringHistory = SteeringHistory()
    }
    
    // MARK: - High-Level Steering Operations
    
    /// Perform comprehensive band and device testing at a location
    func performComprehensiveSurvey(at location: simd_float3, 
                                   completion: @escaping ([SteeringMeasurement]) -> Void) async {
        print("🎯 Starting comprehensive steering survey at location (\(location.x), \(location.y), \(location.z))")
        
        var measurements: [SteeringMeasurement] = []
        let availableDevices = apiManager.availableDevices
        let supportedBands: [WiFiFrequencyBand] = [.band2_4GHz, .band5GHz, .band6GHz]
        
        // Record baseline measurement
        if let baseline = await recordBaselineMeasurement(at: location) {
            measurements.append(baseline)
        }
        
        // Test each device × band combination
        for device in availableDevices {
            for band in supportedBands {
                if device.supportedBands.contains(band) {
                    do {
                        let measurement = try await performSteeringTest(
                            device: device,
                            band: band,
                            location: location
                        )
                        measurements.append(measurement)
                        
                        // Add stabilization delay
                        try await Task.sleep(nanoseconds: UInt64(stabilizationDelay * 1_000_000_000))
                        
                    } catch {
                        print("⚠️ Steering test failed for \(device.id) on \(band.displayName): \(error)")
                        
                        // Add failed measurement for completeness
                        let failedMeasurement = SteeringMeasurement(
                            location: location,
                            timestamp: Date(),
                            device: device,
                            band: band,
                            signalStrength: nil,
                            steeringResult: SteeringResult(
                                success: false,
                                band: band,
                                device: device,
                                signalStrength: -100,
                                stabilizationTime: 0,
                                timestamp: Date(),
                                error: error.localizedDescription
                            ),
                            measurementDuration: 0
                        )
                        measurements.append(failedMeasurement)
                    }
                }
            }
        }
        
        // Return to optimal configuration
        if let optimal = findOptimalConfiguration(from: measurements) {
            do {
                _ = try await steerToOptimal(optimal, at: location)
                print("✅ Returned to optimal configuration: \(optimal.device.id) on \(optimal.band.displayName)")
            } catch {
                print("⚠️ Failed to return to optimal configuration: \(error)")
            }
        }
        
        // Store in history
        steeringHistory.addSequence(SteeringSequence(
            id: UUID().uuidString,
            location: location,
            startTime: measurements.first?.timestamp ?? Date(),
            endTime: measurements.last?.timestamp ?? Date(),
            measurements: measurements
        ))
        
        completion(measurements)
    }
    
    /// Steer to specific band and measure result
    func steerToBand(_ band: WiFiFrequencyBand, at location: simd_float3) async throws -> SteeringResult {
        guard let currentDevice = apiManager.currentConnection?.device else {
            throw PluginError.steeringNotAvailable
        }
        
        return try await apiManager.steerToBand(band, device: currentDevice)
    }
    
    /// Steer to specific device and measure result
    func steerToDevice(_ device: PlumeDevice, at location: simd_float3) async throws -> SteeringResult {
        return try await apiManager.steerToDevice(device)
    }
    
    // MARK: - Individual Steering Tests
    
    private func performSteeringTest(device: PlumeDevice, 
                                   band: WiFiFrequencyBand, 
                                   location: simd_float3) async throws -> SteeringMeasurement {
        let startTime = Date()
        
        print("📡 Testing \(device.type.rawValue) \(device.id) on \(band.displayName)")
        
        // Step 1: Steer to device if not already connected
        if apiManager.currentConnection?.device.id != device.id {
            _ = try await apiManager.steerToDevice(device)
            try await Task.sleep(nanoseconds: UInt64(stabilizationDelay * 1_000_000_000))
        }
        
        // Step 2: Steer to specific band
        let steeringResult = try await apiManager.steerToBand(band, device: device)
        
        // Step 3: Wait for signal stabilization
        try await Task.sleep(nanoseconds: UInt64(stabilizationDelay * 1_000_000_000))
        
        // Step 4: Measure signal strength
        let signalStrength = steeringResult.signalStrength
        
        let measurementDuration = Date().timeIntervalSince(startTime)
        
        return SteeringMeasurement(
            location: location,
            timestamp: Date(),
            device: device,
            band: band,
            signalStrength: signalStrength,
            steeringResult: steeringResult,
            measurementDuration: measurementDuration
        )
    }
    
    private func recordBaselineMeasurement(at location: simd_float3) async -> SteeringMeasurement? {
        guard let currentConnection = apiManager.currentConnection else { return nil }
        
        return SteeringMeasurement(
            location: location,
            timestamp: Date(),
            device: currentConnection.device,
            band: currentConnection.band,
            signalStrength: currentConnection.signalStrength,
            steeringResult: SteeringResult(
                success: true,
                band: currentConnection.band,
                device: currentConnection.device,
                signalStrength: currentConnection.signalStrength,
                stabilizationTime: 0,
                timestamp: Date()
            ),
            measurementDuration: 0
        )
    }
    
    // MARK: - Optimization Logic
    
    private func findOptimalConfiguration(from measurements: [SteeringMeasurement]) -> SteeringMeasurement? {
        // Find measurement with best signal strength
        return measurements
            .filter { $0.steeringResult.success && $0.signalStrength != nil }
            .max { first, second in
                (first.signalStrength ?? -100) < (second.signalStrength ?? -100)
            }
    }
    
    private func steerToOptimal(_ optimal: SteeringMeasurement, at location: simd_float3) async throws -> SteeringResult {
        // First steer to device
        if apiManager.currentConnection?.device.id != optimal.device.id {
            _ = try await apiManager.steerToDevice(optimal.device)
        }
        
        // Then steer to band
        return try await apiManager.steerToBand(optimal.band, device: optimal.device)
    }
    
    // MARK: - History and Analytics
    
    func getSteeringHistory() -> [SteeringSequence] {
        return steeringHistory.getRecentSequences()
    }
    
    func analyzeSteeringPatterns() -> SteeringAnalytics {
        return steeringHistory.analyzePatterns()
    }
}

// MARK: - Data Structures

struct SteeringMeasurement {
    let location: simd_float3
    let timestamp: Date
    let device: PlumeDevice
    let band: WiFiFrequencyBand
    let signalStrength: Int?
    let steeringResult: SteeringResult
    let measurementDuration: TimeInterval
    
    var isSuccessful: Bool {
        return steeringResult.success && signalStrength != nil
    }
}

struct SteeringSequence {
    let id: String
    let location: simd_float3
    let startTime: Date
    let endTime: Date
    let measurements: [SteeringMeasurement]
    
    var duration: TimeInterval {
        return endTime.timeIntervalSince(startTime)
    }
    
    var successfulMeasurements: [SteeringMeasurement] {
        return measurements.filter { $0.isSuccessful }
    }
    
    var bestMeasurement: SteeringMeasurement? {
        return successfulMeasurements.max { first, second in
            (first.signalStrength ?? -100) < (second.signalStrength ?? -100)
        }
    }
}

// MARK: - Steering History Management

class SteeringHistory {
    private var sequences: [SteeringSequence] = []
    private let maxHistorySize = 100 // Keep last 100 sequences
    
    func addSequence(_ sequence: SteeringSequence) {
        sequences.append(sequence)
        
        // Maintain history size
        if sequences.count > maxHistorySize {
            sequences.removeFirst(sequences.count - maxHistorySize)
        }
        
        print("📊 Added steering sequence \(sequence.id) with \(sequence.measurements.count) measurements")
    }
    
    func getRecentSequences(limit: Int = 10) -> [SteeringSequence] {
        return Array(sequences.suffix(limit))
    }
    
    func analyzePatterns() -> SteeringAnalytics {
        let totalSequences = sequences.count
        let totalMeasurements = sequences.flatMap { $0.measurements }.count
        let successfulMeasurements = sequences.flatMap { $0.successfulMeasurements }.count
        
        let averageSequenceDuration = sequences.isEmpty ? 0 : 
            sequences.map { $0.duration }.reduce(0, +) / Double(sequences.count)
        
        // Band performance analysis
        var bandPerformance: [WiFiFrequencyBand: [Int]] = [:]
        for sequence in sequences {
            for measurement in sequence.successfulMeasurements {
                if let signalStrength = measurement.signalStrength {
                    bandPerformance[measurement.band, default: []].append(signalStrength)
                }
            }
        }
        
        let bandAverages = bandPerformance.mapValues { strengths in
            strengths.isEmpty ? 0 : strengths.reduce(0, +) / strengths.count
        }
        
        return SteeringAnalytics(
            totalSequences: totalSequences,
            totalMeasurements: totalMeasurements,
            successRate: totalMeasurements > 0 ? Double(successfulMeasurements) / Double(totalMeasurements) : 0,
            averageSequenceDuration: averageSequenceDuration,
            bandPerformance: bandAverages
        )
    }
}

struct SteeringAnalytics {
    let totalSequences: Int
    let totalMeasurements: Int
    let successRate: Double
    let averageSequenceDuration: TimeInterval
    let bandPerformance: [WiFiFrequencyBand: Int]
    
    var successRatePercentage: String {
        return String(format: "%.1f%%", successRate * 100)
    }
    
    var averageDurationFormatted: String {
        return String(format: "%.1f seconds", averageSequenceDuration)
    }
}