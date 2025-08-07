import Foundation
import RoomPlan
import ARKit
import simd

/// RoomAccuracyValidator provides comprehensive analysis and validation of RoomPlan 3D data
/// against the 2D floor plan rendering to identify accuracy issues and provide recommendations.
class RoomAccuracyValidator: ObservableObject {
    
    // MARK: - Properties
    
    @Published var validationResults: ValidationResults?
    @Published var accuracyMetrics: AccuracyMetrics?
    @Published var recommendations: [AccuracyRecommendation] = []
    
    // MARK: - Data Structures
    
    struct ValidationResults {
        let timestamp: Date
        let capturedRoomData: CapturedRoom
        let extractedRoomData: ExtractedRoomData
        let floorPlanData: FloorPlanData
        let comparisonResults: ComparisonResults
        let overallAccuracyScore: Float
        let validationSummary: String
    }
    
    struct ExtractedRoomData {
        let wallPositions: [WallData]
        let furniturePositions: [FurnitureData]
        let roomDimensions: RoomDimensions
        let floorSurfaces: [FloorSurface]
        let roomBounds: RoomBounds
    }
    
    struct FloorPlanData {
        let renderedWallPoints: [simd_float2]
        let renderedFurniturePositions: [simd_float2]
        let renderedRoomBounds: RoomBounds2D
        let coordinateTransform: CoordinateTransform
    }
    
    struct ComparisonResults {
        let wallAccuracy: WallAccuracyResults
        let furnitureAccuracy: FurnitureAccuracyResults
        let dimensionAccuracy: DimensionAccuracyResults
        let scaleConsistency: ScaleConsistencyResults
    }
    
    struct WallData {
        let id: UUID
        let position: simd_float3
        let dimensions: simd_float3
        let orientation: Float
        let cornerPoints: [simd_float3]
        let confidence: Float
    }
    
    struct FurnitureData {
        let id: UUID
        let category: CapturedRoom.Object.Category
        let position: simd_float3
        let dimensions: simd_float3
        let rotation: Float
        let confidence: Float
        let distanceFromWalls: [Float]
    }
    
    struct RoomDimensions {
        let width: Float
        let length: Float
        let height: Float
        let area: Float
        let perimeter: Float
    }
    
    struct FloorSurface {
        let id: UUID
        let center: simd_float3
        let dimensions: simd_float3
        let boundaryPoints: [simd_float2]
    }
    
    struct RoomBounds {
        let min: simd_float3
        let max: simd_float3
        let center: simd_float3
    }
    
    struct RoomBounds2D {
        let min: simd_float2
        let max: simd_float2
        let center: simd_float2
    }
    
    struct CoordinateTransform {
        let scale: Float
        let translation: simd_float2
        let rotation: Float
    }
    
    struct WallAccuracyResults {
        let positionErrors: [Float]
        let angleErrors: [Float]
        let averagePositionError: Float
        let averageAngleError: Float
        let maxPositionError: Float
        let maxAngleError: Float
        let wallMatchingRate: Float
        let missingWalls: [WallData]
        let extraWalls: [simd_float2]
    }
    
    struct FurnitureAccuracyResults {
        let positionErrors: [Float]
        let scaleErrors: [Float]
        let averagePositionError: Float
        let averageScaleError: Float
        let maxPositionError: Float
        let furnitureMatchingRate: Float
        let misplacedFurniture: [FurnitureData]
        let wallProximityErrors: [Float]
    }
    
    struct DimensionAccuracyResults {
        let widthError: Float
        let lengthError: Float
        let areaError: Float
        let perimeterError: Float
        let aspectRatioError: Float
    }
    
    struct ScaleConsistencyResults {
        let scaleVariation: Float
        let coordinateSystemAlignment: Float
        let transformationAccuracy: Float
    }
    
    struct AccuracyMetrics {
        let overallAccuracy: Float
        let wallAccuracy: Float
        let furnitureAccuracy: Float
        let scaleAccuracy: Float
        let coordinateAccuracy: Float
        
        let detailedBreakdown: [String: Float]
        let confidenceScore: Float
    }
    
    struct AccuracyRecommendation {
        let type: RecommendationType
        let severity: Severity
        let issue: String
        let recommendation: String
        let technicalDetails: String
        let estimatedImpact: Float
    }
    
    enum RecommendationType {
        case wallPositioning
        case furniturePlacement
        case scaleConsistency
        case coordinateAlignment
        case renderingAccuracy
        case dataQuality
    }
    
    enum Severity {
        case critical
        case high
        case medium
        case low
        case info
        
        var color: String {
            switch self {
            case .critical: return "🔴"
            case .high: return "🟠"
            case .medium: return "🟡"
            case .low: return "🟢"
            case .info: return "ℹ️"
            }
        }
    }
    
    // MARK: - Main Validation Function
    
    /// Validates the accuracy of 2D floor plan rendering against 3D RoomPlan data
    func validateRoomAccuracy(
        capturedRoom: CapturedRoom,
        roomAnalyzer: RoomAnalyzer,
        coordinateTransform: CoordinateTransform? = nil
    ) -> ValidationResults {
        print("🔍 RoomAccuracyValidator: Starting comprehensive room accuracy validation")
        print("   3D Data: \(capturedRoom.walls.count) walls, \(capturedRoom.objects.count) objects, \(capturedRoom.floors.count) floors")
        
        let startTime = Date()
        
        // Step 1: Extract detailed 3D room data
        let extractedData = extractDetailedRoomData(from: capturedRoom)
        print("✅ Extracted 3D room data: \(extractedData.wallPositions.count) walls, \(extractedData.furniturePositions.count) furniture items")
        
        // Step 2: Extract 2D floor plan representation
        let floorPlanData = extractFloorPlanData(from: roomAnalyzer, transform: coordinateTransform)
        print("✅ Extracted 2D floor plan data: \(floorPlanData.renderedWallPoints.count) wall points")
        
        // Step 3: Perform detailed accuracy comparisons
        let comparisons = performAccuracyComparisons(
            extracted3D: extractedData,
            floorPlan2D: floorPlanData
        )
        print("✅ Completed accuracy comparisons")
        
        // Step 4: Calculate overall accuracy score
        let overallScore = calculateOverallAccuracyScore(from: comparisons)
        
        // Step 5: Generate validation summary
        let summary = generateValidationSummary(
            extractedData: extractedData,
            comparisons: comparisons,
            score: overallScore
        )
        
        // Step 6: Generate recommendations
        generateRecommendations(from: comparisons, extractedData: extractedData)
        
        let validationTime = Date().timeIntervalSince(startTime)
        print("🎯 Validation completed in \(String(format: "%.2f", validationTime))s with overall accuracy: \(String(format: "%.1f", overallScore * 100))%")
        
        let results = ValidationResults(
            timestamp: Date(),
            capturedRoomData: capturedRoom,
            extractedRoomData: extractedData,
            floorPlanData: floorPlanData,
            comparisonResults: comparisons,
            overallAccuracyScore: overallScore,
            validationSummary: summary
        )
        
        // Update published properties
        DispatchQueue.main.async {
            self.validationResults = results
            self.accuracyMetrics = self.calculateAccuracyMetrics(from: comparisons)
        }
        
        return results
    }
    
    // MARK: - 3D Data Extraction
    
    private func extractDetailedRoomData(from capturedRoom: CapturedRoom) -> ExtractedRoomData {
        print("📐 Extracting detailed 3D room data...")
        
        // Extract wall data with enhanced analysis
        let wallPositions = capturedRoom.walls.enumerated().map { index, wall in
            extractWallData(wall: wall, index: index)
        }
        
        // Extract furniture data with spatial relationships
        let furniturePositions = capturedRoom.objects.enumerated().map { index, object in
            extractFurnitureData(object: object, index: index, walls: capturedRoom.walls)
        }
        
        // Calculate room dimensions from floor surfaces
        let roomDimensions = calculateRoomDimensions(from: capturedRoom.floors)
        
        // Extract floor surface data
        let floorSurfaces = capturedRoom.floors.enumerated().map { index, floor in
            extractFloorSurface(floor: floor, index: index)
        }
        
        // Calculate overall room bounds
        let roomBounds = calculateRoomBounds(from: capturedRoom)
        
        print("   📊 Extracted: \(wallPositions.count) walls, \(furniturePositions.count) furniture, \(floorSurfaces.count) floors")
        
        return ExtractedRoomData(
            wallPositions: wallPositions,
            furniturePositions: furniturePositions,
            roomDimensions: roomDimensions,
            floorSurfaces: floorSurfaces,
            roomBounds: roomBounds
        )
    }
    
    private func extractWallData(wall: CapturedRoom.Surface, index: Int) -> WallData {
        let transform = wall.transform
        let position = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let dimensions = wall.dimensions
        
        // Calculate wall orientation from transform matrix
        let forwardVector = simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        let orientation = atan2(forwardVector.z, forwardVector.x)
        
        // Calculate wall corner points
        let cornerPoints = calculateWallCornerPoints(transform: transform, dimensions: dimensions)
        
        // Convert confidence to float
        let confidenceValue = confidenceToFloat(wall.confidence)
        
        print("   🧱 Wall \(index): pos(\(String(format: "%.2f", position.x)), \(String(format: "%.2f", position.z))), orientation: \(String(format: "%.1f", orientation * 180 / .pi))°, confidence: \(String(format: "%.2f", confidenceValue))")
        
        return WallData(
            id: UUID(),
            position: position,
            dimensions: dimensions,
            orientation: orientation,
            cornerPoints: cornerPoints,
            confidence: confidenceValue
        )
    }
    
    private func calculateWallCornerPoints(transform: simd_float4x4, dimensions: simd_float3) -> [simd_float3] {
        let center = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        
        // Extract basis vectors from transform
        let right = simd_normalize(simd_float3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z))
        let up = simd_normalize(simd_float3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z))
        let forward = simd_normalize(simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
        
        let halfWidth = dimensions.x / 2
        let halfHeight = dimensions.y / 2
        let halfDepth = dimensions.z / 2
        
        // Calculate 8 corner points of the wall
        return [
            center - right * halfWidth - up * halfHeight - forward * halfDepth,
            center + right * halfWidth - up * halfHeight - forward * halfDepth,
            center + right * halfWidth + up * halfHeight - forward * halfDepth,
            center - right * halfWidth + up * halfHeight - forward * halfDepth,
            center - right * halfWidth - up * halfHeight + forward * halfDepth,
            center + right * halfWidth - up * halfHeight + forward * halfDepth,
            center + right * halfWidth + up * halfHeight + forward * halfDepth,
            center - right * halfWidth + up * halfHeight + forward * halfDepth
        ]
    }
    
    private func extractFurnitureData(object: CapturedRoom.Object, index: Int, walls: [CapturedRoom.Surface]) -> FurnitureData {
        let transform = object.transform
        let position = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let dimensions = object.dimensions
        
        // Calculate furniture rotation
        let forwardVector = simd_float3(transform.columns.2.x, 0, transform.columns.2.z)
        let rotation = atan2(forwardVector.z, forwardVector.x)
        
        // Calculate distances to all walls
        let distancesToWalls = walls.map { wall in
            let wallPosition = simd_float3(wall.transform.columns.3.x, wall.transform.columns.3.y, wall.transform.columns.3.z)
            return simd_distance(position, wallPosition)
        }
        
        let confidence = confidenceToFloat(object.confidence)
        
        print("   📦 Furniture \(index) (\(object.category)): pos(\(String(format: "%.2f", position.x)), \(String(format: "%.2f", position.z))), nearest wall: \(String(format: "%.2f", distancesToWalls.min() ?? 0))m")
        
        return FurnitureData(
            id: UUID(),
            category: object.category,
            position: position,
            dimensions: dimensions,
            rotation: rotation,
            confidence: confidence,
            distanceFromWalls: distancesToWalls
        )
    }
    
    private func calculateRoomDimensions(from floors: [CapturedRoom.Surface]) -> RoomDimensions {
        guard !floors.isEmpty else {
            return RoomDimensions(width: 0, length: 0, height: 0, area: 0, perimeter: 0)
        }
        
        // Use the largest floor surface for room dimensions
        let primaryFloor = floors.max { a, b in
            (a.dimensions.x * a.dimensions.z) < (b.dimensions.x * b.dimensions.z)
        } ?? floors[0]
        
        let width = primaryFloor.dimensions.x
        let length = primaryFloor.dimensions.z
        let height = primaryFloor.dimensions.y
        let area = width * length
        let perimeter = 2 * (width + length)
        
        print("   📏 Room dimensions: \(String(format: "%.2f", width))m × \(String(format: "%.2f", length))m, area: \(String(format: "%.1f", area))m²")
        
        return RoomDimensions(
            width: width,
            length: length,
            height: height,
            area: area,
            perimeter: perimeter
        )
    }
    
    private func extractFloorSurface(floor: CapturedRoom.Surface, index: Int) -> FloorSurface {
        let transform = floor.transform
        let center = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let dimensions = floor.dimensions
        
        // Calculate boundary points from floor surface
        let boundaryPoints = calculateFloorBoundaryPoints(transform: transform, dimensions: dimensions)
        
        return FloorSurface(
            id: UUID(),
            center: center,
            dimensions: dimensions,
            boundaryPoints: boundaryPoints
        )
    }
    
    private func calculateFloorBoundaryPoints(transform: simd_float4x4, dimensions: simd_float3) -> [simd_float2] {
        let center = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        
        // Extract rotation from transform
        let forwardX = transform.columns.2.x
        let forwardZ = transform.columns.2.z
        let rotation = atan2(forwardZ, forwardX)
        
        let halfWidth = dimensions.x / 2
        let halfDepth = dimensions.z / 2
        
        // Create corners in local space
        let localCorners = [
            simd_float2(-halfWidth, -halfDepth),
            simd_float2(halfWidth, -halfDepth),
            simd_float2(halfWidth, halfDepth),
            simd_float2(-halfWidth, halfDepth)
        ]
        
        // Transform to world coordinates
        let center2D = simd_float2(center.x, center.z)
        return localCorners.map { corner in
            let rotatedX = corner.x * cos(rotation) - corner.y * sin(rotation)
            let rotatedZ = corner.x * sin(rotation) + corner.y * cos(rotation)
            return center2D + simd_float2(rotatedX, rotatedZ)
        }
    }
    
    private func calculateRoomBounds(from capturedRoom: CapturedRoom) -> RoomBounds {
        var allPoints: [simd_float3] = []
        
        // Add wall positions
        for wall in capturedRoom.walls {
            let position = simd_float3(wall.transform.columns.3.x, wall.transform.columns.3.y, wall.transform.columns.3.z)
            allPoints.append(position)
        }
        
        // Add object positions
        for object in capturedRoom.objects {
            let position = simd_float3(object.transform.columns.3.x, object.transform.columns.3.y, object.transform.columns.3.z)
            allPoints.append(position)
        }
        
        // Add floor centers
        for floor in capturedRoom.floors {
            let position = simd_float3(floor.transform.columns.3.x, floor.transform.columns.3.y, floor.transform.columns.3.z)
            allPoints.append(position)
        }
        
        guard !allPoints.isEmpty else {
            return RoomBounds(min: simd_float3(0, 0, 0), max: simd_float3(0, 0, 0), center: simd_float3(0, 0, 0))
        }
        
        let minX = allPoints.map { $0.x }.min() ?? 0
        let maxX = allPoints.map { $0.x }.max() ?? 0
        let minY = allPoints.map { $0.y }.min() ?? 0
        let maxY = allPoints.map { $0.y }.max() ?? 0
        let minZ = allPoints.map { $0.z }.min() ?? 0
        let maxZ = allPoints.map { $0.z }.max() ?? 0
        
        let min = simd_float3(minX, minY, minZ)
        let max = simd_float3(maxX, maxY, maxZ)
        let center = (min + max) / 2
        
        return RoomBounds(min: min, max: max, center: center)
    }
    
    // MARK: - 2D Floor Plan Data Extraction
    
    private func extractFloorPlanData(from roomAnalyzer: RoomAnalyzer, transform: CoordinateTransform?) -> FloorPlanData {
        print("🎨 Extracting 2D floor plan rendering data...")
        
        // Extract wall points from room analyzer
        var allWallPoints: [simd_float2] = []
        for room in roomAnalyzer.identifiedRooms {
            allWallPoints.append(contentsOf: room.wallPoints)
        }
        
        // Extract furniture positions
        let furniturePositions = roomAnalyzer.furnitureItems.map { furniture in
            simd_float2(furniture.position.x, furniture.position.z)
        }
        
        // Calculate 2D room bounds
        let roomBounds2D = calculate2DRoomBounds(wallPoints: allWallPoints, furniturePositions: furniturePositions)
        
        // Use provided transform or calculate default
        let coordinateTransform = transform ?? calculateCoordinateTransform(from: roomBounds2D)
        
        print("   🎨 2D Data: \(allWallPoints.count) wall points, \(furniturePositions.count) furniture positions")
        
        return FloorPlanData(
            renderedWallPoints: allWallPoints,
            renderedFurniturePositions: furniturePositions,
            renderedRoomBounds: roomBounds2D,
            coordinateTransform: coordinateTransform
        )
    }
    
    private func calculate2DRoomBounds(wallPoints: [simd_float2], furniturePositions: [simd_float2]) -> RoomBounds2D {
        let allPoints = wallPoints + furniturePositions
        
        guard !allPoints.isEmpty else {
            return RoomBounds2D(min: simd_float2(0, 0), max: simd_float2(0, 0), center: simd_float2(0, 0))
        }
        
        let minX = allPoints.map { $0.x }.min() ?? 0
        let maxX = allPoints.map { $0.x }.max() ?? 0
        let minY = allPoints.map { $0.y }.min() ?? 0
        let maxY = allPoints.map { $0.y }.max() ?? 0
        
        let min = simd_float2(minX, minY)
        let max = simd_float2(maxX, maxY)
        let center = (min + max) / 2
        
        return RoomBounds2D(min: min, max: max, center: center)
    }
    
    private func calculateCoordinateTransform(from bounds2D: RoomBounds2D) -> CoordinateTransform {
        let size = bounds2D.max - bounds2D.min
        let scale = max(size.x, size.y) > 0 ? 1.0 / max(size.x, size.y) : 1.0
        
        return CoordinateTransform(
            scale: scale,
            translation: -bounds2D.center,
            rotation: 0
        )
    }
    
    // MARK: - Accuracy Comparisons
    
    private func performAccuracyComparisons(extracted3D: ExtractedRoomData, floorPlan2D: FloorPlanData) -> ComparisonResults {
        print("🔍 Performing detailed accuracy comparisons...")
        
        let wallAccuracy = analyzeWallAccuracy(
            walls3D: extracted3D.wallPositions,
            walls2D: floorPlan2D.renderedWallPoints
        )
        
        let furnitureAccuracy = analyzeFurnitureAccuracy(
            furniture3D: extracted3D.furniturePositions,
            furniture2D: floorPlan2D.renderedFurniturePositions
        )
        
        let dimensionAccuracy = analyzeDimensionAccuracy(
            dimensions3D: extracted3D.roomDimensions,
            bounds2D: floorPlan2D.renderedRoomBounds
        )
        
        let scaleConsistency = analyzeScaleConsistency(
            bounds3D: extracted3D.roomBounds,
            bounds2D: floorPlan2D.renderedRoomBounds,
            transform: floorPlan2D.coordinateTransform
        )
        
        return ComparisonResults(
            wallAccuracy: wallAccuracy,
            furnitureAccuracy: furnitureAccuracy,
            dimensionAccuracy: dimensionAccuracy,
            scaleConsistency: scaleConsistency
        )
    }
    
    private func analyzeWallAccuracy(walls3D: [WallData], walls2D: [simd_float2]) -> WallAccuracyResults {
        print("   🧱 Analyzing wall accuracy...")
        
        var positionErrors: [Float] = []
        var angleErrors: [Float] = []
        var missingWalls: [WallData] = []
        var matchedWalls = 0
        
        for wall3D in walls3D {
            // Find closest 2D wall point
            let wall3DPos2D = simd_float2(wall3D.position.x, wall3D.position.z)
            
            if let closest2D = findClosest2DPoint(to: wall3DPos2D, in: walls2D) {
                let distance = simd_distance(wall3DPos2D, closest2D)
                positionErrors.append(distance)
                
                if distance < 1.0 { // Consider walls within 1m as matched
                    matchedWalls += 1
                } else {
                    missingWalls.append(wall3D)
                }
            } else {
                missingWalls.append(wall3D)
            }
        }
        
        let averagePositionError = positionErrors.isEmpty ? 0 : positionErrors.reduce(0, +) / Float(positionErrors.count)
        let maxPositionError = positionErrors.max() ?? 0
        let wallMatchingRate = walls3D.isEmpty ? 1.0 : Float(matchedWalls) / Float(walls3D.count)
        
        // Calculate angle errors (simplified for now)
        let averageAngleError: Float = 0 // Would need more sophisticated angle matching
        
        print("     📊 Wall accuracy: avg error \(String(format: "%.2f", averagePositionError))m, matching rate \(String(format: "%.1f", wallMatchingRate * 100))%")
        
        return WallAccuracyResults(
            positionErrors: positionErrors,
            angleErrors: angleErrors,
            averagePositionError: averagePositionError,
            averageAngleError: averageAngleError,
            maxPositionError: maxPositionError,
            maxAngleError: 0,
            wallMatchingRate: wallMatchingRate,
            missingWalls: missingWalls,
            extraWalls: []
        )
    }
    
    private func analyzeFurnitureAccuracy(furniture3D: [FurnitureData], furniture2D: [simd_float2]) -> FurnitureAccuracyResults {
        print("   📦 Analyzing furniture accuracy...")
        
        var positionErrors: [Float] = []
        var scaleErrors: [Float] = []
        var misplacedFurniture: [FurnitureData] = []
        var matchedFurniture = 0
        
        for furniture3D in furniture3D {
            let furniture3DPos2D = simd_float2(furniture3D.position.x, furniture3D.position.z)
            
            if let closest2D = findClosest2DPoint(to: furniture3DPos2D, in: furniture2D) {
                let distance = simd_distance(furniture3DPos2D, closest2D)
                positionErrors.append(distance)
                
                if distance < 0.5 { // Consider furniture within 0.5m as matched
                    matchedFurniture += 1
                } else {
                    misplacedFurniture.append(furniture3D)
                }
            } else {
                misplacedFurniture.append(furniture3D)
            }
        }
        
        let averagePositionError = positionErrors.isEmpty ? 0 : positionErrors.reduce(0, +) / Float(positionErrors.count)
        let maxPositionError = positionErrors.max() ?? 0
        let furnitureMatchingRate = furniture3D.isEmpty ? 1.0 : Float(matchedFurniture) / Float(furniture3D.count)
        
        // Calculate wall proximity errors
        let wallProximityErrors = furniture3D.compactMap { furniture in
            furniture.distanceFromWalls.min()
        }
        
        print("     📊 Furniture accuracy: avg error \(String(format: "%.2f", averagePositionError))m, matching rate \(String(format: "%.1f", furnitureMatchingRate * 100))%")
        
        return FurnitureAccuracyResults(
            positionErrors: positionErrors,
            scaleErrors: scaleErrors,
            averagePositionError: averagePositionError,
            averageScaleError: 0,
            maxPositionError: maxPositionError,
            furnitureMatchingRate: furnitureMatchingRate,
            misplacedFurniture: misplacedFurniture,
            wallProximityErrors: wallProximityErrors
        )
    }
    
    private func analyzeDimensionAccuracy(dimensions3D: RoomDimensions, bounds2D: RoomBounds2D) -> DimensionAccuracyResults {
        print("   📏 Analyzing dimension accuracy...")
        
        let bounds2DSize = bounds2D.max - bounds2D.min
        let widthError = abs(dimensions3D.width - bounds2DSize.x) / dimensions3D.width
        let lengthError = abs(dimensions3D.length - bounds2DSize.y) / dimensions3D.length
        
        let area2D = bounds2DSize.x * bounds2DSize.y
        let areaError = abs(dimensions3D.area - area2D) / dimensions3D.area
        
        let perimeter2D = 2 * (bounds2DSize.x + bounds2DSize.y)
        let perimeterError = abs(dimensions3D.perimeter - perimeter2D) / dimensions3D.perimeter
        
        let aspectRatio3D = dimensions3D.width / dimensions3D.length
        let aspectRatio2D = bounds2DSize.x / bounds2DSize.y
        let aspectRatioError = abs(aspectRatio3D - aspectRatio2D) / aspectRatio3D
        
        print("     📊 Dimension errors: width \(String(format: "%.1f", widthError * 100))%, area \(String(format: "%.1f", areaError * 100))%")
        
        return DimensionAccuracyResults(
            widthError: widthError,
            lengthError: lengthError,
            areaError: areaError,
            perimeterError: perimeterError,
            aspectRatioError: aspectRatioError
        )
    }
    
    private func analyzeScaleConsistency(bounds3D: RoomBounds, bounds2D: RoomBounds2D, transform: CoordinateTransform) -> ScaleConsistencyResults {
        print("   📐 Analyzing scale consistency...")
        
        let size3D = bounds3D.max - bounds3D.min
        let size2D = bounds2D.max - bounds2D.min
        
        let scaleX = size2D.x / size3D.x
        let scaleZ = size2D.y / size3D.z
        
        let scaleVariation = abs(scaleX - scaleZ) / max(scaleX, scaleZ)
        
        // Simple coordinate system alignment check
        let center3D2D = simd_float2(bounds3D.center.x, bounds3D.center.z)
        let centerAlignment = simd_distance(center3D2D, bounds2D.center)
        
        let transformationAccuracy = 1.0 - min(scaleVariation, 1.0)
        
        print("     📊 Scale consistency: variation \(String(format: "%.1f", scaleVariation * 100))%, accuracy \(String(format: "%.1f", transformationAccuracy * 100))%")
        
        return ScaleConsistencyResults(
            scaleVariation: scaleVariation,
            coordinateSystemAlignment: centerAlignment,
            transformationAccuracy: transformationAccuracy
        )
    }
    
    // MARK: - Helper Functions
    
    private func findClosest2DPoint(to point: simd_float2, in points: [simd_float2]) -> simd_float2? {
        guard !points.isEmpty else { return nil }
        
        return points.min { a, b in
            simd_distance(point, a) < simd_distance(point, b)
        }
    }
    
    private func confidenceToFloat(_ confidence: CapturedRoom.Confidence) -> Float {
        switch confidence {
        case .high: return 0.9
        case .medium: return 0.6
        case .low: return 0.3
        @unknown default: return 0.3
        }
    }
    
    // MARK: - Scoring and Recommendations
    
    private func calculateOverallAccuracyScore(from comparisons: ComparisonResults) -> Float {
        let wallScore = comparisons.wallAccuracy.wallMatchingRate * (1.0 - comparisons.wallAccuracy.averagePositionError / 2.0)
        let furnitureScore = comparisons.furnitureAccuracy.furnitureMatchingRate * (1.0 - comparisons.furnitureAccuracy.averagePositionError / 1.0)
        let dimensionScore = 1.0 - (comparisons.dimensionAccuracy.areaError + comparisons.dimensionAccuracy.aspectRatioError) / 2.0
        let scaleScore = comparisons.scaleConsistency.transformationAccuracy
        
        // Weighted average
        let overallScore = (wallScore * 0.35 + furnitureScore * 0.25 + dimensionScore * 0.25 + scaleScore * 0.15)
        
        return max(0, min(1, overallScore))
    }
    
    private func calculateAccuracyMetrics(from comparisons: ComparisonResults) -> AccuracyMetrics {
        let wallAccuracy = comparisons.wallAccuracy.wallMatchingRate * (1.0 - min(comparisons.wallAccuracy.averagePositionError / 2.0, 1.0))
        let furnitureAccuracy = comparisons.furnitureAccuracy.furnitureMatchingRate
        let scaleAccuracy = comparisons.scaleConsistency.transformationAccuracy
        let coordinateAccuracy = 1.0 - min(comparisons.scaleConsistency.coordinateSystemAlignment / 5.0, 1.0)
        
        let overallAccuracy = calculateOverallAccuracyScore(from: comparisons)
        
        let detailedBreakdown: [String: Float] = [
            "Wall Positioning": wallAccuracy,
            "Furniture Placement": furnitureAccuracy,
            "Scale Consistency": scaleAccuracy,
            "Coordinate Alignment": coordinateAccuracy,
            "Dimension Accuracy": 1.0 - comparisons.dimensionAccuracy.areaError,
            "Room Shape": 1.0 - comparisons.dimensionAccuracy.aspectRatioError
        ]
        
        let confidenceScore = (wallAccuracy + furnitureAccuracy + scaleAccuracy + coordinateAccuracy) / 4.0
        
        return AccuracyMetrics(
            overallAccuracy: overallAccuracy,
            wallAccuracy: wallAccuracy,
            furnitureAccuracy: furnitureAccuracy,
            scaleAccuracy: scaleAccuracy,
            coordinateAccuracy: coordinateAccuracy,
            detailedBreakdown: detailedBreakdown,
            confidenceScore: confidenceScore
        )
    }
    
    private func generateRecommendations(from comparisons: ComparisonResults, extractedData: ExtractedRoomData) {
        var newRecommendations: [AccuracyRecommendation] = []
        
        // Wall positioning recommendations
        if comparisons.wallAccuracy.averagePositionError > 0.5 {
            newRecommendations.append(AccuracyRecommendation(
                type: .wallPositioning,
                severity: comparisons.wallAccuracy.averagePositionError > 1.0 ? .high : .medium,
                issue: "Wall positions in 2D floor plan deviate significantly from 3D data",
                recommendation: "Improve wall boundary extraction from RoomPlan surfaces. Consider using actual wall corner points instead of surface centers.",
                technicalDetails: "Average position error: \(String(format: "%.2f", comparisons.wallAccuracy.averagePositionError))m. Max error: \(String(format: "%.2f", comparisons.wallAccuracy.maxPositionError))m",
                estimatedImpact: comparisons.wallAccuracy.averagePositionError
            ))
        }
        
        // Furniture placement recommendations
        if comparisons.furnitureAccuracy.furnitureMatchingRate < 0.8 {
            newRecommendations.append(AccuracyRecommendation(
                type: .furniturePlacement,
                severity: comparisons.furnitureAccuracy.furnitureMatchingRate < 0.5 ? .high : .medium,
                issue: "Furniture placement accuracy is below acceptable threshold",
                recommendation: "Review furniture coordinate transformation. Ensure consistent coordinate system between 3D detection and 2D rendering.",
                technicalDetails: "Matching rate: \(String(format: "%.1f", comparisons.furnitureAccuracy.furnitureMatchingRate * 100))%. Average error: \(String(format: "%.2f", comparisons.furnitureAccuracy.averagePositionError))m",
                estimatedImpact: 1.0 - comparisons.furnitureAccuracy.furnitureMatchingRate
            ))
        }
        
        // Scale consistency recommendations
        if comparisons.scaleConsistency.scaleVariation > 0.1 {
            newRecommendations.append(AccuracyRecommendation(
                type: .scaleConsistency,
                severity: comparisons.scaleConsistency.scaleVariation > 0.2 ? .high : .medium,
                issue: "Scale inconsistency detected between axes",
                recommendation: "Implement uniform scaling algorithm. Verify coordinate transform calculations maintain aspect ratio.",
                technicalDetails: "Scale variation: \(String(format: "%.1f", comparisons.scaleConsistency.scaleVariation * 100))%",
                estimatedImpact: comparisons.scaleConsistency.scaleVariation
            ))
        }
        
        // Dimension accuracy recommendations
        if comparisons.dimensionAccuracy.areaError > 0.1 {
            newRecommendations.append(AccuracyRecommendation(
                type: .renderingAccuracy,
                severity: comparisons.dimensionAccuracy.areaError > 0.2 ? .high : .medium,
                issue: "Room area calculation shows significant discrepancy",
                recommendation: "Verify room boundary calculation algorithm. Check floor surface interpretation and boundary point extraction.",
                technicalDetails: "Area error: \(String(format: "%.1f", comparisons.dimensionAccuracy.areaError * 100))%",
                estimatedImpact: comparisons.dimensionAccuracy.areaError
            ))
        }
        
        // Data quality recommendations
        let lowConfidenceItems = extractedData.furniturePositions.filter { $0.confidence < 0.5 }.count
        if lowConfidenceItems > 0 {
            newRecommendations.append(AccuracyRecommendation(
                type: .dataQuality,
                severity: .info,
                issue: "Some detected objects have low confidence scores",
                recommendation: "Consider filtering or highlighting low-confidence detections in the visualization.",
                technicalDetails: "\(lowConfidenceItems) items with confidence < 0.5",
                estimatedImpact: Float(lowConfidenceItems) / Float(extractedData.furniturePositions.count)
            ))
        }
        
        DispatchQueue.main.async {
            self.recommendations = newRecommendations
        }
    }
    
    private func generateValidationSummary(extractedData: ExtractedRoomData, comparisons: ComparisonResults, score: Float) -> String {
        let wallAccuracyPercent = comparisons.wallAccuracy.wallMatchingRate * 100
        let furnitureAccuracyPercent = comparisons.furnitureAccuracy.furnitureMatchingRate * 100
        let scaleAccuracyPercent = comparisons.scaleConsistency.transformationAccuracy * 100
        
        return """
        🎯 Room Accuracy Validation Summary
        
        📊 Overall Accuracy: \(String(format: "%.1f", score * 100))%
        
        🧱 Wall Analysis:
        • Position matching: \(String(format: "%.1f", wallAccuracyPercent))%
        • Average position error: \(String(format: "%.2f", comparisons.wallAccuracy.averagePositionError))m
        • Missing walls: \(comparisons.wallAccuracy.missingWalls.count)
        
        📦 Furniture Analysis:
        • Position matching: \(String(format: "%.1f", furnitureAccuracyPercent))%
        • Average position error: \(String(format: "%.2f", comparisons.furnitureAccuracy.averagePositionError))m
        • Misplaced items: \(comparisons.furnitureAccuracy.misplacedFurniture.count)
        
        📏 Room Dimensions:
        • Area accuracy: \(String(format: "%.1f", (1.0 - comparisons.dimensionAccuracy.areaError) * 100))%
        • Aspect ratio accuracy: \(String(format: "%.1f", (1.0 - comparisons.dimensionAccuracy.aspectRatioError) * 100))%
        
        📐 Scale Consistency:
        • Transformation accuracy: \(String(format: "%.1f", scaleAccuracyPercent))%
        • Scale variation: \(String(format: "%.1f", comparisons.scaleConsistency.scaleVariation * 100))%
        
        🔧 Recommendations: \(recommendations.count) issues identified
        """
    }
    
    // MARK: - Debugging and Visualization
    
    func generateDebugVisualizationData() -> DebugVisualizationData? {
        guard let results = validationResults else { return nil }
        
        return DebugVisualizationData(
            original3DWalls: results.extractedRoomData.wallPositions.map { wall in
                DebugWall3D(position: wall.position, dimensions: wall.dimensions, confidence: wall.confidence)
            },
            rendered2DWalls: results.floorPlanData.renderedWallPoints,
            original3DFurniture: results.extractedRoomData.furniturePositions.map { furniture in
                DebugFurniture3D(position: furniture.position, dimensions: furniture.dimensions, category: furniture.category)
            },
            rendered2DFurniture: results.floorPlanData.renderedFurniturePositions,
            coordinateTransform: results.floorPlanData.coordinateTransform,
            accuracyHeatmap: generateAccuracyHeatmap(from: results.comparisonResults)
        )
    }
    
    private func generateAccuracyHeatmap(from comparisons: ComparisonResults) -> [AccuracyHeatmapPoint] {
        var heatmapPoints: [AccuracyHeatmapPoint] = []
        
        // Add wall accuracy points
        for (index, error) in comparisons.wallAccuracy.positionErrors.enumerated() {
            let accuracy = max(0, 1.0 - error / 2.0) // Normalize to 0-1 scale
            heatmapPoints.append(AccuracyHeatmapPoint(
                position: simd_float2(0, 0), // Would need actual wall positions
                accuracy: accuracy,
                type: .wall
            ))
        }
        
        // Add furniture accuracy points
        for (index, error) in comparisons.furnitureAccuracy.positionErrors.enumerated() {
            let accuracy = max(0, 1.0 - error / 1.0) // Normalize to 0-1 scale
            heatmapPoints.append(AccuracyHeatmapPoint(
                position: simd_float2(0, 0), // Would need actual furniture positions
                accuracy: accuracy,
                type: .furniture
            ))
        }
        
        return heatmapPoints
    }
}

// MARK: - Debug Visualization Data Structures

struct DebugVisualizationData {
    let original3DWalls: [DebugWall3D]
    let rendered2DWalls: [simd_float2]
    let original3DFurniture: [DebugFurniture3D]
    let rendered2DFurniture: [simd_float2]
    let coordinateTransform: RoomAccuracyValidator.CoordinateTransform
    let accuracyHeatmap: [AccuracyHeatmapPoint]
}

struct DebugWall3D {
    let position: simd_float3
    let dimensions: simd_float3
    let confidence: Float
}

struct DebugFurniture3D {
    let position: simd_float3
    let dimensions: simd_float3
    let category: CapturedRoom.Object.Category
}

struct AccuracyHeatmapPoint {
    let position: simd_float2
    let accuracy: Float
    let type: AccuracyPointType
}

enum AccuracyPointType {
    case wall
    case furniture
    case room
}

// MARK: - Extensions

extension RoomType {
    var rawValue: String {
        switch self {
        case .livingRoom: return "Living Room"
        case .kitchen: return "Kitchen"
        case .bedroom: return "Bedroom"
        case .bathroom: return "Bathroom"
        case .diningRoom: return "Dining Room"
        case .office: return "Office"
        case .hallway: return "Hallway"
        case .closet: return "Closet"
        case .laundryRoom: return "Laundry Room"
        case .garage: return "Garage"
        case .unknown: return "Unknown"
        }
    }
}

// Support for RoomType if not already defined
enum RoomType {
    case livingRoom
    case kitchen
    case bedroom
    case bathroom
    case diningRoom
    case office
    case hallway
    case closet
    case laundryRoom
    case garage
    case unknown
}