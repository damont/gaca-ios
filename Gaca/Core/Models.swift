import Foundation

// Wire models — exactly what gaca-api returns (see gaca/gaca-planning/alerts/api-contract.md
// and <base>/openapi.json). Decoded with snake_case → camelCase key conversion. The app
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
    let suggestedActions: [SuggestedAction]?
    let links: [AlertLink]?
    let artifactId: String?
    let status: String
    let effectiveStatus: String
    let snoozeUntil: Date?
    let sessionId: String?
    let resolutionNote: String?
    /// Key/value rows to show for `data`, flattened by the API.
    let dataRows: [DataRow]?
    /// The page made for this alert, resolved by the API.
    let artifact: ArtifactRef?

    struct DataRow: Decodable, Sendable, Hashable {
        let key: String
        let value: String
    }
}

struct AlertList: Decodable, Sendable { let alerts: [Alert] }
struct AlertResolve: Encodable { var note: String? = nil }
struct AlertSnooze: Encodable { let until: Date }
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

    var activityDate: Date { lastActivityAt ?? createdAt }
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
    let messages: [Message]
    /// A run is in flight right now (newer servers only).
    let running: Bool?
    let runStartedAt: Date?
    /// Send this as Last-Event-ID when opening the event stream: it replays exactly the
    /// in-flight run's events and nothing older (newer servers only).
    let resumeSeq: Int?
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
}

struct ArtifactList: Decodable, Sendable { let artifacts: [Artifact] }
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
