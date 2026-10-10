import Foundation
import Observation
import SwiftUI

/// App-wide state: who's signed in, and where a notification or link asked us to go.
/// Everything else is fetched per screen from the API.
@MainActor
@Observable
final class AppModel {
    enum AuthState: Equatable { case restoring, signedOut, signedIn(UserResponse) }

    let api: APIClient
    var auth: AuthState = .restoring
    /// The selected tab.
    var tab: AppTab = .chat
    /// Pushed screens per tab (NavigationStack paths).
    var chatPath: [Route] = []
    var todayPath: [Route] = []
    var inboxPath: [Route] = []
    var artifactsPath: [Route] = []
    var skillsPath: [Route] = []
    /// The chat thread currently on screen, so a push for it can be skipped.
    var visibleSessionId: String?
    /// The device's APNs token once iOS hands it over; registered with the API on sign-in.
    var pushToken: String?
    /// The crew as last fetched from the API — read by every screen that colors things by
    /// crew member. Refreshed whenever a screen that shows crew loads.
    var crew: [CrewMember] = []
    var crewHost: String?
    var canCreateCrew = false

    func refreshCrew() async throws {
        let list = try await api.crew()
        apply(list)
    }

    func apply(_ list: CrewList) {
        crew = list.crew
        crewHost = list.host
        canCreateCrew = list.canCreate
    }

    func style(for crewName: String?) -> CrewStyle {
        guard let crewName, let member = crew.first(where: { $0.name == crewName }) else { return .neutral }
        return member.style
    }

    /// How many alerts need attention — the Inbox tab's badge.
    var inboxCount = 0

    func refreshInboxCount() async {
        if let alerts = try? await api.alerts(statuses: ["new", "completed"]) { inboxCount = alerts.count }
    }

    var defaultCrew: CrewMember? { crew.first(where: \.isDefault) ?? crew.first }

    init(api: APIClient) {
        self.api = api
        #if DEBUG
        if ProcessInfo.processInfo.environment["GACA_UITEST_RESET"] != nil { api.tokens.set(nil) }
        #endif
        api.onUnauthorized = { [weak self] in
            Task { @MainActor in self?.signOutLocally() }
        }
    }

    convenience init() {
        self.init(api: APIClient(settings: SettingsStore(), tokens: TokenStore()))
    }

    func restore() async {
        guard api.tokens.token != nil else { auth = .signedOut; return }
        do {
            auth = .signedIn(try await api.me())
            await registerPushIfPossible()
        } catch APIError.unauthorized {
            auth = .signedOut
        } catch {
            // Offline at launch: stay signed in with a placeholder so cached screens can retry.
            auth = .signedIn(UserResponse(id: "", name: "", email: ""))
        }
    }

    func signedIn(with token: String) async throws {
        api.tokens.set(token)
        auth = .signedIn(try await api.me())
        tab = .chat
        await registerPushIfPossible()
    }

    func signOut() async {
        if let pushToken { try? await api.unregisterPush(token: pushToken) }
        signOutLocally()
    }

    private func signOutLocally() {
        api.tokens.set(nil)
        auth = .signedOut
        chatPath = []; todayPath = []; inboxPath = []; artifactsPath = []; skillsPath = []
    }

    func didReceivePushToken(_ token: String) async {
        pushToken = token
        await registerPushIfPossible()
    }

    private func registerPushIfPossible() async {
        guard case .signedIn = auth, let pushToken else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        try? await api.registerPush(token: pushToken, environment: environment)
    }

    // MARK: Navigation from outside (notification taps, gaca:// links)

    func openAlert(_ id: String) {
        tab = .inbox
        inboxPath = [.alert(id)]
    }

    func openSession(_ id: String) {
        tab = .chat
        chatPath = [.thread(id)]
    }

    func openArtifact(_ id: String) {
        tab = .artifacts
        artifactsPath = [.artifact(id)]
    }

    func handle(url: URL) {
        // gaca://artifact/<id>, gaca://alert/<id>, gaca://session/<id>
        guard url.scheme == "gaca", let host = url.host() else { return }
        let id = url.pathComponents.dropFirst().first ?? ""
        guard !id.isEmpty else { return }
        switch host {
        case "artifact": openArtifact(id)
        case "alert": openAlert(id)
        case "session": openSession(id)
        default: break
        }
    }
}

enum AppTab: Hashable { case chat, today, inbox, artifacts, skills }

/// Every pushed screen in the app.
enum Route: Hashable {
    case thread(String, draft: String? = nil)
    case history
    case alert(String)
    case artifact(String)
    case crew(String)
    case settings
}
