import ARKit
import SceneKit
import UIKit
import simd
import RoomPlan

class ARVisualizationManager: NSObject, ObservableObject {
    @Published var isARActive = false
    @Published var wifiOverlaysVisible = true
    @Published var measurementNodes: [SCNNode] = []
    
    private var sceneView: ARSCNView?
    private var wifiSurveyManager: WiFiSurveyManager?
    private var roomAnalyzer: RoomAnalyzer?
    
    // iOS 17+ Shared ARSession support for perfect coordinate alignment
    private var isUsingSharedARSession = false
    
    private var measurementDisplayNodes: [SCNNode] = []
    private var routerPlacementNodes: [SCNNode] = []
    private var coverageOverlayNodes: [SCNNode] = []
    private var roomOutlineNodes: [SCNNode] = []
    
    // Performance optimization: Node pooling
    private var nodePool: [SCNNode] = []
    private let maxNodes = 20 // Reduce max nodes for better performance
    
    // Performance optimization: Update throttling
    private var lastUpdateTime: TimeInterval = 0
    private let updateInterval: TimeInterval = 2.0 // Update every 2 seconds to reduce load
    
    deinit {
        print("🧹 ARVisualizationManager deallocating - cleaning up AR session")
        stopARSession()
        clearAllVisualizations()
    }
    
    func configure(sceneView: ARSCNView, wifiManager: WiFiSurveyManager, roomAnalyzer: RoomAnalyzer) {
        self.sceneView = sceneView
        self.wifiSurveyManager = wifiManager
        self.roomAnalyzer = roomAnalyzer
        
        // Only setup AR if supported
        if ARWorldTrackingConfiguration.isSupported {
            setupARSession()
        }
    }
    
    func setCapturedRoomData(_ capturedRoom: CapturedRoom?) {
        // This will be used to align AR coordinate system with RoomPlan coordinate system
        self.capturedRoomData = capturedRoom
        if let capturedRoom = capturedRoom {
            createRoomOutlines(from: capturedRoom)
            calculateCoordinateTransform(from: capturedRoom)
        }
    }
    
    // Store room data for coordinate alignment
    private var capturedRoomData: CapturedRoom?
    private var coordinateTransform: simd_float4x4 = matrix_identity_float4x4
    private var roomCenterOffset: simd_float3 = simd_float3(0, 0, 0)
    
    // Calibration system
    private var isCalibrationMode = false
    private var calibrationPoints: [(ar: simd_float3, room: simd_float3)] = []
    private var needsCalibration = true
    
    private func setupARSession() {
        guard let sceneView = sceneView else { return }
        
        let configuration = ARWorldTrackingConfiguration()
        // Reduce AR complexity for better performance
        configuration.sceneReconstruction = .mesh // Remove classification to reduce load
        configuration.environmentTexturing = .none // Disable environment texturing
        
        // Disable person segmentation for better performance
        // if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
        //     configuration.frameSemantics.insert(.personSegmentationWithDepth)
        // }
        
        sceneView.session.run(configuration)
        sceneView.delegate = self
        isARActive = true
    }
    
    func addWiFiMeasurementVisualization(at position: simd_float3, measurement: WiFiMeasurement) {
        guard let sceneView = sceneView else { return }
        
        // Performance optimization: Limit number of nodes
        if measurementDisplayNodes.count >= maxNodes {
            // Remove oldest node
            let oldestNode = measurementDisplayNodes.removeFirst()
            oldestNode.removeFromParentNode()
            
            // Return to pool for reuse
            oldestNode.removeAllAnimations()
            nodePool.append(oldestNode)
        }
        
        // Apply coordinate transformation to align with room coordinates
        let alignedPosition = transformARToRoomCoordinates(position)
        
        // Create the main measurement node (floating sphere)
        let node = getOrCreateMeasurementNode(for: measurement)
        node.position = SCNVector3(alignedPosition.x, alignedPosition.y, alignedPosition.z)
        
        // Add floor indicator (colored dot on the floor)
        let floorIndicator = createFloorIndicatorNode(for: measurement)
        floorIndicator.position = SCNVector3(alignedPosition.x, alignedPosition.y - 1.5, alignedPosition.z) // Place on floor
        
        sceneView.scene.rootNode.addChildNode(node)
        sceneView.scene.rootNode.addChildNode(floorIndicator)
        measurementDisplayNodes.append(node)
        measurementDisplayNodes.append(floorIndicator)
        
        DispatchQueue.main.async {
            if self.measurementNodes.count >= self.maxNodes {
                self.measurementNodes.removeFirst()
            }
            self.measurementNodes.append(node)
        }
    }
    
    private func getOrCreateMeasurementNode(for measurement: WiFiMeasurement) -> SCNNode {
        // Try to reuse a node from the pool
        if let reusableNode = nodePool.popLast() {
            updateMeasurementNode(reusableNode, for: measurement)
            return reusableNode
        } else {
            return createMeasurementNode(for: measurement)
        }
    }
    
    private func updateMeasurementNode(_ node: SCNNode, for measurement: WiFiMeasurement) {
        // Update the sphere material color
        if let sphere = node.geometry as? SCNSphere,
           let material = sphere.materials.first {
            let color = signalStrengthColor(measurement.signalStrength)
            material.diffuse.contents = color
            material.emission.contents = color
        }
        
        // Update the text
        if let textNode = node.childNodes.first {
            if let text = textNode.geometry as? SCNText {
                text.string = "\(measurement.signalStrength)dBm\n\(String(format: "%.1f", measurement.speed))Mbps"
            }
        }
        
        // Re-add animation
        let pulseAnimation = CABasicAnimation(keyPath: "transform.scale")
        pulseAnimation.fromValue = 1.0
        pulseAnimation.toValue = 1.2
        pulseAnimation.duration = 1.0
        pulseAnimation.repeatCount = .infinity
        pulseAnimation.autoreverses = true
        node.addAnimation(pulseAnimation, forKey: "pulse")
    }
    
    private func createMeasurementNode(for measurement: WiFiMeasurement) -> SCNNode {
        let node = SCNNode()
        
        // Create a slightly larger sphere for better visibility
        let sphere = SCNSphere(radius: 0.08)
        let material = SCNMaterial()
        
        let baseColor = signalStrengthColor(measurement.signalStrength)
        material.diffuse.contents = baseColor
        material.emission.contents = baseColor.withAlphaComponent(0.3)
        material.transparency = 0.7
        
        // Add metallic look for better visibility
        material.metalness.contents = 0.1
        material.roughness.contents = 0.3
        
        sphere.materials = [material]
        node.geometry = sphere
        
        // Add a ring around the measurement point
        let ringGeometry = SCNTorus(ringRadius: 0.12, pipeRadius: 0.01)
        let ringMaterial = SCNMaterial()
        ringMaterial.diffuse.contents = baseColor
        ringMaterial.emission.contents = baseColor
        ringGeometry.materials = [ringMaterial]
        
        let ringNode = SCNNode(geometry: ringGeometry)
        ringNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        node.addChildNode(ringNode)
        
        let textNode = createTextNode(for: measurement)
        textNode.position = SCNVector3(0, 0.15, 0)
        node.addChildNode(textNode)
        
        // Enhanced pulsing animation
        let pulseAnimation = CABasicAnimation(keyPath: "transform.scale")
        pulseAnimation.fromValue = 0.8
        pulseAnimation.toValue = 1.1
        pulseAnimation.duration = 1.5
        pulseAnimation.repeatCount = .infinity
        pulseAnimation.autoreverses = true
        pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        node.addAnimation(pulseAnimation, forKey: "pulse")
        
        return node
    }
    
    private func createTextNode(for measurement: WiFiMeasurement) -> SCNNode {
        let text = SCNText(string: "\(measurement.signalStrength)dBm\n\(String(format: "%.1f", measurement.speed))Mbps", extrusionDepth: 0.01)
        text.font = UIFont.systemFont(ofSize: 0.05)
        text.materials.first?.diffuse.contents = UIColor.white
        
        let textNode = SCNNode(geometry: text)
        textNode.scale = SCNVector3(0.01, 0.01, 0.01)
        
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = [.Y]
        textNode.constraints = [billboardConstraint]
        
        return textNode
    }
    
    private func createFloorIndicatorNode(for measurement: WiFiMeasurement) -> SCNNode {
        let node = SCNNode()
        
        // Create a colored circle on the floor
        let circleGeometry = SCNCylinder(radius: 0.15, height: 0.01) // Thin cylinder as floor circle
        let material = SCNMaterial()
        
        let signalColor = signalStrengthColor(measurement.signalStrength)
        material.diffuse.contents = signalColor
        material.emission.contents = signalColor.withAlphaComponent(0.5)
        material.transparency = 0.8
        
        // Add pulsing effect for better visibility
        material.metalness.contents = 0.2
        material.roughness.contents = 0.1
        
        circleGeometry.materials = [material]
        node.geometry = circleGeometry
        
        // Add inner circle with speed information
        let innerCircle = SCNCylinder(radius: 0.08, height: 0.02)
        let innerMaterial = SCNMaterial()
        
        // Color inner circle based on speed
        let speedColor: UIColor
        if measurement.speed > 100 {
            speedColor = SpectrumBranding.Colors.excellentSignal
        } else if measurement.speed > 50 {
            speedColor = SpectrumBranding.Colors.goodSignal
        } else if measurement.speed > 20 {
            speedColor = SpectrumBranding.Colors.fairSignal
        } else {
            speedColor = SpectrumBranding.Colors.poorSignal
        }
        
        innerMaterial.diffuse.contents = speedColor
        innerMaterial.emission.contents = speedColor.withAlphaComponent(0.3)
        innerMaterial.transparency = 0.6
        innerCircle.materials = [innerMaterial]
        
        let innerNode = SCNNode(geometry: innerCircle)
        innerNode.position = SCNVector3(0, 0.005, 0) // Slightly above main circle
        node.addChildNode(innerNode)
        
        // Add subtle animation
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.9
        scaleAnimation.toValue = 1.1
        scaleAnimation.duration = 2.0
        scaleAnimation.repeatCount = .infinity
        scaleAnimation.autoreverses = true
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        node.addAnimation(scaleAnimation, forKey: "floorPulse")
        
        // Add a small text label for signal strength
        let floorText = SCNText(string: "\(measurement.signalStrength)", extrusionDepth: 0.005)
        floorText.font = UIFont.boldSystemFont(ofSize: 0.04)
        floorText.materials.first?.diffuse.contents = UIColor.white
        
        let floorTextNode = SCNNode(geometry: floorText)
        floorTextNode.position = SCNVector3(-0.02, 0.01, -0.02) // Center the text
        floorTextNode.scale = SCNVector3(0.01, 0.01, 0.01)
        
        let textBillboard = SCNBillboardConstraint()
        textBillboard.freeAxes = [.Y]
        floorTextNode.constraints = [textBillboard]
        
        node.addChildNode(floorTextNode)
        
        return node
    }
    
    private func signalStrengthColor(_ strength: Int) -> UIColor {
        return SpectrumBranding.signalStrengthColor(for: strength)
    }
    
    func visualizeOptimalRouterPlacements(_ placements: [simd_float3]) {
        clearRouterPlacementNodes()
        
        guard let sceneView = sceneView else { return }
        
        for placement in placements {
            let node = createRouterPlacementNode()
            node.position = SCNVector3(placement.x, placement.y + 0.5, placement.z)
            
            sceneView.scene.rootNode.addChildNode(node)
            routerPlacementNodes.append(node)
        }
    }
    
    private func createRouterPlacementNode() -> SCNNode {
        let node = SCNNode()
        
        let box = SCNBox(width: 0.2, height: 0.1, length: 0.2, chamferRadius: 0.02)
        let material = SCNMaterial()
        material.diffuse.contents = SpectrumBranding.Colors.spectrumBlue
        material.transparency = 0.7
        box.materials = [material]
        
        node.geometry = box
        
        let text = SCNText(string: "📡 Router", extrusionDepth: 0.01)
        text.font = UIFont.boldSystemFont(ofSize: 0.08)
        text.materials.first?.diffuse.contents = UIColor.white
        
        let textNode = SCNNode(geometry: text)
        textNode.position = SCNVector3(0, 0.1, 0)
        textNode.scale = SCNVector3(0.01, 0.01, 0.01)
        
        let billboardConstraint = SCNBillboardConstraint()
        textNode.constraints = [billboardConstraint]
        
        node.addChildNode(textNode)
        
        let rotateAnimation = CABasicAnimation(keyPath: "rotation")
        rotateAnimation.fromValue = SCNVector4(0, 1, 0, 0)
        rotateAnimation.toValue = SCNVector4(0, 1, 0, Float.pi * 2)
        rotateAnimation.duration = 4.0
        rotateAnimation.repeatCount = .infinity
        node.addAnimation(rotateAnimation, forKey: "rotate")
        
        return node
    }
    
    func createCoverageHeatmap(_ heatmapData: WiFiHeatmapData) {
        clearCoverageOverlayNodes()
        
        guard let sceneView = sceneView else { return }
        
        // Validate coverage map has sufficient data points
        guard heatmapData.coverageMap.count > 1 else {
            print("⚠️ Insufficient coverage data points for heatmap: \(heatmapData.coverageMap.count)")
            return
        }
        
        for (position, coverage) in heatmapData.coverageMap {
            // Validate coverage value is in reasonable range
            guard coverage > 0 && coverage < 10.0 else {
                print("⚠️ Invalid coverage value: \(coverage) at position \(position)")
                continue
            }
            
            let node = createCoverageOverlayNode(coverage: coverage)
            node.position = SCNVector3(position.x, position.y + 0.01, position.z)
            
            sceneView.scene.rootNode.addChildNode(node)
            coverageOverlayNodes.append(node)
        }
    }
    
    private func createCoverageOverlayNode(coverage: Double) -> SCNNode {
        let node = SCNNode()
        
        let plane = SCNPlane(width: 0.5, height: 0.5)
        let material = SCNMaterial()
        
        let alpha = Float(coverage * 0.5)
        material.diffuse.contents = signalStrengthColor(Int((coverage - 1.0) * 50.0 - 100))
        material.transparency = CGFloat(alpha)
        material.writesToDepthBuffer = false
        
        plane.materials = [material]
        node.geometry = plane
        
        node.eulerAngles = SCNVector3(-Float.pi/2, 0, 0)
        
        return node
    }
    
    func toggleWiFiOverlays() {
        wifiOverlaysVisible.toggle()
        
        let alpha: Float = wifiOverlaysVisible ? 1.0 : 0.0
        
        for node in measurementDisplayNodes + routerPlacementNodes + coverageOverlayNodes {
            node.opacity = CGFloat(alpha)
        }
    }
    
    func clearAllVisualizations() {
        clearMeasurementNodes()
        clearRouterPlacementNodes()
        clearCoverageOverlayNodes()
        clearRoomOutlines()
    }
    
    private func clearMeasurementNodes() {
        measurementDisplayNodes.forEach { $0.removeFromParentNode() }
        measurementDisplayNodes.removeAll()
        
        DispatchQueue.main.async {
            self.measurementNodes.removeAll()
        }
    }
    
    private func clearRouterPlacementNodes() {
        routerPlacementNodes.forEach { $0.removeFromParentNode() }
        routerPlacementNodes.removeAll()
    }
    
    private func clearCoverageOverlayNodes() {
        coverageOverlayNodes.forEach { $0.removeFromParentNode() }
        coverageOverlayNodes.removeAll()
    }
    
    private func clearRoomOutlines() {
        roomOutlineNodes.forEach { $0.removeFromParentNode() }
        roomOutlineNodes.removeAll()
    }
    
    private func createRoomOutlines(from capturedRoom: CapturedRoom) {
        clearRoomOutlines()
        
        guard let sceneView = sceneView else { return }
        
        print("🏠 Creating room outlines for \(capturedRoom.walls.count) walls")
        
        // Create outlines for walls
        for wall in capturedRoom.walls {
            let wallNode = createWallOutlineNode(from: wall)
            sceneView.scene.rootNode.addChildNode(wallNode)
            roomOutlineNodes.append(wallNode)
        }
        
        // Create outlines for floors
        for floor in capturedRoom.floors {
            let floorNode = createFloorOutlineNode(from: floor)
            sceneView.scene.rootNode.addChildNode(floorNode)
            roomOutlineNodes.append(floorNode)
        }
    }
    
    private func createWallOutlineNode(from wall: CapturedRoom.Surface) -> SCNNode {
        let node = SCNNode()
        
        // Create a thin box representing the wall outline
        let wallGeometry = SCNBox(
            width: CGFloat(wall.dimensions.x),
            height: CGFloat(wall.dimensions.y),
            length: 0.02, // Very thin outline
            chamferRadius: 0
        )
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.transparency = 0.7
        material.writesToDepthBuffer = false
        wallGeometry.materials = [material]
        
        node.geometry = wallGeometry
        node.simdTransform = wall.transform
        
        return node
    }
    
    private func createFloorOutlineNode(from floor: CapturedRoom.Surface) -> SCNNode {
        let node = SCNNode()
        
        // Create a thin plane for floor outline
        let floorGeometry = SCNPlane(
            width: CGFloat(floor.dimensions.x),
            height: CGFloat(floor.dimensions.z)
        )
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.transparency = 0.3
        material.writesToDepthBuffer = false
        floorGeometry.materials = [material]
        
        node.geometry = floorGeometry
        node.simdTransform = floor.transform
        
        // Rotate to lay flat
        node.eulerAngles = SCNVector3(-Float.pi/2, 0, 0)
        
        return node
    }
    
    func startARSession() {
        guard let sceneView = sceneView else {
            print("❌ Cannot start AR session: sceneView is nil")
            return
        }
        
        // iOS 17+: If using shared ARSession, don't start new session
        if isUsingSharedARSession {
            print("🎯 Using shared ARSession - Perfect coordinate alignment active")
            sceneView.delegate = self
            isARActive = true
            return
        }
        
        guard !isARActive else {
            print("⚠️ AR session already active, ignoring start request")
            return
        }
        
        guard ARWorldTrackingConfiguration.isSupported else {
            print("❌ ARWorldTrackingConfiguration not supported on this device")
            return
        }
        
        // Stop any existing session first
        sceneView.session.pause()
        
        let configuration = ARWorldTrackingConfiguration()
        // Use lightweight AR configuration for better performance
        configuration.sceneReconstruction = .mesh
        configuration.environmentTexturing = .none
        
        // Set delegate before running session
        sceneView.delegate = self
        
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isARActive = true
        
        print("✅ AR session started successfully")
    }
    
    func startARSessionWithRoomPlanCoordinates(_ coordinateSystem: simd_float4x4) {
        startARSession()
        
        // Note: setWorldOrigin is not available in the public ARKit API
        // We'll handle coordinate alignment through our transform methods instead
        print("🎯 AR session started - coordinate alignment handled through transforms")
    }
    
    // iOS 17+ method to enable shared ARSession mode for perfect coordinate alignment
    func setSharedARSessionMode(_ enabled: Bool) {
        isUsingSharedARSession = enabled
        if enabled {
            print("🎯 Shared ARSession mode enabled - Perfect coordinate alignment active")
        } else {
            print("⚠️ Shared ARSession mode disabled - Using separate session")
        }
    }
    
    func stopARSession() {
        guard isARActive else { return }
        
        // Clean up all AR visualizations before stopping
        clearAllVisualizations()
        
        // iOS 17+: Don't stop shared ARSession, just clear delegate
        if isUsingSharedARSession {
            print("🎯 Preserving shared ARSession - only clearing delegate")
            sceneView?.delegate = nil
        } else {
            // iOS 16: Stop separate AR session
            sceneView?.session.pause()
            sceneView?.delegate = nil
            print("🛑 AR session stopped and cleaned up")
        }
        
        isARActive = false
        isUsingSharedARSession = false
    }
    
    // MARK: - Coordinate System Alignment
    
    private func calculateCoordinateTransform(from capturedRoom: CapturedRoom) {
        // Calculate the room center from floor surfaces with improved accuracy
        guard !capturedRoom.floors.isEmpty else { 
            print("⚠️ No floor data available for coordinate alignment")
            return 
        }
        
        // Method 1: Calculate center from floor bounds instead of just transform origins
        var minBounds = simd_float3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxBounds = simd_float3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        
        for floor in capturedRoom.floors {
            let center = simd_float3(floor.transform.columns.3.x, floor.transform.columns.3.y, floor.transform.columns.3.z)
            let halfSize = floor.dimensions / 2
            
            minBounds = simd_min(minBounds, center - halfSize)
            maxBounds = simd_max(maxBounds, center + halfSize)
        }
        
        let geometricCenter = (minBounds + maxBounds) / 2
        roomCenterOffset = geometricCenter
        
        print("🔄 Coordinate alignment: Geometric room center at (\(String(format: "%.3f", geometricCenter.x)), \(String(format: "%.3f", geometricCenter.y)), \(String(format: "%.3f", geometricCenter.z)))")
        print("   Room bounds: min(\(String(format: "%.3f", minBounds.x)), \(String(format: "%.3f", minBounds.y)), \(String(format: "%.3f", minBounds.z))) max(\(String(format: "%.3f", maxBounds.x)), \(String(format: "%.3f", maxBounds.y)), \(String(format: "%.3f", maxBounds.z)))")
        
        // Try to find matching features between AR and Room coordinate systems
        alignWithRoomFeatures(capturedRoom)
    }
    
    private func alignWithRoomFeatures(_ capturedRoom: CapturedRoom) {
        // Method 1: Try to align using walls as reference points
        alignWithWalls(capturedRoom)
        
        // Method 2: Try to align using furniture if available
        alignWithFurniture(capturedRoom)
        
        // Method 3: Use room bounds as fallback
        alignWithRoomBounds(capturedRoom)
    }
    
    private func alignWithWalls(_ capturedRoom: CapturedRoom) {
        guard !capturedRoom.walls.isEmpty else { return }
        
        // Find the longest wall as a primary reference
        let longestWall = capturedRoom.walls.max { wall1, wall2 in
            wall1.dimensions.x < wall2.dimensions.x
        }
        
        if let wall = longestWall {
            let wallCenter = simd_float3(wall.transform.columns.3.x, wall.transform.columns.3.y, wall.transform.columns.3.z)
            let wallDirection = simd_float3(wall.transform.columns.0.x, wall.transform.columns.0.y, wall.transform.columns.0.z)
            
            print("🧱 Primary wall reference: center (\(wallCenter.x), \(wallCenter.y), \(wallCenter.z)), direction (\(wallDirection.x), \(wallDirection.y), \(wallDirection.z))")
            
            // Store wall reference for coordinate transformation
            // This could be enhanced with more sophisticated alignment algorithms
        }
    }
    
    private func alignWithFurniture(_ capturedRoom: CapturedRoom) {
        guard !capturedRoom.objects.isEmpty else { return }
        
        // Use large furniture items as reference points
        let largeFurniture = capturedRoom.objects.filter { object in
            let volume = object.dimensions.x * object.dimensions.y * object.dimensions.z
            return volume > 0.5 // Objects larger than 0.5 cubic meters
        }
        
        if !largeFurniture.isEmpty {
            print("🪑 Found \(largeFurniture.count) large furniture items for alignment reference")
            
            for furniture in largeFurniture.prefix(3) { // Use up to 3 reference points
                let position = simd_float3(furniture.transform.columns.3.x, furniture.transform.columns.3.y, furniture.transform.columns.3.z)
                print("   Furniture \(furniture.category) at (\(position.x), \(position.y), \(position.z))")
            }
        }
    }
    
    private func alignWithRoomBounds(_ capturedRoom: CapturedRoom) {
        // Calculate overall room bounds as fallback alignment method
        guard !capturedRoom.floors.isEmpty else { return }
        
        var minBounds = simd_float3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxBounds = simd_float3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        
        for floor in capturedRoom.floors {
            let center = simd_float3(floor.transform.columns.3.x, floor.transform.columns.3.y, floor.transform.columns.3.z)
            let halfSize = floor.dimensions / 2
            
            minBounds = simd_min(minBounds, center - halfSize)
            maxBounds = simd_max(maxBounds, center + halfSize)
        }
        
        let roomSize = maxBounds - minBounds
        print("📐 Room bounds: min(\(minBounds.x), \(minBounds.y), \(minBounds.z)) max(\(maxBounds.x), \(maxBounds.y), \(maxBounds.z))")
        print("📏 Room size: (\(roomSize.x), \(roomSize.y), \(roomSize.z))")
    }
    
    private func transformARToRoomCoordinates(_ arPosition: simd_float3) -> simd_float3 {
        // iOS 17+: With shared ARSession, coordinates are perfectly aligned!
        if isUsingSharedARSession {
            // Perfect coordinate alignment - no transformation needed
            print("🎯 Perfect coordinate alignment: AR(\(String(format: "%.2f", arPosition.x)), \(String(format: "%.2f", arPosition.y)), \(String(format: "%.2f", arPosition.z))) = Room coordinates")
            return arPosition
        }
        
        // iOS 16: Apply coordinate transformation with room data if available
        var transformed = arPosition
        
        // Apply room center offset if we have room data
        if roomCenterOffset != simd_float3(0, 0, 0) {
            transformed = arPosition - roomCenterOffset
            print("🔄 Room-aligned transform: AR(\(String(format: "%.2f", arPosition.x)), \(String(format: "%.2f", arPosition.y)), \(String(format: "%.2f", arPosition.z))) -> Room(\(String(format: "%.2f", transformed.x)), \(String(format: "%.2f", transformed.y)), \(String(format: "%.2f", transformed.z)))")
        } else {
            print("⚠️ No room alignment data - using AR coordinates directly")
        }
        
        return transformed
    }
    
    private func transformRoomToARCoordinates(_ roomPosition: simd_float3) -> simd_float3 {
        // Simplified inverse transformation - just return as-is for now
        return roomPosition
    }
}

extension ARVisualizationManager: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // Performance optimization: Throttle updates
        guard time - lastUpdateTime > updateInterval else { return }
        lastUpdateTime = time
        
        guard let sceneView = sceneView else { return }
        
        // Extract position without retaining the ARFrame - use a more efficient approach
        guard let currentFrame = sceneView.session.currentFrame else { return }
        
        // Immediately extract the position data without holding frame reference
        let cameraTransform = currentFrame.camera.transform
        let position = simd_float3(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        
        // Release frame reference immediately by not storing it anywhere
        
        if let wifiManager = wifiSurveyManager, wifiManager.isRecording {
            // Transform AR coordinates to room-aligned coordinates
            let alignedPosition = transformARToRoomCoordinates(position)
            let roomType = determineCurrentRoomType(at: alignedPosition)
            let measurementCountBefore = wifiManager.measurements.count
            
            // Record measurement using aligned coordinates
            wifiManager.recordMeasurement(at: alignedPosition, roomType: roomType)
            
            // Add visualization for new measurement (only if a new one was actually added)
            if wifiManager.measurements.count > measurementCountBefore,
               let lastMeasurement = wifiManager.measurements.last {
                print("🎯 Adding AR visualization for measurement at aligned position (\(alignedPosition.x), \(alignedPosition.y), \(alignedPosition.z))")
                print("   Original AR position: (\(position.x), \(position.y), \(position.z))")
                addWiFiMeasurementVisualization(at: position, measurement: lastMeasurement)
            }
        }
    }
    
    private func determineCurrentRoomType(at position: simd_float3) -> RoomType? {
        guard let roomAnalyzer = roomAnalyzer else { return nil }
        
        // Use improved room detection method from RoomAnalyzer
        if let containingRoom = roomAnalyzer.findRoomContaining(position: position) {
            print("   ✅ User is in \(containingRoom.type.rawValue)")
            return containingRoom.type
        }
        
        print("   ❓ User location not in any identified room")
        return nil
    }
    
    private func isUserStandingInRoom(_ userPosition: simd_float3, room: RoomAnalyzer.IdentifiedRoom) -> Bool {
        // Check if user's position is within the room bounds
        // Use room's floor surface as the reference
        let roomBounds = room.bounds
        let roomCenter = room.center
        
        // Calculate room boundaries from the surface dimensions
        let halfWidth = roomBounds.dimensions.x / 2
        let halfDepth = roomBounds.dimensions.z / 2
        
        // Check if user is within the room's horizontal boundaries
        let isWithinWidth = abs(userPosition.x - roomCenter.x) <= halfWidth
        let isWithinDepth = abs(userPosition.z - roomCenter.z) <= halfDepth
        
        // Check if user is at reasonable height above the floor (within 0.5m to 3m above floor)
        let floorHeight = roomCenter.y
        let heightAboveFloor = userPosition.y - floorHeight
        let isAtReasonableHeight = heightAboveFloor >= 0.5 && heightAboveFloor <= 3.0
        
        let isInRoom = isWithinWidth && isWithinDepth && isAtReasonableHeight
        
        if isInRoom {
            print("     📍 User within room bounds: width=\(isWithinWidth), depth=\(isWithinDepth), height=\(String(format: "%.2f", heightAboveFloor))m above floor")
        }
        
        return isInRoom
    }
}