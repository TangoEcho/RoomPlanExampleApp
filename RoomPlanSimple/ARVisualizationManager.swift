import ARKit
import SceneKit
import UIKit
import simd

class ARVisualizationManager: NSObject, ObservableObject {
    @Published var isARActive = false
    @Published var wifiOverlaysVisible = true
    @Published var measurementNodes: [SCNNode] = []
    
    private var sceneView: ARSCNView?
    private var wifiSurveyManager: WiFiSurveyManager?
    private var roomAnalyzer: RoomAnalyzer?
    
    private var measurementDisplayNodes: [SCNNode] = []
    private var routerPlacementNodes: [SCNNode] = []
    private var coverageOverlayNodes: [SCNNode] = []
    
    func configure(sceneView: ARSCNView, wifiManager: WiFiSurveyManager, roomAnalyzer: RoomAnalyzer) {
        self.sceneView = sceneView
        self.wifiSurveyManager = wifiManager
        self.roomAnalyzer = roomAnalyzer
        
        // Only setup AR if supported
        if ARWorldTrackingConfiguration.isSupported {
            setupARSession()
        }
    }
    
    private func setupARSession() {
        guard let sceneView = sceneView else { return }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .meshWithClassification
        configuration.environmentTexturing = .automatic
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        }
        
        sceneView.session.run(configuration)
        sceneView.delegate = self
        isARActive = true
    }
    
    func addWiFiMeasurementVisualization(at position: simd_float3, measurement: WiFiMeasurement) {
        guard let sceneView = sceneView else { return }
        
        let node = createMeasurementNode(for: measurement)
        node.position = SCNVector3(position.x, position.y, position.z)
        
        sceneView.scene.rootNode.addChildNode(node)
        measurementDisplayNodes.append(node)
        
        DispatchQueue.main.async {
            self.measurementNodes.append(node)
        }
    }
    
    private func createMeasurementNode(for measurement: WiFiMeasurement) -> SCNNode {
        let node = SCNNode()
        
        let sphere = SCNSphere(radius: 0.05)
        let material = SCNMaterial()
        
        material.diffuse.contents = signalStrengthColor(measurement.signalStrength)
        material.emission.contents = signalStrengthColor(measurement.signalStrength)
        material.transparency = 0.8
        
        sphere.materials = [material]
        node.geometry = sphere
        
        let textNode = createTextNode(for: measurement)
        textNode.position = SCNVector3(0, 0.1, 0)
        node.addChildNode(textNode)
        
        let pulseAnimation = CABasicAnimation(keyPath: "transform.scale")
        pulseAnimation.fromValue = 1.0
        pulseAnimation.toValue = 1.2
        pulseAnimation.duration = 1.0
        pulseAnimation.repeatCount = .infinity
        pulseAnimation.autoreverses = true
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
    
    private func signalStrengthColor(_ strength: Int) -> UIColor {
        let normalizedStrength = Float(strength + 100) / 50.0
        
        switch normalizedStrength {
        case 0.8...1.0:
            return UIColor.green
        case 0.6..<0.8:
            return UIColor.yellow
        case 0.4..<0.6:
            return UIColor.orange
        default:
            return UIColor.red
        }
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
        material.diffuse.contents = UIColor.systemBlue
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
        
        for (position, coverage) in heatmapData.coverageMap {
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
    
    func stopARSession() {
        sceneView?.session.pause()
        isARActive = false
    }
}

extension ARVisualizationManager: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let sceneView = sceneView,
              let currentFrame = sceneView.session.currentFrame else { return }
        
        let transform = currentFrame.camera.transform
        let position = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        
        if let wifiManager = wifiSurveyManager, wifiManager.isRecording {
            let roomType = determineCurrentRoomType(at: position)
            wifiManager.recordMeasurement(at: position, roomType: roomType)
        }
    }
    
    private func determineCurrentRoomType(at position: simd_float3) -> RoomType? {
        guard let roomAnalyzer = roomAnalyzer else { return nil }
        
        for room in roomAnalyzer.identifiedRooms {
            if isPositionInRoom(position, room: room) {
                return room.type
            }
        }
        return nil
    }
    
    private func isPositionInRoom(_ position: simd_float3, room: RoomAnalyzer.IdentifiedRoom) -> Bool {
        let distance = simd_distance(position, room.center)
        let roomRadius = sqrt(room.area) / 2
        return distance <= roomRadius
    }
}