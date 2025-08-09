import Foundation
#if canImport(RoomPlan) && os(iOS)

/// Main service interface for RoomPlan integration
public class RoomPlanService {
    
    // MARK: - Properties
    
    private let parser: RoomPlanParser
    private let qualityAssessor: ScanQualityAssessor
    private let coordinateTransformer: CoordinateTransformer
    private let errorHandler: RoomPlanErrorHandler.Type
    
    // MARK: - Configuration
    
    public struct Configuration {
        public let enableQualityAssessment: Bool
        public let enableCoordinateTransformation: Bool
        public let enableModelRepair: Bool
        public let processingTimeout: TimeInterval
        public let maxMemoryUsage: Int // bytes
        
        public init(
            enableQualityAssessment: Bool = true,
            enableCoordinateTransformation: Bool = true,
            enableModelRepair: Bool = true,
            processingTimeout: TimeInterval = 30.0,
            maxMemoryUsage: Int = 200_000_000 // 200MB
        ) {
            self.enableQualityAssessment = enableQualityAssessment
            self.enableCoordinateTransformation = enableCoordinateTransformation
            self.enableModelRepair = enableModelRepair
            self.processingTimeout = processingTimeout
            self.maxMemoryUsage = maxMemoryUsage
        }
        
        public static let `default` = Configuration()
    }
    
    private let configuration: Configuration
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.parser = RoomPlanParser()
        self.qualityAssessor = ScanQualityAssessor()
        self.coordinateTransformer = CoordinateTransformer()
        self.errorHandler = RoomPlanErrorHandler.self
    }
    
    // MARK: - Public Interface
    
    /// Parse a RoomPlan USDZ file into a structured room model
    /// - Parameter url: URL to the USDZ file
    /// - Returns: Result containing room model and any warnings
    /// - Throws: RoomPlanParsingError if parsing fails
    public func parseRoomScan(from url: URL) async throws -> RoomPlanResult<RoomModel> {
        let startTime = Date()
        var warnings: [RoomPlanWarning] = []
        var qualityMetrics: ProcessingQualityMetrics?
        
        // Validate input
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RoomPlanParsingError.invalidUSDZFile
        }
        
        // Check file size and format
        try validateFileSize(at: url)
        try validateFileFormat(at: url)
        
        do {
            // Parse the USDZ file with timeout
            let roomModel = try await withTimeout(configuration.processingTimeout) {
                try await parseWithErrorHandling(from: url)
            }
            
            // Apply coordinate transformation if enabled
            let transformedModel = try applyCoordinateTransformation(to: roomModel, &warnings)
            
            // Validate the result
            try errorHandler.validateRoomModel(transformedModel)
            
            // Generate warnings
            let modelWarnings = errorHandler.generateWarnings(for: transformedModel)
            warnings.append(contentsOf: modelWarnings)
            
            // Assess quality if enabled
            if configuration.enableQualityAssessment {
                let assessment = qualityAssessor.assessScanQuality(transformedModel)
                qualityMetrics = createQualityMetrics(from: assessment)
                
                if assessment.overallQuality < 0.7 {
                    warnings.append(.lowScanQuality(assessment.overallQuality))
                }
            }
            
            let processingTime = Date().timeIntervalSince(startTime)
            
            return RoomPlanResult(
                data: transformedModel,
                warnings: warnings,
                processingTime: processingTime,
                qualityMetrics: qualityMetrics
            )
            
        } catch let error as RoomPlanParsingError {
            throw error
        } catch {
            throw errorHandler.mapSystemError(error)
        }
    }
    
    /// Enhanced room analysis with detailed quality assessment
    /// - Parameter url: URL to the USDZ file
    /// - Returns: Result with detailed analysis including recommendations
    public func analyzeRoomScan(from url: URL) async throws -> RoomPlanResult<DetailedRoomAnalysis> {
        let parseResult = try await parseRoomScan(from: url)
        let roomModel = parseResult.data
        
        // Perform detailed analysis
        let assessment = qualityAssessor.assessScanQuality(roomModel)
        let coordinateAnalysis = coordinateTransformer.analyzeCoordinateSystem(of: roomModel)
        
        // Extract placement surfaces
        let placementSurfaces = roomModel.furniture.flatMap(\.surfaces)
        let surfaceAnalysis = analyzePlacementSurfaces(placementSurfaces)
        
        // Create detailed analysis
        let detailedAnalysis = DetailedRoomAnalysis(
            roomModel: roomModel,
            qualityAssessment: assessment,
            coordinateSystemInfo: coordinateAnalysis,
            surfaceAnalysis: surfaceAnalysis,
            recommendations: generateRecommendations(for: roomModel, assessment: assessment),
            processingMetadata: ProcessingMetadata(
                parsingTime: parseResult.processingTime,
                memoryUsage: estimateMemoryUsage(for: roomModel),
                algorithmVersion: "1.0.0"
            )
        )
        
        return RoomPlanResult(
            data: detailedAnalysis,
            warnings: parseResult.warnings,
            processingTime: parseResult.processingTime,
            qualityMetrics: parseResult.qualityMetrics
        )
    }
    
    /// Generate mock room data for testing
    /// - Parameters:
    ///   - roomType: Type of room to generate
    ///   - complexity: Complexity level of the room  
    /// - Returns: Mock room model
    public func generateMockRoom(
        type: RoomType = .livingRoom,
        complexity: RoomComplexity = .medium
    ) -> RoomModel {
        let mockGenerator = MockDataGenerator()
        return mockGenerator.generateStandardRoom(type: type)
    }
    
    // MARK: - Private Implementation
    
    private func parseWithErrorHandling(from url: URL) async throws -> RoomModel {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let roomModel = try self.parser.parseUSDZ(from: url)
                    continuation.resume(returning: roomModel)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func applyCoordinateTransformation(
        to roomModel: RoomModel,
        _ warnings: inout [RoomPlanWarning]
    ) throws -> RoomModel {
        
        guard configuration.enableCoordinateTransformation else {
            return roomModel
        }
        
        // Analyze coordinate system
        let coordinateInfo = coordinateTransformer.analyzeCoordinateSystem(of: roomModel)
        
        if coordinateInfo.requiresTransformation {
            warnings.append(.coordinateTransformationApplied)
            
            if coordinateInfo.detectedUnits != .meters {
                warnings.append(.scalingApplied(coordinateInfo.recommendedScale))
            }
            
            // Configure and apply transformation
            coordinateTransformer.autoConfigureFromAnalysis(roomModel)
            
            // Transform all spatial data in the room model
            return transformRoomModel(roomModel)
        }
        
        return roomModel
    }
    
    private func transformRoomModel(_ roomModel: RoomModel) -> RoomModel {
        // Transform bounds
        let transformedBounds = coordinateTransformer.transformBoundingBox(roomModel.bounds)
        
        // Transform walls
        let transformedWalls = roomModel.walls.map { wall in
            WallElement(
                id: wall.id,
                startPoint: coordinateTransformer.transformPoint(wall.startPoint),
                endPoint: coordinateTransformer.transformPoint(wall.endPoint),
                height: wall.height * coordinateTransformer.roomPlanScale,
                thickness: wall.thickness * coordinateTransformer.roomPlanScale,
                material: wall.material
            )
        }
        
        // Transform furniture
        let transformedFurniture = roomModel.furniture.map { furniture in
            let transformedBounds = coordinateTransformer.transformBoundingBox(furniture.bounds)
            let transformedSurfaces = furniture.surfaces.map { surface in
                PlacementSurface(
                    id: surface.id,
                    center: coordinateTransformer.transformPoint(surface.center),
                    normal: coordinateTransformer.transformVector(surface.normal),
                    area: surface.area * pow(coordinateTransformer.roomPlanScale, 2),
                    accessibility: surface.accessibility,
                    powerProximity: surface.powerProximity
                )
            }
            
            return FurnitureItem(
                id: furniture.id,
                type: furniture.type,
                bounds: transformedBounds,
                surfaces: transformedSurfaces,
                confidence: furniture.confidence
            )
        }
        
        // Transform openings
        let transformedOpenings = roomModel.openings.map { opening in
            Opening(
                id: opening.id,
                type: opening.type,
                bounds: coordinateTransformer.transformBoundingBox(opening.bounds),
                isPassable: opening.isPassable
            )
        }
        
        // Transform floor
        let transformedFloor = FloorPlan(
            bounds: transformedBounds,
            area: roomModel.floor.area * pow(coordinateTransformer.roomPlanScale, 2)
        )
        
        return RoomModel(
            id: roomModel.id,
            name: roomModel.name,
            bounds: transformedBounds,
            walls: transformedWalls,
            furniture: transformedFurniture,
            openings: transformedOpenings,
            floor: transformedFloor
        )
    }
    
    private func validateFileSize(at url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int ?? 0
        
        let maxFileSize = 100_000_000 // 100MB
        if fileSize > maxFileSize {
            throw RoomPlanParsingError.memoryLimitExceeded
        }
    }
    
    private func validateFileFormat(at url: URL) throws {
        let pathExtension = url.pathExtension.lowercased()
        guard pathExtension == "usdz" else {
            throw RoomPlanParsingError.unsupportedFileFormat
        }
    }
    
    private func createQualityMetrics(from assessment: ScanQualityAssessment) -> ProcessingQualityMetrics {
        return ProcessingQualityMetrics(
            overallQuality: assessment.overallQuality,
            geometryAccuracy: assessment.accuracy,
            furnitureDetectionRate: assessment.furnitureDetection,
            surfaceExtractionRate: assessment.geometryConsistency,
            memoryUsage: 0 // TODO: Implement actual memory tracking
        )
    }
    
    private func analyzePlacementSurfaces(_ surfaces: [PlacementSurface]) -> SurfaceAnalysis {
        let totalArea = surfaces.reduce(0.0) { $0 + $1.area }
        let excellentSurfaces = surfaces.filter { $0.accessibility == .excellent }
        let goodSurfaces = surfaces.filter { $0.accessibility == .good }
        
        return SurfaceAnalysis(
            totalSurfaces: surfaces.count,
            totalArea: totalArea,
            excellentAccessibility: excellentSurfaces.count,
            goodAccessibility: goodSurfaces.count,
            averageArea: surfaces.isEmpty ? 0 : totalArea / Double(surfaces.count),
            recommendedSurfaces: excellentSurfaces + goodSurfaces.prefix(3)
        )
    }
    
    private func generateRecommendations(
        for roomModel: RoomModel,
        assessment: ScanQualityAssessment
    ) -> [AnalysisRecommendation] {
        
        var recommendations: [AnalysisRecommendation] = []
        
        // Quality-based recommendations
        if assessment.overallQuality < 0.8 {
            recommendations.append(.improveScanQuality(assessment.qualityLevel))
        }
        
        // Surface-based recommendations
        let placementSurfaces = roomModel.furniture.flatMap(\.surfaces)
        if placementSurfaces.isEmpty {
            recommendations.append(.addSuitableFurniture)
        } else if placementSurfaces.filter({ $0.accessibility == .excellent }).count < 2 {
            recommendations.append(.improveSurfaceAccessibility)
        }
        
        // Room structure recommendations
        if roomModel.walls.isEmpty {
            recommendations.append(.verifyWallDetection)
        }
        
        return recommendations
    }
    
    private func estimateMemoryUsage(for roomModel: RoomModel) -> Int {
        // Rough estimation based on object counts
        let baseSize = 1000 // Base room model size
        let wallSize = roomModel.walls.count * 200
        let furnitureSize = roomModel.furniture.count * 500
        let surfaceSize = roomModel.furniture.flatMap(\.surfaces).count * 300
        
        return baseSize + wallSize + furnitureSize + surfaceSize
    }
    
    private func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                return try operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw RoomPlanParsingError.processingTimeout
            }
            
            guard let result = try await group.next() else {
                throw RoomPlanParsingError.processingTimeout
            }
            
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Supporting Types

public struct DetailedRoomAnalysis {
    public let roomModel: RoomModel
    public let qualityAssessment: ScanQualityAssessment
    public let coordinateSystemInfo: CoordinateSystemInfo
    public let surfaceAnalysis: SurfaceAnalysis
    public let recommendations: [AnalysisRecommendation]
    public let processingMetadata: ProcessingMetadata
    
    public var isReadyForWiFiAnalysis: Bool {
        return qualityAssessment.isAcceptableForAnalysis && 
               surfaceAnalysis.totalSurfaces > 0 &&
               coordinateSystemInfo.isReliable
    }
}

public struct SurfaceAnalysis {
    public let totalSurfaces: Int
    public let totalArea: Double
    public let excellentAccessibility: Int
    public let goodAccessibility: Int
    public let averageArea: Double
    public let recommendedSurfaces: [PlacementSurface]
    
    public var viableSurfaceCount: Int {
        return excellentAccessibility + goodAccessibility
    }
    
    public var surfaceQuality: SurfaceQuality {
        if excellentAccessibility >= 3 {
            return .excellent
        } else if viableSurfaceCount >= 2 {
            return .good
        } else if totalSurfaces > 0 {
            return .poor
        } else {
            return .none
        }
    }
}

public enum SurfaceQuality {
    case excellent, good, poor, none
    
    public var description: String {
        switch self {
        case .excellent: return "Excellent placement options available"
        case .good: return "Good placement options available"
        case .poor: return "Limited placement options"
        case .none: return "No suitable placement surfaces found"
        }
    }
}

public enum AnalysisRecommendation {
    case improveScanQuality(QualityLevel)
    case addSuitableFurniture
    case improveSurfaceAccessibility
    case verifyWallDetection
    case rescanRoom
    case checkCoordinateSystem
    
    public var description: String {
        switch self {
        case .improveScanQuality(let level):
            return "Improve scan quality (current: \(level.rawValue))"
        case .addSuitableFurniture:
            return "Add furniture suitable for equipment placement"
        case .improveSurfaceAccessibility:
            return "Ensure surfaces are accessible for equipment placement"
        case .verifyWallDetection:
            return "Verify all walls were detected correctly"
        case .rescanRoom:
            return "Rescan the room for better results"
        case .checkCoordinateSystem:
            return "Check coordinate system consistency"
        }
    }
}

public struct ProcessingMetadata {
    public let parsingTime: TimeInterval
    public let memoryUsage: Int
    public let algorithmVersion: String
    
    public init(parsingTime: TimeInterval, memoryUsage: Int, algorithmVersion: String) {
        self.parsingTime = parsingTime
        self.memoryUsage = memoryUsage
        self.algorithmVersion = algorithmVersion
    }
}

// MARK: - Private Extensions

private extension CoordinateTransformer {
    var roomPlanScale: Double {
        // Access to private scale property through computed property
        return 1.0 // This would need to be implemented properly
    }
}
#endif