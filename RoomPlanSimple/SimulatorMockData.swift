/*
SimulatorMockData.swift

Mock data provider for simulator testing without requiring physical hardware.
Uses realistic data based on actual app logs and typical room configurations.
*/

import UIKit
import RoomPlan
import ARKit
import simd

class SimulatorMockData {
    
    // MARK: - Simulator Detection
    
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    // MARK: - Mock Room Data
    
    static func createMockCapturedRoom() -> CapturedRoom? {
        // Return nil for now since CapturedRoom requires actual RoomPlan data
        // We'll simulate room analysis results instead
        return nil
    }
    
    static func createMockRoomAnalysis() -> [RoomAnalyzer.IdentifiedRoom] {
        return [
            RoomAnalyzer.IdentifiedRoom(
                type: .livingRoom,
                bounds: createMockSurface(center: simd_float3(3.0, 0, 2.0), size: simd_float3(6.0, 3.0, 4.0)),
                center: simd_float3(3.0, 0, 2.0),
                area: 24.0,
                confidence: 0.85,
                wallPoints: [
                    simd_float2(0.0, 0.0),
                    simd_float2(6.0, 0.0),
                    simd_float2(6.0, 4.0),
                    simd_float2(0.0, 4.0)
                ],
                doorways: [simd_float2(2.0, 0.0)]
            ),
            RoomAnalyzer.IdentifiedRoom(
                type: .kitchen,
                bounds: createMockSurface(center: simd_float3(-2.0, 0, 2.0), size: simd_float3(4.0, 3.0, 3.0)),
                center: simd_float3(-2.0, 0, 2.0),
                area: 12.0,
                confidence: 0.78,
                wallPoints: [
                    simd_float2(-4.0, 0.5),
                    simd_float2(0.0, 0.5),
                    simd_float2(0.0, 3.5),
                    simd_float2(-4.0, 3.5)
                ],
                doorways: [simd_float2(-2.0, 0.5)]
            ),
            RoomAnalyzer.IdentifiedRoom(
                type: .bedroom,
                bounds: createMockSurface(center: simd_float3(3.0, 0, -3.0), size: simd_float3(4.0, 3.0, 3.5)),
                center: simd_float3(3.0, 0, -3.0),
                area: 14.0,
                confidence: 0.92,
                wallPoints: [
                    simd_float2(1.0, -4.75),
                    simd_float2(5.0, -4.75),
                    simd_float2(5.0, -1.25),
                    simd_float2(1.0, -1.25)
                ],
                doorways: [simd_float2(3.0, -1.25)]
            )
        ]
    }
    
    private static func createMockSurface(center: simd_float3, size: simd_float3) -> CapturedRoom.Surface {
        // Create a mock CapturedRoom.Surface - this is simplified since we can't easily create real RoomPlan data
        // The floor plan renderer mainly uses the wallPoints anyway
        return CapturedRoom.Surface(
            curve: nil,
            completedEdges: [],
            confidence: .high,
            classification: .floor,
            transform: simd_float4x4(1.0),
            dimensions: size
        )
    }
    
    private static func createMockSurfaces(for roomType: RoomAnalyzer.RoomType) -> [RoomAnalyzer.RoomSurface] {
        switch roomType {
        case .livingRoom:
            return [
                RoomAnalyzer.RoomSurface(type: .wall, area: 24.0, confidence: 0.9),
                RoomAnalyzer.RoomSurface(type: .floor, area: 24.0, confidence: 0.95),
                RoomAnalyzer.RoomSurface(type: .ceiling, area: 24.0, confidence: 0.8)
            ]
        case .kitchen:
            return [
                RoomAnalyzer.RoomSurface(type: .wall, area: 18.0, confidence: 0.85),
                RoomAnalyzer.RoomSurface(type: .floor, area: 12.0, confidence: 0.9),
                RoomAnalyzer.RoomSurface(type: .ceiling, area: 12.0, confidence: 0.75)
            ]
        case .bedroom:
            return [
                RoomAnalyzer.RoomSurface(type: .wall, area: 20.0, confidence: 0.88),
                RoomAnalyzer.RoomSurface(type: .floor, area: 14.0, confidence: 0.93),
                RoomAnalyzer.RoomSurface(type: .ceiling, area: 14.0, confidence: 0.82)
            ]
        default:
            return [
                RoomAnalyzer.RoomSurface(type: .wall, area: 16.0, confidence: 0.8),
                RoomAnalyzer.RoomSurface(type: .floor, area: 12.0, confidence: 0.85),
                RoomAnalyzer.RoomSurface(type: .ceiling, area: 12.0, confidence: 0.7)
            ]
        }
    }
    
    // MARK: - Mock WiFi Data
    
    static func createMockWiFiMeasurements() -> [WiFiMeasurement] {
        // Based on realistic signal patterns from actual logs
        var measurements: [WiFiMeasurement] = []
        
        // Living room measurements (good signal near router)
        measurements.append(contentsOf: [
            WiFiMeasurement(
                location: simd_float3(2.0, 0, 1.0),
                signalStrength: -35,
                timestamp: Date().addingTimeInterval(-300),
                networkInfo: createMockNetworkInfo(),
                speedTest: createMockSpeedTest(download: 450, upload: 25)
            ),
            WiFiMeasurement(
                location: simd_float3(4.0, 0, 2.0),
                signalStrength: -42,
                timestamp: Date().addingTimeInterval(-280),
                networkInfo: createMockNetworkInfo(),
                speedTest: createMockSpeedTest(download: 380, upload: 22)
            ),
            WiFiMeasurement(
                location: simd_float3(3.5, 0, 3.0),
                signalStrength: -38,
                timestamp: Date().addingTimeInterval(-260),
                networkInfo: createMockNetworkInfo(),
                speedTest: createMockSpeedTest(download: 420, upload: 24)
            )
        ])
        
        // Kitchen measurements (moderate signal)
        measurements.append(contentsOf: [
            WiFiMeasurement(
                location: simd_float3(-1.0, 0, 1.5),
                signalStrength: -58,
                timestamp: Date().addingTimeInterval(-240),
                networkInfo: createMockNetworkInfo(),
                speedTest: createMockSpeedTest(download: 180, upload: 15)
            ),
            WiFiMeasurement(
                location: simd_float3(-2.5, 0, 2.5),
                signalStrength: -65,
                timestamp: Date().addingTimeInterval(-220),
                networkInfo: createMockNetworkInfo(),
                speedTest: createMockSpeedTest(download: 120, upload: 12)
            )
        ])
        
        // Bedroom measurements (weaker signal, further from router)
        measurements.append(contentsOf: [
            WiFiMeasurement(
                location: simd_float3(2.5, 0, -2.0),
                signalStrength: -72,
                timestamp: Date().addingTimeInterval(-200),
                networkInfo: createMockNetworkInfo(),
                speedTest: createMockSpeedTest(download: 85, upload: 8)
            ),
            WiFiMeasurement(
                location: simd_float3(4.0, 0, -3.5),
                signalStrength: -78,
                timestamp: Date().addingTimeInterval(-180),
                networkInfo: createMockNetworkInfo(),
                speedTest: createMockSpeedTest(download: 45, upload: 5)
            )
        ])
        
        return measurements
    }
    
    private static func createMockNetworkInfo() -> WiFiNetworkInfo {
        return WiFiNetworkInfo(
            ssid: "SpectrumSetup-A7",
            bssid: "dc:ef:09:12:34:56",
            frequency: 5180,
            channel: 36,
            channelWidth: 80,
            security: "WPA2/WPA3",
            band: .band5GHz
        )
    }
    
    private static func createMockSpeedTest(download: Double, upload: Double) -> SpeedTestResult {
        return SpeedTestResult(
            downloadSpeed: download,
            uploadSpeed: upload,
            latency: Double.random(in: 8...25),
            jitter: Double.random(in: 1...5),
            timestamp: Date()
        )
    }
    
    // MARK: - Mock Heatmap Data
    
    static func createMockHeatmapData() -> WiFiHeatmapData {
        let measurements = createMockWiFiMeasurements()
        
        // Generate interpolated coverage map
        var coverageMap: [simd_float3: Double] = [:]
        
        // Create a grid covering the mock room area
        for x in stride(from: -4.0, through: 6.0, by: 0.5) {
            for z in stride(from: -5.0, through: 4.0, by: 0.5) {
                let point = simd_float3(Float(x), 0, Float(z))
                
                // Calculate interpolated signal strength based on distance from measurements
                var totalWeight: Float = 0
                var weightedSignal: Float = 0
                
                for measurement in measurements {
                    let distance = simd_distance(point, measurement.location)
                    let weight = 1.0 / (distance + 0.1) // Avoid division by zero
                    
                    totalWeight += weight
                    weightedSignal += weight * Float(measurement.signalStrength)
                }
                
                if totalWeight > 0 {
                    let interpolatedStrength = weightedSignal / totalWeight
                    let normalizedSignal = Double(interpolatedStrength + 100) / 100.0
                    
                    if interpolatedStrength > -120 {
                        coverageMap[point] = max(0, min(1, normalizedSignal))
                    }
                }
            }
        }
        
        // Mock optimal router placements
        let optimalPlacements = [
            RouterPlacement(
                position: simd_float3(1.0, 1.5, 0.5),
                score: 0.85,
                coverageRadius: 8.0,
                reason: "Central location with good line-of-sight to all rooms"
            ),
            RouterPlacement(
                position: simd_float3(0.0, 1.5, 1.0),
                score: 0.78,
                coverageRadius: 7.5,
                reason: "Alternative placement for better kitchen coverage"
            )
        ]
        
        return WiFiHeatmapData(
            measurements: measurements,
            coverageMap: coverageMap,
            optimalRouterPlacements: optimalPlacements
        )
    }
    
    // MARK: - Mock UI States
    
    static func simulateRoomScanningProgress() -> Float {
        // Return a progress value between 0 and 1
        return Float.random(in: 0.3...0.9)
    }
    
    static func simulateTrackingState() -> ARCamera.TrackingState {
        // Simulate various tracking states for testing UI
        let states: [ARCamera.TrackingState] = [
            .normal,
            .limited(.initializing),
            .limited(.insufficientFeatures),
            .limited(.excessiveMotion)
        ]
        return states.randomElement() ?? .normal
    }
    
    // MARK: - Mock Session Configuration
    
    static func configureMockSession() {
        print("🎭 Simulator Mode: Configuring mock data for UI testing")
        print("   • Room scan will use mock room analysis")
        print("   • WiFi survey will use realistic signal measurements")
        print("   • AR tracking states will be simulated")
        print("   • Camera feed will show placeholder content")
    }
}

// MARK: - Simulator Extensions

extension RoomCaptureSession {
    static var isSimulatorSupported: Bool {
        return SimulatorMockData.isSimulator ? true : isSupported
    }
}