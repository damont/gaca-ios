import Foundation

// Wire models — exactly what gaca-api returns (see <base>/api/openapi.json). Decoded with snake_case → camelCase key conversion. The app
// renders these as-is: anything derived (labels, previews, activity summaries) comes from
// the API so every client shows the same thing.

// MARK: Auth

/// What `GET /setup` answers before this phone has a credential: is this a GACA server.
struct SetupStatus: Decodable, Sendable {
    let version: String?
    let claimed: Bool?
}

/// Trading the one-time code from `gaca-api pair` for this device's credential.
struct PairRequest: Encodable { let code: String; let name: String }
struct PairResponse: Decodable, Sendable {
    let accessToken: String
    let deviceId: String?
}

struct UserResponse: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let email: String
}


// MARK: Agent & crew

struct AgentStatus: Decodable, Sendable {
    let connected: Bool
    let host: String?
}

struct CrewMember: Decodable, Sendable, Identifiable, Hashable {
    let name: String
    let port: Int
    let color: String
    let isDefault: Bool
    var id: String { name }
    var style: CrewStyle { CrewStyle(hex: color) }
}

struct CrewList: Decodable, Sendable {
    let host: String?
    let crew: [CrewMember]
    let canCreate: Bool
}

struct CrewMemberCreate: Encodable {
    let name: String
    var color: String? = nil
    var port: Int? = nil
    var apiKey: String? = nil
}

struct CrewMemberUpdate: Encodable {
    let port: Int
    let apiKey: String
}

struct AgentConnect: Encodable {
    let host: String
    let port: Int
    let apiKey: String
    let name: String
}

struct AgentHostUpdate: Encodable { let host: String }

struct Skill: Decodable, Sendable, Identifiable, Hashable {
    let name: String
    let description: String?
    let category: String?
    /// How often it's been used; 0 (or absent, from an older server) when the engine keeps no count.
    var useCount: Int? = nil
    var id: String { name }
}

struct CrewProfile: Decodable, Sendable {
    struct Model: Decodable, Sendable { let provider: String?; let name: String? }
    struct Channel: Decodable, Sendable, Hashable { let name: String; let state: String?; let needsAttention: Bool? }
    struct SkillCategory: Decodable, Sendable, Hashable { let name: String; let count: Int }
    struct Toolset: Decodable, Sendable, Hashable { let name: String; let label: String; let description: String? }
    struct Job: Decodable, Sendable, Identifiable, Hashable {
        let id: String
        let name: String
        let schedule: String
        let enabled: Bool?
        let nextRun: Date?
        let lastRun: Date?
        let lastStatus: String?
        let kind: String?
    }
    struct Purpose: Decodable, Sendable {
        let summary: String?
        let instructions: String?
        let isGeneric: Bool?
    }

    let name: String
    let color: String
    let isDefault: Bool
    let status: String?
    let engine: String?
    let model: Model?
    let channels: [Channel]?
    let skillCount: Int?
    let skillCategories: [SkillCategory]?
    let toolsets: [Toolset]?
    let jobs: [Job]?
    let unavailable: [String]?
    let purpose: Purpose?
}

// MARK: Alerts

struct SuggestedAction: Codable, Sendable, Hashable {
    let label: String
    let prompt: String
}

struct AlertLink: Decodable, Sendable, Hashable {
    let url: String
    let label: String?

    var isWeb: Bool { url.lowercased().hasPrefix("https://") || url.lowercased().hasPrefix("http://") }
    var title: String { label ?? url }
}

struct Alert: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let createdAt: Date
    let source: String
    let crew: String?
    let kind: String
    let severity: String
    let title: String
    let body: String?
    let data: JSONValue?
    let links: [AlertLink]?
    let artifactId: String?
    /// `new` while open; otherwise how it ended: done_by_gaca / done_by_me / noted / not_useful.
    let status: String
    let effectiveStatus: String
    /// When `status` last changed — the time to show next to "Done by Hermes".
    let statusChangedAt: Date?
    let sessionId: String?
    let resolutionNote: String?
    /// Key/value rows to show for `data`, flattened by the API.
    let dataRows: [DataRow]?
    /// The page made for this alert, resolved by the API.
    let artifact: ArtifactRef?
    /// The actions with their state and results. Every field is the API's decision; the app shows it and posts the tap.
    let actions: [AlertAction]?
    /// How the alert's screen lays out, decided by the API so every app behaves the same.
    let workflow: AlertWorkflow?
    /// The latest email draft, if an agent wrote one.
    let draft: AlertDraft?
    /// True when the crew member it names was removed: read-only history now. Absent on older servers.
    let crewRemoved: Bool?
    let parentAlertId: String?

    var isOpen: Bool { status == "new" }
    var isCrewRemoved: Bool { crewRemoved ?? false }
    var actionList: [AlertAction] { actions ?? [] }
    var flow: AlertWorkflow { workflow ?? AlertWorkflow() }
    /// Only web addresses ever become tappable, whatever the server says.
    var webLinks: [AlertLink] { (links ?? []).filter(\.isWeb) }

    struct DataRow: Decodable, Sendable, Hashable {
        let key: String
        let value: String
    }
}

/// An email draft an agent wrote. The API built `mailto` and `copyText`; the app only opens or copies them.
struct AlertDraft: Decodable, Sendable, Hashable {
    let to: String?
    let subject: String?
    let body: String
    let copyText: String?
    let mailto: String?

    var textToCopy: String { copyText ?? body }
}

/// What an action did once it ran: the agent's short answer, links it gave, or a draft it wrote.
struct ActionResult: Decodable, Sendable, Hashable {
    let summary: String?
    let links: [AlertLink]?
    let draft: AlertDraft?
    let error: String?
}

/// One tappable action and where it stands — `state` is idle / running / done / failed.
struct AlertAction: Decodable, Sendable, Hashable, Identifiable {
    let index: Int
    let kind: String?
    let label: String
    let detail: String?
    /// The word on the button: "Add", "Draft", "Do it".
    let cta: String?
    /// An "Add all"-style action: shown as the one big button, not as a row.
    let prominent: Bool?
    /// Where it stands while running ("Hermes is on it").
    let note: String?
    let state: String?
    let canRun: Bool?
    let result: ActionResult?

    var id: Int { index }
    var button: String { cta ?? "Do it" }
    var isProminent: Bool { prominent ?? false }
    var runState: String { state ?? "idle" }
    var runnable: Bool { canRun ?? false }
}

struct CloseOption: Decodable, Sendable, Hashable {
    let reason: String
    let label: String
    let primary: Bool?
}

struct ChatEntry: Decodable, Sendable, Hashable {
    var hint: String? = nil
    var prominent: Bool? = nil
}

/// The layout decisions for an alert's screen. `phase`: open / working / waiting_on_you / closed.
struct AlertWorkflow: Decodable, Sendable, Hashable {
    var phase: String? = nil
    var phaseLabel: String? = nil
    var actionsHeading: String? = nil
    var progressLabel: String? = nil
    var chat: ChatEntry? = nil
    var closeHeading: String? = nil
    var closeOptions: [CloseOption]? = nil
    var closeHint: String? = nil
    var closedNote: String? = nil

    var currentPhase: String { phase ?? "open" }
    var chatHint: String { chat?.hint ?? "" }
    var chatProminent: Bool { chat?.prominent ?? false }
    var closeChoices: [CloseOption] { closeOptions ?? [] }
}

struct AlertList: Decodable, Sendable { let alerts: [Alert] }
/// POST /alerts/{id}/close — `reason` is one the API offered in `workflow.close_options`
/// (done_by_me / noted / not_useful; done_by_gaca is set by the server only).
struct AlertClose: Encodable {
    let reason: String
    var note: String? = nil
}
struct AlertTakeToChat: Encodable {
    var suggestedActionIndex: Int? = nil
    var crew: String? = nil
}
struct TakeToChatOut: Decodable, Sendable {
    let alert: Alert
    let sessionId: String
    let draft: String?
}
struct AlertDelegate: Encodable {
    var instruction: String? = nil
    var suggestedActionIndex: Int? = nil
    var crew: String? = nil
}
struct AlertCreate: Encodable {
    let kind: String
    let title: String
    var body: String? = nil
    var source: String = "ios"
    var crew: String? = nil
}

// MARK: Sessions & messages

struct Session: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let createdAt: Date
    let title: String?
    let status: String
    let crew: String?
    let alertId: String?
    let summary: String?
    let preview: String?
    /// When the chat last saw a message — what the list shows as "2m".
    let lastActivityAt: Date?
    /// True when `crew` was removed: the chat is read-only history. Absent on older servers.
    var crewRemoved: Bool? = nil

    var activityDate: Date { lastActivityAt ?? createdAt }
    var isCrewRemoved: Bool { crewRemoved ?? false }
}

struct SessionList: Decodable, Sendable { let sessions: [Session] }

struct SessionDetail: Decodable, Sendable {
    let id: String
    let createdAt: Date
    let title: String?
    let status: String
    let crew: String?
    let alertId: String?
    let summary: String?
    let preview: String?
    var crewRemoved: Bool? = nil
    let messages: [Message]
    /// A run is in flight right now (newer servers only).
    let running: Bool?
    let runStartedAt: Date?
    /// Send this as Last-Event-ID when opening the event stream: it replays exactly the
    /// in-flight run's events and nothing older (newer servers only).
    let resumeSeq: Int?

    var isCrewRemoved: Bool { crewRemoved ?? false }
}

struct Attachment: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let contentType: String
    let size: Int
    let url: String
}

struct ArtifactRef: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let crew: String?
    let missing: Bool?
}

struct MessageActivity: Decodable, Sendable, Hashable {
    struct Tool: Decodable, Sendable, Hashable { let name: String; let count: Int; let errors: Int? }
    let tools: [Tool]
    let durationSeconds: Double
    let label: String
}

struct Message: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let sessionId: String
    let role: String
    let content: String
    let createdAt: Date
    let attachments: [Attachment]?
    /// `content` with artifact links taken out (newer servers only; fall back to content).
    let displayContent: String?
    let artifacts: [ArtifactRef]?
    let activity: MessageActivity?
    /// An email draft the agent wrote in this reply; `displayContent` is then only the words before it.
    var draft: AlertDraft? = nil

    var isUser: Bool { role == "user" }
    var text: String { displayContent ?? content }
}

struct SessionCreate: Encodable {
    var title: String? = nil
    var crew: String? = nil
}

struct MessageCreate: Encodable {
    let content: String
    var attachmentIds: [String] = []
}

struct MessageAccepted: Decodable, Sendable { let turnId: String }

// MARK: Briefing

struct Briefing: Decodable, Sendable {
    struct Item: Decodable, Sendable, Hashable {
        let title: String
        let body: String?
        let time: String?
        let location: String?
        let link: String?
        let priority: String?
    }
    struct Section: Decodable, Sendable, Hashable, Identifiable {
        let key: String
        let title: String
        let kind: String
        let headline: String?
        let items: [Item]?
        var id: String { key }
    }
    let date: String
    let summary: String?
    let sections: [Section]?
}

// MARK: Artifacts

struct Artifact: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let crew: String?
    let sessionId: String?
    let alertId: String?
    let archived: Bool?
    let position: Int?
    let version: Int
    let rev: Int
    let updatedAt: Date
    let lastOpenedAt: Date?
    // Cloud-aware fields (servers before Part 8 omit them: a local page you own).
    /// `local` (on your server) or `cloud`.
    var home: String? = nil
    /// Your role on it: owner, maintainer, editor or viewer.
    var role: String? = nil
    /// The owner's handle when it is not you.
    var sharedBy: String? = nil
    var memberCount: Int? = nil
    /// True while it is being moved to the cloud (read-only until that ends).
    var moving: Bool? = nil
    var cloudStatus: String? = nil
    /// Set once this page has been published to the gallery.
    var publishedTemplateId: String? = nil
}

struct ArtifactList: Decodable, Sendable {
    let artifacts: [Artifact]
    /// True when the cloud could not be asked and the cloud rows are from the server's last look.
    var stale: Bool? = nil
}
struct ArtifactOrder: Encodable { let ids: [String] }
struct ArtifactPatch: Encodable {
    var title: String? = nil
    var archived: Bool? = nil
}

// MARK: Push

struct PushTokenRegister: Encodable {
    let token: String
    let platform: String
    let environment: String
}
struct PushTokenUnregister: Encodable { let token: String }

// MARK: Generic JSON

/// Arbitrary JSON (an alert's `data`, an artifact's state) carried through untouched.
enum JSONValue: Codable, Sendable, Hashable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }
}

// MARK: Automations

/// One past run in an automation's row of squares; `status` is ok / failed / running.
struct RunMark: Decodable, Sendable, Hashable {
    let id: String?
    let status: String
    let at: Date?
}

/// GET /automations — something a crew member does on a schedule. `status` is one of ok,
/// failed, running, paused, done, never_run; `recent` is at most 10 runs, oldest first.
struct Automation: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    /// Which crew member owns it.
    let crew: String?
    /// Plain English, e.g. "Every day at 7:30 AM".
    let schedule: String
    var cronExpr: String? = nil
    let status: String
    var lastStatus: String? = nil
    var lastRun: Date? = nil
    var nextRun: Date? = nil
    var recent: [RunMark]? = nil

    var state: AutomationStatus { AutomationStatus(wire: status) }
    var lastRunStatus: RunStatus? { lastStatus.map(RunStatus.init(wire:)) }
    var marks: [RunMark] { recent ?? [] }
    var needsAttention: Bool { state == .failed }
    var owner: String { crew ?? "" }
}

struct AutomationList: Decodable, Sendable {
    var automations: [Automation] = []
    /// Crew members whose automations couldn't be read — say so rather than show an empty list as true.
    var unavailable: [String]? = nil
}

/// GET /crew/{name}/automations/{id}/runs, newest first.
struct AutomationRun: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let status: String
    var startedAt: Date? = nil
    var finishedAt: Date? = nil
    var durationSeconds: Double? = nil
    var summary: String? = nil
    var error: String? = nil

    var runStatus: RunStatus { RunStatus(wire: status) }
    /// What it said, or why it failed; nil when it had nothing to say.
    var output: String? { [error, summary].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}

/// How one run ended. An unknown word from a newer server reads as ok rather than as a failure.
enum RunStatus: Sendable {
    case ok, failed, running
    init(wire: String) {
        switch wire {
        case "failed": self = .failed
        case "running": self = .running
        default: self = .ok
        }
    }
}

/// The job's state as the API words it: paused jobs were switched off by the crew member, not the app.
enum AutomationStatus: Sendable {
    case ok, failed, running, paused, done, neverRun
    init(wire: String) {
        switch wire {
        case "failed": self = .failed
        case "running": self = .running
        case "paused": self = .paused
        case "done": self = .done
        case "never_run": self = .neverRun
        default: self = .ok
        }
    }
}
