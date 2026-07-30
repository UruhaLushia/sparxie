import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "SystemColors"
    ) else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "zip.atri.sparxie/system_colors",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "getAccentColor" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let color = UIView().tintColor ?? UIColor.systemBlue
      var red: CGFloat = 0
      var green: CGFloat = 0
      var blue: CGFloat = 0
      var alpha: CGFloat = 0
      guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
        result(nil)
        return
      }
      let argb = (Int(alpha * 255) << 24) | (Int(red * 255) << 16)
        | (Int(green * 255) << 8) | Int(blue * 255)
      result(argb)
    }
  }
}
