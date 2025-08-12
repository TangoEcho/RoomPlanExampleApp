import Foundation
import simd

// MARK: - Plume Data Correlator

class PlumeDataCorrelator {
    
    // Configuration
    private let timestampTolerance: TimeInterval = 2.0 // ±2 seconds
    private let locationTolerance: Float = 1.0 // 1 meter radius
    private let maxCorrelationHistory = 1000
    
    private var correlationHistory: [CorrelatedMeasurement] = []
    
    // MARK: - Correlation Logic
    
    /// Correlate WiFi measurements with Plume connection states
    func correlate(measurements: [WiFiMeasurement], with plugin: PlumePlugin) -> [CorrelatedMeasurement] {
        var correlatedResults: [CorrelatedMeasurement] = []
        
        print("🔗 Correlating \(measurements.count) WiFi measurements with Plume data")
        
        for measurement in measurements {
            let correlation = correlateIndividualMeasurement(measurement, with: plugin)
            correlatedResults.append(correlation)
        }
        
        // Add to history
        correlationHistory.append(contentsOf: correlatedResults)
        maintainHistoryBounds()
        
        let highConfidenceCount = correlatedResults.filter { $0.correlationConfidence > 0.7 }.count
        print("✅ Correlation complete: \(highConfidenceCount)/\(correlatedResults.count) high confidence matches")
        
        return correlatedResults
    }
    
    private func correlateIndividualMeasurement(_ measurement: WiFiMeasurement, 
                                              with plugin: PlumePlugin) -> CorrelatedMeasurement {
        
        // Get current Plume connection state
        guard let plumeState = plugin.getCurrentConnectionState() else {
            return CorrelatedMeasurement(
                appMeasurement: measurement,
                plumeState: nil,
                correlationConfidence: 0.0,
                timestampDelta: 0
            )
        }
        
        // Calculate timestamp correlation
        let timestampDelta = abs(measurement.timestamp.timeIntervalSince(plumeState.timestamp))
        let timestampConfidence = calculateTimestampConfidence(delta: timestampDelta)
        
        // Calculate location correlation (if available)
        let locationConfidence = calculateLocationConfidence(
            appLocation: measurement.location,
            plumeLocation: plumeState.location
        )
        
        // Calculate signal correlation
        let signalConfidence = calculateSignalConfidence(
            appSignal: measurement.signalStrength,
            plumeSignal: plumeState.connection.signalStrength
        )
        
        // Combined confidence score (weighted average)
        let combinedConfidence = (timestampConfidence * 0.4) + 
                               (locationConfidence * 0.3) + 
                               (signalConfidence * 0.3)
        
        return CorrelatedMeasurement(
            appMeasurement: measurement,
            plumeState: plumeState,
            correlationConfidence: combinedConfidence,
            timestampDelta: timestampDelta
        )
    }
    
    // MARK: - Confidence Calculation Methods
    
    private func calculateTimestampConfidence(delta: TimeInterval) -> Float {
        if delta <= timestampTolerance {
            // Linear decay from 1.0 at 0 seconds to 0.0 at tolerance
            return Float(1.0 - (delta / timestampTolerance))
        } else {
            return 0.0
        }
    }
    
    private func calculateLocationConfidence(appLocation: simd_float3, 
                                           plumeLocation: simd_float3?) -> Float {
        guard let plumeLocation = plumeLocation else {
            return 0.5 // Neutral confidence when location unknown
        }
        
        let distance = simd_distance(appLocation, plumeLocation)
        
        if distance <= locationTolerance {
            // Linear decay from 1.0 at 0 meters to 0.0 at tolerance
            return 1.0 - (distance / locationTolerance)
        } else {
            return 0.0
        }
    }
    
    private func calculateSignalConfidence(appSignal: Int, plumeSignal: Int) -> Float {
        let signalDifference = abs(appSignal - plumeSignal)
        
        // Consider signals within 10dBm as highly correlated
        if signalDifference <= 10 {
            return 1.0 - (Float(signalDifference) / 10.0)
        } else {
            return 0.0
        }
    }
    
    // MARK: - Analysis and Validation
    
    /// Validate correlation accuracy using known ground truth
    func validateCorrelationAccuracy() -> CorrelationValidation {
        let highConfidenceMeasurements = correlationHistory.filter { $0.correlationConfidence > 0.7 }
        let mediumConfidenceMeasurements = correlationHistory.filter { 
            $0.correlationConfidence > 0.4 && $0.correlationConfidence <= 0.7 
        }
        let lowConfidenceMeasurements = correlationHistory.filter { $0.correlationConfidence <= 0.4 }
        
        let averageConfidence = correlationHistory.isEmpty ? 0 : 
            correlationHistory.map { $0.correlationConfidence }.reduce(0, +) / Float(correlationHistory.count)
        
        let averageTimestampDelta = correlationHistory.isEmpty ? 0 :
            correlationHistory.map { $0.timestampDelta }.reduce(0, +) / Double(correlationHistory.count)
        
        return CorrelationValidation(
            totalCorrelations: correlationHistory.count,
            highConfidenceCount: highConfidenceMeasurements.count,
            mediumConfidenceCount: mediumConfidenceMeasurements.count,
            lowConfidenceCount: lowConfidenceMeasurements.count,
            averageConfidence: averageConfidence,
            averageTimestampDelta: averageTimestampDelta
        )
    }
    
    /// Generate correlation report for debugging
    func generateCorrelationReport() -> CorrelationReport {
        let validation = validateCorrelationAccuracy()
        
        // Analyze timestamp distribution
        let timestampDeltas = correlationHistory.map { $0.timestampDelta }
        let maxTimestampDelta = timestampDeltas.max() ?? 0
        let minTimestampDelta = timestampDeltas.min() ?? 0
        
        // Analyze signal differences
        let signalDifferences = correlationHistory.compactMap { correlation -> Int? in
            guard let plumeState = correlation.plumeState else { return nil }
            return abs(correlation.appMeasurement.signalStrength - plumeState.connection.signalStrength)
        }
        
        let averageSignalDifference = signalDifferences.isEmpty ? 0 :
            signalDifferences.reduce(0, +) / signalDifferences.count
        
        return CorrelationReport(
            validation: validation,
            timestampRange: (min: minTimestampDelta, max: maxTimestampDelta),
            averageSignalDifference: averageSignalDifference,
            correlationSummary: generateCorrelationSummary()
        )
    }
    
    private func generateCorrelationSummary() -> [String] {
        var summary: [String] = []
        
        let validation = validateCorrelationAccuracy()
        
        summary.append("📊 Correlation Summary:")
        summary.append("   Total correlations: \(validation.totalCorrelations)")
        summary.append("   High confidence (>70%): \(validation.highConfidenceCount)")
        summary.append("   Medium confidence (40-70%): \(validation.mediumConfidenceCount)")
        summary.append("   Low confidence (<40%): \(validation.lowConfidenceCount)")
        summary.append("   Average confidence: \(String(format: "%.1f%%", validation.averageConfidence * 100))")
        summary.append("   Average timestamp delta: \(String(format: "%.2f", validation.averageTimestampDelta))s")
        
        if validation.averageConfidence > 0.8 {
            summary.append("✅ Excellent correlation quality")
        } else if validation.averageConfidence > 0.6 {
            summary.append("🟡 Good correlation quality")
        } else {
            summary.append("🔴 Poor correlation quality - check timing synchronization")
        }
        
        return summary
    }
    
    // MARK: - Real-time Correlation Monitoring
    
    /// Get real-time correlation status
    func getCurrentCorrelationStatus() -> CorrelationStatus {
        let recentCorrelations = Array(correlationHistory.suffix(10)) // Last 10 measurements
        
        let recentAverageConfidence = recentCorrelations.isEmpty ? 0 :
            recentCorrelations.map { $0.correlationConfidence }.reduce(0, +) / Float(recentCorrelations.count)
        
        let recentHighConfidenceCount = recentCorrelations.filter { $0.correlationConfidence > 0.7 }.count
        
        let status: CorrelationQuality
        if recentAverageConfidence > 0.8 {
            status = .excellent
        } else if recentAverageConfidence > 0.6 {
            status = .good
        } else if recentAverageConfidence > 0.4 {
            status = .fair
        } else {
            status = .poor
        }
        
        return CorrelationStatus(
            quality: status,
            recentAverageConfidence: recentAverageConfidence,
            recentHighConfidenceCount: recentHighConfidenceCount,
            totalHistorySize: correlationHistory.count
        )
    }
    
    // MARK: - Memory Management
    
    private func maintainHistoryBounds() {
        if correlationHistory.count > maxCorrelationHistory {
            let excess = correlationHistory.count - maxCorrelationHistory
            correlationHistory.removeFirst(excess)
            print("🧹 Trimmed \(excess) old correlations to maintain memory bounds")
        }
    }
    
    func clearHistory() {
        correlationHistory.removeAll()
        print("🧹 Cleared correlation history")
    }
}

// MARK: - Supporting Data Structures

struct CorrelationValidation {
    let totalCorrelations: Int
    let highConfidenceCount: Int
    let mediumConfidenceCount: Int
    let lowConfidenceCount: Int
    let averageConfidence: Float
    let averageTimestampDelta: TimeInterval
    
    var highConfidencePercentage: Double {
        return totalCorrelations > 0 ? Double(highConfidenceCount) / Double(totalCorrelations) * 100 : 0
    }
}

struct CorrelationReport {
    let validation: CorrelationValidation
    let timestampRange: (min: TimeInterval, max: TimeInterval)
    let averageSignalDifference: Int
    let correlationSummary: [String]
}

enum CorrelationQuality {
    case excellent // >80% confidence
    case good      // 60-80% confidence
    case fair      // 40-60% confidence
    case poor      // <40% confidence
    
    var displayName: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }
    
    var emoji: String {
        switch self {
        case .excellent: return "✅"
        case .good: return "🟢"
        case .fair: return "🟡"
        case .poor: return "🔴"
        }
    }
}

struct CorrelationStatus {
    let quality: CorrelationQuality
    let recentAverageConfidence: Float
    let recentHighConfidenceCount: Int
    let totalHistorySize: Int
    
    var displayText: String {
        return "\(quality.emoji) \(quality.displayName) (\(String(format: "%.1f%%", recentAverageConfidence * 100)))"
    }
}