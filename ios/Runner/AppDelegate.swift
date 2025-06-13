import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // SOLUTION D'URGENCE: Try-catch pour éviter le crash
    do {
      GeneratedPluginRegistrant.register(with: self)
    } catch {
      print("❌ [iOS] Erreur plugins: \(error) - Application continue sans certains plugins")
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}