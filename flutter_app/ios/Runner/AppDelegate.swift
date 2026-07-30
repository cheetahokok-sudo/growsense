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

    // Height Scan (AR height measurement) — platform view + availability probe.
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HeightScan")!
    registrar.register(
      HeightScanViewFactory(messenger: registrar.messenger()),
      withId: "growsense/height_scan_view"
    )
    HeightScanViewFactory.registerAvailabilityChannel(messenger: registrar.messenger())
  }
}
