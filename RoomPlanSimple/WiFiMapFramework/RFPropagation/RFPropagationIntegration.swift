import Foundation
import simd

/// Integration layer that connects the new RF Propagation Engine with existing WiFi survey system
public class RFPropagationIntegration {
    
    // MARK: - Properties
    
    /// Core RF propagation engine
    private let rfEngine: RFPropagationEngine
    
    /// Existing WiFi survey manager
    private var wifiSurveyManager: WiFiSurveyManager?
    
    /// Current room model for predictions
    private var currentRoomModel: RoomModel?
    
    /// Router configurations
    private var routerConfigurations: [RouterConfiguration] = []
    
    /// Calibration data for improving accuracy
    private var calibrationPoints: [CalibrationPoint] = []
    
    // MARK: - Initialization
    
    /// Initialize RF propagation integration
    /// - Parameters:
    ///   - environment: Indoor environment type for propagation modeling
    ///   - wifiSurveyManager: Existing WiFi survey manager (optional)
    public init(environment: IndoorEnvironment = .residential, wifiSurveyManager: WiFiSurveyManager? = nil) {
        self.rfEngine = RFPropagationEngine(environment: environment, useAdvancedRayTracing: true)
        self.wifiSurveyManager = wifiSurveyManager
        
        print("🔬 RF Propagation Integration initialized")
        print("   Environment: \(environment.rawValue)")
        print("   WiFi Survey Manager: \(wifiSurveyManager != nil ? "connected" : "not connected")")
    }
    
    // MARK: - Room Model Integration
    
    /// Update room model from RoomAnalyzer data
    /// - Parameter roomAnalyzer: Room analyzer with identified rooms and furniture
    public func updateRoomModel(from roomAnalyzer: RoomAnalyzer) {
        print("🏠 Updating room model from RoomAnalyzer")
        print("   Identified rooms: \(roomAnalyzer.identifiedRooms.count)")
        print("   Furniture items: \(roomAnalyzer.furnitureItems.count)")
        
        // Convert RoomAnalyzer data to RoomModel format
        let roomModel = convertToRoomModel(roomAnalyzer: roomAnalyzer)
        self.currentRoomModel = roomModel
        
        print("🏠 Room model updated successfully")
        print("   Total walls: \(roomModel.walls.count)")
        print("   Room bounds: \(roomModel.bounds)")
    }
    
    /// Add router configuration for RF predictions
    /// - Parameters:
    ///   - position: 3D position of the router
    ///   - deviceSpec: Router device specifications
    ///   - orientation: Router orientation in radians (default: 0)
    ///   - elevation: Height above floor in meters (default: 1.5m)
    public func addRouter(
        at position: Point3D,
        deviceSpec: DeviceSpec,
        orientation: Float = 0.0,
        elevation: Float = 1.5
    ) -> UUID {
        let routerId = UUID()
        let routerConfig = RouterConfiguration(
            id: routerId,
            position: position,
            deviceSpec: deviceSpec,
            orientation: orientation,
            elevation: elevation
        )
        
        routerConfigurations.append(routerConfig)
        
        print("📡 Added router at position \(position)")
        print("   Router ID: \(routerId)")
        print("   Supported bands: \(deviceSpec.supportedStandards.flatMap { $0.supportedBands })")
        
        return routerId
    }
    
    /// Add router using existing WiFi measurement data to infer position
    /// - Parameter measurements: WiFi measurements to analyze for router position
    public func inferAndAddRouter(from measurements: [WiFiMeasurement]) {
        guard !measurements.isEmpty else {
            print("⚠️ No measurements provided for router inference")
            return
        }
        
        // Find the location with strongest signal (likely closest to router)
        let strongestMeasurement = measurements.max { $0.averageRSSI() < $1.averageRSSI() }
        guard let routerLocation = strongestMeasurement?.location else {
            print("⚠️ Could not infer router location from measurements")
            return
        }
        
        // Create a standard WiFi 7 router spec
        let standardRouterSpec = createStandardWiFi7Router()
        
        let routerId = addRouter(
            at: routerLocation,
            deviceSpec: standardRouterSpec,
            orientation: 0.0,
            elevation: 1.5
        )
        
        print("📡 Inferred router location from measurements")
        print("   Inferred position: \(routerLocation)")
        print("   Based on \(measurements.count) measurements")
        print("   Router ID: \(routerId)")
    }
    
    // MARK: - Prediction Methods
    
    /// Predict signal strength at a specific location
    /// - Parameters:
    ///   - location: 3D point to predict signal strength
    ///   - frequency: Optional specific frequency (calculates all bands if nil)
    /// - Returns: Signal prediction result
    public func predictSignalStrength(at location: Point3D, frequency: Float? = nil) -> SignalPrediction? {
        guard let roomModel = currentRoomModel else {
            print("⚠️ No room model available for prediction")
            return nil
        }
        
        guard !routerConfigurations.isEmpty else {
            print("⚠️ No routers configured for prediction")
            return nil
        }
        
        // Use the first router for single-point prediction
        // In a full implementation, this would combine predictions from all routers
        let primaryRouter = routerConfigurations[0]
        
        return rfEngine.calculateSignalStrength(
            from: primaryRouter,
            to: location,
            in: roomModel,
            at: frequency
        )
    }
    
    /// Generate comprehensive coverage map
    /// - Parameters:
    ///   - gridResolution: Grid spacing in meters (default: 0.5m)
    ///   - progressCallback: Optional progress reporting callback
    /// - Returns: Complete coverage map or nil if prerequisites not met
    public func generateCoverageMap(
        gridResolution: Double = 0.5,
        progressCallback: ((Double) -> Void)? = nil
    ) -> CoverageMap? {
        guard let roomModel = currentRoomModel else {
            print("⚠️ No room model available for coverage map generation")
            return nil
        }
        
        guard !routerConfigurations.isEmpty else {
            print("⚠️ No routers configured for coverage map generation")
            return nil
        }
        
        print("🗺️ Generating coverage map...")
        print("   Grid resolution: \(gridResolution)m")
        print("   Routers: \(routerConfigurations.count)")
        
        return rfEngine.generateCoverageMap(
            routers: routerConfigurations,
            floorPlan: roomModel,
            gridResolution: gridResolution,
            progressCallback: progressCallback
        )
    }
    
    /// Compare current coverage with measured WiFi data for validation
    /// - Parameter measurements: WiFi measurements for comparison
    /// - Returns: Validation results
    public func validatePredictions(against measurements: [WiFiMeasurement]) -> ValidationResults {
        guard let roomModel = currentRoomModel else {
            return ValidationResults(accuracy: 0.0, meanError: Double.infinity, validationPoints: 0)
        }
        
        var validationPoints: [CalibrationPoint] = []
        var totalError: Double = 0.0
        var validComparisons = 0
        
        print("🔬 Validating predictions against \(measurements.count) measurements")
        
        for measurement in measurements {
            // Get prediction for this location
            if let prediction = predictSignalStrength(at: measurement.location) {
                let calibrationPoint = CalibrationPoint(
                    location: measurement.location,
                    prediction: prediction,
                    measurement: measurement
                )
                
                validationPoints.append(calibrationPoint)
                
                // Calculate error (simplified - using best RSSI comparison)
                let predictedRSSI = prediction.bestRSSI
                let measuredRSSI = measurement.averageRSSI()
                let error = abs(Double(predictedRSSI - measuredRSSI))
                
                totalError += error
                validComparisons += 1
                
                print("   Location \(measurement.location): Predicted \(String(format: "%.1f", predictedRSSI))dBm, Measured \(String(format: "%.1f", measuredRSSI))dBm, Error: \(String(format: "%.1f", error))dB")
            }
        }
        
        // Store calibration points for future model improvements
        self.calibrationPoints.append(contentsOf: validationPoints)
        
        let meanError = validComparisons > 0 ? totalError / Double(validComparisons) : Double.infinity
        let accuracy = validComparisons > 0 ? max(0.0, 1.0 - meanError / 20.0) : 0.0 // Normalize error to accuracy
        
        let results = ValidationResults(
            accuracy: accuracy,
            meanError: meanError,
            validationPoints: validComparisons
        )
        
        print("🔬 Validation completed")
        print("   Mean error: \(String(format: "%.1f", meanError))dB")
        print("   Accuracy: \(String(format: "%.1f", accuracy * 100))%")
        print("   Validation points: \(validComparisons)")
        
        return results
    }
    
    /// Find optimal router placement locations
    /// - Parameters:
    ///   - candidateLocations: Potential placement locations to evaluate
    ///   - maxRecommendations: Maximum number of recommendations to return
    /// - Returns: Ranked placement recommendations
    public func findOptimalPlacements(
        candidateLocations: [Point3D],
        maxRecommendations: Int = 5
    ) -> [PlacementRecommendation] {
        guard let roomModel = currentRoomModel else {
            print("⚠️ No room model available for placement optimization")
            return []
        }
        
        print("🎯 Evaluating \(candidateLocations.count) candidate locations for optimal placement")
        
        var recommendations: [PlacementRecommendation] = []
        let standardRouterSpec = createStandardWiFi7Router()
        
        for (index, location) in candidateLocations.enumerated() {
            // Create temporary router configuration
            let tempRouter = RouterConfiguration(
                id: UUID(),
                position: location,
                deviceSpec: standardRouterSpec
            )
            
            // Predict signal strength at this location
            let prediction = rfEngine.calculateSignalStrength(
                from: tempRouter,
                to: roomModel.bounds.center, // Predict coverage from this location to room center
                in: roomModel
            )
            
            // Calculate placement score based on coverage potential
            let coverageScore = calculatePlacementScore(
                prediction: prediction,
                location: location,
                roomModel: roomModel
            )
            
            let recommendation = PlacementRecommendation(
                location: location,
                transmitter: convertToRFTransmitter(tempRouter),
                prediction: convertToOldSignalPrediction(prediction), // Convert to old format for compatibility
                score: coverageScore,
                reasoning: generatePlacementReasoning(prediction: prediction, location: location)
            )
            
            recommendations.append(recommendation)
            
            if (index + 1) % 10 == 0 {
                print("   Evaluated \(index + 1)/\(candidateLocations.count) locations")
            }
        }
        
        // Sort by score and return top recommendations
        let sortedRecommendations = recommendations
            .sorted { $0.score > $1.score }
            .prefix(maxRecommendations)
        
        print("🎯 Placement optimization completed")
        print("   Top score: \(String(format: "%.3f", sortedRecommendations.first?.score ?? 0))")
        print("   Returning \(sortedRecommendations.count) recommendations")
        
        return Array(sortedRecommendations)
    }
    
    // MARK: - Integration with Existing Systems
    
    /// Update predictions when new WiFi measurements are collected
    /// - Parameter measurement: New WiFi measurement to incorporate
    public func incorporateNewMeasurement(_ measurement: WiFiMeasurement) {
        print("📊 Incorporating new WiFi measurement at \(measurement.location)")
        
        // If we have a prediction for this location, create a calibration point
        if let prediction = predictSignalStrength(at: measurement.location) {
            let calibrationPoint = CalibrationPoint(
                location: measurement.location,
                prediction: prediction,
                measurement: measurement
            )
            
            calibrationPoints.append(calibrationPoint)
            
            // If we have enough calibration points, consider updating the model
            if calibrationPoints.count >= 20 { // Arbitrary threshold
                updateModelCalibration()
            }
        }
    }
    
    /// Get coverage statistics for the current configuration
    /// - Returns: Coverage statistics or nil if no coverage map available
    public func getCoverageStatistics() -> CoverageStatistics? {
        guard let coverageMap = generateCoverageMap() else {
            return nil
        }
        
        return coverageMap.statistics
    }
    
    /// Export detailed RF analysis report
    /// - Returns: Formatted analysis report
    public func generateAnalysisReport() -> RFAnalysisReport? {
        guard let roomModel = currentRoomModel,
              let coverageMap = generateCoverageMap() else {
            return nil
        }
        
        let statistics = coverageMap.statistics
        let deadZones = coverageMap.deadZones
        
        return RFAnalysisReport(
            roomModel: roomModel,
            routerConfigurations: routerConfigurations,
            coverageStatistics: statistics,
            deadZones: deadZones,
            calibrationPoints: calibrationPoints,
            validationAccuracy: calculateOverallValidationAccuracy(),
            recommendations: generateImprovementRecommendations(coverageMap: coverageMap)
        )
    }
    
    // MARK: - Private Helper Methods
    
    /// Convert RoomAnalyzer data to RoomModel format
    private func convertToRoomModel(roomAnalyzer: RoomAnalyzer) -> RoomModel {
        // Convert identified rooms to walls
        var walls: [WallElement] = []
        var allFurniture: [FurnitureItem] = []
        
        // Calculate overall bounds
        var minPoint = simd_float3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxPoint = simd_float3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        
        for room in roomAnalyzer.identifiedRooms {
            // Convert wall points to wall elements
            for i in 0..<room.wallPoints.count {
                let startPoint = room.wallPoints[i]
                let endPoint = room.wallPoints[(i + 1) % room.wallPoints.count]
                
                // Convert 2D wall points to 3D
                let start3D = simd_float3(startPoint.x, 0.0, startPoint.y)
                let end3D = simd_float3(endPoint.x, 0.0, endPoint.y)
                
                let wall = WallElement(
                    id: UUID(),
                    startPoint: start3D,
                    endPoint: end3D,
                    height: 2.4, // Standard ceiling height
                    thickness: 0.1, // 10cm standard wall thickness
                    material: .drywall // Default to drywall
                )
                
                walls.append(wall)
                
                // Update bounds
                minPoint = simd_min(minPoint, start3D)
                minPoint = simd_min(minPoint, end3D)
                maxPoint = simd_max(maxPoint, start3D)
                maxPoint = simd_max(maxPoint, end3D)
            }
        }
        
        // Convert furniture items
        for furnitureItem in roomAnalyzer.furnitureItems {
            let bounds = BoundingBox(
                min: furnitureItem.position - furnitureItem.dimensions * 0.5,
                max: furnitureItem.position + furnitureItem.dimensions * 0.5
            )
            
            let furniture = FurnitureItem(
                id: UUID(),
                type: convertFurnitureType(furnitureItem.category),
                bounds: bounds,
                surfaces: [], // Simplified - no placement surfaces for now
                confidence: furnitureItem.confidence
            )
            
            allFurniture.append(furniture)
        }
        
        // Create room model
        let bounds = BoundingBox(min: minPoint, max: maxPoint)
        let floorPlan = FloorPlan(bounds: bounds, area: bounds.size.x * bounds.size.z)
        
        return RoomModel(
            id: UUID(),
            name: "Converted Room Model",
            bounds: bounds,
            walls: walls,
            furniture: allFurniture,
            openings: [], // Simplified - no openings for now
            floor: floorPlan
        )
    }
    
    /// Convert RoomAnalyzer furniture category to RoomModel furniture type
    private func convertFurnitureType(_ category: RoomAnalyzer.FurnitureCategory) -> FurnitureType {
        switch category {
        case .sofa: return .sofa
        case .table: return .table
        case .bed: return .bed
        case .refrigerator: return .cabinet // Close approximation
        case .storage: return .cabinet
        case .chair: return .chair
        case .washerDryer: return .cabinet
        case .television: return .table // TV stand approximation
        case .dishwasher: return .cabinet
        }
    }
    
    /// Create a standard WiFi 7 router device specification
    private func createStandardWiFi7Router() -> DeviceSpec {
        return DeviceSpec(
            model: "Standard WiFi 7 Router",
            manufacturer: "Generic",
            antennaGain: [2.0, 3.0, 3.0], // dBi for 2.4/5/6 GHz
            txPower: [20.0, 23.0, 23.0],  // dBm for 2.4/5/6 GHz
            supportedStandards: [.wifi7],
            dimensions: simd_float3(0.25, 0.05, 0.15), // Standard router dimensions
            powerRequirement: 15.0 // Watts
        )
    }
    
    /// Calculate placement score for a location
    private func calculatePlacementScore(
        prediction: SignalPrediction,
        location: Point3D,
        roomModel: RoomModel
    ) -> Double {
        // Base score on signal quality and confidence
        let qualityScore = Double(prediction.bestRSSI + 100) / 50.0 // Normalize RSSI to 0-1
        let confidenceScore = prediction.confidence
        
        // Consider accessibility (simplified - check if location is not inside furniture)
        let accessibilityScore = isLocationAccessible(location, in: roomModel) ? 1.0 : 0.3
        
        // Weighted combination
        return (qualityScore * 0.5 + confidenceScore * 0.3 + accessibilityScore * 0.2)
    }
    
    /// Check if a location is accessible for router placement
    private func isLocationAccessible(_ location: Point3D, in roomModel: RoomModel) -> Bool {
        // Simple check: ensure location is not inside furniture
        for furniture in roomModel.furniture {
            if furniture.bounds.contains(location) {
                return false
            }
        }
        return true
    }
    
    /// Generate placement reasoning text
    private func generatePlacementReasoning(prediction: SignalPrediction, location: Point3D) -> String {
        let quality = prediction.signalQuality
        let confidence = Int(prediction.confidence * 100)
        return "Location provides \(quality.rawValue) coverage with \(confidence)% confidence. Signal strength: \(String(format: "%.1f", prediction.bestRSSI))dBm"
    }
    
    /// Update model calibration based on accumulated calibration points
    private func updateModelCalibration() {
        print("🔧 Updating model calibration with \(calibrationPoints.count) points")
        
        // Calculate average prediction error
        let errors = calibrationPoints.compactMap { point in
            point.predictionErrors.values.first // Use first available band error
        }
        
        if !errors.isEmpty {
            let meanError = errors.reduce(0, +) / Double(errors.count)
            print("   Mean prediction error: \(String(format: "%.1f", meanError))dB")
            
            // In a full implementation, this would adjust model parameters
            // For now, just log the calibration opportunity
            if meanError > 8.0 {
                print("   ⚠️ High prediction error detected - model recalibration recommended")
            }
        }
    }
    
    /// Calculate overall validation accuracy from all calibration points
    private func calculateOverallValidationAccuracy() -> Double {
        guard !calibrationPoints.isEmpty else { return 0.0 }
        
        let accuracyScores = calibrationPoints.map { $0.accuracyScore }
        return accuracyScores.reduce(0, +) / Double(accuracyScores.count)
    }
    
    /// Generate improvement recommendations based on coverage analysis
    private func generateImprovementRecommendations(coverageMap: CoverageMap) -> [String] {
        var recommendations: [String] = []
        let stats = coverageMap.statistics
        
        // Coverage-based recommendations
        if stats.usableCoveragePercentage < 0.9 {
            recommendations.append("Consider adding additional access points to improve coverage to 90%+")
        }
        
        if stats.averageSignalStrength < -65.0 {
            recommendations.append("Average signal strength is below optimal - consider repositioning existing routers")
        }
        
        // Dead zone recommendations
        if !coverageMap.deadZones.isEmpty {
            recommendations.append("Found \(coverageMap.deadZones.count) dead zones - consider targeted extender placement")
        }
        
        // Redundancy recommendations
        if stats.redundantCoveragePercentage < 0.3 {
            recommendations.append("Low redundancy detected - consider mesh network configuration for improved reliability")
        }
        
        return recommendations
    }
    
    /// Convert new SignalPrediction to old format for compatibility
    private func convertToOldSignalPrediction(_ newPrediction: SignalPrediction) -> SignalPrediction_Old {
        // This is a compatibility shim - in practice you'd update the calling code
        // to use the new SignalPrediction format
        let signalStrength = SignalStrength(
            bands: Dictionary(
                newPrediction.predictedRSSI.compactMap { (band, rssi) in
                    (band, Double(rssi.rssi))
                },
                uniquingKeysWith: { first, _ in first }
            )
        )
        
        return SignalPrediction_Old(
            location: newPrediction.location,
            overallStrength: signalStrength,
            bandAnalysis: [:], // Simplified
            dominantBand: newPrediction.predictedRSSI.max { $0.value.rssi < $1.value.rssi }?.key ?? .band5GHz,
            overallQuality: newPrediction.signalQuality,
            confidence: newPrediction.confidence,
            timestamp: Date()
        )
    }
    
    /// Convert RouterConfiguration to RFTransmitter for compatibility
    private func convertToRFTransmitter(_ router: RouterConfiguration) -> RFTransmitter {
        var powerMap: [FrequencyBand: Double] = [:]
        var gainMap: [FrequencyBand: Double] = [:]
        
        for (index, band) in [FrequencyBand.band2_4GHz, .band5GHz, .band6GHz].enumerated() {
            if index < router.deviceSpec.txPower.count {
                powerMap[band] = Double(router.deviceSpec.txPower[index])
            }
            if index < router.deviceSpec.antennaGain.count {
                gainMap[band] = Double(router.deviceSpec.antennaGain[index])
            }
        }
        
        return RFTransmitter(
            location: router.position,
            power: powerMap,
            antennaGain: gainMap,
            antennaPattern: .omnidirectional
        )
    }
}

// MARK: - Supporting Data Structures

/// Validation results for prediction accuracy
public struct ValidationResults {
    /// Overall accuracy score (0-1, higher is better)
    public let accuracy: Double
    
    /// Mean prediction error in dB
    public let meanError: Double
    
    /// Number of validation points used
    public let validationPoints: Int
    
    /// Whether the validation meets acceptable criteria
    public var isAcceptable: Bool {
        return accuracy > 0.7 && meanError < 10.0 && validationPoints >= 5
    }
}

/// Comprehensive RF analysis report
public struct RFAnalysisReport {
    /// Room model used for analysis
    public let roomModel: RoomModel
    
    /// Router configurations analyzed
    public let routerConfigurations: [RouterConfiguration]
    
    /// Coverage statistics
    public let coverageStatistics: CoverageStatistics
    
    /// Identified dead zones
    public let deadZones: [DeadZone]
    
    /// Calibration points used
    public let calibrationPoints: [CalibrationPoint]
    
    /// Overall validation accuracy
    public let validationAccuracy: Double
    
    /// Improvement recommendations
    public let recommendations: [String]
    
    /// Generate formatted report text
    public func generateReportText() -> String {
        var report = "RF Propagation Analysis Report\n"
        report += "==============================\n\n"
        
        report += "Room Configuration:\n"
        report += "- Bounds: \(roomModel.bounds)\n"
        report += "- Walls: \(roomModel.walls.count)\n"
        report += "- Furniture items: \(roomModel.furniture.count)\n\n"
        
        report += "Router Configuration:\n"
        for (index, router) in routerConfigurations.enumerated() {
            report += "- Router \(index + 1): \(router.deviceSpec.model) at \(router.position)\n"
        }
        report += "\n"
        
        report += "Coverage Statistics:\n"
        report += "- Total points: \(coverageStatistics.totalPoints)\n"
        report += "- Usable coverage: \(String(format: "%.1f", coverageStatistics.usableCoveragePercentage * 100))%\n"
        report += "- Average signal: \(String(format: "%.1f", coverageStatistics.averageSignalStrength))dBm\n"
        report += "- Quality score: \(String(format: "%.3f", coverageStatistics.overallQualityScore))\n\n"
        
        if !deadZones.isEmpty {
            report += "Dead Zones: \(deadZones.count) identified\n\n"
        }
        
        report += "Validation:\n"
        report += "- Accuracy: \(String(format: "%.1f", validationAccuracy * 100))%\n"
        report += "- Calibration points: \(calibrationPoints.count)\n\n"
        
        if !recommendations.isEmpty {
            report += "Recommendations:\n"
            for (index, recommendation) in recommendations.enumerated() {
                report += "\(index + 1). \(recommendation)\n"
            }
        }
        
        return report
    }
}

// MARK: - Compatibility Types (to be removed once old system is updated)

/// Temporary compatibility type for old SignalPrediction
private struct SignalPrediction_Old {
    let location: Point3D
    let overallStrength: SignalStrength
    let bandAnalysis: [FrequencyBand: BandPrediction]
    let dominantBand: FrequencyBand
    let overallQuality: SignalQuality
    let confidence: Double
    let timestamp: Date
}

/// Temporary compatibility type for SignalStrength
private struct SignalStrength {
    let bands: [FrequencyBand: Double]
    
    var dominantBand: FrequencyBand {
        return bands.max { $0.value < $1.value }?.key ?? .band5GHz
    }
    
    var quality: SignalQuality {
        let maxRSSI = bands.values.max() ?? -100.0
        return SignalQuality.fromRSSI(Float(maxRSSI))
    }
}

/// Temporary compatibility type for RFTransmitter
private struct RFTransmitter {
    let location: Point3D
    let power: [FrequencyBand: Double]
    let antennaGain: [FrequencyBand: Double]
    let antennaPattern: AntennaPattern
}

/// Antenna pattern types
private enum AntennaPattern {
    case omnidirectional
    case directional
}