import Foundation
import UIKit

class WiFiReportGenerator {
    
    func generateReport(heatmapData: WiFiHeatmapData, 
                       rooms: [RoomAnalyzer.IdentifiedRoom], 
                       furniture: [RoomAnalyzer.FurnitureItem]) -> URL {
        
        let report = WiFiCoverageReport(
            heatmapData: heatmapData,
            rooms: rooms,
            furniture: furniture,
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
                    <div class="stat-number">\(report.rooms.count)</div>
                    <div>Rooms Analyzed</div>
                </div>
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
}

struct WiFiCoverageReport {
    let heatmapData: WiFiHeatmapData
    let rooms: [RoomAnalyzer.IdentifiedRoom]
    let furniture: [RoomAnalyzer.FurnitureItem]
    let generatedAt: Date
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