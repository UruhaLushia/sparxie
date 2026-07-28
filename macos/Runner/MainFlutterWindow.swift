import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let systemColorsRegistrar = flutterViewController.registrar(
      forPlugin: "SystemColors"
    )
    let systemColorsChannel = FlutterMethodChannel(
      name: "zip.atri.sparxie/system_colors",
      binaryMessenger: systemColorsRegistrar.messenger
    )
    systemColorsChannel.setMethodCallHandler { call, result in
      guard call.method == "getAccentColor" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let color = NSColor.controlAccentColor.usingColorSpace(.deviceRGB) else {
        result(nil)
        return
      }
      let alpha = UInt64((color.alphaComponent * 255).rounded())
      let red = UInt64((color.redComponent * 255).rounded())
      let green = UInt64((color.greenComponent * 255).rounded())
      let blue = UInt64((color.blueComponent * 255).rounded())
      result(NSNumber(value: (alpha << 24) | (red << 16) | (green << 8) | blue))
    }

    super.awakeFromNib()
  }
}
