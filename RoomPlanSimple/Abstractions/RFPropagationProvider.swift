import Foundation
import simd

protocol RFPropagationProvider {
    func initialize(environment: IndoorEnvironment)
    func updateRoomModel(from analyzer: RoomAnalyzer)
    func predictSignalStrength(at location: simd_float3, frequency: Float?) -> SignalPrediction?
    func generateCoverageMap(gridResolution: Double, progress: ((Double) -> Void)?) -> CoverageMap?
    func validatePredictions(measurements: [WiFiMeasurement]) -> ValidationResults?
    func generateAnalysisReport() -> RFAnalysisReport?
}


