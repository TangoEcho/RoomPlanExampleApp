import Foundation
import simd

protocol WiFiControlProvider: AnyObject {
    var isEnabled: Bool { get }
    func initialize() async throws
    func shutdown() async
    func canSteerDevice() -> Bool
    func steerToBand(_ band: WiFiFrequencyBand, at location: simd_float3) async throws -> SteeringResult
    func steerToDevice(_ deviceId: String, at location: simd_float3) async throws -> SteeringResult
    func getCurrentConnectionState() -> PlumeConnectionState?
    func correlate(measurements: [WiFiMeasurement]) -> [CorrelatedMeasurement]
    func correlationStatusText() -> String
}

final class NoOpWiFiControlProvider: WiFiControlProvider {
    var isEnabled: Bool { false }
    func initialize() async throws {}
    func shutdown() async {}
    func canSteerDevice() -> Bool { false }
    func steerToBand(_ band: WiFiFrequencyBand, at location: simd_float3) async throws -> SteeringResult {
        throw PluginError.steeringNotAvailable
    }
    func steerToDevice(_ deviceId: String, at location: simd_float3) async throws -> SteeringResult {
        throw PluginError.steeringNotAvailable
    }
    func getCurrentConnectionState() -> PlumeConnectionState? { nil }
    func correlate(measurements: [WiFiMeasurement]) -> [CorrelatedMeasurement] { [] }
    func correlationStatusText() -> String { "WiFi control disabled" }
}


