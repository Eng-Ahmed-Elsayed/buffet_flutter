import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// The background time asked for as the app leaves the screen.
  private var orderWatchTask: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications' iOS setup: without a notification-center
    // delegate, iOS shows nothing for an app in the foreground and a tap never
    // reaches Dart. The local order alert fires only in the foreground, and on
    // iOS it is the only alert there is (no push). Set before super, so the
    // plugins registering during launch chain to it.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate

    // iOS suspends an app within seconds of it leaving the screen, and with
    // no push the Ready chime depends on Dart still looking at the orders
    // (BackgroundOrderWatch). Asking for background time buys about half a
    // minute; iOS decides, and ends it by calling the expiry handler.
    // Notifications rather than delegate overrides, so this holds whether the
    // lifecycle arrives through the app or through a scene.
    let centre = NotificationCenter.default
    centre.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.beginOrderWatch() }
    centre.addObserver(
      forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.endOrderWatch() }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func beginOrderWatch() {
    endOrderWatch()
    orderWatchTask = UIApplication.shared.beginBackgroundTask(withName: "order-watch") {
      [weak self] in self?.endOrderWatch()
    }
  }

  private func endOrderWatch() {
    guard orderWatchTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(orderWatchTask)
    orderWatchTask = .invalid
  }
}
