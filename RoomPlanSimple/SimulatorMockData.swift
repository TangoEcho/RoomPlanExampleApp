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
        // Create mock room data with wall points that match WiFi measurement coordinates
        // This ensures the coordinate systems are aligned
        
        // Since we can't easily create CapturedRoom.Surface in simulator without actual RoomPlan data,
        // we'll return empty array and let the renderer show placeholder content
        // The coordinate system fixes in FloorPlanRenderer will handle this properly
        
        print("🎭 SimulatorMockData: Returning empty room analysis - using placeholder rendering")
        return []
    }
    
    
    
    // MARK: - Mock WiFi Data
    
    static func createMockWiFiMeasurements() -> [WiFiMeasurement] {
        // WiFi measurements that align with room coordinate system
        // Room coordinates: Living room (0,0) to (5,4), Kitchen (-3,0) to (0,3), Bedroom (1,-4) to (5,0)
        var measurements: [WiFiMeasurement] = []
        
        // Living room measurements - INSIDE the room bounds (0,0) to (5,4)
        measurements.append(contentsOf: [
            WiFiMeasurement(
                location: simd_float3(2.0, 0, 1.0),    // Center of living room
                timestamp: Date().addingTimeInterval(-300),
                signalStrength: -35,
                networkName: createMockNetworkInfo(),
                speed: createMockSpeedTest(download: 450, upload: 25),
                frequency: "5.2 GHz",
                roomType: .livingRoom
            ),
            WiFiMeasurement(
                location: simd_float3(4.0, 0, 2.0),    // Right side of living room
                timestamp: Date().addingTimeInterval(-280),
                signalStrength: -42,
                networkName: createMockNetworkInfo(),
                speed: createMockSpeedTest(download: 380, upload: 22),
                frequency: "5.2 GHz",
                roomType: .livingRoom
            ),
            WiFiMeasurement(
                location: simd_float3(1.5, 0, 3.0),    // Upper left of living room
                timestamp: Date().addingTimeInterval(-260),
                signalStrength: -38,
                networkName: createMockNetworkInfo(),
                speed: createMockSpeedTest(download: 420, upload: 24),
                frequency: "5.2 GHz",
                roomType: .livingRoom
            )
        ])
        
        // Kitchen measurements - INSIDE the kitchen bounds (-3,0) to (0,3)
        measurements.append(contentsOf: [
            WiFiMeasurement(
                location: simd_float3(-1.5, 0, 1.5),   // Center of kitchen
                timestamp: Date().addingTimeInterval(-240),
                signalStrength: -58,
                networkName: createMockNetworkInfo(),
                speed: createMockSpeedTest(download: 180, upload: 15),
                frequency: "5.2 GHz",
                roomType: .kitchen
            ),
            WiFiMeasurement(
                location: simd_float3(-2.5, 0, 2.2),   // Far corner of kitchen
                timestamp: Date().addingTimeInterval(-220),
                signalStrength: -65,
                networkName: createMockNetworkInfo(),
                speed: createMockSpeedTest(download: 120, upload: 12),
                frequency: "5.2 GHz",
                roomType: .kitchen
            )
        ])
        
        // Bedroom measurements - INSIDE the bedroom bounds (1,-4) to (5,0)
        measurements.append(contentsOf: [
            WiFiMeasurement(
                location: simd_float3(2.5, 0, -2.0),   // Center of bedroom
                timestamp: Date().addingTimeInterval(-200),
                signalStrength: -72,
                networkName: createMockNetworkInfo(),
                speed: createMockSpeedTest(download: 85, upload: 8),
                frequency: "5.2 GHz",
                roomType: .bedroom
            ),
            WiFiMeasurement(
                location: simd_float3(4.0, 0, -3.5),   // Far corner of bedroom
                timestamp: Date().addingTimeInterval(-180),
                signalStrength: -78,
                networkName: createMockNetworkInfo(),
                speed: createMockSpeedTest(download: 45, upload: 5),
                frequency: "5.2 GHz",
                roomType: .bedroom
            )
        ])
        
        print("🎭 Created \(measurements.count) WiFi measurements aligned with room coordinates")
        for measurement in measurements {
            print("   📍 WiFi Point: (\(measurement.location.x), \(measurement.location.z)) - \(measurement.roomType?.rawValue ?? "unknown")")
        }
        
        return measurements
    }
    
    private static func createMockNetworkInfo() -> String {
        return "SpectrumSetup-A7" // Just return SSID as string for now
    }
    
    private static func createMockSpeedTest(download: Double, upload: Double) -> Double {
        return download // Just return download speed as double for now
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
        
        // Mock optimal router placements (as simple positions)
        let optimalPlacements = [
            simd_float3(1.0, 1.5, 0.5), // Central location
            simd_float3(0.0, 1.5, 1.0)  // Alternative placement
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