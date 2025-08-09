import Foundation

/// Assesses the quality of RoomPlan scans and determines if they're suitable for WiFi analysis
public class ScanQualityAssessor {
    
    // MARK: - Quality Thresholds
    
    private struct Thresholds {
        static let minRoomVolume: Double = 2.0        // 2 cubic meters minimum
        static let maxRoomVolume: Double = 1000.0     // 1000 cubic meters maximum
        static let minFurnitureConfidence: Double = 0.3
        static let minWallCount: Int = 3              // At least 3 walls for meaningful analysis
        static let maxAspectRatio: Double = 10.0      // Room shouldn't be extremely elongated
        static let minFloorArea: Double = 4.0         // 4 square meters minimum
    }
    
    // MARK: - Public Interface
    
    /// Assess the overall quality of a room scan
    /// - Parameter roomModel: The parsed room model to assess
    /// - Returns: Comprehensive quality assessment
    public func assessScanQuality(_ roomModel: RoomModel) -> ScanQualityAssessment {
        let completeness = assessRoomCompleteness(roomModel)
        let accuracy = assessGeometricAccuracy(roomModel)
        let furnitureDetection = assessFurnitureDetection(roomModel)
        let consistency = assessGeometryConsistency(roomModel)
        
        let overallQuality = calculateOverallQuality(
            completeness: completeness,
            accuracy: accuracy,
            furnitureDetection: furnitureDetection,
            consistency: consistency
        )
        
        let issues = identifyQualityIssues(roomModel)
        let recommendations = generateRecommendations(for: issues)
        
        return ScanQualityAssessment(
            completeness: completeness,
            accuracy: accuracy,
            furnitureDetection: furnitureDetection,
            geometryConsistency: consistency,
            overallQuality: overallQuality,
            identifiedIssues: issues,
            recommendations: recommendations
        )
    }
    
    // MARK: - Completeness Assessment
    
    private func assessRoomCompleteness(_ room: RoomModel) -> Double {
        var score = 0.0
        var maxScore = 0.0
        
        // Check for basic room structure (40% of completeness score)
        maxScore += 0.4
        if !room.walls.isEmpty {
            score += 0.2
        }
        if room.floor.area > 0 {
            score += 0.2
        }
        
        // Check room bounds reasonableness (30% of completeness score)
        maxScore += 0.3
        let volume = room.bounds.volume
        if volume >= Thresholds.minRoomVolume && volume <= Thresholds.maxRoomVolume {
            score += 0.3
        } else if volume > 0 {
            // Partial credit for having some volume
            score += 0.1
        }
        
        // Check furniture presence (20% of completeness score)
        maxScore += 0.2
        if !room.furniture.isEmpty {
            let furnitureCount = room.furniture.count
            let furnitureScore = min(1.0, Double(furnitureCount) / 5.0) // Optimal around 5 pieces
            score += 0.2 * furnitureScore
        }
        
        // Check for openings (10% of completeness score)
        maxScore += 0.1
        if !room.openings.isEmpty {
            score += 0.1
        }
        
        return maxScore > 0 ? score / maxScore : 0.0
    }
    
    // MARK: - Accuracy Assessment
    
    private func assessGeometricAccuracy(_ room: RoomModel) -> Double {
        var score = 0.0
        var checks = 0
        
        // Check room proportions
        checks += 1
        let size = room.bounds.size
        let aspectRatio = max(size.x, size.y) / min(size.x, size.y)
        if aspectRatio <= Thresholds.maxAspectRatio {
            score += 1.0
        } else {
            // Gradual penalty for extreme aspect ratios
            score += max(0.0, 1.0 - (aspectRatio - Thresholds.maxAspectRatio) / 10.0)
        }
        
        // Check wall consistency
        if !room.walls.isEmpty {
            checks += 1
            score += assessWallConsistency(room.walls)
        }
        
        // Check furniture-room size consistency
        if !room.furniture.isEmpty {
            checks += 1
            score += assessFurnitureRoomConsistency(room.furniture, roomBounds: room.bounds)
        }
        
        // Check floor area consistency
        checks += 1
        let calculatedFloorArea = size.x * size.y
        let reportedFloorArea = room.floor.area
        let areaRatio = min(calculatedFloorArea, reportedFloorArea) / max(calculatedFloorArea, reportedFloorArea)
        score += areaRatio
        
        return checks > 0 ? score / Double(checks) : 0.0
    }
    
    private func assessWallConsistency(_ walls: [WallElement]) -> Double {
        guard walls.count >= Thresholds.minWallCount else { return 0.0 }
        
        var consistencyScore = 0.0
        var checks = 0
        
        // Check wall connectivity (walls should form a connected boundary)
        checks += 1
        let connectivityScore = calculateWallConnectivity(walls)
        consistencyScore += connectivityScore
        
        // Check wall heights are consistent
        checks += 1
        let heights = walls.map(\.height)
        let avgHeight = heights.reduce(0, +) / Double(heights.count)
        let heightVariance = heights.map { pow($0 - avgHeight, 2) }.reduce(0, +) / Double(heights.count)
        let heightConsistency = max(0.0, 1.0 - heightVariance / (avgHeight * avgHeight))
        consistencyScore += heightConsistency
        
        // Check reasonable wall dimensions
        checks += 1
        let dimensionScore = walls.map { wall in
            let length = wall.startPoint.distance(to: wall.endPoint)
            return (length >= 0.5 && length <= 20.0 && wall.height >= 2.0 && wall.height <= 5.0) ? 1.0 : 0.0
        }.reduce(0, +) / Double(walls.count)
        consistencyScore += dimensionScore
        
        return checks > 0 ? consistencyScore / Double(checks) : 0.0
    }
    
    private func calculateWallConnectivity(_ walls: [WallElement]) -> Double {
        // Check how many walls have endpoints that connect to other walls
        var connectedEndpoints = 0
        let totalEndpoints = walls.count * 2
        let connectionTolerance = 0.1 // 10cm tolerance
        
        for wall in walls {
            let startPoint = wall.startPoint
            let endPoint = wall.endPoint
            
            // Check if start point connects to any other wall
            if walls.contains(where: { otherWall in
                otherWall.id != wall.id && 
                (otherWall.startPoint.distance(to: startPoint) < connectionTolerance ||
                 otherWall.endPoint.distance(to: startPoint) < connectionTolerance)
            }) {
                connectedEndpoints += 1
            }
            
            // Check if end point connects to any other wall
            if walls.contains(where: { otherWall in
                otherWall.id != wall.id && 
                (otherWall.startPoint.distance(to: endPoint) < connectionTolerance ||
                 otherWall.endPoint.distance(to: endPoint) < connectionTolerance)
            }) {
                connectedEndpoints += 1
            }
        }
        
        return totalEndpoints > 0 ? Double(connectedEndpoints) / Double(totalEndpoints) : 0.0
    }
    
    private func assessFurnitureRoomConsistency(_ furniture: [FurnitureItem], roomBounds: BoundingBox) -> Double {
        var consistencyScore = 0.0
        var validFurniture = 0
        
        for item in furniture {
            // Check if furniture is within room bounds
            if roomBounds.contains(item.bounds.center) {
                validFurniture += 1
                
                // Check if furniture size is reasonable relative to room
                let furnitureVolume = item.bounds.volume
                let roomVolume = roomBounds.volume
                let volumeRatio = furnitureVolume / roomVolume
                
                // Furniture should be a reasonable fraction of room volume
                if volumeRatio < 0.5 { // Furniture shouldn't take up more than 50% of room
                    consistencyScore += 1.0
                } else {
                    consistencyScore += 0.5 // Partial credit
                }
            }
        }
        
        return furniture.isEmpty ? 1.0 : consistencyScore / Double(furniture.count)
    }
    
    // MARK: - Furniture Detection Assessment
    
    private func assessFurnitureDetection(_ room: RoomModel) -> Double {
        guard !room.furniture.isEmpty else { return 0.3 } // Partial credit for rooms with no furniture
        
        var score = 0.0
        var checks = 0
        
        // Check furniture count is reasonable for room size
        checks += 1
        let roomArea = room.bounds.size.x * room.bounds.size.y
        let expectedFurnitureCount = estimateExpectedFurnitureCount(for: roomArea)
        let actualCount = room.furniture.count
        let countRatio = min(Double(actualCount), expectedFurnitureCount) / max(Double(actualCount), expectedFurnitureCount)
        score += countRatio
        
        // Check average furniture confidence
        checks += 1
        let avgConfidence = room.furniture.map(\.confidence).reduce(0, +) / Double(room.furniture.count)
        score += avgConfidence
        
        // Check furniture type diversity (good scans detect different types)
        checks += 1
        let uniqueTypes = Set(room.furniture.map(\.type))
        let diversityScore = min(1.0, Double(uniqueTypes.count) / 3.0) // Good diversity around 3+ types
        score += diversityScore
        
        // Check for placement-suitable furniture
        checks += 1
        let placementSuitableFurniture = room.furniture.filter { item in
            [.table, .desk, .dresser, .shelf, .cabinet, .counter, .nightstand].contains(item.type)
        }
        let suitabilityScore = Double(placementSuitableFurniture.count) / max(1.0, Double(room.furniture.count))
        score += suitabilityScore
        
        return checks > 0 ? score / Double(checks) : 0.0
    }
    
    private func estimateExpectedFurnitureCount(for roomArea: Double) -> Double {
        // Rough heuristic based on room size
        switch roomArea {
        case 0..<10:    // Small room (< 10 m²)
            return 2.0
        case 10..<25:   // Medium room (10-25 m²)
            return 4.0
        case 25..<50:   // Large room (25-50 m²)
            return 6.0
        default:        // Very large room (> 50 m²)
            return 8.0
        }
    }
    
    // MARK: - Geometry Consistency Assessment
    
    private func assessGeometryConsistency(_ room: RoomModel) -> Double {
        var score = 0.0
        var checks = 0
        
        // Check bounds consistency
        checks += 1
        let boundsScore = assessBoundsConsistency(room)
        score += boundsScore
        
        // Check object overlap issues
        checks += 1
        let overlapScore = assessObjectOverlaps(room)
        score += overlapScore
        
        // Check scale consistency
        checks += 1
        let scaleScore = assessScaleConsistency(room)
        score += scaleScore
        
        return checks > 0 ? score / Double(checks) : 0.0
    }
    
    private func assessBoundsConsistency(_ room: RoomModel) -> Double {
        var issues = 0
        
        // Check if all objects are within room bounds
        for furniture in room.furniture {
            if !room.bounds.intersects(furniture.bounds) {
                issues += 1
            }
        }
        
        for wall in room.walls {
            if !room.bounds.contains(wall.startPoint) || !room.bounds.contains(wall.endPoint) {
                issues += 1
            }
        }
        
        // Check if room bounds are reasonable
        let size = room.bounds.size
        if size.x <= 0 || size.y <= 0 || size.z <= 0 {
            issues += 2 // Major issue
        }
        
        let totalObjects = room.furniture.count + room.walls.count + 1 // +1 for room bounds check
        return max(0.0, 1.0 - Double(issues) / Double(max(1, totalObjects)))
    }
    
    private func assessObjectOverlaps(_ room: RoomModel) -> Double {
        var overlapCount = 0
        let furniture = room.furniture
        
        // Check furniture-furniture overlaps
        for i in 0..<furniture.count {
            for j in (i+1)..<furniture.count {
                if furniture[i].bounds.intersects(furniture[j].bounds) {
                    // Check if it's a significant overlap (> 10% of smaller object)
                    let overlapVolume = calculateOverlapVolume(furniture[i].bounds, furniture[j].bounds)
                    let smallerVolume = min(furniture[i].bounds.volume, furniture[j].bounds.volume)
                    if overlapVolume > smallerVolume * 0.1 {
                        overlapCount += 1
                    }
                }
            }
        }
        
        let totalPairs = (furniture.count * (furniture.count - 1)) / 2
        return totalPairs > 0 ? max(0.0, 1.0 - Double(overlapCount) / Double(totalPairs)) : 1.0
    }
    
    private func calculateOverlapVolume(_ bounds1: BoundingBox, _ bounds2: BoundingBox) -> Double {
        let overlapMin = Point3D(
            x: max(bounds1.min.x, bounds2.min.x),
            y: max(bounds1.min.y, bounds2.min.y),
            z: max(bounds1.min.z, bounds2.min.z)
        )
        
        let overlapMax = Point3D(
            x: min(bounds1.max.x, bounds2.max.x),
            y: min(bounds1.max.y, bounds2.max.y),
            z: min(bounds1.max.z, bounds2.max.z)
        )
        
        if overlapMin.x < overlapMax.x && overlapMin.y < overlapMax.y && overlapMin.z < overlapMax.z {
            return (overlapMax.x - overlapMin.x) * (overlapMax.y - overlapMin.y) * (overlapMax.z - overlapMin.z)
        }
        
        return 0.0
    }
    
    private func assessScaleConsistency(_ room: RoomModel) -> Double {
        // Check if all dimensions are in consistent units
        let roomSize = room.bounds.size
        let roomMagnitude = sqrt(roomSize.x * roomSize.x + roomSize.y * roomSize.y + roomSize.z * roomSize.z)
        
        var scaleConsistency = 0.0
        var objectCount = 0
        
        // Check furniture scales relative to room
        for furniture in room.furniture {
            objectCount += 1
            let furnitureSize = furniture.bounds.size
            let furnitureMagnitude = sqrt(furnitureSize.x * furnitureSize.x + furnitureSize.y * furnitureSize.y + furnitureSize.z * furnitureSize.z)
            
            // Furniture should be much smaller than room
            if furnitureMagnitude < roomMagnitude * 0.8 {
                scaleConsistency += 1.0
            } else {
                scaleConsistency += 0.5 // Partial credit
            }
        }
        
        return objectCount > 0 ? scaleConsistency / Double(objectCount) : 1.0
    }
    
    // MARK: - Overall Quality Calculation
    
    private func calculateOverallQuality(
        completeness: Double,
        accuracy: Double,
        furnitureDetection: Double,
        consistency: Double
    ) -> Double {
        // Weighted average with completeness and accuracy being most important
        let weights = [
            completeness: 0.35,
            accuracy: 0.35,
            consistency: 0.20,
            furnitureDetection: 0.10
        ]
        
        return weights.reduce(0.0) { sum, pair in
            sum + pair.key * pair.value
        }
    }
    
    // MARK: - Issue Identification
    
    private func identifyQualityIssues(_ room: RoomModel) -> [QualityIssue] {
        var issues: [QualityIssue] = []
        
        // Check for missing walls
        if room.walls.isEmpty {
            issues.append(.missingWalls)
        } else if room.walls.count < Thresholds.minWallCount {
            issues.append(.insufficientWalls)
        }
        
        // Check room size
        let volume = room.bounds.volume
        if volume < Thresholds.minRoomVolume {
            issues.append(.roomTooSmall)
        } else if volume > Thresholds.maxRoomVolume {
            issues.append(.roomTooLarge)
        }
        
        // Check furniture
        if room.furniture.isEmpty {
            issues.append(.noFurnitureDetected)
        } else {
            let lowConfidenceFurniture = room.furniture.filter { $0.confidence < Thresholds.minFurnitureConfidence }
            if lowConfidenceFurniture.count > room.furniture.count / 2 {
                issues.append(.lowFurnitureConfidence)
            }
        }
        
        // Check aspect ratio
        let size = room.bounds.size
        let aspectRatio = max(size.x, size.y) / min(size.x, size.y)
        if aspectRatio > Thresholds.maxAspectRatio {
            issues.append(.extremeAspectRatio)
        }
        
        // Check floor area
        if room.floor.area < Thresholds.minFloorArea {
            issues.append(.insufficientFloorArea)
        }
        
        return issues
    }
    
    // MARK: - Recommendations Generation
    
    private func generateRecommendations(for issues: [QualityIssue]) -> [QualityRecommendation] {
        var recommendations: [QualityRecommendation] = []
        
        for issue in issues {
            switch issue {
            case .missingWalls, .insufficientWalls:
                recommendations.append(.rescanWithBetterWallCoverage)
                
            case .roomTooSmall:
                recommendations.append(.ensureCompleteRoomCapture)
                
            case .roomTooLarge:
                recommendations.append(.considerMultipleScans)
                
            case .noFurnitureDetected, .lowFurnitureConfidence:
                recommendations.append(.improveScanning)
                
            case .extremeAspectRatio:
                recommendations.append(.validateRoomBoundaries)
                
            case .insufficientFloorArea:
                recommendations.append(.rescanFloorArea)
                
            case .inconsistentScale:
                recommendations.append(.checkScanningDistance)
                
            case .objectOverlaps:
                recommendations.append(.validateObjectDetection)
            }
        }
        
        // Remove duplicates
        return Array(Set(recommendations))
    }
}

// MARK: - Supporting Types

public struct ScanQualityAssessment {
    public let completeness: Double
    public let accuracy: Double
    public let furnitureDetection: Double
    public let geometryConsistency: Double
    public let overallQuality: Double
    public let identifiedIssues: [QualityIssue]
    public let recommendations: [QualityRecommendation]
    
    public var isAcceptableForAnalysis: Bool {
        return overallQuality > 0.7 && completeness > 0.8
    }
    
    public var qualityLevel: QualityLevel {
        switch overallQuality {
        case 0.9...:
            return .excellent
        case 0.8..<0.9:
            return .good
        case 0.7..<0.8:
            return .acceptable
        case 0.5..<0.7:
            return .poor
        default:
            return .unusable
        }
    }
}

public enum QualityLevel: String, CaseIterable {
    case excellent = "excellent"
    case good = "good"
    case acceptable = "acceptable"
    case poor = "poor"
    case unusable = "unusable"
    
    public var description: String {
        switch self {
        case .excellent:
            return "Excellent scan quality - ready for analysis"
        case .good:
            return "Good scan quality - suitable for analysis"
        case .acceptable:
            return "Acceptable scan quality - may have minor limitations"
        case .poor:
            return "Poor scan quality - consider rescanning"
        case .unusable:
            return "Unusable scan quality - rescan required"
        }
    }
}

public enum QualityIssue: String, CaseIterable, Hashable {
    case missingWalls = "missing_walls"
    case insufficientWalls = "insufficient_walls"
    case roomTooSmall = "room_too_small"
    case roomTooLarge = "room_too_large"
    case noFurnitureDetected = "no_furniture_detected"
    case lowFurnitureConfidence = "low_furniture_confidence"
    case extremeAspectRatio = "extreme_aspect_ratio"
    case insufficientFloorArea = "insufficient_floor_area"
    case inconsistentScale = "inconsistent_scale"
    case objectOverlaps = "object_overlaps"
    
    public var description: String {
        switch self {
        case .missingWalls:
            return "No walls detected in scan"
        case .insufficientWalls:
            return "Too few walls detected for reliable analysis"
        case .roomTooSmall:
            return "Room appears unusually small"
        case .roomTooLarge:
            return "Room appears unusually large"
        case .noFurnitureDetected:
            return "No furniture detected in scan"
        case .lowFurnitureConfidence:
            return "Low confidence in furniture detection"
        case .extremeAspectRatio:
            return "Room has extreme length-to-width ratio"
        case .insufficientFloorArea:
            return "Insufficient floor area detected"
        case .inconsistentScale:
            return "Inconsistent object scaling detected"
        case .objectOverlaps:
            return "Objects appear to overlap inappropriately"
        }
    }
}

public enum QualityRecommendation: String, CaseIterable, Hashable {
    case rescanWithBetterWallCoverage = "rescan_walls"
    case ensureCompleteRoomCapture = "complete_capture"
    case considerMultipleScans = "multiple_scans"
    case improveScanning = "improve_scanning"
    case validateRoomBoundaries = "validate_boundaries"
    case rescanFloorArea = "rescan_floor"
    case checkScanningDistance = "check_distance"
    case validateObjectDetection = "validate_objects"
    
    public var description: String {
        switch self {
        case .rescanWithBetterWallCoverage:
            return "Rescan ensuring all walls are captured"
        case .ensureCompleteRoomCapture:
            return "Ensure the entire room is captured in the scan"
        case .considerMultipleScans:
            return "Consider breaking large spaces into multiple scans"
        case .improveScanning:
            return "Improve scanning technique for better furniture detection"
        case .validateRoomBoundaries:
            return "Validate room boundaries are correctly detected"
        case .rescanFloorArea:
            return "Rescan to capture complete floor area"
        case .checkScanningDistance:
            return "Check scanning distance and technique"
        case .validateObjectDetection:
            return "Validate object detection results manually"
        }
    }
}