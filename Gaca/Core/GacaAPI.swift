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

    // MARK: Automations
    /// Never cached by the API: every call asks the crew members' engines.
    func automations(crew: String? = nil) async throws -> AutomationList {
        var q: [URLQueryItem] = []
        if let crew { q.append(URLQueryItem(name: "crew", value: crew)) }
        return try await get("automations", query: q)
    }
    /// Newest first.
    func automationRuns(crew: String, id: String, limit: Int = 20) async throws -> [AutomationRun] {
        try await get("crew/\(crew.urlPath)/automations/\(id.urlPath)/runs", query: [URLQueryItem(name: "limit", value: String(limit))])
    }
    /// A request, not an instant start: the engine begins on its next tick (about a minute).
    func runAutomation(crew: String, id: String) async throws -> Automation {
        try await post("crew/\(crew.urlPath)/automations/\(id.urlPath)/run")
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
    /// Close an open alert with one of the reasons the API offered in `workflow.close_options`.
    func closeAlert(_ id: String, reason: String, note: String? = nil) async throws -> Alert {
        try await post("alerts/\(id)/close", AlertClose(reason: reason, note: note))
    }
    /// Tap one of the alert's actions. Returns the alert with the run in flight; read it again to see it settle.
    func runAlertAction(_ id: String, index: Int) async throws -> Alert { try await post("alerts/\(id)/actions/\(index)/run") }
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
        try await artifactList(includeArchived: includeArchived).artifacts
    }
    /// The list as the server gave it, with `stale` (the cloud could not be asked; cloud rows are the last known).
    func artifactList(includeArchived: Bool) async throws -> ArtifactList {
        try await get("artifacts", query: [
            URLQueryItem(name: "include_archived", value: includeArchived ? "true" : "false"),
            URLQueryItem(name: "limit", value: "200"),
        ])
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

    // MARK: Heartbeat
    /// Never cached: each call asks gaca-api, so what shows is what the heartbeat will obey.
    func heartbeatSettings() async throws -> HeartbeatSettings { try await get("heartbeat/settings") }
    /// Partial: only what changes is sent (a cleared pause as an explicit null).
    func updateHeartbeat(_ change: HeartbeatChange) async throws -> HeartbeatSettings {
        try await sendRaw("PUT", "heartbeat/settings", body: try change.body())
    }

    // MARK: GACA Cloud link (the server forwards to the cloud; the app never does)
    func cloudLink() async throws -> CloudLinkStatus { try await get("cloud/link") }
    func startCloudLink() async throws -> CloudLinkStarted { try await post("cloud/link/start", CloudLinkStart(scope: "manage")) }
    func pollCloudLink() async throws -> CloudLinkPoll { try await post("cloud/link/poll") }
    /// The owner's switch for their agents. The server answers with the whole status.
    func setCloudAgentAccess(_ enabled: Bool) async throws -> CloudLinkStatus {
        try await send("PUT", "cloud/agent-access", json: CloudAgentAccess(enabled: enabled))
    }
    /// Without `force` the server refuses (409 `cloud_artifacts_present`) while pages live in the cloud.
    func unlinkCloud(force: Bool) async throws -> UnlinkResult {
        do {
            let out: CloudUnlinked = try await send("DELETE", "cloud/link", query: [URLQueryItem(name: "force", value: force ? "true" : "false")])
            return .done(out.message ?? "")
        } catch let error as APIError where error.code == "cloud_artifacts_present" {
            return .blocked(UnlinkBlock(owned: error.infoInt("owned") ?? 0, shared: error.infoInt("shared") ?? 0,
                                        inProgress: error.infoInt("in_progress") ?? 0))
        }
    }

    // MARK: Gallery
    /// Only what is listed: the cloud also returns your own unlisted or blocked ones.
    func templates(cursor: String? = nil, limit: Int = 30) async throws -> (templates: [Template], next: String?) {
        var q = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { q.append(URLQueryItem(name: "cursor", value: cursor)) }
        let list: TemplateList = try await get("cloud/templates", query: q)
        return ((list.templates ?? []).filter(\.isListed), list.nextCursor)
    }
    /// Makes a private copy of a template on this server. Answers with the new page.
    func installTemplate(_ id: String) async throws -> Artifact { try await post("cloud/templates/\(id.urlPath)/install") }

    // MARK: Sharing a page
    func movePreview(_ id: String) async throws -> MovePreview { try await get("artifacts/\(id)/move-preview") }
    /// Blocks until the move is done (it uploads, then checks the cloud copy). Safe to retry. If the connection drops
    /// while waiting the server may still be working, so this asks how the page stands (every 3 s, up to 2 minutes).
    func moveToCloud(_ id: String, acknowledged: Bool) async throws -> Artifact {
        do {
            let out: MoveResult = try await sendLong("POST", "artifacts/\(id)/move-to-cloud", json: MoveRequest(acknowledgeNotCarried: acknowledged))
            return out.artifact
        } catch APIError.network {
            for _ in 0..<40 {
                try await Task.sleep(for: .seconds(3))
                guard let page = try? await artifact(id) else { continue }
                if page.isMoving || page.cloudStatus == "moving" { continue }
                if page.isCloud { return page }
                throw TransferNotFinished(message: "The move did not finish. Your page here is unchanged; you can try again.")
            }
            throw TransferNotFinished(message: "Lost the connection while moving. Check the list in a moment: if the page still shows as moving, wait; otherwise try again (it is safe to retry).")
        }
    }
    func shareCheck(_ id: String) async throws -> ValidationReport {
        try await post("cloud/gacabits/\(id.urlPath)/validations", ValidationRun(subject: "share"))
    }
    /// The invite link, shown once. Nothing here is saved anywhere.
    func createInvite(_ id: String, _ options: ShareOptions) async throws -> InviteLink {
        try await post("cloud/gacabits/\(id.urlPath)/invites",
                       InviteCreate(role: options.role.rawValue, expiresInDays: options.expiryDays, maxUses: options.maxUses))
    }

    // MARK: Joining a shared page
    func previewInvite(token: String) async throws -> InvitePreview { try await post("cloud/invites/preview", InviteToken(token: token)) }
    /// Joining twice is harmless on the cloud's side (already a member is a no-op).
    func redeemInvite(token: String) async throws -> Redeemed { try await post("cloud/invites/redeem", InviteToken(token: token)) }

    // MARK: Publishing (works for a private page and a cloud page alike)
    func publishCheck(_ id: String, _ listing: PublishListing) async throws -> PublishReview {
        let report: ValidationReport = try await post("artifacts/\(id)/publish-check",
                                                      PublishCheck(title: listing.cleanTitle, description: listing.cleanDescription))
        return PublishReview(report: report, fallbackTitle: listing.cleanTitle)
    }
    /// Only after the person confirmed the preview whose `hash` this is. The cloud refuses if anything changed since.
    func publish(_ id: String, _ listing: PublishListing, hash: String) async throws -> Template {
        try await post("artifacts/\(id)/publish", PublishRequest(title: listing.cleanTitle, description: listing.cleanDescription,
                                                                 visibility: listing.visibility.rawValue, confirmedPreview: true, previewHash: hash))
    }

    // MARK: Bring home and leave
    /// Bring a page you own back here. Blocks until it has arrived. Safe to retry.
    func bringHome(_ page: Artifact) async throws -> BringHomeResult {
        do {
            return try await sendLong("POST", "artifacts/\(page.id)/bring-home", json: BringHomeRequest(acknowledgeMembers: page.needsMemberAck))
        } catch APIError.network {
            throw TransferNotFinished(message: "Lost the connection while bringing it home. Check the list in a moment: if the page is still in the cloud, it is safe to try again.")
        }
    }
    /// Cancel a bring home while the cloud still has its copy.
    func undoBringHome(_ id: String) async throws -> Bool {
        let out: UndoResult = try await post("artifacts/\(id)/undo-bring-home")
        return out.undone ?? false
    }
    /// A member leaves a page shared with them. The owner can't (the cloud refuses).
    func leavePage(_ id: String) async throws { try await sendVoid("POST", "cloud/gacabits/\(id.urlPath)/leave", json: EmptyBody()) }

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
