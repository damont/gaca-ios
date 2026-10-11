import Foundation
import Observation
import SwiftUI
import UIKit

/// App-wide state: which server this phone is paired with, and where a notification or link
/// asked us to go. Everything else is fetched per screen from the API.
@MainActor
@Observable
final class AppModel {
    /// `unpaired` carries a server address to prefill (a revoked phone keeps its server).
    enum AuthState: Equatable { case restoring, unpaired(server: String?), signedIn(UserResponse) }

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
    /// A `gaca://setup` link that arrived (tapped or scanned elsewhere) for the pairing screen.
    var pendingSetupLink: SetupLink?
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
        if ProcessInfo.processInfo.environment["GACA_UITEST_RESET"] != nil {
            api.tokens.set(nil)
            api.settings.apiBaseString = nil
            // Flow tests start already paired (the pairing screen has its own test).
            if let token = ProcessInfo.processInfo.environment["GACA_UITEST_TOKEN"] { api.tokens.set(token) }
        }
        #endif
        api.onUnauthorized = { [weak self] in
            // A 401 means the server revoked this phone: back to pairing, server prefilled.
            Task { @MainActor in self?.forgetCredential(keepServer: true) }
        }
    }

    convenience init() {
        self.init(api: APIClient(settings: SettingsStore(), tokens: TokenStore()))
    }

    func restore() async {
        guard api.tokens.token != nil, api.settings.apiBaseString != nil else {
            auth = .unpaired(server: api.settings.serverLabel)
            return
        }
        do {
            auth = .signedIn(try await api.me())
            await registerPushIfPossible()
        } catch APIError.unauthorized {
            auth = .unpaired(server: api.settings.serverLabel)
        } catch {
            // Server unreachable at launch: stay paired; screens retry on their own.
            auth = .signedIn(UserResponse(id: "", name: "", email: ""))
        }
    }

    /// Pair with the server at `address` using the code `gaca-api pair` printed. Nothing is
    /// saved until the server accepts the code, so a typo never leaves the app pointed at a
    /// dead address.
    func pair(address: String, code: String) async throws {
        guard let base = ServerAddress.normalize(address, allowHTTP: ServerAddress.allowsHTTP), let url = URL(string: base) else {
            throw PairingError.badAddress
        }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PairingError.noCode }
        do {
            _ = try await api.setupStatus(at: url)
        } catch {
            throw PairingError.unreachable(error.localizedDescription)
        }
        let paired = try await api.pair(at: url, code: trimmed, deviceName: UIDevice.current.name)
        api.settings.apiBaseString = base
        api.tokens.set(paired.accessToken)
        auth = .signedIn(try await api.me())
        tab = .chat
        await registerPushIfPossible()
    }

    /// Settings › Disconnect: tell the server to forget this phone, then forget it here.
    func disconnect() async {
        if let pushToken { try? await api.unregisterPush(token: pushToken) }
        try? await api.unpairThisDevice()
        forgetCredential(keepServer: false)
    }

    private func forgetCredential(keepServer: Bool) {
        let server = api.settings.serverLabel
        api.tokens.set(nil)
        if !keepServer { api.settings.apiBaseString = nil }
        auth = .unpaired(server: keepServer ? server : nil)
        crew = []
        inboxCount = 0
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
        // gaca://setup?url=…&code=… pairs (only while unpaired — a stray link must not
        // silently move a paired phone to another server).
        if let link = SetupLink(url.absoluteString) {
            if case .unpaired = auth { pendingSetupLink = link }
            return
        }
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

enum PairingError: LocalizedError {
    case badAddress, noCode, unreachable(String)

    var errorDescription: String? {
        switch self {
        case .badAddress: return "That doesn't look like a server address. Try something like gaca.example.com."
        case .noCode: return "Enter the pairing code your server printed."
        case .unreachable(let why): return "Couldn't reach a GACA server there. \(why)"
        }
    }
}
