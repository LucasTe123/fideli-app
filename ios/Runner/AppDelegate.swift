import Flutter
import PassKit
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
    let channel = FlutterMethodChannel(
      name: "app.fideli/wallet",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "addPass",
            let arguments = call.arguments as? [String: Any],
            let encoded = arguments["base64"] as? String,
            let data = Data(base64Encoded: encoded) else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        let pass = try PKPass(data: data)
        guard let controller = PKAddPassesViewController(pass: pass),
              let presenter = self?.topViewController() else {
          result(FlutterError(code: "PASSKIT_UNAVAILABLE", message: "No se pudo abrir Apple Wallet", details: nil))
          return
        }
        presenter.present(controller, animated: true)
        result(true)
      } catch {
        result(FlutterError(code: "INVALID_PASS", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    var controller = scene?.windows.first { $0.isKeyWindow }?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }
}
