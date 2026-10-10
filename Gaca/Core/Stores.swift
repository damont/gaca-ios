import Foundation
import Security

/// Device-local configuration: which API this app talks to. (Everything about the user's
/// data lives in gaca-api; this is only "where is it".)
final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "apiBase"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static var bundledDefault: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "GacaDefaultAPIBase") as? String ?? ""
        return raw.isEmpty ? "https://goodandcheapagent.com/api/" : raw
    }

    var apiBaseString: String {
        get { defaults.string(forKey: key) ?? Self.bundledDefault }
        set { defaults.set(Self.normalize(newValue), forKey: key) }
    }

    var apiBase: URL { URL(string: apiBaseString) ?? URL(string: Self.bundledDefault)! }

    /// Always ends in a single slash, so relative paths append cleanly.
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s + "/"
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
