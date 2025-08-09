import Foundation
import simd

/// Core RF propagation models for WiFi signal prediction
public class PropagationModels {
    
    // MARK: - Free Space Path Loss
    
    /// Calculate free space path loss using Friis equation
    /// - Parameters:
    ///   - distance: Distance in meters
    ///   - frequency: Frequency in MHz
    /// - Returns: Path loss in dB
    public static func freeSpacePathLoss(distance: Float, frequency: Float) -> Float {
        guard distance > 0 && frequency > 0 else { return Float.infinity }
        
        // FSPL (dB) = 20*log10(d) + 20*log10(f) + 92.45
        // where d is in km, f is in GHz
        let distanceKm = distance / 1000.0
        let frequencyGHz = frequency / 1000.0
        
        return 20 * log10(distanceKm) + 20 * log10(frequencyGHz) + 92.45
    }
    
    /// Calculate reference path loss at 1 meter for given frequency
    /// - Parameter frequency: Frequency in MHz
    /// - Returns: Reference path loss in dB
    public static func referencePathLoss(frequency: Float) -> Float {
        return freeSpacePathLoss(distance: 1.0, frequency: frequency)
    }
    
    // MARK: - Indoor Path Loss Models
    
    /// ITU Indoor Path Loss Model (ITU-R P.1238)
    /// Suitable for WiFi 7 multi-band analysis
    public struct ITUIndoorModel {
        let pathLossExponent: Float
        let frequencyFactor: Float
        let shadowingStdDev: Float
        
        public init(environment: IndoorEnvironment = .residential) {
            switch environment {
            case .residential:
                self.pathLossExponent = 2.8
                self.frequencyFactor = 2.0
                self.shadowingStdDev = 4.0
            case .office:
                self.pathLossExponent = 3.2
                self.frequencyFactor = 2.2
                self.shadowingStdDev = 6.0
            case .commercial:
                self.pathLossExponent = 3.0
                self.frequencyFactor = 2.0
                self.shadowingStdDev = 5.0
            case .industrial:
                self.pathLossExponent = 2.2
                self.frequencyFactor = 1.8
                self.shadowingStdDev = 8.0
            }
        }
        
        /// Calculate path loss for given distance and frequency
        /// - Parameters:
        ///   - distance: Distance in meters
        ///   - frequency: Frequency in MHz
        ///   - floors: Number of floors between transmitter and receiver
        /// - Returns: Path loss in dB
        public func pathLoss(distance: Float, frequency: Float, floors: Int = 0) -> Float {
            guard distance > 0 else { return 0 }
            
            let referenceDistance: Float = 1.0 // meters
            let referenceLoss = PropagationModels.referencePathLoss(frequency: frequency)
            
            // Base path loss calculation
            let distanceLoss = pathLossExponent * 10 * log10(distance / referenceDistance)
            
            // Frequency-dependent loss (WiFi 7 specific)
            let frequencyLoss = frequencyFactor * log10(frequency / 2400.0) // Normalized to 2.4GHz
            
            // Floor penetration loss
            let floorLoss = Float(floors) * floorPenetrationLoss(frequency: frequency)
            
            return referenceLoss + distanceLoss + frequencyLoss + floorLoss
        }
        
        private func floorPenetrationLoss(frequency: Float) -> Float {
            // Enhanced floor penetration model for multi-floor scenarios
            let baseLoss: Float
            switch frequency {
            case 2400...2500: baseLoss = 12.0 // 2.4GHz
            case 5000...6000: baseLoss = 16.0 // 5GHz
            case 6000...7200: baseLoss = 20.0 // 6GHz
            default: baseLoss = 15.0
            }
            
            // Additional loss for floor construction materials - this needs environment context
            let constructionLoss: Float = 3.0  // Default construction loss
            
            return baseLoss + constructionLoss
        }
    }
    
    /// Log-Distance Path Loss Model with shadowing
    public struct LogDistanceModel {
        let pathLossExponent: Double
        let referenceDistance: Double
        let shadowingVariance: Double
        let referencePathLoss: Double
        
        public init(
            pathLossExponent: Double = 2.0,
            referenceDistance: Double = 1.0,
            shadowingVariance: Double = 4.0,
            frequency: Double
        ) {
            self.pathLossExponent = pathLossExponent
            self.referenceDistance = referenceDistance
            self.shadowingVariance = shadowingVariance
            self.referencePathLoss = PropagationModels.freeSpacePathLoss(
                distance: referenceDistance,
                frequency: frequency
            )
        }
        
        /// Calculate path loss with optional shadowing
        /// - Parameters:
        ///   - distance: Distance in meters
        ///   - includeShadowing: Whether to include random shadowing
        /// - Returns: Path loss in dB
        public func pathLoss(distance: Double, includeShadowing: Bool = false) -> Double {
            guard distance > 0 else { return 0 }
            
            let baseLoss = referencePathLoss + 
                          10 * pathLossExponent * log10(distance / referenceDistance)
            
            if includeShadowing {
                // Add log-normal shadowing
                let shadowingComponent = Double.random(in: -2*shadowingVariance...2*shadowingVariance)
                return baseLoss + shadowingComponent
            }
            
            return baseLoss
        }
    }
    
    // MARK: - Multi-Floor Propagation Models
    
    /// Multi-floor path loss model for vertical signal propagation
    public struct MultiFloorModel {
        private let baseModel: ITUIndoorModel
        private let environment: IndoorEnvironment
        
        public init(environment: IndoorEnvironment = .residential) {
            self.environment = environment
            self.baseModel = ITUIndoorModel(environment: environment)
        }
        
        /// Calculate path loss including vertical propagation between floors
        /// - Parameters:
        ///   - distance3D: 3D distance between transmitter and receiver
        ///   - horizontalDistance: Horizontal distance component
        ///   - verticalDistance: Vertical distance component (floor separation)
        ///   - frequency: Frequency in MHz
        ///   - floorsSeparated: Number of floors between transmitter and receiver
        /// - Returns: Total path loss in dB
        public func pathLoss(
            distance3D: Double,
            horizontalDistance: Double,
            verticalDistance: Double,
            frequency: Double,
            floorsSeparated: Int
        ) -> Double {
            
            // Base horizontal propagation loss
            let horizontalLoss = baseModel.pathLoss(
                distance: horizontalDistance,
                frequency: frequency,
                floors: 0
            )
            
            // Vertical propagation component
            let verticalLoss = calculateVerticalLoss(
                verticalDistance: verticalDistance,
                frequency: frequency,
                floors: floorsSeparated
            )
            
            // Combined 3D path loss adjustment
            let geometryFactor = calculate3DGeometryFactor(
                horizontalDistance: horizontalDistance,
                verticalDistance: verticalDistance
            )
            
            return horizontalLoss + verticalLoss + geometryFactor
        }
        
        private func calculateVerticalLoss(
            verticalDistance: Double,
            frequency: Double,
            floors: Int
        ) -> Double {
            guard floors > 0 else { return 0.0 }
            
            // Base floor penetration loss - calculate manually since method is private
            let baseFloorLoss = calculateFloorPenetrationLoss(frequency: frequency)
            
            // Distance-based vertical loss (different from horizontal)
            let verticalPathLoss = 20 * log10(max(verticalDistance, 1.0)) // Free space component
            
            // Floor-specific attenuation
            let floorAttenuation = Double(floors) * baseFloorLoss
            
            // Frequency-dependent vertical propagation
            let frequencyFactor = getVerticalFrequencyFactor(frequency: frequency)
            
            return verticalPathLoss + floorAttenuation * frequencyFactor
        }
        
        private func calculate3DGeometryFactor(
            horizontalDistance: Double,
            verticalDistance: Double
        ) -> Double {
            // Geometric factor for 3D propagation vs 2D
            let totalDistance = sqrt(horizontalDistance * horizontalDistance + verticalDistance * verticalDistance)
            let horizontalRatio = horizontalDistance / totalDistance
            
            // Less loss when signal path is more vertical (less obstruction)
            return -2.0 * (1.0 - horizontalRatio)
        }
        
        private func getVerticalFrequencyFactor(frequency: Double) -> Double {
            // Vertical propagation frequency characteristics
            switch frequency {
            case 2400...2500: return 0.8  // 2.4GHz penetrates better vertically
            case 5000...6000: return 1.0  // 5GHz baseline
            case 6000...7200: return 1.3  // 6GHz has more vertical loss
            default: return 1.0
            }
        }
        
        private func calculateFloorPenetrationLoss(frequency: Double) -> Double {
            // Replicate floor penetration calculation for multi-floor model
            let baseLoss: Double
            switch frequency {
            case 2400...2500: baseLoss = 12.0 // 2.4GHz
            case 5000...6000: baseLoss = 16.0 // 5GHz
            case 6000...7200: baseLoss = 20.0 // 6GHz
            default: baseLoss = 15.0
            }
            
            // Additional loss for floor construction materials
            let constructionLoss: Double
            switch environment {
            case .residential: constructionLoss = 2.0  // Wood/light construction
            case .office: constructionLoss = 4.0      // Steel and concrete
            case .commercial: constructionLoss = 3.0  // Mixed construction
            case .industrial: constructionLoss = 6.0  // Heavy construction
            }
            
            return baseLoss + constructionLoss
        }
    }
    
    // MARK: - WiFi 7 Specific Models
    
    /// Multi-band path loss model optimized for WiFi 7
    public struct WiFi7MultiBandModel {
        private let models: [FrequencyBand: ITUIndoorModel]
        
        public init(environment: IndoorEnvironment = .residential) {
            self.models = [
                .band2_4GHz: ITUIndoorModel(environment: environment),
                .band5GHz: ITUIndoorModel(environment: environment),
                .band6GHz: ITUIndoorModel(environment: environment)
            ]
        }
        
        /// Calculate path loss for all WiFi 7 bands
        /// - Parameters:
        ///   - distance: Distance in meters
        ///   - floors: Number of floors
        /// - Returns: Dictionary of path loss per band
        public func multiBANDPathLoss(distance: Double, floors: Int = 0) -> [FrequencyBand: Double] {
            var results: [FrequencyBand: Double] = [:]
            
            for (band, model) in models {
                let pathLoss = model.pathLoss(
                    distance: distance,
                    frequency: band.rawValue,
                    floors: floors
                )
                
                // Apply band-specific corrections
                let correctedLoss = pathLoss + bandSpecificCorrection(band: band, distance: distance)
                results[band] = correctedLoss
            }
            
            return results
        }
        
        private func bandSpecificCorrection(band: FrequencyBand, distance: Double) -> Double {
            // WiFi 7 band-specific propagation characteristics
            switch band {
            case .band2_4GHz:
                // Better penetration, less distance loss
                return -1.0
            case .band5GHz:
                // Balanced performance
                return 0.0
            case .band6GHz:
                // Higher frequency losses, less penetration
                return 2.0 + (distance > 10.0 ? 1.0 : 0.0)
            }
        }
    }
    
    // MARK: - Wall Penetration Models
    
    /// Advanced wall penetration model for WiFi 7
    public struct WallPenetrationModel {
        
        /// Calculate penetration loss through a wall
        /// - Parameters:
        ///   - material: Wall material
        ///   - thickness: Wall thickness in meters
        ///   - frequency: Frequency in MHz
        ///   - incidenceAngle: Angle of incidence in radians (0 = perpendicular)
        /// - Returns: Penetration loss in dB
        public static func penetrationLoss(
            material: WallMaterial,
            thickness: Double,
            frequency: Double,
            incidenceAngle: Double = 0.0
        ) -> Double {
            
            // Base attenuation per unit thickness
            let baseAttenuation = baseMaterialAttenuation(material: material, frequency: frequency)
            
            // Thickness scaling
            let thicknessMultiplier = thickness / 0.1 // Normalized to 10cm
            
            // Angle of incidence correction (Snell's law approximation)
            let angleMultiplier = 1.0 / cos(incidenceAngle)
            
            // Frequency-dependent scaling
            let frequencyMultiplier = frequencyScaling(frequency: frequency)
            
            return baseAttenuation * thicknessMultiplier * angleMultiplier * frequencyMultiplier
        }
        
        private static func baseMaterialAttenuation(material: WallMaterial, frequency: Double) -> Double {
            // Material-specific attenuation in dB per 10cm
            switch material {
            case .drywall:
                return 3.0
            case .concrete:
                return frequency > 5000 ? 18.0 : 15.0
            case .brick:
                return frequency > 5000 ? 12.0 : 10.0
            case .wood:
                return 2.5
            case .glass:
                return frequency > 5000 ? 3.5 : 2.0
            case .metal:
                return frequency > 5000 ? 35.0 : 25.0
            }
        }
        
        private static func frequencyScaling(frequency: Double) -> Double {
            // WiFi 7 frequency-specific scaling
            switch frequency {
            case 2400...2500: // 2.4GHz
                return 1.0
            case 5000...6000: // 5GHz
                return 1.2
            case 6000...7200: // 6GHz
                return 1.4
            default:
                return 1.0
            }
        }
        
        /// Calculate total attenuation through multiple walls
        /// - Parameters:
        ///   - walls: Array of wall segments with materials and thicknesses
        ///   - frequency: Frequency in MHz
        /// - Returns: Total penetration loss in dB
        public static func multiWallAttenuation(
            walls: [(material: WallMaterial, thickness: Double, angle: Double)],
            frequency: Double
        ) -> Double {
            return walls.reduce(0.0) { total, wall in
                total + penetrationLoss(
                    material: wall.material,
                    thickness: wall.thickness,
                    frequency: frequency,
                    incidenceAngle: wall.angle
                )
            }
        }
    }
    
    // MARK: - Environmental Factors
    
    /// Environmental correction factors for different scenarios
    public struct EnvironmentalCorrections {
        
        /// Apply humidity correction to path loss
        /// - Parameters:
        ///   - pathLoss: Original path loss in dB
        ///   - humidity: Relative humidity (0-100%)
        ///   - frequency: Frequency in MHz
        /// - Returns: Corrected path loss in dB
        public static func humidityCorrection(
            pathLoss: Double,
            humidity: Double,
            frequency: Double
        ) -> Double {
            // Water vapor absorption increases with frequency
            let absorptionRate = frequency > 5000 ? 0.01 : 0.005 // dB per % humidity
            let humidityLoss = humidity * absorptionRate
            return pathLoss + humidityLoss
        }
        
        /// Apply temperature correction
        /// - Parameters:
        ///   - pathLoss: Original path loss in dB
        ///   - temperature: Temperature in Celsius
        /// - Returns: Corrected path loss in dB
        public static func temperatureCorrection(
            pathLoss: Double,
            temperature: Double
        ) -> Double {
            // Temperature affects refractive index
            let referenceTemp = 20.0 // Celsius
            let tempDifference = temperature - referenceTemp
            let correctionFactor = tempDifference * 0.001 // Small correction
            return pathLoss * (1 + correctionFactor)
        }
        
        /// Apply furniture/clutter correction
        /// - Parameters:
        ///   - pathLoss: Original path loss in dB
        ///   - clutterDensity: Clutter density factor (0-1)
        ///   - frequency: Frequency in MHz
        /// - Returns: Corrected path loss in dB
        public static func clutterCorrection(
            pathLoss: Double,
            clutterDensity: Double,
            frequency: Double
        ) -> Double {
            // Higher frequencies are more affected by small obstacles
            let clutterEffect = clutterDensity * (frequency > 5000 ? 3.0 : 2.0)
            return pathLoss + clutterEffect
        }
    }
}

// MARK: - Supporting Types

/// Indoor environment types for propagation modeling
public enum IndoorEnvironment: String, CaseIterable {
    case residential = "residential"
    case office = "office"
    case commercial = "commercial"
    case industrial = "industrial"
    
    public var description: String {
        switch self {
        case .residential: return "Residential (homes, apartments)"
        case .office: return "Office (corporate buildings)"
        case .commercial: return "Commercial (retail, restaurants)"
        case .industrial: return "Industrial (factories, warehouses)"
        }
    }
}

/// RF propagation parameters for different scenarios
public struct RFPropagationParameters {
    public let environment: IndoorEnvironment
    public let pathLossExponent: Double
    public let shadowingVariance: Double
    public let reflectionCoefficient: Double
    public let maxReflections: Int
    public let clutterFactor: Double
    
    public init(
        environment: IndoorEnvironment,
        pathLossExponent: Double? = nil,
        shadowingVariance: Double? = nil,
        reflectionCoefficient: Double = 0.7,
        maxReflections: Int = 2,
        clutterFactor: Double = 0.3
    ) {
        self.environment = environment
        self.reflectionCoefficient = reflectionCoefficient
        self.maxReflections = maxReflections
        self.clutterFactor = clutterFactor
        
        // Set default values based on environment
        switch environment {
        case .residential:
            self.pathLossExponent = pathLossExponent ?? 2.8
            self.shadowingVariance = shadowingVariance ?? 4.0
        case .office:
            self.pathLossExponent = pathLossExponent ?? 3.2
            self.shadowingVariance = shadowingVariance ?? 6.0
        case .commercial:
            self.pathLossExponent = pathLossExponent ?? 3.0
            self.shadowingVariance = shadowingVariance ?? 5.0
        case .industrial:
            self.pathLossExponent = pathLossExponent ?? 2.2
            self.shadowingVariance = shadowingVariance ?? 8.0
        }
    }
    
    public static func `default`(for environment: IndoorEnvironment) -> RFPropagationParameters {
        return RFPropagationParameters(environment: environment)
    }
}

// MARK: - Validation and Calibration

/// Model validation utilities
public struct ModelValidation {
    
    /// Validate propagation model against measurements
    /// - Parameters:
    ///   - predictions: Predicted signal strengths
    ///   - measurements: Actual measurements
    /// - Returns: Validation metrics
    public static func validateModel(
        predictions: [Double],
        measurements: [Double]
    ) -> ValidationMetrics {
        guard predictions.count == measurements.count, !predictions.isEmpty else {
            return ValidationMetrics(meanError: Double.infinity, rmse: Double.infinity, correlation: 0.0)
        }
        
        let errors = zip(predictions, measurements).map { abs($0 - $1) }
        let meanError = errors.reduce(0, +) / Double(errors.count)
        
        let squaredErrors = zip(predictions, measurements).map { pow($0 - $1, 2) }
        let rmse = sqrt(squaredErrors.reduce(0, +) / Double(squaredErrors.count))
        
        let correlation = calculateCorrelation(predictions, measurements)
        
        return ValidationMetrics(meanError: meanError, rmse: rmse, correlation: correlation)
    }
    
    private static func calculateCorrelation(_ x: [Double], _ y: [Double]) -> Double {
        let n = Double(x.count)
        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n
        
        let numerator = zip(x, y).reduce(0.0) { sum, pair in
            sum + (pair.0 - meanX) * (pair.1 - meanY)
        }
        
        let denomX = x.reduce(0.0) { sum, value in
            sum + pow(value - meanX, 2)
        }
        
        let denomY = y.reduce(0.0) { sum, value in
            sum + pow(value - meanY, 2)
        }
        
        let denominator = sqrt(denomX * denomY)
        
        return denominator > 0 ? numerator / denominator : 0.0
    }
}

/// Validation metrics for model accuracy
public struct ValidationMetrics {
    public let meanError: Double
    public let rmse: Double
    public let correlation: Double
    
    public init(meanError: Double, rmse: Double, correlation: Double) {
        self.meanError = meanError
        self.rmse = rmse
        self.correlation = correlation
    }
    
    /// Overall quality score (0-1, higher is better)
    public var qualityScore: Double {
        let errorScore = max(0, 1 - meanError / 20.0) // Normalize to 20dB
        let rmseScore = max(0, 1 - rmse / 15.0)       // Normalize to 15dB
        let corrScore = max(0, correlation)           // Already 0-1
        
        return (errorScore + rmseScore + corrScore) / 3.0
    }
    
    /// Whether the model meets accuracy requirements
    public var isAcceptable: Bool {
        return meanError < 10.0 && rmse < 8.0 && correlation > 0.7
    }
}