import SceneKit
import UIKit

class NetworkDevice3DModels {
    
    // MARK: - Router 3D Model
    
    static func createRouterModel() -> SCNNode {
        let routerNode = SCNNode()
        routerNode.name = "Router"
        
        // Main router body (rectangular box)
        let bodyGeometry = SCNBox(width: 0.25, height: 0.05, length: 0.15, chamferRadius: 0.01)
        let bodyNode = SCNNode(geometry: bodyGeometry)
        
        // Router body material (dark gray/black)
        let bodyMaterial = SCNMaterial()
        bodyMaterial.diffuse.contents = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)
        bodyMaterial.specular.contents = UIColor.white
        bodyMaterial.shininess = 0.3
        bodyMaterial.metalness.contents = 0.1
        bodyMaterial.roughness.contents = 0.8
        bodyGeometry.materials = [bodyMaterial]
        
        // LED indicator (small blue light)
        let ledGeometry = SCNCylinder(radius: 0.01, height: 0.005)
        let ledNode = SCNNode(geometry: ledGeometry)
        let ledMaterial = SCNMaterial()
        ledMaterial.diffuse.contents = UIColor.systemBlue
        ledMaterial.emission.contents = UIColor.systemBlue
        ledGeometry.materials = [ledMaterial]
        ledNode.position = SCNVector3(0.08, 0.03, 0.05)
        
        // Antenna 1 (left)
        let antenna1 = createAntenna()
        antenna1.position = SCNVector3(-0.08, 0.025, -0.04)
        antenna1.rotation = SCNVector4(0, 0, 1, Float.pi * 0.15) // Slight angle
        
        // Antenna 2 (right)  
        let antenna2 = createAntenna()
        antenna2.position = SCNVector3(0.08, 0.025, -0.04)
        antenna2.rotation = SCNVector4(0, 0, 1, -Float.pi * 0.15) // Slight angle opposite
        
        // Ventilation grilles (aesthetic detail)
        for i in 0..<5 {
            let grille = SCNBox(width: 0.02, height: 0.002, length: 0.001, chamferRadius: 0)
            let grilleMaterial = SCNMaterial()
            grilleMaterial.diffuse.contents = UIColor.black
            grille.materials = [grilleMaterial]
            let grilleNode = SCNNode(geometry: grille)
            grilleNode.position = SCNVector3(-0.06 + Float(i) * 0.03, 0.026, 0.02)
            routerNode.addChildNode(grilleNode)
        }
        
        // Assemble router
        routerNode.addChildNode(bodyNode)
        routerNode.addChildNode(ledNode)
        routerNode.addChildNode(antenna1)
        routerNode.addChildNode(antenna2)
        
        // Add subtle animation to LED
        let pulseAction = SCNAction.sequence([
            SCNAction.fadeOpacity(to: 0.3, duration: 1.0),
            SCNAction.fadeOpacity(to: 1.0, duration: 1.0)
        ])
        ledNode.runAction(SCNAction.repeatForever(pulseAction))
        
        return routerNode
    }
    
    private static func createAntenna() -> SCNNode {
        let antennaNode = SCNNode()
        
        // Antenna base (small cylinder)
        let baseGeometry = SCNCylinder(radius: 0.005, height: 0.02)
        let baseNode = SCNNode(geometry: baseGeometry)
        
        // Antenna rod (thin cylinder)
        let rodGeometry = SCNCylinder(radius: 0.002, height: 0.08)
        let rodNode = SCNNode(geometry: rodGeometry)
        rodNode.position = SCNVector3(0, 0.05, 0)
        
        // Antenna material (black plastic)
        let antennaMaterial = SCNMaterial()
        antennaMaterial.diffuse.contents = UIColor.black
        antennaMaterial.specular.contents = UIColor.darkGray
        antennaMaterial.shininess = 0.1
        
        baseGeometry.materials = [antennaMaterial]
        rodGeometry.materials = [antennaMaterial]
        
        antennaNode.addChildNode(baseNode)
        antennaNode.addChildNode(rodNode)
        
        return antennaNode
    }
    
    // MARK: - WiFi Extender 3D Model
    
    static func createExtenderModel() -> SCNNode {
        let extenderNode = SCNNode()
        extenderNode.name = "WiFiExtender"
        
        // Main extender body (smaller, more compact than router)
        let bodyGeometry = SCNBox(width: 0.12, height: 0.08, length: 0.08, chamferRadius: 0.01)
        let bodyNode = SCNNode(geometry: bodyGeometry)
        
        // Extender body material (white/light gray)
        let bodyMaterial = SCNMaterial()
        bodyMaterial.diffuse.contents = UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
        bodyMaterial.specular.contents = UIColor.white
        bodyMaterial.shininess = 0.5
        bodyMaterial.metalness.contents = 0.05
        bodyMaterial.roughness.contents = 0.6
        bodyGeometry.materials = [bodyMaterial]
        
        // Status LED (green for good connection)
        let ledGeometry = SCNCylinder(radius: 0.008, height: 0.003)
        let ledNode = SCNNode(geometry: ledGeometry)
        let ledMaterial = SCNMaterial()
        ledMaterial.diffuse.contents = UIColor.systemGreen
        ledMaterial.emission.contents = UIColor.systemGreen
        ledGeometry.materials = [ledMaterial]
        ledNode.position = SCNVector3(0, 0.043, 0.035)
        ledNode.rotation = SCNVector4(1, 0, 0, Float.pi/2)
        
        // WiFi signal indicator (curved lines)
        let signalNode = createWiFiSignalIndicator()
        signalNode.position = SCNVector3(0, 0.01, 0.041)
        signalNode.scale = SCNVector3(0.3, 0.3, 0.1)
        
        // Power plug prongs (to show it plugs into wall)
        let prong1 = createPowerProng()
        prong1.position = SCNVector3(-0.02, -0.01, -0.045)
        
        let prong2 = createPowerProng()  
        prong2.position = SCNVector3(0.02, -0.01, -0.045)
        
        // Ethernet port (small rectangular opening)
        let portGeometry = SCNBox(width: 0.016, height: 0.008, length: 0.005, chamferRadius: 0)
        let portNode = SCNNode(geometry: portGeometry)
        let portMaterial = SCNMaterial()
        portMaterial.diffuse.contents = UIColor.black
        portGeometry.materials = [portMaterial]
        portNode.position = SCNVector3(0, -0.02, 0.04)
        
        // Assemble extender
        extenderNode.addChildNode(bodyNode)
        extenderNode.addChildNode(ledNode)
        extenderNode.addChildNode(signalNode)
        extenderNode.addChildNode(prong1)
        extenderNode.addChildNode(prong2)
        extenderNode.addChildNode(portNode)
        
        // Add gentle breathing animation to LED
        let breatheAction = SCNAction.sequence([
            SCNAction.fadeOpacity(to: 0.5, duration: 1.5),
            SCNAction.fadeOpacity(to: 1.0, duration: 1.5)
        ])
        ledNode.runAction(SCNAction.repeatForever(breatheAction))
        
        return extenderNode
    }
    
    private static func createWiFiSignalIndicator() -> SCNNode {
        let signalNode = SCNNode()
        
        // Create three curved signal strength bars
        let signalMaterial = SCNMaterial()
        signalMaterial.diffuse.contents = UIColor.systemBlue
        signalMaterial.emission.contents = UIColor.systemBlue.withAlphaComponent(0.3)
        
        for i in 0..<3 {
            let radius = 0.03 + Float(i) * 0.02
            let signal = SCNTorus(ringRadius: CGFloat(radius), pipeRadius: 0.003)
            signal.materials = [signalMaterial]
            let signalGeometry = SCNNode(geometry: signal)
            signalGeometry.position = SCNVector3(0, 0, 0)
            signalNode.addChildNode(signalGeometry)
        }
        
        return signalNode
    }
    
    private static func createPowerProng() -> SCNNode {
        let prongGeometry = SCNBox(width: 0.008, height: 0.025, length: 0.003, chamferRadius: 0)
        let prongNode = SCNNode(geometry: prongGeometry)
        
        let prongMaterial = SCNMaterial()
        prongMaterial.diffuse.contents = UIColor(red: 0.8, green: 0.7, blue: 0.4, alpha: 1.0) // Brass color
        prongMaterial.metalness.contents = 0.8
        prongMaterial.roughness.contents = 0.2
        prongGeometry.materials = [prongMaterial]
        
        return prongNode
    }
    
    // MARK: - Device Labeling
    
    static func addDeviceLabel(to deviceNode: SCNNode, text: String, deviceType: NetworkDeviceManager.NetworkDevice.DeviceType) -> SCNNode {
        let labelNode = SCNNode()
        
        // Create text geometry
        let textGeometry = SCNText(string: text, extrusionDepth: 0.001)
        textGeometry.font = UIFont.systemFont(ofSize: 0.05, weight: .medium)
        textGeometry.flatness = 0.1
        
        // Text material
        let textMaterial = SCNMaterial()
        textMaterial.diffuse.contents = UIColor.white
        textMaterial.emission.contents = UIColor.white.withAlphaComponent(0.1)
        textGeometry.materials = [textMaterial]
        
        // Create background plane for better readability
        let backgroundGeometry = SCNPlane(width: 0.3, height: 0.08)
        let backgroundNode = SCNNode(geometry: backgroundGeometry)
        let backgroundMaterial = SCNMaterial()
        backgroundMaterial.diffuse.contents = UIColor.black.withAlphaComponent(0.7)
        backgroundMaterial.isDoubleSided = true
        backgroundGeometry.materials = [backgroundMaterial]
        
        // Position text
        let textNode = SCNNode(geometry: textGeometry)
        textNode.position = SCNVector3(-0.12, -0.02, 0.001)
        textNode.scale = SCNVector3(1, 1, 0.5)
        
        // Position background
        backgroundNode.position = SCNVector3(0, 0, 0)
        
        // Assemble label
        labelNode.addChildNode(backgroundNode)
        labelNode.addChildNode(textNode)
        
        // Position label above device
        labelNode.position = SCNVector3(0, 0.15, 0)
        labelNode.constraints = [SCNBillboardConstraint()] // Always face camera
        
        deviceNode.addChildNode(labelNode)
        
        return labelNode
    }
    
    // MARK: - Helper Methods
    
    static func createDeviceModel(for deviceType: NetworkDeviceManager.NetworkDevice.DeviceType, withLabel: Bool = true) -> SCNNode {
        let deviceNode: SCNNode
        
        switch deviceType {
        case .router:
            deviceNode = createRouterModel()
            if withLabel {
                addDeviceLabel(to: deviceNode, text: "📡 Router", deviceType: deviceType)
            }
            
        case .extender:
            deviceNode = createExtenderModel() 
            if withLabel {
                addDeviceLabel(to: deviceNode, text: "📶 Extender", deviceType: deviceType)
            }
        }
        
        // Add subtle glow effect
        deviceNode.categoryBitMask = 1
        deviceNode.castsShadow = true
        
        return deviceNode
    }
    
    static func highlightDevice(_ deviceNode: SCNNode, highlighted: Bool) {
        let action: SCNAction
        
        if highlighted {
            // Add highlight glow
            action = SCNAction.sequence([
                SCNAction.scale(to: 1.1, duration: 0.2),
                SCNAction.repeatForever(SCNAction.sequence([
                    SCNAction.fadeOpacity(to: 0.8, duration: 0.8),
                    SCNAction.fadeOpacity(to: 1.0, duration: 0.8)
                ]))
            ])
        } else {
            // Remove highlight
            deviceNode.removeAllActions()
            action = SCNAction.group([
                SCNAction.scale(to: 1.0, duration: 0.2),
                SCNAction.fadeOpacity(to: 1.0, duration: 0.2)
            ])
        }
        
        deviceNode.runAction(action)
    }
}