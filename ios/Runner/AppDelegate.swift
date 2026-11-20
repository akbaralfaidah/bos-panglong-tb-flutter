import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let ownerNotifChannelName = "com.bospanglong.pos/owner_notifications"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let center = UNUserNotificationCenter.current()
    center.delegate = self

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: ownerNotifChannelName,
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(false)
          return
        }
        switch call.method {
        case "requestPermission":
          self.requestNotificationPermission(result: result)
        case "showTransactionNotification":
          guard let args = call.arguments as? [String: Any] else {
            result(false)
            return
          }
          let id = (args["id"] as? Int) ?? Int(Date().timeIntervalSince1970)
          let title = (args["title"] as? String) ?? "Transaksi Baru"
          let body = (args["body"] as? String) ?? ""
          self.showTransactionNotification(id: id, title: title, body: body, result: result)
        case "cancelAll":
          let notifCenter = UNUserNotificationCenter.current()
          notifCenter.removeAllDeliveredNotifications()
          notifCenter.removeAllPendingNotificationRequests()
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func requestNotificationPermission(result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      DispatchQueue.main.async {
        result(granted)
      }
    }
  }

  private func showTransactionNotification(
    id: Int,
    title: String,
    body: String,
    result: @escaping FlutterResult
  ) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: "owner_tx_\(id)",
      content: content,
      trigger: nil
    )

    UNUserNotificationCenter.current().add(request) { error in
      DispatchQueue.main.async {
        result(error == nil)
      }
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }
}
