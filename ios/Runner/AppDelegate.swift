import Flutter
import UIKit
import FirebaseCore

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// App Group identifier shared with GridNotificationService.
  /// Must match `SharedStorage.appGroupID` and the entitlements plists.
  private static let appGroupID = "group.app.mygrid.grid"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialize Firebase using GoogleService-Info.plist bundled with the app.
    // Required for FirebaseMessaging.getAPNSToken() in PushNotificationService.
    FirebaseApp.configure()

    // Register for remote notifications (required for APNs token)
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Wire the method channel the Flutter `AppGroupBridge` uses to mirror
    // Matrix credentials into the App Group `UserDefaults` so the NSE can
    // fetch events. FlutterPluginRegistry itself doesn't expose a messenger
    // — get one via registrar(forPlugin:), which every plugin host supports.
    guard let registrar = engineBridge.pluginRegistry
      .registrar(forPlugin: "GridAppGroupBridge")
    else { return }
    let channel = FlutterMethodChannel(
      name: "app.mygrid.grid/app_group",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else {
        result(FlutterError(code: "DEAD", message: "AppDelegate gone", details: nil))
        return
      }
      switch call.method {
      case "writeMatrixCredentials":
        self.writeMatrixCredentials(arguments: call.arguments, result: result)
      case "clearMatrixCredentials":
        self.clearMatrixCredentials(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func writeMatrixCredentials(arguments: Any?, result: FlutterResult) {
    guard let args = arguments as? [String: Any?] else {
      result(FlutterError(code: "BAD_ARGS", message: "Expected map", details: nil))
      return
    }
    guard let defaults = UserDefaults(suiteName: AppDelegate.appGroupID) else {
      result(FlutterError(code: "NO_SUITE", message: "App Group unavailable", details: nil))
      return
    }
    // Only write keys that were actually provided; keep previous values
    // otherwise so partial re-bridges don't wipe state.
    if let token = args["access_token"] as? String {
      defaults.set(token, forKey: "access_token")
    }
    if let homeserver = args["homeserver_url"] as? String {
      defaults.set(homeserver, forKey: "homeserver_url")
    }
    if let userID = args["user_id"] as? String {
      defaults.set(userID, forKey: "user_id")
    }
    if let deviceID = args["device_id"] as? String {
      defaults.set(deviceID, forKey: "device_id")
    }
    result(nil)
  }

  private func clearMatrixCredentials(result: FlutterResult) {
    guard let defaults = UserDefaults(suiteName: AppDelegate.appGroupID) else {
      result(FlutterError(code: "NO_SUITE", message: "App Group unavailable", details: nil))
      return
    }
    defaults.removeObject(forKey: "access_token")
    defaults.removeObject(forKey: "homeserver_url")
    defaults.removeObject(forKey: "user_id")
    defaults.removeObject(forKey: "device_id")
    result(nil)
  }
}
