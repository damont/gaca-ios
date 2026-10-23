import Foundation

/// One method per gaca-api endpoint the app uses — mirrors gaca-android's GacaApi.kt.
extension APIClient {
    // MARK: Pairing & identity
    /// Is there a GACA server at `base` (before this phone has a credential)?
    func setupStatus(at base: URL) async throws -> SetupStatus {
        try await unauthenticated("GET", base.appendingPathComponent("setup"), body: nil)
    }
    /// Trade the code `gaca-api pair` printed for this device's credential.
    func pair(at base: URL, code: String, deviceName: String) async throws -> PairResponse {
        try await unauthenticated("POST", base.appendingPathComponent("devices/pair"),
                                  body: try Self.encoder.encode(PairRequest(code: code, name: deviceName)))
    }
    /// This phone forgets the server: the server revokes its credential.
    func unpairThisDevice() async throws { try await sendVoid("DELETE", "devices/me") }
    func me() async throws -> UserResponse { try await get("auth/me") }

    // MARK: Agent & crew
    func agentStatus() async throws -> AgentStatus { try await get("agent") }
    func connectAgent(_ body: AgentConnect) async throws -> CrewList { try await post("agent/connect", body) }
    func updateAgentHost(_ host: String) async throws -> CrewList { try await send("PUT", "agent", json: AgentHostUpdate(host: host)) }
    func crew() async throws -> CrewList { try await get("crew") }
    func addCrewMember(_ body: CrewMemberCreate) async throws -> CrewList { try await post("crew", body) }
    func updateCrewMember(_ name: String, _ body: CrewMemberUpdate) async throws -> CrewList {
        try await send("PUT", "crew/\(name.urlPath)", json: body)
    }
    func removeCrewMember(_ name: String) async throws -> CrewList { try await send("DELETE", "crew/\(name.urlPath)") }
    func setDefaultCrewMember(_ name: String) async throws -> CrewList { try await post("crew/\(name.urlPath)/default") }
    func crewProfile(_ name: String) async throws -> CrewProfile { try await get("crew/\(name.urlPath)/profile") }
    /// Most used first, so the composer's sheet can show the top few as they come.
    func skills(_ name: String) async throws -> [Skill] {
        try await get("crew/\(name.urlPath)/skills", query: [URLQueryItem(name: "sort", value: "popular")])
    }

    // MARK: Alerts
    func alerts(statuses: [String], crew: String? = nil, limit: Int = 100) async throws -> [Alert] {
        var q = statuses.map { URLQueryItem(name: "status", value: $0) }
        if let crew { q.append(URLQueryItem(name: "crew", value: crew)) }
        q.append(URLQueryItem(name: "limit", value: String(limit)))
        let list: AlertList = try await get("alerts", query: q)
        return list.alerts
    }
    func alert(_ id: String) async throws -> Alert { try await get("alerts/\(id)") }
    func act(_ id: String, note: String?) async throws -> Alert { try await post("alerts/\(id)/act", AlertResolve(note: note)) }
    func dismiss(_ id: String, note: String?) async throws -> Alert { try await post("alerts/\(id)/dismiss", AlertResolve(note: note)) }
    func snooze(_ id: String, until: Date) async throws -> Alert { try await post("alerts/\(id)/snooze", AlertSnooze(until: until)) }
    func takeToChat(_ id: String, _ body: AlertTakeToChat) async throws -> TakeToChatOut { try await post("alerts/\(id)/take-to-chat", body) }
    func delegate(_ id: String, _ body: AlertDelegate) async throws -> Alert { try await post("alerts/\(id)/delegate", body) }
    func createAlert(_ body: AlertCreate) async throws -> Alert { try await post("alerts", body) }

    // MARK: Sessions
    func sessions() async throws -> [Session] {
        let list: SessionList = try await get("sessions")
        return list.sessions
    }
    func createSession(crew: String?, title: String? = nil) async throws -> Session {
        try await post("sessions", SessionCreate(title: title, crew: crew))
    }
    func session(_ id: String) async throws -> SessionDetail { try await get("sessions/\(id)") }
    func postMessage(_ sessionId: String, content: String, attachmentIds: [String] = []) async throws -> MessageAccepted {
        try await post("sessions/\(sessionId)/messages", MessageCreate(content: content, attachmentIds: attachmentIds))
    }
    func uploadAttachment(_ sessionId: String, data: Data, contentType: String) async throws -> Attachment {
        let req = request("POST", "sessions/\(sessionId)/attachments", body: data, contentType: contentType)
        let raw = try await self.data(for: req)
        return try APIClient.decoder.decode(Attachment.self, from: raw)
    }
    /// An attachment's `url` is relative to the API base and needs the bearer token.
    func attachmentData(_ relativeURL: String) async throws -> Data {
        try await data(for: request("GET", relativeURL))
    }

    // MARK: Briefing
    func briefing(date: String) async throws -> Briefing {
        try await get("briefings", query: [URLQueryItem(name: "date", value: date)])
    }

    // MARK: Artifacts
    func artifacts(includeArchived: Bool) async throws -> [Artifact] {
        let list: ArtifactList = try await get("artifacts", query: [
            URLQueryItem(name: "include_archived", value: includeArchived ? "true" : "false"),
            URLQueryItem(name: "limit", value: "200"),
        ])
        return list.artifacts
    }
    func artifact(_ id: String) async throws -> Artifact { try await get("artifacts/\(id)") }
    func reorderArtifacts(_ ids: [String]) async throws -> [Artifact] {
        let list: ArtifactList = try await send("PUT", "artifacts/order", json: ArtifactOrder(ids: ids))
        return list.artifacts
    }
    func patchArtifact(_ id: String, _ body: ArtifactPatch) async throws -> Artifact { try await send("PATCH", "artifacts/\(id)", json: body) }
    func deleteArtifact(_ id: String) async throws { try await sendVoid("DELETE", "artifacts/\(id)") }
    func markArtifactOpened(_ id: String) async throws { try await sendVoid("POST", "artifacts/\(id)/opened") }
    func artifactHTML(_ id: String) async throws -> String {
        let data = try await data(for: request("GET", "artifacts/\(id)/html"))
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Push
    func registerPush(token: String, environment: String) async throws {
        try await sendVoid("POST", "push/register", json: PushTokenRegister(token: token, platform: "ios", environment: environment))
    }
    func unregisterPush(token: String) async throws {
        try await sendVoid("POST", "push/unregister", json: PushTokenUnregister(token: token))
    }
}

extension String {
    /// A crew name as a single URL path segment. (URL.appendingPathComponent percent-encodes
    /// for us; this only keeps a stray "/" from splitting the segment.)
    var urlPath: String { replacingOccurrences(of: "/", with: "%2F") }
}

extension APIClient {
    /// Start a delegation: the API records it as an alert and hands it to the crew member.
    func startDelegation(instruction: String, crew: String?) async throws -> Alert {
        try await post("alerts/delegations", DelegationCreate(instruction: instruction, crew: crew, source: "ios"))
    }

    /// An artifact's page, already wrapped by the API (sandbox policy, theme, the app SDK).
    func artifactPage(_ id: String) async throws -> String {
        let data = try await data(for: request("GET", "artifacts/\(id)/page"))
        return String(decoding: data, as: UTF8.self)
    }

    /// Forward one `window.app.*` data call from an artifact page; the API does the dispatch.
    /// Returns the raw JSON body for the page.
    func artifactCall(_ id: String, method: String, args: Data) async throws -> Data {
        var body = Data(#"{"method":"#.utf8)
        body.append(try JSONEncoder().encode(method))
        body.append(Data(#","args":"#.utf8))
        body.append(args.isEmpty ? Data("{}".utf8) : args)
        body.append(Data("}".utf8))
        return try await data(for: request("POST", "artifacts/\(id)/call", body: body))
    }
}

struct DelegationCreate: Encodable {
    let instruction: String
    let crew: String?
    let source: String
}
