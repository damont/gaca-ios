import Foundation

// Small derived rules ported from gaca-android (ArtifactSharing.kt, Heartbeat.kt, CrewLabel.kt,
// InviteLink.kt, Home.kt). They only decide what to offer or how to word it; the server enforces.

// MARK: Artifacts: where a page lives and who has it

enum ArtifactRole: String, Sendable {
    case owner, maintainer, editor, viewer
    var label: String { rawValue.capitalized }
}

/// The chips on the Artifacts tab. Mine and Shared with me split the list; Gallery is a different list altogether.
enum ArtifactFilter: String, CaseIterable, Identifiable, Sendable {
    case mine = "Mine", shared = "Shared with me", gallery = "Gallery"
    var id: String { rawValue }
}

/// The badge on a row. A page can carry more than one (shared and published).
enum ArtifactBadge: String, Sendable {
    case `private` = "Private", shared = "Shared", published = "Published"
}

extension Artifact {
    var isCloud: Bool { home == "cloud" }
    /// An unknown word is treated as the least a person can have, so nothing is offered that the cloud may refuse.
    var accessRole: ArtifactRole { ArtifactRole(rawValue: (role ?? "owner").lowercased()) ?? .viewer }
    var people: Int { memberCount ?? 1 }
    var isMoving: Bool { moving ?? false }
    var isArchived: Bool { archived ?? false }
    var publishedId: String? { publishedTemplateId.flatMap { $0.isEmpty ? nil : $0 } }
    var owner: String? { sharedBy.flatMap { $0.isEmpty ? nil : $0 } }

    var isMine: Bool { accessRole == .owner }
    var isSharedWithMe: Bool { !isMine }
    /// Archive and delete belong to the owner: the cloud refuses them to everybody else.
    var canManage: Bool { isMine }
    /// Only the owner shares, and not while it is archived or in the middle of a move.
    var canShare: Bool {
        isMine && !isArchived && !isMoving && !["moving", "read_only", "brought_home"].contains(cloudStatus ?? "")
    }
    /// Publishing works for a private page and a cloud page alike (POST /artifacts/{id}/publish).
    var canPublish: Bool { canShare }
    var canBringHome: Bool { canShare && isCloud }
    /// A page someone shared with you, which you can walk away from.
    var canLeave: Bool { isSharedWithMe && isCloud && !isMoving }

    func matches(_ filter: ArtifactFilter) -> Bool {
        switch filter {
        case .mine: return isMine
        case .shared: return isSharedWithMe
        case .gallery: return false
        }
    }

    /// Private (only you), Shared (someone else is in it, or it is theirs), Published (in the gallery).
    /// A page in the cloud with nobody else in it is still private.
    var badges: [ArtifactBadge] {
        var out: [ArtifactBadge] = []
        if isCloud && (people > 1 || !isMine) { out.append(.shared) }
        if publishedId != nil { out.append(.published) }
        if out.isEmpty { out.append(.private) }
        return out
    }

    /// "Shared by ada", for somebody else's page.
    var sharedByLine: String? { isSharedWithMe ? "Shared by \(owner ?? "someone")" : nil }
    /// For your own shared page: how many people are in it, you included.
    var peopleLine: String? { isMine && isCloud && people > 1 ? "\(people) people" : nil }

    /// A short status for pages in the middle of a transfer, else nil.
    var transferLine: String? {
        if isMoving || cloudStatus == "moving" { return "Moving to the cloud…" }
        switch cloudStatus {
        case "move_failed": return "Last move did not finish"
        case "bring_home_unconfirmed": return "Brought home, syncing with the cloud"
        case "read_only": return "Read-only"
        case "brought_home": return "Brought home"
        default: return nil
        }
    }

    /// Other people share the page, so bringing it home needs the person's tick about them.
    var needsMemberAck: Bool { people > 1 }

    /// What the person is told before a bring home. Other members lose access, so that is said first.
    var bringHomeWarning: String {
        let others = max(0, people - 1)
        let base = "The page and its data move back to your server and leave the cloud (the cloud keeps its copy for a few days so you can undo)."
        guard others > 0 else { return base }
        return "\(others == 1 ? "1 other person" : "\(others) other people") will lose access to “\(title)”. \(base)"
    }
}

// MARK: Crew

/// What to call a crew member next to old chats and alerts: a removed one is marked, never shown as current.
func crewLabel(_ name: String, removed: Bool) -> String { removed ? "\(name) (removed)" : name }

/// The words on the "remove a crew member" confirmation. When gaca-api can reach the Hermes box
/// (`deletesProfile`, from `CrewList.canCreate`) removing really deletes the profile there.
struct RemoveCrewPrompt { let title: String; let body: String; let confirm: String }

func removeCrewPrompt(_ name: String, deletesProfile: Bool) -> RemoveCrewPrompt {
    deletesProfile
        ? RemoveCrewPrompt(
            title: "Delete \(name)?",
            body: "This permanently deletes the profile on your Hermes box, including its memory, chats with the agent, skills and scheduled jobs. Past chats and alerts stay as read-only history.",
            confirm: "Delete")
        : RemoveCrewPrompt(title: "Remove \(name) from the app?", body: "This does not delete anything on your Hermes box.", confirm: "Remove")
}

// MARK: Heartbeat wording

enum HeartbeatText {
    static let gapPresets = [0, 15, 30, 60, 90, 120, 180, 240, 480, 720]
    static let maxAlertsPerDayLimit = 20

    /// 0 -> "12 AM", 7 -> "7 AM", 12 -> "12 PM", 22 -> "10 PM".
    static func hour(_ hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        let twelve = h % 12 == 0 ? 12 : h % 12
        return "\(twelve) \(h < 12 ? "AM" : "PM")"
    }

    /// 0 -> "No minimum", 30 -> "30 min", 60 -> "1 hour", 120 -> "2 hours", 90 -> "90 min".
    static func gap(_ minutes: Int) -> String {
        if minutes <= 0 { return "No minimum" }
        if minutes % 60 == 0 { return "\(minutes / 60) hour\(minutes == 60 ? "" : "s")" }
        return "\(minutes) min"
    }

    /// The presets plus the saved value, so a value set elsewhere still shows as itself.
    static func gapChoices(current: Int) -> [Int] { Array(Set(gapPresets + [current])).sorted() }

    static func alertsPerDay(_ n: Int) -> String {
        switch n {
        case 0: return "None (urgent only)"
        case 1: return "1 per day"
        default: return "\(n) per day"
        }
    }

    /// The next time the clock reads `hour`:00 here: this morning if it is still earlier, otherwise tomorrow.
    static func nextMorning(now: Date = .now, hour: Int, calendar: Calendar = .current) -> Date {
        var at = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        if at <= now { at = calendar.date(byAdding: .day, value: 1, to: at) ?? at }
        return at
    }
}

// MARK: Invite links

/// Pulls the secret token out of whatever the person pasted or tapped: an invite link
/// (`https://<site>/join/<token>`), the app's own `gaca://join/<token>`, or the bare token. Nil for anything else.
/// The app never contacts the link's address: the token goes only to the person's own server.
func parseInviteToken(_ text: String?) -> String? {
    let raw = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    func valid(_ s: String) -> Bool { s.range(of: "^[A-Za-z0-9_-]{8,512}$", options: .regularExpression) != nil }
    if raw.isEmpty || raw.contains(where: \.isWhitespace) { return nil }
    if !raw.contains("://") { return valid(raw) ? raw : nil }
    guard let url = URLComponents(string: raw) else { return nil }
    var segments = url.path.split(separator: "/").map(String.init)
    switch url.scheme?.lowercased() {
    case "http", "https": break
    case "gaca":
        guard url.host == "join" else { return nil }
        segments = ["join"] + segments
    default: return nil
    }
    guard let at = segments.firstIndex(of: "join"), at + 1 < segments.count, valid(segments[at + 1]) else { return nil }
    return segments[at + 1]
}

/// What went wrong with an invite link, as the cloud's stable codes tell it.
enum JoinProblem {
    case notLinked, linkDead, other
    init(code: String?) {
        switch code {
        case "cloud_not_linked", "cloud_not_configured", "cloud_link_invalid": self = .notLinked
        case "invite_expired", "not_found": self = .linkDead
        default: self = .other
        }
    }
    static let linkDeadText = "This link isn't valid any more. It may have expired, been cancelled, or been used up. Ask the person who shared it for a new one."
}

/// The move (or bring home) did not, or may not have, finished. The message says what to do.
struct TransferNotFinished: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
