import Foundation
import ModelIO
import SceneKit

/// Detects and classifies furniture items from RoomPlan USDZ data
public class FurnitureDetector {
    
    // MARK: - Properties
    
    private let namePatterns: [FurnitureType: [String]]
    private let dimensionRules: [FurnitureType: DimensionRule]
    
    // MARK: - Initialization
    
    public init() {
        self.namePatterns = Self.buildNamePatterns()
        self.dimensionRules = Self.buildDimensionRules()
    }
    
    // MARK: - Public Interface
    
    /// Detect furniture type from a ModelIO object
    /// - Parameter object: The MDLObject to analyze
    /// - Returns: Detected furniture type, or nil if not furniture
    public func detectFurnitureType(from object: MDLObject) -> FurnitureType? {
        let objectName = object.name.lowercased()
        
        // First check by name patterns
        if let typeByName = detectByName(objectName) {
            // Validate with dimension rules
            if let mesh = object as? MDLMesh, validateDimensions(mesh, for: typeByName) {
                return typeByName
            }
        }
        
        // Fallback to dimension-based detection
        if let mesh = object as? MDLMesh {
            return detectByDimensions(mesh, objectName: objectName)
        }
        
        return nil
    }
    
    /// Check if a furniture type is suitable for WiFi extender placement
    /// - Parameter furnitureType: The furniture type to check
    /// - Returns: True if suitable for placement
    public func isPlacementSuitable(_ furnitureType: FurnitureType) -> Bool {
        switch furnitureType {
        case .table, .desk, .dresser, .shelf, .cabinet, .counter, .nightstand:
            return true
        case .sofa, .chair, .bed, .stool:
            return false
        }
    }
    
    // MARK: - Name-Based Detection
    
    private func detectByName(_ name: String) -> FurnitureType? {
        for (furnitureType, patterns) in namePatterns {
            for pattern in patterns {
                if name.contains(pattern) {
                    return furnitureType
                }
            }
        }
        return nil
    }
    
    private static func buildNamePatterns() -> [FurnitureType: [String]] {
        return [
            .table: [
                "table", "dining_table", "coffee_table", "side_table",
                "end_table", "console_table", "conference_table"
            ],
            .desk: [
                "desk", "office_desk", "computer_desk", "writing_desk",
                "workstation", "bureau"
            ],
            .dresser: [
                "dresser", "chest_of_drawers", "drawer", "bureau",
                "armoire", "wardrobe"
            ],
            .shelf: [
                "shelf", "bookshelf", "shelving", "shelving_unit",
                "bookcase", "display_shelf", "wall_shelf"
            ],
            .cabinet: [
                "cabinet", "kitchen_cabinet", "storage_cabinet",
                "media_cabinet", "tv_cabinet", "filing_cabinet"
            ],
            .counter: [
                "counter", "kitchen_counter", "countertop", "bar",
                "kitchen_island", "breakfast_bar"
            ],
            .nightstand: [
                "nightstand", "bedside_table", "night_table", "bedside_cabinet"
            ],
            .sofa: [
                "sofa", "couch", "loveseat", "sectional", "settee",
                "chaise", "lounge"
            ],
            .chair: [
                "chair", "dining_chair", "office_chair", "armchair",
                "recliner", "stool", "ottoman"
            ],
            .bed: [
                "bed", "mattress", "bed_frame", "platform_bed",
                "queen_bed", "king_bed", "twin_bed"
            ],
            .stool: [
                "stool", "bar_stool", "step_stool", "footstool"
            ]
        ]
    }
    
    // MARK: - Dimension-Based Detection
    
    private func detectByDimensions(_ mesh: MDLMesh, objectName: String) -> FurnitureType? {
        let bounds = mesh.boundingBox
        let dimensions = Dimensions(
            width: Double(bounds.maxBounds.x - bounds.minBounds.x),
            depth: Double(bounds.maxBounds.y - bounds.minBounds.y),
            height: Double(bounds.maxBounds.z - bounds.minBounds.z)
        )
        
        // Check against dimension rules in order of specificity
        let orderedTypes: [FurnitureType] = [
            .counter, .desk, .table, .dresser, .cabinet,
            .shelf, .nightstand, .bed, .sofa, .chair, .stool
        ]
        
        for furnitureType in orderedTypes {
            if let rule = dimensionRules[furnitureType],
               rule.matches(dimensions, objectName: objectName) {
                return furnitureType
            }
        }
        
        return nil
    }
    
    private func validateDimensions(_ mesh: MDLMesh, for furnitureType: FurnitureType) -> Bool {
        let bounds = mesh.boundingBox
        let dimensions = Dimensions(
            width: Double(bounds.maxBounds.x - bounds.minBounds.x),
            depth: Double(bounds.maxBounds.y - bounds.minBounds.y),
            height: Double(bounds.maxBounds.z - bounds.minBounds.z)
        )
        
        guard let rule = dimensionRules[furnitureType] else { return true }
        return rule.matches(dimensions, objectName: "")
    }
    
    private static func buildDimensionRules() -> [FurnitureType: DimensionRule] {
        return [
            .table: DimensionRule(
                widthRange: 0.6...3.0,
                depthRange: 0.6...2.0,
                heightRange: 0.6...1.2,
                aspectRatioConstraints: [
                    .maxHeightToWidthRatio(2.0)
                ]
            ),
            .desk: DimensionRule(
                widthRange: 1.0...2.5,
                depthRange: 0.5...1.2,
                heightRange: 0.65...0.85,
                aspectRatioConstraints: [
                    .minWidthToDepthRatio(1.2)
                ]
            ),
            .dresser: DimensionRule(
                widthRange: 0.8...2.0,
                depthRange: 0.4...0.8,
                heightRange: 0.7...1.5,
                aspectRatioConstraints: [
                    .minHeightToDepthRatio(1.2)
                ]
            ),
            .shelf: DimensionRule(
                widthRange: 0.3...3.0,
                depthRange: 0.15...0.6,
                heightRange: 0.3...3.0,
                aspectRatioConstraints: [
                    .maxDepthToWidthRatio(1.0),
                    .minHeightToDepthRatio(1.0)
                ]
            ),
            .cabinet: DimensionRule(
                widthRange: 0.4...2.5,
                depthRange: 0.3...0.8,
                heightRange: 0.5...2.5,
                aspectRatioConstraints: [
                    .minHeightToDepthRatio(1.0)
                ]
            ),
            .counter: DimensionRule(
                widthRange: 1.0...4.0,
                depthRange: 0.5...1.0,
                heightRange: 0.85...1.1,
                aspectRatioConstraints: [
                    .minWidthToDepthRatio(1.5)
                ]
            ),
            .nightstand: DimensionRule(
                widthRange: 0.3...0.8,
                depthRange: 0.3...0.6,
                heightRange: 0.4...0.8,
                aspectRatioConstraints: [
                    .maxWidthToDepthRatio(2.0)
                ]
            ),
            .sofa: DimensionRule(
                widthRange: 1.5...3.5,
                depthRange: 0.8...1.2,
                heightRange: 0.4...1.2,
                aspectRatioConstraints: [
                    .minWidthToDepthRatio(1.5),
                    .maxHeightToWidthRatio(0.8)
                ]
            ),
            .chair: DimensionRule(
                widthRange: 0.4...0.8,
                depthRange: 0.4...0.8,
                heightRange: 0.4...1.3,
                aspectRatioConstraints: [
                    .maxWidthToDepthRatio(2.0)
                ]
            ),
            .bed: DimensionRule(
                widthRange: 0.9...2.2, // Twin to King
                depthRange: 1.9...2.2, // Standard bed lengths
                heightRange: 0.2...1.0,
                aspectRatioConstraints: [
                    .minDepthToWidthRatio(0.9),
                    .maxHeightToWidthRatio(1.0)
                ]
            ),
            .stool: DimensionRule(
                widthRange: 0.25...0.6,
                depthRange: 0.25...0.6,
                heightRange: 0.4...0.8,
                aspectRatioConstraints: [
                    .maxWidthToDepthRatio(1.5)
                ]
            )
        ]
    }
}

// MARK: - Supporting Types

private struct Dimensions {
    let width: Double
    let depth: Double
    let height: Double
    
    var volume: Double {
        return width * depth * height
    }
    
    var maxDimension: Double {
        return max(width, max(depth, height))
    }
    
    var minDimension: Double {
        return min(width, min(depth, height))
    }
}

private struct DimensionRule {
    let widthRange: ClosedRange<Double>
    let depthRange: ClosedRange<Double>
    let heightRange: ClosedRange<Double>
    let aspectRatioConstraints: [AspectRatioConstraint]
    
    func matches(_ dimensions: Dimensions, objectName: String) -> Bool {
        // Check basic dimension ranges
        guard widthRange.contains(dimensions.width),
              depthRange.contains(dimensions.depth),
              heightRange.contains(dimensions.height) else {
            return false
        }
        
        // Check aspect ratio constraints
        for constraint in aspectRatioConstraints {
            if !constraint.satisfied(by: dimensions) {
                return false
            }
        }
        
        return true
    }
}

private enum AspectRatioConstraint {
    case minWidthToDepthRatio(Double)
    case maxWidthToDepthRatio(Double)
    case minHeightToWidthRatio(Double)
    case maxHeightToWidthRatio(Double)
    case minHeightToDepthRatio(Double)
    case maxHeightToDepthRatio(Double)
    case minDepthToWidthRatio(Double)
    case maxDepthToWidthRatio(Double)
    
    func satisfied(by dimensions: Dimensions) -> Bool {
        switch self {
        case .minWidthToDepthRatio(let ratio):
            return dimensions.width / dimensions.depth >= ratio
        case .maxWidthToDepthRatio(let ratio):
            return dimensions.width / dimensions.depth <= ratio
        case .minHeightToWidthRatio(let ratio):
            return dimensions.height / dimensions.width >= ratio
        case .maxHeightToWidthRatio(let ratio):
            return dimensions.height / dimensions.width <= ratio
        case .minHeightToDepthRatio(let ratio):
            return dimensions.height / dimensions.depth >= ratio
        case .maxHeightToDepthRatio(let ratio):
            return dimensions.height / dimensions.depth <= ratio
        case .minDepthToWidthRatio(let ratio):
            return dimensions.depth / dimensions.width >= ratio
        case .maxDepthToWidthRatio(let ratio):
            return dimensions.depth / dimensions.width <= ratio
        }
    }
}