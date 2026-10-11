import SwiftUI
import UIKit
import UserNotifications

@main
struct GacaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    init() {
        let slate = UIColor(Palette.accent)
        UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: slate]
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onAppear { delegate.model = model }
                .onOpenURL { url in model.handle(url: url) }
        }
    }
}

/// Push plumbing: asks for permission, hands the APNs token to the app model (which
/// registers it with gaca-api), and routes notification taps to the right screen.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor var model: AppModel? {
        didSet { if let pending = pendingToken { Task { await model?.didReceivePushToken(pending) } } }
    }
    @MainActor private var pendingToken: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        #if DEBUG
        if ProcessInfo.processInfo.environment["GACA_UITEST_RESET"] != nil { return true }
        #endif
        // Builds signed without the push entitlement (e.g. a free Apple ID) can't get a token.
        guard Bundle.main.object(forInfoDictionaryKey: "GacaPushEnabled") as? String == "YES" else { return true }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            if let model { await model.didReceivePushToken(token) } else { pendingToken = token }
        }
    }

    // A push for the chat that's already on screen is skipped; everything else shows.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let sessionId = notification.request.content.userInfo["session_id"] as? String
        let reply = UncheckedSendable(completionHandler)
        Task { @MainActor in
            if let sessionId, sessionId == self.model?.visibleSessionId {
                reply.value([])
            } else {
                reply.value([.banner, .sound, .list])
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let alertId = info["alert_id"] as? String
        let sessionId = info["session_id"] as? String
        let done = UncheckedSendable(completionHandler)
        Task { @MainActor in
            if let alertId { self.model?.openAlert(alertId) } else if let sessionId { self.model?.openSession(sessionId) }
            done.value()
        }
    }
}

/// Carries a UIKit completion handler across to the main actor.
struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
