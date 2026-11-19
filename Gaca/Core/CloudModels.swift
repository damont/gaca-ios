import Foundation

// Wire models for the heartbeat settings and everything GACA Cloud: the link, moving a page there,
// share checks, invite links, joining, publishing and the gallery. The app only ever talks to its own
// server (<base>/cloud/..., <base>/artifacts/{id}/...); the server holds the cloud token and forwards.

// MARK: Heartbeat

/// GET/PUT /heartbeat/settings — how the agent's periodic check-in behaves. Hours are 0-23 in the
/// phone's zone (`timezone`); quiet hours run from `quietStartHour` to `quietEndHour` and may cross
/// midnight. `pausedUntil` is nil when not paused.
struct HeartbeatSettings: Decodable, Sendable, Equatable {
    var enabled: Bool = true
    var pausedUntil: Date? = nil
    var timezone: String? = nil
    var quietStartHour: Int = 22
    var quietEndHour: Int = 7
    var maxAlertsPerDay: Int = 3
    var minMinutesBetweenAlerts: Int = 60
    var maxRunsPerDay: Int = 30

    enum CodingKeys: String, CodingKey {
        case enabled, pausedUntil, timezone, quietStartHour, quietEndHour, maxAlertsPerDay, minMinutesBetweenAlerts, maxRunsPerDay
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        pausedUntil = try c.decodeIfPresent(Date.self, forKey: .pausedUntil)
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone)
        quietStartHour = try c.decodeIfPresent(Int.self, forKey: .quietStartHour) ?? 22
        quietEndHour = try c.decodeIfPresent(Int.self, forKey: .quietEndHour) ?? 7
        maxAlertsPerDay = try c.decodeIfPresent(Int.self, forKey: .maxAlertsPerDay) ?? 3
        minMinutesBetweenAlerts = try c.decodeIfPresent(Int.self, forKey: .minMinutesBetweenAlerts) ?? 60
        maxRunsPerDay = try c.decodeIfPresent(Int.self, forKey: .maxRunsPerDay) ?? 30
    }

    func isPaused(now: Date = .now) -> Bool { pausedUntil.map { $0 > now } ?? false }

    /// The settings as they will stand once `change` is saved: shown at once, then confirmed (or undone).
    func applying(_ change: HeartbeatChange) -> HeartbeatSettings {
        var s = self
        if let v = change.enabled { s.enabled = v }
        if change.clearPause { s.pausedUntil = nil } else if let v = change.pausedUntil { s.pausedUntil = v }
        if let v = change.quietStartHour { s.quietStartHour = v }
        if let v = change.quietEndHour { s.quietEndHour = v }
        if let v = change.maxAlertsPerDay { s.maxAlertsPerDay = v }
        if let v = change.minMinutesBetweenAlerts { s.minMinutesBetweenAlerts = v }
        return s
    }
}

/// One edit, however small: only what is set is sent.
struct HeartbeatChange: Sendable, Equatable {
    var enabled: Bool? = nil
    var pausedUntil: Date? = nil
    var clearPause = false
    var quietStartHour: Int? = nil
    var quietEndHour: Int? = nil
    var maxAlertsPerDay: Int? = nil
    var minMinutesBetweenAlerts: Int? = nil

    /// The PUT body. The phone's zone goes with every save so quiet hours mean the phone's local hours;
    /// a cleared pause is an explicit null (leaving the field out would keep the pause).
    func body(zone: TimeZone = .current) throws -> Data {
        var obj: [String: Any] = ["timezone": zone.identifier]
        if let enabled { obj["enabled"] = enabled }
        if clearPause { obj["paused_until"] = NSNull() } else if let pausedUntil { obj["paused_until"] = WireDate.format(pausedUntil) }
        if let quietStartHour { obj["quiet_start_hour"] = quietStartHour }
        if let quietEndHour { obj["quiet_end_hour"] = quietEndHour }
        if let maxAlertsPerDay { obj["max_alerts_per_day"] = maxAlertsPerDay }
        if let minMinutesBetweenAlerts { obj["min_minutes_between_alerts"] = minMinutesBetweenAlerts }
        return try JSONSerialization.data(withJSONObject: obj)
    }
}

// MARK: Cloud link

/// GET /cloud/link. `state`: none | pending | linked | invalid (the cloud stopped accepting the link).
struct CloudLinkStatus: Decodable, Sendable, Equatable {
    var linked: Bool? = nil
    var state: String? = nil
    /// The cloud account's display name.
    var handle: String? = nil
    var accountId: String? = nil
    var linkedAt: Date? = nil
    /// `manage` (can move, share, publish) or `read` (can only list and read).
    var scope: String? = nil
    /// The owner's switch: may their agents (Hermes) use the cloud? Off until switched on here.
    var agentAccess: Bool? = nil
    /// False when the server has no cloud address at all. Older servers omit it (= true).
    var configured: Bool? = nil
    /// A link in progress (only while the code is valid), so the same code can be shown again.
    var userCode: String? = nil
    var verificationUri: String? = nil
    var expiresAt: Date? = nil
    var interval: Int? = nil

    enum Kind: Sendable { case notLinked, pending, linked, invalid }

    var kind: Kind {
        switch state {
        case "linked": return .linked
        case "pending": return .pending
        case "invalid": return .invalid
        default: return .notLinked
        }
    }
    var isLinked: Bool { kind == .linked }
    var isConfigured: Bool { configured ?? true }
    var agentsMayUse: Bool { agentAccess ?? false }

    /// The attempt the server still remembers, or nil when any part is missing (an expired code comes back as nulls).
    var pendingAttempt: CloudLinkAttempt? {
        guard let userCode, let verificationUri, let expiresAt else { return nil }
        return CloudLinkAttempt(userCode: userCode, verificationUri: verificationUri, expiresAt: expiresAt, intervalSeconds: interval ?? 5)
    }
}

/// A link attempt in progress: the person checks `userCode` on the page at `verificationUri`.
struct CloudLinkAttempt: Sendable, Equatable {
    let userCode: String
    let verificationUri: String
    let expiresAt: Date
    let intervalSeconds: Int
}

/// POST /cloud/link/start. Always `manage`: the app moves, shares and publishes, each only after the person confirms.
struct CloudLinkStart: Encodable { let scope: String }

struct CloudLinkStarted: Decodable, Sendable {
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int

    func attempt(now: Date = .now) -> CloudLinkAttempt {
        CloudLinkAttempt(userCode: userCode, verificationUri: verificationUri,
                         expiresAt: now.addingTimeInterval(TimeInterval(expiresIn)), intervalSeconds: interval)
    }
}

/// POST /cloud/link/poll: pending | linked | expired | denied.
struct CloudLinkPoll: Decodable, Sendable {
    let status: String
    var interval: Int? = nil
    var retryIn: Int? = nil
    var handle: String? = nil
    var accountId: String? = nil
    var scope: String? = nil
    var linkedAt: Date? = nil

    /// Seconds before the next poll: `retry_in` (called too soon) wins over `interval`; never less than 1.
    func waitSeconds(fallback: Int) -> Int { max(1, retryIn ?? interval ?? fallback) }
}

struct CloudAgentAccess: Encodable { let enabled: Bool }

/// DELETE /cloud/link.
struct CloudUnlinked: Decodable, Sendable {
    var unlinked: Bool? = nil
    var cloudRevoked: Bool? = nil
    var message: String? = nil
}

/// Why an unlink was held back (409 `cloud_artifacts_present`): some pages live only in the cloud.
struct UnlinkBlock: Sendable, Equatable {
    let owned: Int
    let shared: Int
    let inProgress: Int
}

enum UnlinkResult: Sendable {
    /// `message` is the server's own words, e.g. that the cloud could not confirm revoking the link.
    case done(String)
    case blocked(UnlinkBlock)
}

// MARK: Moving a page to the cloud

struct NotCarried: Decodable, Sendable {
    var versionsDropped: Int? = nil
    var handledEventsDropped: Int? = nil
    var crew: String? = nil
    var chatAlertLinks: JSONValue? = nil
    var docVersionsReset: Int? = nil
    var lastOpened: Bool? = nil
    var anything: Bool? = nil

    /// What the cloud will not keep, in plain words. Empty when nothing is lost.
    var lines: [String] {
        var out: [String] = []
        if let n = versionsDropped, n > 0 { out.append("\(plural(n, "older version")) of the page (the cloud keeps the latest 5)") }
        if let n = handledEventsDropped, n > 0 { out.append("\(plural(n, "event")) already handled") }
        if crew != nil { out.append("Which crew member made it") }
        if let links = chatAlertLinks, links != .null { out.append("Its link to the chat or alert it came from") }
        if let n = docVersionsReset, n > 0 { out.append("The edit history of \(plural(n, "document")) (they start again at version 1)") }
        if lastOpened == true { out.append("When you last opened it") }
        return out
    }
}

struct MoveSize: Decodable, Sendable {
    var bytes: Int? = nil
    var limitBytes: Int? = nil
}

/// GET /artifacts/{id}/move-preview: what a move would do. Nothing is sent anywhere.
struct MovePreview: Decodable, Sendable {
    var canMove: Bool? = nil
    var blockedBecause: String? = nil
    var problems: [JSONValue]? = nil
    var size: MoveSize? = nil
    var notCarried: NotCarried? = nil
    var requiresAcknowledgement: Bool? = nil
    var backupDays: Int? = nil

    var movable: Bool { canMove ?? false }
    var lostLines: [String] { notCarried?.lines ?? [] }
    var needsAck: Bool { requiresAcknowledgement ?? false }
    var keepDays: Int { backupDays ?? 30 }

    /// Plain words for why not, when it can't be moved.
    var blockedText: String? {
        guard !movable else { return nil }
        let base: String
        switch blockedBecause {
        case "artifact_archived": base = "Archived pages can't be moved. Unarchive it first."
        case "id_not_portable": base = "This page's id can't be kept in the cloud, so it can't be moved."
        case nil: base = "This page can't be moved to the cloud."
        default: base = "This page can't be moved to the cloud yet."
        }
        var seen = Set<String>()
        let items = (problems ?? []).compactMap { p -> String? in
            switch p {
            case .string(let s): return s
            case .object(let o): if case .string(let s)? = o["item"] { return s } else { return nil }
            default: return nil
            }
        }.filter { seen.insert($0).inserted }
        return items.isEmpty ? base : base + " " + items.joined(separator: "; ") + "."
    }
}

struct MoveRequest: Encodable { let acknowledgeNotCarried: Bool }
struct MoveResult: Decodable, Sendable {
    let artifact: Artifact
    var verified: Bool? = nil
}

// MARK: Checks

struct Finding: Decodable, Sendable, Hashable {
    var rule: String? = nil
    var severity: String? = nil
    var message: String? = nil
    var location: String? = nil

    enum Level: Int, Comparable, Sendable {
        case block, warn, info
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }
    var level: Level {
        switch severity {
        case "block": return .block
        case "warn": return .warn
        default: return .info
        }
    }
    var text: String { message ?? "" }
}

/// POST /cloud/gacabits/{id}/validations (share) and POST /artifacts/{id}/publish-check (publish).
struct ValidationReport: Decodable, Sendable {
    var status: String? = nil
    var findings: [Finding]? = nil
    /// Publish checks only: the hash of exactly what would be published, and that content itself.
    var contentHash: String? = nil
    var preview: JSONValue? = nil

    var sortedFindings: [Finding] { (findings ?? []).sorted { $0.level < $1.level } }
    var blocked: Bool { status == "blocked" || (findings ?? []).contains { $0.level == .block } }
    var warnings: Int { (findings ?? []).filter { $0.level == .warn }.count }
}

struct ValidationRun: Encodable { let subject: String }

// MARK: Invites

/// The three modes of an invite link. The role is fixed when the link is made; the owner can't be granted.
enum ShareRole: String, CaseIterable, Identifiable, Sendable {
    case viewer, editor, maintainer

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var canDo: String {
        switch self {
        case .viewer: return "Can open the page and read its data. Cannot change anything."
        case .editor: return "Can read and change the page's data (checked against its shapes). Cannot change the page itself."
        case .maintainer: return "Can change the data and edit the page itself. Every edit is versioned and checked, and you can undo it."
        }
    }
    var youCan: String {
        switch self {
        case .viewer: return "You can open the page and read its data. You can't change anything."
        case .editor: return "You can read and change the page's data. You can't change the page itself."
        case .maintainer: return "You can change the data and edit the page itself. Every edit is versioned and checked, and the owner can undo it."
        }
    }
    init?(wire: String) { self.init(rawValue: wire.lowercased()) }
}

/// What the owner picked for the link. Defaults are the safest: a viewer, for a week, for one person.
struct ShareOptions: Sendable, Equatable {
    static let expiryChoices = [1, 7, 30]
    static let useChoices = [1, 5, 10, 25]

    var role: ShareRole = .viewer
    var expiryDays = 7
    var maxUses = 1

    /// The sentence the owner confirms. A link is a secret: whoever holds it can join.
    var summary: String {
        "Anyone who has the link can join as \(role.label.lowercased()). It works for \(plural(expiryDays, "day")) and for up to \(plural(maxUses, "person", "people"))."
    }
}

struct InviteCreate: Encodable {
    let role: String
    let expiresInDays: Int
    let maxUses: Int
}

/// The answer to creating an invite link. `url` is the secret link and comes back only this once.
struct InviteLink: Decodable, Sendable {
    var id: String? = nil
    var role: String? = nil
    var url: String? = nil
    var expiresAt: Date? = nil
    var maxUses: Int? = nil
}

struct InviteToken: Encodable { let token: String }

struct AccountRef: Decodable, Sendable, Hashable {
    var id: String? = nil
    var handle: String? = nil
    var displayName: String? = nil

    /// What to call them: display name, else handle, else nil.
    var name: String? {
        if let d = displayName, !d.isEmpty { return d }
        if let h = handle, !h.isEmpty { return h }
        return nil
    }
}

/// What an invite link would add. The cloud sends no page data here, and no id.
struct InvitePreview: Decodable, Sendable {
    var gacabitTitle: String? = nil
    var role: String? = nil
    var invitedBy: AccountRef? = nil
    var alreadyMember: Bool? = nil

    var title: String { (gacabitTitle?.isEmpty == false ? gacabitTitle : nil) ?? "Untitled page" }
    var roleWord: String { role ?? "viewer" }
    var roleLabel: String { ShareRole(wire: roleWord)?.label ?? roleWord.capitalized }
    /// What the role allows. An access level this version does not know is described as nothing, not guessed at.
    var youCan: String {
        ShareRole(wire: roleWord)?.youCan ?? "This app doesn't know this kind of access yet, so it can't tell you what it allows."
    }
    var isMember: Bool { alreadyMember ?? false }
}

/// The page you were added to (only the bits the app needs; the server answers with a whole list row).
struct Redeemed: Decodable, Sendable {
    var id: String? = nil
    var title: String? = nil
}

// MARK: Publish

/// Where a published page shows up. Both kinds are public to whoever can reach them.
enum PublishVisibility: String, CaseIterable, Identifiable, Sendable {
    case listed, unlisted
    var id: String { rawValue }
    var label: String { self == .listed ? "In the gallery" : "Not listed" }
    var explain: String {
        self == .listed
            ? "Anyone can find it in the gallery and add their own copy."
            : "Kept out of the gallery list, but anyone who is given its address can see it and add a copy."
    }
}

/// What the owner typed. Blank text is sent as nothing, in the check and the publish alike (the hash covers it).
struct PublishListing: Sendable, Equatable {
    var title: String
    var description = ""
    var visibility: PublishVisibility = .listed

    var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var cleanDescription: String? {
        let d = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return d.isEmpty ? nil : d
    }
    var isValid: Bool { !cleanTitle.isEmpty && cleanTitle.count <= 120 && (cleanDescription?.count ?? 0) <= 500 }

    /// The sentence the owner confirms.
    var summary: String {
        "“\(cleanTitle)” will be public. \(visibility.explain) Only the page and its shapes are published, never its data. People who add a copy keep it."
    }
}

/// POST /artifacts/{id}/publish-check — works for a private page and a cloud page alike.
struct PublishCheck: Encodable {
    let title: String
    let description: String?
}

/// POST /artifacts/{id}/publish — the same listing text as the check (the hash covers it), plus the confirmation.
struct PublishRequest: Encodable {
    let title: String
    let description: String?
    let visibility: String
    let confirmedPreview: Bool
    let previewHash: String
}

/// What would go out, in plain words. Read from the cloud's own preview, never from the page here.
struct PublishPreview: Sendable {
    let title: String
    let description: String?
    let license: String?
    let tags: [String]
    let pageBytes: Int
    let shapes: Int

    var pageSizeText: String { pageBytes < 1024 ? "\(pageBytes) bytes" : "\((pageBytes + 512) / 1024) KB" }
}

/// The cloud's publish check: findings, what would go out, and the hash that ties a publish to this exact preview.
struct PublishReview: Sendable {
    let report: ValidationReport
    let hash: String?
    let preview: PublishPreview

    /// No hash means the cloud did not give us something to confirm, so nothing can be published.
    var canPublish: Bool { !report.blocked && !(hash ?? "").isEmpty }

    init(report: ValidationReport, fallbackTitle: String) {
        self.report = report
        hash = report.contentHash.flatMap { $0.isEmpty ? nil : $0 }
        func text(_ v: JSONValue?) -> String? { if case .string(let s)? = v, !s.isEmpty { return s } else { return nil } }
        var listing: [String: JSONValue] = [:]
        var html: String? = nil
        var shapes = 0
        if case .object(let p)? = report.preview {
            if case .object(let l)? = p["listing"] { listing = l }
            html = text(p["html"])
            if case .object(let s)? = p["schemas"] { shapes = s.count }
        }
        var tags: [String] = []
        if case .array(let a)? = listing["tags"] { tags = a.compactMap { if case .string(let s) = $0 { return s } else { return nil } } }
        preview = PublishPreview(title: text(listing["title"]) ?? fallbackTitle, description: text(listing["description"]),
                                 license: text(listing["license"]), tags: tags, pageBytes: html?.utf8.count ?? 0, shapes: shapes)
    }
}

// MARK: Bring home

struct BringHomeRequest: Encodable { let acknowledgeMembers: Bool }

struct BringHomeResult: Decodable, Sendable {
    let artifact: Artifact
    var confirmed: Bool? = nil
    var undoUntil: String? = nil
    var warning: String? = nil
    var membersLostAccess: Int? = nil
}

struct UndoResult: Decodable, Sendable {
    var home: String? = nil
    var undone: Bool? = nil
}

// MARK: Gallery

/// A public template other people published (GET /cloud/templates, read through the server).
struct Template: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    var description: String? = nil
    var tags: [String]? = nil
    var category: String? = nil
    var author: AccountRef? = nil
    var status: String? = nil
    var downloads: Int? = nil

    var isListed: Bool { (status ?? "listed") == "listed" }
    var tagList: [String] { tags ?? [] }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        return title.localizedCaseInsensitiveContains(q)
            || (description ?? "").localizedCaseInsensitiveContains(q)
            || tagList.contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

struct TemplateList: Decodable, Sendable {
    var templates: [Template]? = nil
    var nextCursor: String? = nil
}

// MARK: Wording helpers

func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String {
    n == 1 ? "1 \(one)" : "\(n) \(many ?? one + "s")"
}
