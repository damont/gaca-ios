import Foundation
import Security

/// Device-local configuration: which server this phone is paired with. (Everything about the
/// owner's data lives in gaca-api; this is only "where is it".) The app ships without one —
/// pairing sets it.
final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "apiBase"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The paired server's API base (ends in `/api/`), or nil before pairing.
    var apiBaseString: String? {
        get {
            #if DEBUG
            // UI tests point the app at a throwaway local API.
            if let override = ProcessInfo.processInfo.environment["GACA_API_BASE"] { return ServerAddress.normalize(override, allowHTTP: true) }
            #endif
            return defaults.string(forKey: key)
        }
        set { defaults.set(newValue, forKey: key) }
    }

    /// Where requests go. Before pairing nothing calls the API, so a placeholder that can't
    /// resolve is safer than a crash.
    var apiBase: URL { apiBaseString.flatMap(URL.init(string:)) ?? URL(string: "https://unpaired.invalid/api/")! }

    /// The paired server as a person would say it: "gaca.example.com".
    var serverLabel: String? {
        guard let s = apiBaseString, let url = URL(string: s), let host = url.host() else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return host + port
    }
}

/// The bearer token, kept in the Keychain.
final class TokenStore: @unchecked Sendable {
    private let service: String
    private let account = "access_token"
    private let lock = NSLock()
    private var cached: String?
    private var loaded = false

    init(service: String = "dev.monts.gaca.auth") {
        self.service = service
    }

    var token: String? {
        lock.lock(); defer { lock.unlock() }
        if !loaded {
            cached = read()
            loaded = true
        }
        return cached
    }

    func set(_ token: String?) {
        lock.lock(); defer { lock.unlock() }
        cached = token
        loaded = true
        delete()
        if let token { write(token) }
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ token: String) {
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    private func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
