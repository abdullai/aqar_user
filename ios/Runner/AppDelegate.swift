import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// يُصفَّر عدّاد أيقونة التطبيق عند الدخول/الخروج (يطابق سلوك المطلوب في الواجهة).
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    application.applicationIconBadgeNumber = 0
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    application.applicationIconBadgeNumber = 0
    super.applicationWillResignActive(application)
  }
}
