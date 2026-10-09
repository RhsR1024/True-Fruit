import Flutter
import UIKit
import DuanjuCore
import CFNetwork

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var originalPlaybackBrightness: CGFloat?

  private func resetPlaybackBrightness() {
    guard let brightness = originalPlaybackBrightness else { return }
    UIScreen.main.brightness = brightness
    originalPlaybackBrightness = nil
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    resetPlaybackBrightness()
    super.applicationWillResignActive(application)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    ZgjEnsureCoreLinked()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceSettings") {
      let channel = FlutterMethodChannel(name: "duanju/device", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "device_unavailable", message: "设备服务已关闭", details: nil))
          return
        }
        switch call.method {
        case "getPlaybackBrightness":
          result(Double(UIScreen.main.brightness))
          return
        case "setPlaybackBrightness":
          guard let args = call.arguments as? [String: Any],
                let value = args["value"] as? NSNumber, value.doubleValue.isFinite else {
            result(FlutterError(code: "invalid_brightness", message: "亮度值无效", details: nil))
            return
          }
          if self.originalPlaybackBrightness == nil {
            self.originalPlaybackBrightness = UIScreen.main.brightness
          }
          UIScreen.main.brightness = CGFloat(min(1.0, max(0.01, value.doubleValue)))
          result(nil)
          return
        case "resetPlaybackBrightness":
          self.resetPlaybackBrightness()
          result(nil)
          return
        case "systemProxy":
          break
        default:
          result(FlutterMethodNotImplemented)
          return
        }
        let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] ?? [:]
        func address(_ prefix: String) -> String {
          guard (settings["\(prefix)Enable"] as? NSNumber)?.boolValue == true,
                let host = settings["\(prefix)Proxy"] as? String,
                let port = settings["\(prefix)Port"] as? NSNumber,
                !host.isEmpty, port.intValue > 0 else { return "" }
          let name = host.contains(":") ? "[\(host)]" : host
          return "http://\(name):\(port.intValue)"
        }
        let http = address("HTTP")
        let https = address("HTTPS")
        result(["http": http, "https": https.isEmpty ? http : https,
                "bypass": settings["ExceptionsList"] as? [String] ?? [],
                "pac": (settings["ProxyAutoConfigEnable"] as? NSNumber)?.boolValue == true])
      }
    }
  }
}
