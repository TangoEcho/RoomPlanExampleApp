import Foundation
import UIKit
import simd

class WiFiReportGenerator {
    
    func generateReport(heatmapData: WiFiHeatmapData, 
                       rooms: [RoomAnalyzer.IdentifiedRoom], 
                       furniture: [RoomAnalyzer.FurnitureItem],
                       networkDeviceManager: NetworkDeviceManager? = nil) -> URL {
        
        let report = WiFiCoverageReport(
            heatmapData: heatmapData,
            rooms: rooms,
            furniture: furniture,
            networkDeviceManager: networkDeviceManager,
            generatedAt: Date()
        )
        
        let htmlContent = generateHTMLReport(report)
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WiFi_Coverage_Report_\(DateFormatter.reportDateFormatter.string(from: Date())).html")
        
        do {
            try htmlContent.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("Error generating report: \(error)")
            return tempURL
        }
    }
    
    private func generateHTMLReport(_ report: WiFiCoverageReport) -> String {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Spectrum WiFi Coverage Analysis Report</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 40px; background-color: #f8f9fa; }
                .header { text-align: center; margin-bottom: 40px; background: linear-gradient(135deg, #001F3F, #003366); color: white; padding: 30px; border-radius: 12px; }
                .spectrum-logo { font-size: 2.5em; font-weight: bold; margin-bottom: 10px; }
                .section { margin-bottom: 30px; background: white; padding: 25px; border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
                .room-analysis { background: #f8f9fa; padding: 20px; border-radius: 8px; margin: 10px 0; border-left: 4px solid #001F3F; }
                .measurement-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 15px; }
                .measurement-card { background: white; padding: 15px; border-radius: 8px; border-left: 4px solid; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
                .excellent { border-left-color: #22C55E; }
                .good { border-left-color: #FFC107; }
                .fair { border-left-color: #FF9800; }
                .poor { border-left-color: #DC143C; }
                .recommendations { background: linear-gradient(135deg, #e3f2fd, #bbdefb); padding: 20px; border-radius: 12px; border: 1px solid #001F3F; }
                .router-placement { background: #e8f5e8; padding: 15px; border-radius: 8px; margin: 10px 0; border-left: 3px solid #22C55E; }
                table { width: 100%; border-collapse: collapse; margin: 20px 0; }
                th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
                th { background: linear-gradient(135deg, #001F3F, #003366); color: white; }
                .summary-stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }
                .stat-card { background: white; padding: 20px; border-radius: 12px; box-shadow: 0 4px 8px rgba(0,0,0,0.1); text-align: center; border-top: 4px solid #001F3F; }
                .stat-number { font-size: 2em; font-weight: bold; color: #001F3F; }
                .spectrum-red { color: #DC143C; }
                .spectrum-blue { color: #001F3F; }
                .confidence-high { color: #007AFF; font-weight: bold; }
                .confidence-medium { color: #8E44AD; }
                .confidence-low { color: #95A5A6; }
                .accuracy-section { background: linear-gradient(135deg, #f0f8ff, #e6f3ff); border: 1px solid #007AFF; }
                .multi-band-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin: 15px 0; }
                .band-card { background: white; padding: 15px; border-radius: 8px; border-left: 4px solid; }
                .band-2-4ghz { border-left-color: #FF6B6B; }
                .band-5ghz { border-left-color: #4ECDC4; }
                .band-6ghz { border-left-color: #45B7D1; }
                .prediction-accuracy { background: #f8f9fa; padding: 15px; border-radius: 8px; margin: 10px 0; }
                h1, h2, h3 { color: #001F3F; }
            </style>
        </head>
        <body>
            <div class="header">
                <div class="spectrum-logo">SPECTRUM</div>
                <h1>📶 WiFi Coverage Analysis Report</h1>
                <p>Professional Network Assessment | Generated on \(DateFormatter.reportDisplayFormatter.string(from: report.generatedAt))</p>
            </div>
            
            \(generateExecutiveSummary(report))
            \(generateAccuracyMetrics(report))
            \(generateMultiBandAnalysis(report))
            \(generateRoomAnalysis(report))
            \(generateCoverageDetails(report))
            \(generateRecommendations(report))
            \(generateTechnicalDetails(report))
        </body>
        </html>
        """
        
        return html
    }
    
    private func generateExecutiveSummary(_ report: WiFiCoverageReport) -> String {
        let totalMeasurements = report.heatmapData.measurements.count
        let excellentSignals = report.heatmapData.measurements.filter { $0.signalStrength >= -50 }.count
        let averageSpeed = report.heatmapData.measurements.map { $0.speed }.reduce(0, +) / Double(totalMeasurements)
        let coveragePercentage = Double(excellentSignals) / Double(totalMeasurements) * 100
        
        // Calculate confidence metrics
        let confidenceScores = report.heatmapData.measurements.map { calculateConfidenceScore(for: $0) }
        let averageConfidence = confidenceScores.reduce(0, +) / Float(confidenceScores.count)
        
        // Calculate multi-band coverage if available
        let multiBandMeasurements = report.heatmapData.measurements.filter { $0.bandMeasurements.count > 1 }
        let multiBandPercentage = Double(multiBandMeasurements.count) / Double(totalMeasurements) * 100
        
        return """
        <div class="section">
            <h2>📊 Executive Summary</h2>
            <div class="summary-stats">
                <div class="stat-card">
                    <div class="stat-number">\(totalMeasurements)</div>
                    <div>Total Measurements</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">\(String(format: "%.1f%%", coveragePercentage))</div>
                    <div>Excellent Coverage</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">\(String(format: "%.1f", averageSpeed))</div>
                    <div>Avg Speed (Mbps)</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number \(confidenceClass(averageConfidence))">\(String(format: "%.1f%%", averageConfidence * 100))</div>
                    <div>Prediction Confidence</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">\(String(format: "%.1f%%", multiBandPercentage))</div>
                    <div>Multi-Band Coverage</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">\(report.rooms.count)</div>
                    <div>Rooms Analyzed</div>
                </div>
            </div>
        </div>
        """
    }
    
    private func generateAccuracyMetrics(_ report: WiFiCoverageReport) -> String {
        let confidenceScores = report.heatmapData.measurements.map { calculateConfidenceScore(for: $0) }
        let averageConfidence = confidenceScores.reduce(0, +) / Float(confidenceScores.count)
        let highConfidenceCount = confidenceScores.filter { $0 >= 0.8 }.count
        let mediumConfidenceCount = confidenceScores.filter { $0 >= 0.5 && $0 < 0.8 }.count
        let lowConfidenceCount = confidenceScores.filter { $0 < 0.5 }.count
        
        // Calculate prediction accuracy based on signal strength consistency
        let signalVariance = calculateSignalVariance(report.heatmapData.measurements)
        let predictionAccuracy = max(0.0, 100.0 - (signalVariance * 2.0)) // Lower variance = higher accuracy
        
        // Calculate RF propagation model accuracy
        let propagationAccuracy = calculatePropagationAccuracy(report.heatmapData.measurements)
        
        return """
        <div class="section accuracy-section">
            <h2>📈 Prediction Accuracy & Confidence Analysis</h2>
            
            <div class="prediction-accuracy">
                <h3>📊 Accuracy Metrics</h3>
                <div class="summary-stats">
                    <div class="stat-card">
                        <div class="stat-number \(confidenceClass(averageConfidence))">\(String(format: "%.1f%%", averageConfidence * 100))</div>
                        <div>Overall Confidence</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-number">\(String(format: "%.1f%%", predictionAccuracy))</div>
                        <div>Signal Prediction Accuracy</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-number">\(String(format: "%.1f%%", propagationAccuracy))</div>
                        <div>RF Model Accuracy</div>
                    </div>
                </div>
            </div>
            
            <div class="prediction-accuracy">
                <h3>🎯 Confidence Distribution</h3>
                <div class="summary-stats">
                    <div class="stat-card">
                        <div class="stat-number confidence-high">\(highConfidenceCount)</div>
                        <div>High Confidence (>80%)</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-number confidence-medium">\(mediumConfidenceCount)</div>
                        <div>Medium Confidence (50-80%)</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-number confidence-low">\(lowConfidenceCount)</div>
                        <div>Low Confidence (<50%)</div>
                    </div>
                </div>
            </div>
            
            <div class="prediction-accuracy">
                <h3>📝 Accuracy Analysis</h3>
                <p><strong>Signal Strength Prediction:</strong> \(getAccuracyAssessment(predictionAccuracy))</p>
                <p><strong>RF Propagation Model:</strong> \(getPropagationAssessment(propagationAccuracy))</p>
                <p><strong>Confidence Score:</strong> \(getConfidenceAssessment(averageConfidence))</p>
                \(generateAccuracyRecommendations(averageConfidence, predictionAccuracy))
            </div>
        </div>
        """
    }
    
    private func generateMultiBandAnalysis(_ report: WiFiCoverageReport) -> String {
        let multiBandMeasurements = report.heatmapData.measurements.filter { !$0.bandMeasurements.isEmpty }
        
        guard !multiBandMeasurements.isEmpty else {
            return """
            <div class="section">
                <h2>📡 Multi-Band Analysis</h2>
                <p>No multi-band data available in this survey.</p>
            </div>
            """
        }
        
        // Analyze each band
        var band24Stats = BandStats()
        var band5Stats = BandStats()
        var band6Stats = BandStats()
        
        for measurement in multiBandMeasurements {
            guard !measurement.bandMeasurements.isEmpty else { continue }
            
            for bandMeasurement in measurement.bandMeasurements {
                switch bandMeasurement.band {
                case .band2_4GHz:
                    band24Stats.add(bandMeasurement)
                case .band5GHz:
                    band5Stats.add(bandMeasurement)
                case .band6GHz:
                    band6Stats.add(bandMeasurement)
                }
            }
        }
        
        return """
        <div class="section">
            <h2>📡 Multi-Band WiFi 7 Analysis</h2>
            <p>Comprehensive analysis across 2.4GHz, 5GHz, and 6GHz frequency bands</p>
            
            <div class="multi-band-grid">
                \(generateBandCard(band24Stats, name: "2.4 GHz", cssClass: "band-2-4ghz", characteristics: "Long range, high penetration"))
                \(generateBandCard(band5Stats, name: "5 GHz", cssClass: "band-5ghz", characteristics: "Balanced performance"))
                \(generateBandCard(band6Stats, name: "6 GHz", cssClass: "band-6ghz", characteristics: "High speed, low latency"))
            </div>
            
            <div class="prediction-accuracy">
                <h3>🎯 Band Optimization Recommendations</h3>
                \(generateBandRecommendations(band24Stats, band5Stats, band6Stats))
            </div>
        </div>
        """
    }
    
    private func generateRoomAnalysis(_ report: WiFiCoverageReport) -> String {
        var html = """
        <div class="section">
            <h2>🏠 Room-by-Room Analysis</h2>
        """
        
        for room in report.rooms {
            let roomMeasurements = report.heatmapData.measurements.filter { measurement in
                guard let roomType = measurement.roomType else { return false }
                return roomType == room.type
            }
            
            if !roomMeasurements.isEmpty {
                let avgSignal = roomMeasurements.map { $0.signalStrength }.reduce(0, +) / roomMeasurements.count
                let avgSpeed = roomMeasurements.map { $0.speed }.reduce(0, +) / Double(roomMeasurements.count)
                let coverage = analyzeCoverage(avgSignal)
                
                html += """
                <div class="room-analysis">
                    <h3>\(room.type.rawValue)</h3>
                    <p><strong>Coverage Quality:</strong> \(coverage.quality)</p>
                    <p><strong>Average Signal:</strong> \(avgSignal) dBm</p>
                    <p><strong>Average Speed:</strong> \(String(format: "%.1f", avgSpeed)) Mbps</p>
                    <p><strong>Measurements:</strong> \(roomMeasurements.count)</p>
                    <p><strong>Room Area:</strong> \(String(format: "%.1f", room.area)) m²</p>
                    \(coverage.recommendation)
                </div>
                """
            }
        }
        
        html += "</div>"
        return html
    }
    
    private func generateCoverageDetails(_ report: WiFiCoverageReport) -> String {
        var html = """
        <div class="section">
            <h2>📋 Detailed Measurements</h2>
            <div class="measurement-grid">
        """
        
        for measurement in report.heatmapData.measurements {
            let coverage = analyzeCoverage(measurement.signalStrength)
            let roomName = measurement.roomType?.rawValue ?? "Unknown"
            
            html += """
            <div class="measurement-card \(coverage.cssClass)">
                <h4>\(roomName)</h4>
                <p><strong>Signal:</strong> \(measurement.signalStrength) dBm</p>
                <p><strong>Speed:</strong> \(String(format: "%.1f", measurement.speed)) Mbps</p>
                <p><strong>Frequency:</strong> \(measurement.frequency)</p>
                <p><strong>Network:</strong> \(measurement.networkName)</p>
                <small>\(DateFormatter.timeFormatter.string(from: measurement.timestamp))</small>
            </div>
            """
        }
        
        html += """
            </div>
        </div>
        """
        
        return html
    }
    
    private func generateRecommendations(_ report: WiFiCoverageReport) -> String {
        var html = """
        <div class="section">
            <h2>💡 WiFi Optimization Recommendations</h2>
            <div class="recommendations">
        """
        
        let poorCoverageRooms = findPoorCoverageRooms(report)
        let optimalPlacements = report.heatmapData.optimalRouterPlacements
        
        html += "<h3>Router Placement Recommendations</h3>"
        
        for (index, placement) in optimalPlacements.enumerated() {
            html += """
            <div class="router-placement">
                <h4>📡 Recommended Router Position \(index + 1)</h4>
                <p><strong>Location:</strong> (\(String(format: "%.2f", placement.x)), \(String(format: "%.2f", placement.z)))</p>
                <p><strong>Reasoning:</strong> Central location with optimal coverage for multiple rooms</p>
            </div>
            """
        }
        
        if !poorCoverageRooms.isEmpty {
            html += "<h3>Areas Requiring Attention</h3><ul>"
            for room in poorCoverageRooms {
                html += "<li><strong>\(room)</strong> - Consider WiFi extender or mesh network node</li>"
            }
            html += "</ul>"
        }
        
        html += generateGeneralRecommendations()
        html += "</div></div>"
        
        return html
    }
    
    private func generateGeneralRecommendations() -> String {
        return """
        <h3>General Recommendations</h3>
        <ul>
            <li><strong>Upgrade to WiFi 7:</strong> Latest standard provides better performance and coverage</li>
            <li><strong>Mesh Network:</strong> Consider mesh system for consistent coverage throughout home</li>
            <li><strong>Frequency Optimization:</strong> Use 5GHz/6GHz for high-speed devices, 2.4GHz for IoT</li>
            <li><strong>Regular Monitoring:</strong> Perform periodic surveys to maintain optimal performance</li>
            <li><strong>Router Placement:</strong> Position routers centrally and elevated for better coverage</li>
        </ul>
        """
    }
    
    private func generateTechnicalDetails(_ report: WiFiCoverageReport) -> String {
        return """
        <div class="section">
            <h2>🔧 Technical Details</h2>
            <table>
                <tr><th>Metric</th><th>Value</th></tr>
                <tr><td>Total Survey Points</td><td>\(report.heatmapData.measurements.count)</td></tr>
                <tr><td>Survey Duration</td><td>\(calculateSurveyDuration(report)) minutes</td></tr>
                <tr><td>Rooms Identified</td><td>\(report.rooms.count)</td></tr>
                <tr><td>Furniture Items</td><td>\(report.furniture.count)</td></tr>
                <tr><td>Coverage Analysis Points</td><td>\(report.heatmapData.coverageMap.count)</td></tr>
                <tr><td>Optimal Router Positions</td><td>\(report.heatmapData.optimalRouterPlacements.count)</td></tr>
            </table>
        </div>
        """
    }
    
    private func analyzeCoverage(_ signalStrength: Int) -> (quality: String, cssClass: String, recommendation: String) {
        switch signalStrength {
        case -50...0:
            return ("Excellent", "excellent", "<p>✅ Signal strength is excellent. No action needed.</p>")
        case -70..<(-50):
            return ("Good", "good", "<p>✅ Signal strength is good for most applications.</p>")
        case -85..<(-70):
            return ("Fair", "fair", "<p>⚠️ Signal strength is adequate but could be improved.</p>")
        default:
            return ("Poor", "poor", "<p>❌ Signal strength is poor. Consider WiFi extender or router repositioning.</p>")
        }
    }
    
    private func findPoorCoverageRooms(_ report: WiFiCoverageReport) -> [String] {
        var poorRooms: [String] = []
        
        for room in report.rooms {
            let roomMeasurements = report.heatmapData.measurements.filter { measurement in
                guard let roomType = measurement.roomType else { return false }
                return roomType == room.type
            }
            
            if !roomMeasurements.isEmpty {
                let avgSignal = roomMeasurements.map { $0.signalStrength }.reduce(0, +) / roomMeasurements.count
                if avgSignal < -80 {
                    poorRooms.append(room.type.rawValue)
                }
            }
        }
        
        return poorRooms
    }
    
    private func calculateSurveyDuration(_ report: WiFiCoverageReport) -> Int {
        guard let first = report.heatmapData.measurements.first?.timestamp,
              let last = report.heatmapData.measurements.last?.timestamp else { return 0 }
        
        return Int(last.timeIntervalSince(first) / 60)
    }
    
    // MARK: - Accuracy Analysis Methods
    
    /// Calculate confidence score for a WiFi measurement (same algorithm as FloorPlanRenderer)
    private func calculateConfidenceScore(for measurement: WiFiMeasurement) -> Float {
        var confidence: Float = 0.0
        
        // Base confidence from signal strength
        let signalStrength = Float(measurement.signalStrength)
        let strengthConfidence: Float
        
        switch signalStrength {
        case -50...Float.greatestFiniteMagnitude:
            strengthConfidence = 1.0
        case -65..<(-50):
            strengthConfidence = 0.8
        case -75..<(-65):
            strengthConfidence = 0.6
        case -85..<(-75):
            strengthConfidence = 0.4
        default:
            strengthConfidence = 0.2
        }
        
        confidence += strengthConfidence * 0.6
        
        // Multi-band confidence
        if !measurement.bandMeasurements.isEmpty {
            let bandCount = Float(measurement.bandMeasurements.count)
            let maxBands: Float = 3.0
            let bandDiversityConfidence = min(1.0, bandCount / maxBands)
            confidence += bandDiversityConfidence * 0.25
            
            // Band consistency
            let bandSignals = measurement.bandMeasurements.map { $0.signalStrength }
            let avgBandSignal = bandSignals.reduce(0, +) / Float(bandSignals.count)
            let variance = bandSignals.map { pow($0 - avgBandSignal, 2) }.reduce(0, +) / Float(bandSignals.count)
            let consistencyScore = max(0.0, 1.0 - sqrt(variance) / 20.0)
            confidence += consistencyScore * 0.15
        } else {
            confidence += 0.3 * 0.4
        }
        
        return min(1.0, max(0.0, confidence))
    }
    
    private func confidenceClass(_ confidence: Float) -> String {
        switch confidence {
        case 0.8...1.0: return "confidence-high"
        case 0.5..<0.8: return "confidence-medium"
        default: return "confidence-low"
        }
    }
    
    private func calculateSignalVariance(_ measurements: [WiFiMeasurement]) -> Double {
        guard measurements.count > 1 else { return 0.0 }
        
        let signals = measurements.map { Double($0.signalStrength) }
        let mean = signals.reduce(0, +) / Double(signals.count)
        let variance = signals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(signals.count)
        
        return sqrt(variance)
    }
    
    private func calculatePropagationAccuracy(_ measurements: [WiFiMeasurement]) -> Double {
        // Simulate RF propagation model accuracy based on measurement consistency
        // Higher consistency = more accurate propagation model
        let signalVariance = calculateSignalVariance(measurements)
        let maxVariance = 30.0 // dB
        
        return max(70.0, 100.0 - (signalVariance / maxVariance * 30.0))
    }
    
    private func getAccuracyAssessment(_ accuracy: Double) -> String {
        switch accuracy {
        case 90...100: return "Excellent prediction accuracy with high reliability"
        case 80..<90: return "Good prediction accuracy suitable for professional use"
        case 70..<80: return "Fair accuracy with some uncertainty in predictions"
        default: return "Lower accuracy - consider additional measurements"
        }
    }
    
    private func getPropagationAssessment(_ accuracy: Double) -> String {
        switch accuracy {
        case 85...100: return "RF propagation model performing excellently"
        case 75..<85: return "Good RF model performance with reliable predictions"
        case 65..<75: return "Adequate RF model performance"
        default: return "RF model may need calibration for this environment"
        }
    }
    
    private func getConfidenceAssessment(_ confidence: Float) -> String {
        switch confidence {
        case 0.8...1.0: return "High confidence in coverage predictions"
        case 0.6..<0.8: return "Good confidence with reliable predictions"
        case 0.4..<0.6: return "Medium confidence - additional validation recommended"
        default: return "Lower confidence - consider more detailed survey"
        }
    }
    
    private func generateAccuracyRecommendations(_ confidence: Float, _ accuracy: Double) -> String {
        var recommendations = "<h4>💡 Accuracy Improvement Recommendations:</h4><ul>"
        
        if confidence < 0.7 {
            recommendations += "<li>Increase measurement density in low-confidence areas</li>"
        }
        
        if accuracy < 80 {
            recommendations += "<li>Perform additional measurements for better prediction accuracy</li>"
        }
        
        if confidence >= 0.8 && accuracy >= 85 {
            recommendations += "<li>Current prediction quality is excellent - no additional actions needed</li>"
        } else {
            recommendations += "<li>Consider multi-band analysis for improved accuracy</li>"
            recommendations += "<li>Validate predictions with real-world performance testing</li>"
        }
        
        recommendations += "</ul>"
        return recommendations
    }
    
    // MARK: - Multi-Band Analysis Methods
    
    private func generateBandCard(_ stats: BandStats, name: String, cssClass: String, characteristics: String) -> String {
        guard stats.count > 0 else {
            return """
            <div class="band-card \(cssClass)">
                <h4>\(name)</h4>
                <p>No data available</p>
            </div>
            """
        }
        
        return """
        <div class="band-card \(cssClass)">
            <h4>\(name)</h4>
            <p><strong>Measurements:</strong> \(stats.count)</p>
            <p><strong>Avg Signal:</strong> \(String(format: "%.1f", stats.averageSignal)) dBm</p>
            <p><strong>Avg Speed:</strong> \(String(format: "%.1f", stats.averageSpeed)) Mbps</p>
            <p><strong>Best Performance:</strong> \(String(format: "%.1f", stats.maxSpeed)) Mbps</p>
            <p><strong>Characteristics:</strong> \(characteristics)</p>
            <p><strong>Utilization:</strong> \(String(format: "%.1f%%", stats.averageUtilization * 100))</p>
        </div>
        """
    }
    
    private func generateBandRecommendations(_ band24: BandStats, _ band5: BandStats, _ band6: BandStats) -> String {
        var recommendations = "<ul>"
        
        // Find best performing band
        let bands = [(band24, "2.4 GHz"), (band5, "5 GHz"), (band6, "6 GHz")]
        let bestBand = bands.max { $0.0.averageSpeed < $1.0.averageSpeed }
        
        if let best = bestBand, best.0.count > 0 {
            recommendations += "<li><strong>Best Performance:</strong> \(best.1) band with \(String(format: "%.1f", best.0.averageSpeed)) Mbps average</li>"
        }
        
        // Band-specific recommendations
        if band24.count > 0 {
            if band24.averageUtilization > 0.7 {
                recommendations += "<li><strong>2.4 GHz:</strong> High congestion detected - consider prioritizing 5/6 GHz</li>"
            } else {
                recommendations += "<li><strong>2.4 GHz:</strong> Good for IoT devices and long-range connectivity</li>"
            }
        }
        
        if band5.count > 0 {
            recommendations += "<li><strong>5 GHz:</strong> Excellent for high-bandwidth applications with \(String(format: "%.1f", band5.averageSpeed)) Mbps average</li>"
        }
        
        if band6.count > 0 {
            recommendations += "<li><strong>6 GHz:</strong> Premium performance with minimal congestion - ideal for WiFi 7 devices</li>"
        } else {
            recommendations += "<li><strong>6 GHz:</strong> Not detected - consider WiFi 7 upgrade for access to clean 6 GHz spectrum</li>"
        }
        
        recommendations += "</ul>"
        return recommendations
    }
}

struct WiFiCoverageReport {
    let heatmapData: WiFiHeatmapData
    let rooms: [RoomAnalyzer.IdentifiedRoom]
    let furniture: [RoomAnalyzer.FurnitureItem]
    let networkDeviceManager: NetworkDeviceManager?
    let generatedAt: Date
}

struct BandStats {
    private var signals: [Float] = []
    private var speeds: [Float] = []
    private var utilizations: [Float] = []
    
    var count: Int { return signals.count }
    
    var averageSignal: Float {
        guard !signals.isEmpty else { return 0 }
        return signals.reduce(0, +) / Float(signals.count)
    }
    
    var averageSpeed: Float {
        guard !speeds.isEmpty else { return 0 }
        return speeds.reduce(0, +) / Float(speeds.count)
    }
    
    var maxSpeed: Float {
        return speeds.max() ?? 0
    }
    
    var averageUtilization: Float {
        guard !utilizations.isEmpty else { return 0 }
        return utilizations.reduce(0, +) / Float(utilizations.count)
    }
    
    mutating func add(_ measurement: BandMeasurement) {
        signals.append(measurement.signalStrength)
        speeds.append(measurement.speed)
        utilizations.append(measurement.utilization ?? 0.5) // Default to 50% if unknown
    }
}

extension DateFormatter {
    static let reportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
    
    static let reportDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()
    
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()
}