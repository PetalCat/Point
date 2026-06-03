import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Must be called before any GMSMapView is created.
    // Empty string avoids the checkServicePreconditions crash; real tiles need a key.
    let mapsKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String ?? ""
    if !mapsKey.isEmpty { GMSServices.provideAPIKey(mapsKey) }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Native Keychain channel — replaces the iOS-26-broken secure-storage plugin.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KeychainChannel") {
      KeychainChannel.register(with: registrar.messenger())
    }
  }
}
