/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The sample app's main entry point.
*/

import UIKit
import RoomPlan

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    // MARK: UISceneSession life cycle

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        var configurationName = "Default Configuration"
        
        // Check if we're in simulator - allow simulator to run the full app
        #if targetEnvironment(simulator)
        let isSupported = true  // Force simulator support
        print("🎭 Simulator Mode: Using Default Configuration")
        #else
        let isSupported = RoomCaptureSession.isSupported
        print("📱 Device Mode: isSupported = \(isSupported)")
        #endif
        
        if !isSupported {
            configurationName = "Unsupported Device"
            print("⚠️ Using Unsupported Device configuration")
        } else {
            print("✅ Using Default Configuration")
        }
        
        return UISceneConfiguration(name: configurationName, sessionRole: connectingSceneSession.role)
    }
}

