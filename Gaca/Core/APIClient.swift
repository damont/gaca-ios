import Foundation

/// What went wrong talking to gaca-api, in words a screen can show as-is.
enum APIError: LocalizedError, Equatable {
    case unauthorized
    case http(status: Int, detail: String?)
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Your session expired — sign in again."
        case .http(_, let detail?): return detail
        case .http(let status, nil): return "The server answered \(status)."
        case .network(let message): return message
        case .decoding: return "The server sent something this app couldn't read."
        }
    }
}

/// The one HTTP client for gaca-api. Every path is relative to the base URL, which always
/// ends in `/api/` — same convention as the Android app's Retrofit interface.
final class APIClient: @unchecked Sendable {
    let settings: SettingsStore
    let tokens: TokenStore
    private let session: URLSession
    /// Called when any request comes back 401, so the app can drop to the sign-in screen.
    var onUnauthorized: (@Sendable () -> Void)?

    init(settings: SettingsStore, tokens: TokenStore, session: URLSession = .shared) {
        self.settings = settings
        self.tokens = tokens
        self.session = session
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let raw = try c.decode(String.self)
            if let date = WireDate.parse(raw) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unreadable date \(raw)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(WireDate.format(date))
        }
        return e
    }()

    func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: settings.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, contentType: String = "application/json") -> URLRequest {
        var req = URLRequest(url: url(path, query: query))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = tokens.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = body
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [], json: (any Encodable)? = nil, as: T.Type = T.self) async throws -> T {
        let body = try json.map { try Self.encoder.encode($0) }
        let data = try await perform(request(method, path, query: query, body: body))
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    func sendVoid(_ method: String, _ path: String, json: (any Encodable)? = nil) async throws {
        let body = try json.map { try Self.encoder.encode($0) }
        _ = try await perform(request(method, path, body: body))
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as: T.Type = T.self) async throws -> T {
        try await send("GET", path, query: query, as: T.self)
    }

    func post<T: Decodable>(_ path: String, _ json: (any Encodable)? = nil, as: T.Type = T.self) async throws -> T {
        try await send("POST", path, json: json ?? EmptyBody(), as: T.self)
    }

    /// A call to a server this phone isn't paired with yet (no token, an explicit address).
    func unauthenticated<T: Decodable>(_ method: String, _ url: URL, body: Data?) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        req.timeoutInterval = 20
        let data = try await perform(req)
        do { return try Self.decoder.decode(T.self, from: data) } catch { throw APIError.decoding(String(describing: error)) }
    }

    func data(for request: URLRequest) async throws -> Data {
        try await perform(request)
    }

    private func perform(_ req: URLRequest) async throws -> Data {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.network("Couldn't reach the server. Check your connection.")
        }
        guard let http = response as? HTTPURLResponse else { return data }
        if http.statusCode == 401, req.value(forHTTPHeaderField: "Authorization") != nil {
            onUnauthorized?()
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, detail: Self.detail(from: data))
        }
        return data
    }

    /// FastAPI errors carry `{"detail": "..."}` (or a list of validation errors).
    static func detail(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let s = obj["detail"] as? String { return s }
        if let list = obj["detail"] as? [[String: Any]], let first = list.first?["msg"] as? String { return first }
        return nil
    }
}

struct EmptyBody: Codable {}

/// gaca-api writes Python `isoformat()` timestamps: with or without fractional seconds,
/// with an explicit offset (usually +00:00) or none (treated as UTC).
enum WireDate {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        var s = raw
        // No zone designator → UTC.
        let hasZone = s.hasSuffix("Z") || s.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil
        if !hasZone { s += "Z" }
        // Python can emit microseconds (6 digits); ISO8601DateFormatter wants ≤3.
        if let dot = s.firstIndex(of: "."), let end = s[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
            let digits = s[s.index(after: dot)..<end]
            if digits.count > 3 { s.replaceSubrange(s.index(after: dot)..<end, with: digits.prefix(3)) }
        }
        return fractional.date(from: s) ?? plain.date(from: s)
    }

    static func format(_ date: Date) -> String { fractional.string(from: date) }
}
