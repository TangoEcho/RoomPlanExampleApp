import Foundation
import RoomPlan
import RealityKit
import ModelIO
import SceneKit
import simd
import MetalKit

// MARK: - USDZ RF Propagation Integrator
/// Integrates RF propagation visualization into USDZ files from RoomPlan
class USDZRFPropagationIntegrator {
    
    // MARK: - Properties
    private let propagationModel: RFPropagationModel
    private let heatmapGenerator: RFHeatmapGenerator
    private var capturedRoom: CapturedRoom?
    private var propagationData: [RFPropagationModel.PropagationPoint] = []
    
    // Visualization settings
    private var visualizationStyle: VisualizationStyle = .volumetric
    private var signalOpacity: Float = 0.6
    private var gridResolution: Float = 0.5 // meters
    private var heightLevels: Int = 5
    
    // MARK: - Enums
    enum VisualizationStyle {
        case planar          // 2D heatmap on floor
        case volumetric      // 3D volume rendering
        case particles       // Particle-based visualization
        case isosurfaces     // Signal strength contours
        case hybrid          // Combination of styles
    }
    
    enum ExportFormat {
        case usdz
        case usda
        case usd
    }
    
    // MARK: - Initialization
    init(propagationModel: RFPropagationModel) {
        self.propagationModel = propagationModel
        self.heatmapGenerator = RFHeatmapGenerator(propagationModel: propagationModel)
        print("🎨 USDZ RF Propagation Integrator initialized")
    }
    
    // MARK: - Configuration
    func configure(with capturedRoom: CapturedRoom) {
        self.capturedRoom = capturedRoom
        
        // Extract rooms for propagation model
        let rooms = extractRoomsFromCapturedRoom(capturedRoom)
        propagationModel.configureWithRooms(rooms)
    }
    
    func setVisualizationStyle(_ style: VisualizationStyle) {
        self.visualizationStyle = style
    }
    
    func setSignalOpacity(_ opacity: Float) {
        self.signalOpacity = max(0.0, min(1.0, opacity))
    }
    
    // MARK: - USDZ Enhancement
    
    /// Enhance existing USDZ file with RF propagation
    func enhanceUSDZ(at url: URL, outputURL: URL) async throws {
        print("🔧 Enhancing USDZ with RF propagation...")
        
        // Load the USDZ file
        let asset = try await loadUSDZAsset(from: url)
        
        // Generate propagation data
        generatePropagationData()
        
        // Add RF visualization based on style
        switch visualizationStyle {
        case .planar:
            try await addPlanarVisualization(to: asset)
        case .volumetric:
            try await addVolumetricVisualization(to: asset)
        case .particles:
            try await addParticleVisualization(to: asset)
        case .isosurfaces:
            try await addIsosurfaceVisualization(to: asset)
        case .hybrid:
            try await addHybridVisualization(to: asset)
        }
        
        // Export enhanced USDZ
        try await exportUSDZ(asset: asset, to: outputURL)
        
        print("✅ USDZ enhanced successfully")
    }
    
    /// Create new USDZ with RF propagation from RoomPlan data
    func createRFUSDZ(outputURL: URL) async throws {
        guard let room = capturedRoom else {
            throw IntegratorError.noCapturedRoom
        }
        
        print("🏗 Creating RF-enhanced USDZ...")
        
        // Create base scene
        let scene = createBaseScene(from: room)
        
        // Generate propagation data
        generatePropagationData()
        
        // Add RF visualization
        addRFVisualizationToScene(scene)
        
        // Export to USDZ
        try await exportSceneToUSDZ(scene: scene, to: outputURL)
        
        print("✅ RF-enhanced USDZ created successfully")
    }
    
    // MARK: - Propagation Data Generation
    
    private func generatePropagationData() {
        // Generate 3D propagation volume
        propagationData = propagationModel.generate3DPropagationVolume(
            resolution: gridResolution,
            heightLevels: heightLevels
        )
        
        print("📊 Generated \(propagationData.count) propagation points")
    }
    
    // MARK: - Visualization Methods
    
    private func addPlanarVisualization(to asset: MDLAsset) async throws {
        // Create floor heatmap mesh
        let heatmapMesh = createHeatmapMesh()
        
        // Apply signal strength texture
        let texture = try await createSignalTexture()
        applyTextureToMesh(heatmapMesh, texture: texture)
        
        // Add to asset
        asset.add(heatmapMesh)
    }
    
    private func addVolumetricVisualization(to asset: MDLAsset) async throws {
        // Create voxel grid for volumetric rendering
        let voxelGrid = createVoxelGrid()
        
        // Apply signal strength colors
        colorVoxelGrid(voxelGrid)
        
        // Add to asset
        asset.add(voxelGrid)
    }
    
    private func addParticleVisualization(to asset: MDLAsset) async throws {
        // Create particle system
        let particles = createSignalParticles()
        
        // Add to asset
        asset.add(particles)
    }
    
    private func addIsosurfaceVisualization(to asset: MDLAsset) async throws {
        // Create isosurfaces for different signal levels
        let signalLevels: [Float] = [-30, -50, -70, -85] // dBm
        
        for level in signalLevels {
            let isosurface = createIsosurface(at: level)
            asset.add(isosurface)
        }
    }
    
    private func addHybridVisualization(to asset: MDLAsset) async throws {
        // Combine multiple visualization styles
        try await addPlanarVisualization(to: asset)
        try await addIsosurfaceVisualization(to: asset)
        
        // Add access point indicators
        addAccessPointIndicators(to: asset)
    }
    
    // MARK: - Mesh Creation
    
    private func createHeatmapMesh() -> MDLMesh {
        let allocator = MDLMeshBufferDataAllocator()
        
        // Calculate mesh dimensions based on room bounds
        let bounds = calculateRoomBounds()
        let width = bounds.max.x - bounds.min.x
        let depth = bounds.max.z - bounds.min.z
        
        // Create plane mesh
        let mesh = MDLMesh(
            planeWithExtent: vector3(width, depth, 0),
            segments: vector2(Int32(width / gridResolution), Int32(depth / gridResolution)),
            geometryType: .triangles,
            allocator: allocator
        )
        
        mesh.name = "RF_Heatmap"
        
        // Position at floor level
        let transform = MDLTransform()
        transform.translation = vector3(
            (bounds.min.x + bounds.max.x) / 2,
            0.01, // Slightly above floor
            (bounds.min.z + bounds.max.z) / 2
        )
        mesh.transform = transform
        
        return mesh
    }
    
    private func createVoxelGrid() -> MDLMesh {
        let allocator = MDLMeshBufferDataAllocator()
        var vertices: [Float] = []
        var normals: [Float] = []
        var colors: [Float] = []
        var indices: [UInt32] = []
        
        let voxelSize: Float = gridResolution
        var vertexIndex: UInt32 = 0
        
        for point in propagationData {
            // Skip weak signals for performance
            guard point.signalStrength > -85 else { continue }
            
            // Create voxel cube at this point
            let center = point.position
            let halfSize = voxelSize / 2
            
            // Define cube vertices
            let cubeVertices: [simd_float3] = [
                center + simd_float3(-halfSize, -halfSize, -halfSize),
                center + simd_float3( halfSize, -halfSize, -halfSize),
                center + simd_float3( halfSize,  halfSize, -halfSize),
                center + simd_float3(-halfSize,  halfSize, -halfSize),
                center + simd_float3(-halfSize, -halfSize,  halfSize),
                center + simd_float3( halfSize, -halfSize,  halfSize),
                center + simd_float3( halfSize,  halfSize,  halfSize),
                center + simd_float3(-halfSize,  halfSize,  halfSize)
            ]
            
            // Add vertices
            for vertex in cubeVertices {
                vertices.append(contentsOf: [vertex.x, vertex.y, vertex.z])
                normals.append(contentsOf: [0, 1, 0]) // Simplified normals
                
                // Color based on signal strength
                let color = signalStrengthToColor(point.signalStrength)
                colors.append(contentsOf: [color.r, color.g, color.b, signalOpacity])
            }
            
            // Define cube faces (triangles)
            let faceIndices: [UInt32] = [
                // Front face
                0, 1, 2, 0, 2, 3,
                // Back face
                4, 6, 5, 4, 7, 6,
                // Top face
                3, 2, 6, 3, 6, 7,
                // Bottom face
                0, 5, 1, 0, 4, 5,
                // Right face
                1, 5, 6, 1, 6, 2,
                // Left face
                0, 3, 7, 0, 7, 4
            ]
            
            // Add indices with offset
            for index in faceIndices {
                indices.append(vertexIndex + index)
            }
            
            vertexIndex += 8
        }
        
        // Create mesh from vertices
        let vertexBuffer = allocator.newBuffer(
            with: Data(bytes: vertices, count: vertices.count * MemoryLayout<Float>.size),
            type: .vertex
        )
        
        let normalBuffer = allocator.newBuffer(
            with: Data(bytes: normals, count: normals.count * MemoryLayout<Float>.size),
            type: .vertex
        )
        
        let colorBuffer = allocator.newBuffer(
            with: Data(bytes: colors, count: colors.count * MemoryLayout<Float>.size),
            type: .vertex
        )
        
        let indexBuffer = allocator.newBuffer(
            with: Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size),
            type: .index
        )
        
        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: indices.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: nil
        )
        
        let mesh = MDLMesh(
            vertexBuffers: [vertexBuffer, normalBuffer, colorBuffer],
            vertexCount: vertices.count / 3,
            descriptor: createVoxelVertexDescriptor(),
            submeshes: [submesh]
        )
        
        mesh.name = "RF_VoxelGrid"
        
        return mesh
    }
    
    private func createSignalParticles() -> MDLMesh {
        let allocator = MDLMeshBufferDataAllocator()
        var vertices: [Float] = []
        var colors: [Float] = []
        
        // Create particles at measurement points
        for point in propagationData {
            // Add particle position
            vertices.append(contentsOf: [point.position.x, point.position.y, point.position.z])
            
            // Add particle color based on signal strength
            let color = signalStrengthToColor(point.signalStrength)
            colors.append(contentsOf: [color.r, color.g, color.b, signalOpacity])
        }
        
        let vertexBuffer = allocator.newBuffer(
            with: Data(bytes: vertices, count: vertices.count * MemoryLayout<Float>.size),
            type: .vertex
        )
        
        let colorBuffer = allocator.newBuffer(
            with: Data(bytes: colors, count: colors.count * MemoryLayout<Float>.size),
            type: .vertex
        )
        
        let mesh = MDLMesh(
            vertexBuffers: [vertexBuffer, colorBuffer],
            vertexCount: vertices.count / 3,
            descriptor: createParticleVertexDescriptor(),
            submeshes: []
        )
        
        mesh.name = "RF_Particles"
        
        return mesh
    }
    
    private func createIsosurface(at signalLevel: Float) -> MDLMesh {
        // Use marching cubes algorithm to create isosurface
        let marchingCubes = MarchingCubesGenerator(
            data: propagationData,
            isoLevel: signalLevel,
            resolution: gridResolution
        )
        
        return marchingCubes.generateMesh()
    }
    
    // MARK: - Texture Creation
    
    private func createSignalTexture() async throws -> MDLTexture {
        let textureSize = 1024
        
        // Generate heatmap image
        guard let heatmapImage = heatmapGenerator.generateHeatmapImage(
            size: CGSize(width: textureSize, height: textureSize)
        ) else {
            throw IntegratorError.textureGenerationFailed
        }
        
        // Convert to MDLTexture
        guard let cgImage = heatmapImage.cgImage else {
            throw IntegratorError.invalidImage
        }
        
        let texture = MDLTexture(
            cgImage: cgImage,
            name: "RF_SignalTexture",
            assetResolver: nil
        )
        
        return texture
    }
    
    private func applyTextureToMesh(_ mesh: MDLMesh, texture: MDLTexture) {
        let material = MDLMaterial(name: "RF_Material", scatteringFunction: MDLScatteringFunction())
        
        let property = MDLMaterialProperty(
            name: "baseColor",
            semantic: .baseColor,
            texture: texture
        )
        
        material.setProperty(property)
        
        // Set transparency
        let opacityProperty = MDLMaterialProperty(
            name: "opacity",
            semantic: .opacity,
            float: signalOpacity
        )
        material.setProperty(opacityProperty)
        
        // Apply material to mesh
        for submesh in mesh.submeshes as! [MDLSubmesh] {
            submesh.material = material
        }
    }
    
    // MARK: - Scene Creation
    
    private func createBaseScene(from room: CapturedRoom) -> SCNScene {
        let scene = SCNScene()
        
        // Add room geometry
        addRoomGeometry(to: scene, room: room)
        
        // Add lighting
        addLighting(to: scene)
        
        // Add camera
        addCamera(to: scene)
        
        return scene
    }
    
    private func addRoomGeometry(to scene: SCNScene, room: CapturedRoom) {
        let roomNode = SCNNode()
        roomNode.name = "Room"
        
        // Add walls
        for wall in room.walls {
            let wallNode = createWallNode(from: wall)
            roomNode.addChildNode(wallNode)
        }
        
        // Add floor
        for floor in room.floors {
            let floorNode = createFloorNode(from: floor)
            roomNode.addChildNode(floorNode)
        }
        
        // Add ceiling
        for ceiling in room.ceilings {
            let ceilingNode = createCeilingNode(from: ceiling)
            roomNode.addChildNode(ceilingNode)
        }
        
        // Add doors
        for door in room.doors {
            let doorNode = createDoorNode(from: door)
            roomNode.addChildNode(doorNode)
        }
        
        // Add windows
        for window in room.windows {
            let windowNode = createWindowNode(from: window)
            roomNode.addChildNode(windowNode)
        }
        
        scene.rootNode.addChildNode(roomNode)
    }
    
    private func addRFVisualizationToScene(_ scene: SCNScene) {
        let rfNode = SCNNode()
        rfNode.name = "RF_Visualization"
        
        switch visualizationStyle {
        case .planar:
            addPlanarVisualizationToNode(rfNode)
        case .volumetric:
            addVolumetricVisualizationToNode(rfNode)
        case .particles:
            addParticleVisualizationToNode(rfNode)
        case .isosurfaces:
            addIsosurfaceVisualizationToNode(rfNode)
        case .hybrid:
            addHybridVisualizationToNode(rfNode)
        }
        
        scene.rootNode.addChildNode(rfNode)
    }
    
    private func addPlanarVisualizationToNode(_ node: SCNNode) {
        // Create heatmap plane
        let bounds = calculateRoomBounds()
        let width = CGFloat(bounds.max.x - bounds.min.x)
        let depth = CGFloat(bounds.max.z - bounds.min.z)
        
        let plane = SCNPlane(width: width, height: depth)
        
        // Generate and apply heatmap texture
        if let heatmapImage = heatmapGenerator.generateHeatmapImage(
            size: CGSize(width: 1024, height: 1024)
        ) {
            let material = SCNMaterial()
            material.diffuse.contents = heatmapImage
            material.transparency = CGFloat(signalOpacity)
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            plane.materials = [material]
        }
        
        let planeNode = SCNNode(geometry: plane)
        planeNode.position = SCNVector3(
            (bounds.min.x + bounds.max.x) / 2,
            0.01,
            (bounds.min.z + bounds.max.z) / 2
        )
        planeNode.eulerAngles.x = -.pi / 2
        
        node.addChildNode(planeNode)
    }
    
    private func addVolumetricVisualizationToNode(_ node: SCNNode) {
        // Create voxel visualization
        for point in propagationData {
            guard point.signalStrength > -85 else { continue }
            
            let voxel = SCNBox(
                width: CGFloat(gridResolution),
                height: CGFloat(gridResolution),
                length: CGFloat(gridResolution),
                chamferRadius: 0
            )
            
            let material = SCNMaterial()
            let color = signalStrengthToColor(point.signalStrength)
            material.diffuse.contents = UIColor(
                red: CGFloat(color.r),
                green: CGFloat(color.g),
                blue: CGFloat(color.b),
                alpha: CGFloat(signalOpacity)
            )
            material.transparency = CGFloat(signalOpacity)
            voxel.materials = [material]
            
            let voxelNode = SCNNode(geometry: voxel)
            voxelNode.position = SCNVector3(point.position)
            
            node.addChildNode(voxelNode)
        }
    }
    
    private func addParticleVisualizationToNode(_ node: SCNNode) {
        let particleSystem = SCNParticleSystem()
        
        // Configure particle system
        particleSystem.birthRate = 100
        particleSystem.particleLifeSpan = 5
        particleSystem.particleSize = 0.1
        particleSystem.particleColor = UIColor.white
        particleSystem.particleColorVariation = SCNVector4(1, 1, 1, 0)
        
        // Custom particle positions based on propagation data
        var particlePositions: [SCNVector3] = []
        for point in propagationData {
            particlePositions.append(SCNVector3(point.position))
        }
        
        node.addParticleSystem(particleSystem)
    }
    
    private func addIsosurfaceVisualizationToNode(_ node: SCNNode) {
        let signalLevels: [Float] = [-30, -50, -70, -85]
        let colors: [UIColor] = [.green, .yellow, .orange, .red]
        
        for (level, color) in zip(signalLevels, colors) {
            let isosurfaceNode = createIsosurfaceNode(at: level, color: color)
            node.addChildNode(isosurfaceNode)
        }
    }
    
    private func addHybridVisualizationToNode(_ node: SCNNode) {
        addPlanarVisualizationToNode(node)
        addIsosurfaceVisualizationToNode(node)
        addAccessPointNodes(to: node)
    }
    
    // MARK: - Helper Methods
    
    private func createWallNode(from surface: CapturedRoom.Surface) -> SCNNode {
        let wall = SCNBox(
            width: CGFloat(surface.dimensions.x),
            height: CGFloat(surface.dimensions.y),
            length: 0.1,
            chamferRadius: 0
        )
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.lightGray
        wall.materials = [material]
        
        let node = SCNNode(geometry: wall)
        node.position = SCNVector3(surface.transform.position)
        node.orientation = SCNQuaternion(surface.transform.rotation)
        
        return node
    }
    
    private func createFloorNode(from surface: CapturedRoom.Surface) -> SCNNode {
        let floor = SCNPlane(
            width: CGFloat(surface.dimensions.x),
            height: CGFloat(surface.dimensions.y)
        )
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.darkGray
        floor.materials = [material]
        
        let node = SCNNode(geometry: floor)
        node.position = SCNVector3(surface.transform.position)
        node.eulerAngles.x = -.pi / 2
        
        return node
    }
    
    private func createCeilingNode(from surface: CapturedRoom.Surface) -> SCNNode {
        let ceiling = SCNPlane(
            width: CGFloat(surface.dimensions.x),
            height: CGFloat(surface.dimensions.y)
        )
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        ceiling.materials = [material]
        
        let node = SCNNode(geometry: ceiling)
        node.position = SCNVector3(surface.transform.position)
        node.eulerAngles.x = .pi / 2
        
        return node
    }
    
    private func createDoorNode(from surface: CapturedRoom.Surface) -> SCNNode {
        let door = SCNBox(
            width: CGFloat(surface.dimensions.x),
            height: CGFloat(surface.dimensions.y),
            length: 0.05,
            chamferRadius: 0
        )
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.brown
        door.materials = [material]
        
        let node = SCNNode(geometry: door)
        node.position = SCNVector3(surface.transform.position)
        node.orientation = SCNQuaternion(surface.transform.rotation)
        
        return node
    }
    
    private func createWindowNode(from surface: CapturedRoom.Surface) -> SCNNode {
        let window = SCNBox(
            width: CGFloat(surface.dimensions.x),
            height: CGFloat(surface.dimensions.y),
            length: 0.02,
            chamferRadius: 0
        )
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.cyan.withAlphaComponent(0.3)
        material.transparency = 0.3
        window.materials = [material]
        
        let node = SCNNode(geometry: window)
        node.position = SCNVector3(surface.transform.position)
        node.orientation = SCNQuaternion(surface.transform.rotation)
        
        return node
    }
    
    private func createIsosurfaceNode(at level: Float, color: UIColor) -> SCNNode {
        // This would use marching cubes to create the isosurface geometry
        // Simplified version for demonstration
        let node = SCNNode()
        node.name = "Isosurface_\(level)"
        
        // Add isosurface geometry here
        
        return node
    }
    
    private func addAccessPointNodes(to node: SCNNode) {
        // Add visual indicators for access points
        // This would show the optimal AP placements from the propagation model
    }
    
    private func addAccessPointIndicators(to asset: MDLAsset) {
        // Add 3D models for access points
    }
    
    private func addLighting(to scene: SCNScene) {
        // Add ambient light
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 500
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
        
        // Add directional light
        let directionalLight = SCNLight()
        directionalLight.type = .directional
        directionalLight.intensity = 1000
        let directionalNode = SCNNode()
        directionalNode.light = directionalLight
        directionalNode.eulerAngles = SCNVector3(-Float.pi/4, 0, 0)
        scene.rootNode.addChildNode(directionalNode)
    }
    
    private func addCamera(to scene: SCNScene) {
        let camera = SCNCamera()
        camera.fieldOfView = 60
        
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 5, 10)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        
        scene.rootNode.addChildNode(cameraNode)
    }
    
    private func calculateRoomBounds() -> (min: simd_float3, max: simd_float3) {
        guard let room = capturedRoom else {
            return (simd_float3(-5, 0, -5), simd_float3(5, 3, 5))
        }
        
        var minPoint = simd_float3(Float.infinity, Float.infinity, Float.infinity)
        var maxPoint = simd_float3(-Float.infinity, -Float.infinity, -Float.infinity)
        
        for surface in room.walls + room.floors + room.ceilings {
            let position = surface.transform.position
            minPoint = simd_min(minPoint, position)
            maxPoint = simd_max(maxPoint, position)
        }
        
        return (minPoint, maxPoint)
    }
    
    private func extractRoomsFromCapturedRoom(_ room: CapturedRoom) -> [RoomAnalyzer.IdentifiedRoom] {
        // Convert CapturedRoom data to IdentifiedRoom format
        // This is a simplified conversion
        var rooms: [RoomAnalyzer.IdentifiedRoom] = []
        
        // Extract wall points from surfaces
        var wallPoints: [simd_float3] = []
        for wall in room.walls {
            wallPoints.append(wall.transform.position)
        }
        
        if !wallPoints.isEmpty {
            let identifiedRoom = RoomAnalyzer.IdentifiedRoom(
                type: .unknown,
                wallPoints: wallPoints,
                floorArea: calculateFloorArea(from: wallPoints),
                objects: room.objects
            )
            rooms.append(identifiedRoom)
        }
        
        return rooms
    }
    
    private func calculateFloorArea(from points: [simd_float3]) -> Float {
        guard points.count >= 3 else { return 0 }
        
        // Calculate area using shoelace formula
        var area: Float = 0
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            area += points[i].x * points[j].z
            area -= points[j].x * points[i].z
        }
        
        return abs(area) / 2
    }
    
    private func signalStrengthToColor(_ strength: Float) -> (r: Float, g: Float, b: Float) {
        // Map signal strength to color
        let normalized = (strength + 100) / 70 // Normalize -100 to -30 dBm to 0-1
        
        if normalized < 0.25 {
            // Red to orange
            return (1.0, normalized * 4, 0.0)
        } else if normalized < 0.5 {
            // Orange to yellow
            return (1.0, 1.0, (normalized - 0.25) * 4)
        } else if normalized < 0.75 {
            // Yellow to green
            return (1.0 - (normalized - 0.5) * 4, 1.0, 0.0)
        } else {
            // Green
            return (0.0, 1.0, 0.0)
        }
    }
    
    private func createVoxelVertexDescriptor() -> MDLVertexDescriptor {
        let descriptor = MDLVertexDescriptor()
        
        // Position attribute
        descriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        
        // Normal attribute
        descriptor.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3,
            offset: 0,
            bufferIndex: 1
        )
        
        // Color attribute
        descriptor.attributes[2] = MDLVertexAttribute(
            name: MDLVertexAttributeColor,
            format: .float4,
            offset: 0,
            bufferIndex: 2
        )
        
        // Layout
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: 12)
        descriptor.layouts[1] = MDLVertexBufferLayout(stride: 12)
        descriptor.layouts[2] = MDLVertexBufferLayout(stride: 16)
        
        return descriptor
    }
    
    private func createParticleVertexDescriptor() -> MDLVertexDescriptor {
        let descriptor = MDLVertexDescriptor()
        
        // Position attribute
        descriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        
        // Color attribute
        descriptor.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeColor,
            format: .float4,
            offset: 0,
            bufferIndex: 1
        )
        
        // Layout
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: 12)
        descriptor.layouts[1] = MDLVertexBufferLayout(stride: 16)
        
        return descriptor
    }
    
    // MARK: - Export Methods
    
    private func loadUSDZAsset(from url: URL) async throws -> MDLAsset {
        return MDLAsset(url: url)
    }
    
    private func exportUSDZ(asset: MDLAsset, to url: URL) async throws {
        asset.export(to: url)
    }
    
    private func exportSceneToUSDZ(scene: SCNScene, to url: URL) async throws {
        scene.write(to: url, options: nil, delegate: nil, progressHandler: nil)
    }
    
    // MARK: - Error Handling
    
    enum IntegratorError: Error {
        case noCapturedRoom
        case textureGenerationFailed
        case invalidImage
        case exportFailed
    }
}

// MARK: - Marching Cubes Generator
/// Generates isosurface meshes using marching cubes algorithm
class MarchingCubesGenerator {
    private let data: [RFPropagationModel.PropagationPoint]
    private let isoLevel: Float
    private let resolution: Float
    
    init(data: [RFPropagationModel.PropagationPoint], isoLevel: Float, resolution: Float) {
        self.data = data
        self.isoLevel = isoLevel
        self.resolution = resolution
    }
    
    func generateMesh() -> MDLMesh {
        // Simplified marching cubes implementation
        // In a real implementation, this would use lookup tables and proper triangulation
        
        let allocator = MDLMeshBufferDataAllocator()
        
        // Create a simple sphere at the iso level for demonstration
        let mesh = MDLMesh(
            sphereWithExtent: vector3(1, 1, 1),
            segments: vector2(32, 32),
            inwardNormals: false,
            geometryType: .triangles,
            allocator: allocator
        )
        
        mesh.name = "Isosurface_\(isoLevel)"
        
        return mesh
    }
}

// MARK: - Extensions
extension SCNVector3 {
    init(_ simdVector: simd_float3) {
        self.init(simdVector.x, simdVector.y, simdVector.z)
    }
}

extension SCNQuaternion {
    init(_ simdQuaternion: simd_quatf) {
        self.init(simdQuaternion.imag.x, simdQuaternion.imag.y, simdQuaternion.imag.z, simdQuaternion.real)
    }
}

extension SCNNode {
    func look(at target: SCNVector3) {
        let constraint = SCNLookAtConstraint(target: SCNNode())
        constraint.target?.position = target
        self.constraints = [constraint]
    }
}