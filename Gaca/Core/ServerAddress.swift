import Foundation

/// Turning what someone typed (or what a pairing link carried) into the API base the app talks
/// to — same rules as the Android app (gaca-android util/ServerAddress.kt).
enum ServerAddress {
    /// → the API base URL, always ending in `/api/`; nil if it can't be a server address. A bare
    /// `host.example.com` means https. Plain http only when `allowHTTP` (debug builds, a dev box).
    static func normalize(_ input: String, allowHTTP: Bool) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        let withScheme = text.contains("://") ? text : "https://" + text
        guard var parts = URLComponents(string: withScheme), let scheme = parts.scheme?.lowercased(),
              let host = parts.host, !host.isEmpty else { return nil }
        guard scheme == "https" || (allowHTTP && scheme == "http") else { return nil }
        guard parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { return nil }
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/api") { path.removeLast(4) }
        parts.scheme = scheme
        parts.path = path + "/api/"
        return parts.string
    }

    static var allowsHTTP: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

/// `gaca://setup?url=…&code=…` — what `gaca-api pair` prints and its QR code carries.
struct SetupLink: Equatable {
    let url: String?
    let code: String?

    /// The link in a scanned QR code or a tapped link; nil if it's anything else.
    init?(_ text: String?) {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let parts = URLComponents(string: text), parts.scheme == "gaca", parts.host == "setup" else { return nil }
        let items = parts.queryItems ?? []
        url = items.first { $0.name == "url" }?.value
        code = items.first { $0.name == "code" }?.value
    }
}
