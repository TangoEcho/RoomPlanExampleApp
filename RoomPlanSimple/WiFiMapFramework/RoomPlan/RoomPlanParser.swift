import Foundation
import ModelIO
import SceneKit
#if canImport(RoomPlan) && os(iOS)
import RoomPlan
#endif

/// Main parser for extracting spatial data from RoomPlan USDZ files
#if canImport(RoomPlan) && os(iOS)
public class RoomPlanParser {
    
    // MARK: - Properties
    
    private let coordinateTransformer: CoordinateTransformer
    private let furnitureDetector: FurnitureDetector
    private let surfaceAnalyzer: SurfaceAnalyzer
    private let qualityAssessor: ScanQualityAssessor
    
    // MARK: - Initialization
    
    public init() {
        self.coordinateTransformer = CoordinateTransformer()
        self.furnitureDetector = FurnitureDetector()
        self.surfaceAnalyzer = SurfaceAnalyzer()
        self.qualityAssessor = ScanQualityAssessor()
    }
    
    // MARK: - Public Interface
    
    /// Parse a USDZ file from RoomPlan into a structured room model
    /// - Parameter url: URL to the USDZ file
    /// - Returns: Parsed room model with geometry and furniture data
    /// - Throws: RoomPlanParsingError if parsing fails
    public func parseUSDZ(from url: URL) throws -> RoomModel {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RoomPlanParsingError.invalidUSDZFile
        }
        
        // Load USDZ as MDLAsset
        let asset = MDLAsset(url: url)
        
        guard !asset.childObjects(of: MDLObject.self).isEmpty else {
            throw RoomPlanParsingError.missingGeometryData
        }
        
        // Extract core room data
        let roomBounds = try extractRoomBoundaries(from: asset)
        let walls = try extractWallElements(from: asset)
        let furniture = try extractFurnitureItems(from: asset)
        let openings = try extractOpenings(from: asset)
        let floor = try extractFloorPlan(from: asset)
        
        // Create room model
        let roomModel = RoomModel(
            id: UUID(),
            name: url.deletingPathExtension().lastPathComponent,
            bounds: roomBounds,
            walls: walls,
            furniture: furniture,
            openings: openings,
            floor: floor
        )
        
        // Validate and enhance the model
        let qualityAssessment = qualityAssessor.assessScanQuality(roomModel)
        if !qualityAssessment.isAcceptableForAnalysis {
            // Attempt to repair the model
            return try attemptModelRepair(roomModel)
        }
        
        return roomModel
    }
    
    // MARK: - Geometry Extraction
    
    private func extractRoomBoundaries(from asset: MDLAsset) throws -> BoundingBox {
        var minPoint = Point3D(x: Double.infinity, y: Double.infinity, z: Double.infinity)
        var maxPoint = Point3D(x: -Double.infinity, y: -Double.infinity, z: -Double.infinity)
        
        let objects = asset.childObjects(of: MDLObject.self)
        guard !objects.isEmpty else {
            throw RoomPlanParsingError.missingGeometryData
        }
        
        for object in objects {
            if let mesh = object as? MDLMesh {
                let boundingBox = mesh.boundingBox
                
                minPoint.x = min(minPoint.x, Double(boundingBox.minBounds.x))
                minPoint.y = min(minPoint.y, Double(boundingBox.minBounds.y))
                minPoint.z = min(minPoint.z, Double(boundingBox.minBounds.z))
                
                maxPoint.x = max(maxPoint.x, Double(boundingBox.maxBounds.x))
                maxPoint.y = max(maxPoint.y, Double(boundingBox.maxBounds.y))
                maxPoint.z = max(maxPoint.z, Double(boundingBox.maxBounds.z))
            }
        }
        
        // Validate bounds are reasonable
        let bounds = BoundingBox(min: minPoint, max: maxPoint)
        if bounds.size.x < 0.5 || bounds.size.y < 0.5 || bounds.size.z < 1.0 {
            throw RoomPlanParsingError.insufficientRoomData
        }
        
        return bounds
    }
    
    private func extractWallElements(from asset: MDLAsset) throws -> [WallElement] {
        var walls: [WallElement] = []
        
        for object in asset.childObjects(of: MDLObject.self) {
            guard let mesh = object as? MDLMesh else { continue }
            
            // Check if this is a wall object based on name or properties
            if isWallObject(object) {
                if let wall = try? parseWallFromMesh(mesh, objectName: object.name) {
                    walls.append(wall)
                }
            }
        }
        
        // If no explicit walls found, infer from room boundaries
        if walls.isEmpty {
            walls = try inferWallsFromBoundaries(asset)
        }
        
        return walls
    }
    
    private func extractFurnitureItems(from asset: MDLAsset) throws -> [FurnitureItem] {
        var furniture: [FurnitureItem] = []
        
        for object in asset.childObjects(of: MDLObject.self) {
            guard let mesh = object as? MDLMesh else { continue }
            
            if let furnitureType = furnitureDetector.detectFurnitureType(from: object) {
                let bounds = BoundingBox(
                    min: Point3D(
                        x: Double(mesh.boundingBox.minBounds.x),
                        y: Double(mesh.boundingBox.minBounds.y),
                        z: Double(mesh.boundingBox.minBounds.z)
                    ),
                    max: Point3D(
                        x: Double(mesh.boundingBox.maxBounds.x),
                        y: Double(mesh.boundingBox.maxBounds.y),
                        z: Double(mesh.boundingBox.maxBounds.z)
                    )
                )
                
                let surfaces = surfaceAnalyzer.extractPlacementSurfaces(
                    from: mesh,
                    furnitureType: furnitureType,
                    bounds: bounds
                )
                
                let confidence = extractConfidenceScore(from: object)
                
                let item = FurnitureItem(
                    id: UUID(),
                    type: furnitureType,
                    bounds: bounds,
                    surfaces: surfaces,
                    confidence: confidence
                )
                
                furniture.append(item)
            }
        }
        
        return furniture
    }
    
    private func extractOpenings(from asset: MDLAsset) throws -> [Opening] {
        var openings: [Opening] = []
        
        for object in asset.childObjects(of: MDLObject.self) {
            if let openingType = detectOpeningType(from: object) {
                guard let mesh = object as? MDLMesh else { continue }
                
                let bounds = BoundingBox(
                    min: Point3D(
                        x: Double(mesh.boundingBox.minBounds.x),
                        y: Double(mesh.boundingBox.minBounds.y),
                        z: Double(mesh.boundingBox.minBounds.z)
                    ),
                    max: Point3D(
                        x: Double(mesh.boundingBox.maxBounds.x),
                        y: Double(mesh.boundingBox.maxBounds.y),
                        z: Double(mesh.boundingBox.maxBounds.z)
                    )
                )
                
                let opening = Opening(
                    id: UUID(),
                    type: openingType,
                    bounds: bounds,
                    isPassable: openingType == .door || openingType == .opening
                )
                
                openings.append(opening)
            }
        }
        
        return openings
    }
    
    private func extractFloorPlan(from asset: MDLAsset) throws -> FloorPlan {
        // Find floor mesh or infer from room bounds
        for object in asset.childObjects(of: MDLObject.self) {
            if isFloorObject(object), let mesh = object as? MDLMesh {
                let area = calculateFloorArea(from: mesh)
                let bounds = BoundingBox(
                    min: Point3D(
                        x: Double(mesh.boundingBox.minBounds.x),
                        y: Double(mesh.boundingBox.minBounds.y),
                        z: Double(mesh.boundingBox.minBounds.z)
                    ),
                    max: Point3D(
                        x: Double(mesh.boundingBox.maxBounds.x),
                        y: Double(mesh.boundingBox.maxBounds.y),
                        z: Double(mesh.boundingBox.maxBounds.z)
                    )
                )
                
                return FloorPlan(bounds: bounds, area: area)
            }
        }
        
        // Fallback: create floor plan from room boundaries
        let roomBounds = try extractRoomBoundaries(from: asset)
        let area = roomBounds.size.x * roomBounds.size.y
        
        return FloorPlan(bounds: roomBounds, area: area)
    }
    
    // MARK: - Helper Methods
    
    private func isWallObject(_ object: MDLObject) -> Bool {
        let name = object.name.lowercased()
        return name.contains("wall") || 
               name.contains("partition") ||
               name.hasPrefix("wall_")
    }
    
    private func isFloorObject(_ object: MDLObject) -> Bool {
        let name = object.name.lowercased()
        return name.contains("floor") || 
               name.contains("ground") ||
               name.hasPrefix("floor_")
    }
    
    private func parseWallFromMesh(_ mesh: MDLMesh, objectName: String) throws -> WallElement {
        // Extract wall geometry from mesh vertices
        let geometry = try extractWallGeometry(from: mesh)
        
        // Infer material from object properties or name
        let material = inferWallMaterial(from: mesh, name: objectName)
        
        return WallElement(
            id: UUID(),
            startPoint: geometry.startPoint,
            endPoint: geometry.endPoint,
            height: geometry.height,
            thickness: geometry.thickness,
            material: material
        )
    }
    
    private func extractWallGeometry(from mesh: MDLMesh) throws -> WallGeometry {
        // Analyze mesh vertices to determine wall parameters
        guard let vertexBuffer = mesh.vertexBuffers.first?.map,
              let positionAttribute = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition) else {
            throw RoomPlanParsingError.corruptedMeshData
        }
        
        let vertices = extractVertices(from: vertexBuffer, attribute: positionAttribute)
        
        // Find the dominant horizontal edge (wall base)
        let horizontalEdges = findHorizontalEdges(in: vertices)
        guard let mainEdge = horizontalEdges.max(by: { $0.length < $1.length }) else {
            throw RoomPlanParsingError.corruptedMeshData
        }
        
        // Calculate wall parameters
        let startPoint = mainEdge.start
        let endPoint = mainEdge.end
        let height = calculateWallHeight(from: vertices)
        let thickness = estimateWallThickness(from: vertices, mainEdge: mainEdge)
        
        return WallGeometry(
            startPoint: startPoint,
            endPoint: endPoint,
            height: height,
            thickness: thickness
        )
    }
    
    private func detectOpeningType(from object: MDLObject) -> Opening.OpeningType? {
        let name = object.name.lowercased()
        
        if name.contains("door") {
            return .door
        } else if name.contains("window") {
            return .window
        } else if name.contains("opening") || name.contains("arch") {
            return .opening
        }
        
        return nil
    }
    
    private func inferWallMaterial(from mesh: MDLMesh, name: String) -> WallMaterial {
        let lowercaseName = name.lowercased()
        
        if lowercaseName.contains("concrete") {
            return .concrete
        } else if lowercaseName.contains("brick") {
            return .brick
        } else if lowercaseName.contains("wood") {
            return .wood
        } else if lowercaseName.contains("glass") {
            return .glass
        } else if lowercaseName.contains("metal") {
            return .metal
        }
        
        // Default to drywall for residential spaces
        return .drywall
    }
    
    private func extractConfidenceScore(from object: MDLObject) -> Double {
        // RoomPlan doesn't directly provide confidence scores
        // Estimate based on mesh complexity and naming consistency
        
        var confidence = 0.5 // Base confidence
        
        // Higher confidence for well-named objects
        if !object.name.isEmpty && !object.name.contains("unknown") {
            confidence += 0.2
        }
        
        // Higher confidence for objects with reasonable bounds
        if let mesh = object as? MDLMesh {
            let bounds = mesh.boundingBox
            let volume = Double(bounds.maxBounds.x - bounds.minBounds.x) *
                        Double(bounds.maxBounds.y - bounds.minBounds.y) *
                        Double(bounds.maxBounds.z - bounds.minBounds.z)
            
            if volume > 0.1 && volume < 100.0 { // Reasonable furniture volume
                confidence += 0.2
            }
        }
        
        // Cap at reasonable maximum
        return min(confidence, 0.9)
    }
    
    private func calculateFloorArea(from mesh: MDLMesh) -> Double {
        // For now, use bounding box approximation
        // TODO: Implement proper mesh area calculation
        let bounds = mesh.boundingBox
        return Double(bounds.maxBounds.x - bounds.minBounds.x) *
               Double(bounds.maxBounds.y - bounds.minBounds.y)
    }
    
    // MARK: - Model Repair
    
    private func attemptModelRepair(_ model: RoomModel) throws -> RoomModel {
        var repairedModel = model
        
        // Add inferred walls if missing
        if model.walls.isEmpty {
            repairedModel = try addInferredWalls(to: repairedModel)
        }
        
        // Enhance furniture detection if sparse
        if model.furniture.count < 2 {
            repairedModel = addInferredFurniture(to: repairedModel)
        }
        
        // Validate repair was successful
        let newAssessment = qualityAssessor.assessScanQuality(repairedModel)
        if !newAssessment.isAcceptableForAnalysis {
            throw RoomPlanParsingError.insufficientRoomData
        }
        
        return repairedModel
    }
    
    private func addInferredWalls(to model: RoomModel) throws -> RoomModel {
        // Create walls from room boundaries
        let bounds = model.bounds
        let wallHeight = bounds.size.z
        let wallThickness = 0.1 // 10cm default
        
        let walls = [
            // Front wall (min Y)
            WallElement(
                id: UUID(),
                startPoint: Point3D(x: bounds.min.x, y: bounds.min.y, z: bounds.min.z),
                endPoint: Point3D(x: bounds.max.x, y: bounds.min.y, z: bounds.min.z),
                height: wallHeight,
                thickness: wallThickness,
                material: .drywall
            ),
            // Back wall (max Y)
            WallElement(
                id: UUID(),
                startPoint: Point3D(x: bounds.max.x, y: bounds.max.y, z: bounds.min.z),
                endPoint: Point3D(x: bounds.min.x, y: bounds.max.y, z: bounds.min.z),
                height: wallHeight,
                thickness: wallThickness,
                material: .drywall
            ),
            // Left wall (min X)
            WallElement(
                id: UUID(),
                startPoint: Point3D(x: bounds.min.x, y: bounds.max.y, z: bounds.min.z),
                endPoint: Point3D(x: bounds.min.x, y: bounds.min.y, z: bounds.min.z),
                height: wallHeight,
                thickness: wallThickness,
                material: .drywall
            ),
            // Right wall (max X)
            WallElement(
                id: UUID(),
                startPoint: Point3D(x: bounds.max.x, y: bounds.min.y, z: bounds.min.z),
                endPoint: Point3D(x: bounds.max.x, y: bounds.max.y, z: bounds.min.z),
                height: wallHeight,
                thickness: wallThickness,
                material: .drywall
            )
        ]
        
        return RoomModel(
            id: model.id,
            name: model.name,
            bounds: model.bounds,
            walls: walls,
            furniture: model.furniture,
            openings: model.openings,
            floor: model.floor
        )
    }
    
    private func addInferredFurniture(to model: RoomModel) -> RoomModel {
        // Add basic furniture items based on room size and type
        var inferredFurniture = model.furniture
        
        let roomArea = model.bounds.size.x * model.bounds.size.y
        
        // Add a table in the center if room is large enough
        if roomArea > 15.0 {
            let tableSize = Vector3D(x: 1.2, y: 0.8, z: 0.75)
            let tableCenter = model.bounds.center
            
            let tableBounds = BoundingBox(
                min: Point3D(
                    x: tableCenter.x - tableSize.x/2,
                    y: tableCenter.y - tableSize.y/2,
                    z: model.bounds.min.z
                ),
                max: Point3D(
                    x: tableCenter.x + tableSize.x/2,
                    y: tableCenter.y + tableSize.y/2,
                    z: model.bounds.min.z + tableSize.z
                )
            )
            
            let tableTop = PlacementSurface(
                id: UUID(),
                center: Point3D(x: tableCenter.x, y: tableCenter.y, z: tableSize.z),
                normal: Vector3D(x: 0, y: 0, z: 1),
                area: tableSize.x * tableSize.y,
                accessibility: .excellent,
                powerProximity: nil
            )
            
            let table = FurnitureItem(
                id: UUID(),
                type: .table,
                bounds: tableBounds,
                surfaces: [tableTop],
                confidence: 0.3 // Low confidence for inferred furniture
            )
            
            inferredFurniture.append(table)
        }
        
        return RoomModel(
            id: model.id,
            name: model.name,
            bounds: model.bounds,
            walls: model.walls,
            furniture: inferredFurniture,
            openings: model.openings,
            floor: model.floor
        )
    }
    
    private func inferWallsFromBoundaries(_ asset: MDLAsset) throws -> [WallElement] {
        let bounds = try extractRoomBoundaries(from: asset)
        return try addInferredWalls(to: RoomModel(
            id: UUID(),
            name: "temp",
            bounds: bounds,
            walls: [],
            furniture: [],
            openings: [],
            floor: FloorPlan(bounds: bounds, area: bounds.size.x * bounds.size.y)
        )).walls
    }
}

// MARK: - Supporting Types

private struct WallGeometry {
    let startPoint: Point3D
    let endPoint: Point3D
    let height: Double
    let thickness: Double
}

private struct Edge3D {
    let start: Point3D
    let end: Point3D
    
    var length: Double {
        return start.distance(to: end)
    }
}

// MARK: - Vertex Processing Extensions

private extension RoomPlanParser {
    
    func extractVertices(from buffer: MDLMeshBufferMap, attribute: MDLVertexAttributeData) -> [Point3D] {
        var vertices: [Point3D] = []
        
        let stride = attribute.stride
        let offset = attribute.offset
        let count = Int(attribute.bufferSize) / stride
        
        for i in 0..<count {
            let vertexOffset = offset + i * stride
            
            // Assuming 3 float values per vertex (x, y, z)
            let x = Double(buffer.bytes.advanced(by: vertexOffset).assumingMemoryBound(to: Float.self).pointee)
            let y = Double(buffer.bytes.advanced(by: vertexOffset + 4).assumingMemoryBound(to: Float.self).pointee)
            let z = Double(buffer.bytes.advanced(by: vertexOffset + 8).assumingMemoryBound(to: Float.self).pointee)
            
            vertices.append(Point3D(x: x, y: y, z: z))
        }
        
        return vertices
    }
    
    func findHorizontalEdges(in vertices: [Point3D]) -> [Edge3D] {
        var edges: [Edge3D] = []
        
        // Group vertices by similar Z coordinate (floor level)
        let floorVertices = vertices.filter { vertex in
            let minZ = vertices.map(\.z).min() ?? 0
            return abs(vertex.z - minZ) < 0.1 // Within 10cm of floor
        }
        
        // Find connected horizontal edges
        for i in 0..<floorVertices.count {
            for j in (i+1)..<floorVertices.count {
                let distance = floorVertices[i].distance(to: floorVertices[j])
                if distance > 0.5 && distance < 10.0 { // Reasonable wall length
                    edges.append(Edge3D(start: floorVertices[i], end: floorVertices[j]))
                }
            }
        }
        
        return edges
    }
    
    func calculateWallHeight(from vertices: [Point3D]) -> Double {
        let minZ = vertices.map(\.z).min() ?? 0
        let maxZ = vertices.map(\.z).max() ?? 0
        return maxZ - minZ
    }
    
    func estimateWallThickness(from vertices: [Point3D], mainEdge: Edge3D) -> Double {
        // For now, return a reasonable default
        // TODO: Implement proper thickness calculation from mesh geometry
        return 0.1 // 10cm
    }
}
#endif