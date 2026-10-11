import XCTest
@testable import Gaca

/// Decoding the API's real shapes, and the small wire helpers.
final class WireTests: XCTestCase {
    func testParsesPythonIsoDates() {
        XCTAssertNotNil(WireDate.parse("2026-10-10T15:04:05.123456+00:00"))
        XCTAssertNotNil(WireDate.parse("2026-10-10T15:04:05+00:00"))
        XCTAssertNotNil(WireDate.parse("2026-10-10T15:04:05.5Z"))
        // No zone → treated as UTC.
        XCTAssertEqual(WireDate.parse("2026-10-10T15:04:05"), WireDate.parse("2026-10-10T15:04:05Z"))
        XCTAssertNil(WireDate.parse("yesterday"))
    }

    func testDecodesSessionDetailWithActivityAndArtifacts() throws {
        let json = """
        {"id":"s1","created_at":"2026-10-10T15:00:00.000001+00:00","title":null,"status":"idle","crew":"toolshed",
         "alert_id":"a1","summary":"Disk usage","preview":"Done","last_activity_at":"2026-10-10T15:05:00+00:00",
         "running":true,"run_started_at":"2026-10-10T15:04:00+00:00","resume_seq":41,
         "messages":[
           {"id":"m1","session_id":"s1","role":"user","content":"hi","display_content":"hi","created_at":"2026-10-10T15:00:01+00:00",
            "attachments":[{"id":"p1","content_type":"image/jpeg","size":10,"url":"sessions/s1/attachments/p1"}],"artifacts":[],"activity":null},
           {"id":"m2","session_id":"s1","role":"assistant","content":"see [x](gaca://artifact/abc)","display_content":"see",
            "created_at":"2026-10-10T15:00:09+00:00","attachments":[],
            "artifacts":[{"id":"abc","title":"Disk usage","description":"hourly","crew":"toolshed","missing":false}],
            "activity":{"tools":[{"name":"terminal","count":3,"errors":0}],"duration_seconds":41.2,"label":"Ran terminal 3× · 41s"}}
         ]}
        """
        let detail = try APIClient.decoder.decode(SessionDetail.self, from: Data(json.utf8))
        XCTAssertEqual(detail.resumeSeq, 41)
        XCTAssertEqual(detail.running, true)
        XCTAssertEqual(detail.messages.count, 2)
        XCTAssertEqual(detail.messages[0].attachments?.first?.url, "sessions/s1/attachments/p1")
        XCTAssertEqual(detail.messages[1].text, "see")
        XCTAssertEqual(detail.messages[1].artifacts?.first?.title, "Disk usage")
        XCTAssertEqual(detail.messages[1].activity?.label, "Ran terminal 3× · 41s")
    }

    func testOlderServerWithoutNewFieldsStillDecodes() throws {
        let json = """
        {"id":"s1","created_at":"2026-10-10T15:00:00+00:00","status":"idle","messages":[
          {"id":"m1","session_id":"s1","role":"assistant","content":"plain","created_at":"2026-10-10T15:00:01+00:00"}]}
        """
        let detail = try APIClient.decoder.decode(SessionDetail.self, from: Data(json.utf8))
        XCTAssertNil(detail.resumeSeq)
        XCTAssertEqual(detail.messages[0].text, "plain")
    }

    func testDecodesAlert() throws {
        let json = """
        {"id":"a1","user_id":"u","created_at":"2026-10-10T15:00:00+00:00","source":"toolshed","crew":"toolshed",
         "kind":"disk.low","severity":"urgent","title":"Disk at 92%","body":null,"data":{"used":"92%","n":3},
         "suggested_actions":[{"label":"Prune","prompt":"prune it"}],"links":[{"url":"https://x.dev","label":"Dash"}],
         "artifact_id":null,"artifact":null,"status":"new","effective_status":"new","status_changed_at":"2026-10-10T15:00:00+00:00",
         "data_rows":[{"key":"used","value":"92%"},{"key":"n","value":"3"}]}
        """
        let alert = try APIClient.decoder.decode(Alert.self, from: Data(json.utf8))
        XCTAssertEqual(alert.dataRows?.count, 2)
        XCTAssertEqual(alert.suggestedActions?.first?.label, "Prune")
        XCTAssertEqual(SeverityStyle.of(alert.severity).label, "Urgent")
    }

    func testEncodesSnakeCase() throws {
        let data = try APIClient.encoder.encode(MessageCreate(content: "hi", attachmentIds: ["p1"]))
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["attachment_ids"] as? [String], ["p1"])
        let push = try JSONSerialization.jsonObject(with: APIClient.encoder.encode(PushTokenRegister(token: "t", platform: "ios", environment: "sandbox"))) as! [String: Any]
        XCTAssertEqual(push["platform"] as? String, "ios")
        XCTAssertEqual(push["environment"] as? String, "sandbox")
    }

    func testApiErrorDetail() {
        XCTAssertEqual(APIClient.detail(from: Data(#"{"detail":"nope"}"#.utf8)), "nope")
        XCTAssertEqual(APIClient.detail(from: Data(#"{"detail":[{"msg":"field required"}]}"#.utf8)), "field required")
    }

    func testServerAddressNormalizes() {
        XCTAssertEqual(ServerAddress.normalize("gaca.example.com", allowHTTP: false), "https://gaca.example.com/api/")
        XCTAssertEqual(ServerAddress.normalize(" https://gaca.example.com/ ", allowHTTP: false), "https://gaca.example.com/api/")
        XCTAssertEqual(ServerAddress.normalize("https://x.dev/api//", allowHTTP: false), "https://x.dev/api/")
        XCTAssertEqual(ServerAddress.normalize("https://x.dev/gaca", allowHTTP: false), "https://x.dev/gaca/api/")
        XCTAssertEqual(ServerAddress.normalize("http://10.0.0.2:41700", allowHTTP: true), "http://10.0.0.2:41700/api/")
        XCTAssertNil(ServerAddress.normalize("http://10.0.0.2:41700", allowHTTP: false), "plain http only in debug")
        XCTAssertNil(ServerAddress.normalize("", allowHTTP: true))
        XCTAssertNil(ServerAddress.normalize("two words", allowHTTP: true))
        XCTAssertNil(ServerAddress.normalize("https://u:p@x.dev", allowHTTP: false))
        XCTAssertNil(ServerAddress.normalize("https://x.dev/?a=1", allowHTTP: false))
        XCTAssertNil(ServerAddress.normalize("ftp://x.dev", allowHTTP: true))
    }

    func testSetupLink() {
        let link = SetupLink("gaca://setup?url=https%3A%2F%2Fgaca.example.com&code=ABCD1234")
        XCTAssertEqual(link?.url, "https://gaca.example.com")
        XCTAssertEqual(link?.code, "ABCD1234")
        XCTAssertNil(SetupLink("https://gaca.example.com"))
        XCTAssertNil(SetupLink("gaca://artifact/abc"))
        XCTAssertNil(SetupLink(nil))
    }

    func testDecodesPairResponse() throws {
        let out = try APIClient.decoder.decode(PairResponse.self, from: Data(#"{"access_token":"gd_x","token_type":"bearer","device_id":"d1"}"#.utf8))
        XCTAssertEqual(out.accessToken, "gd_x")
    }

    func testCrewHelpers() {
        XCTAssertEqual(crewInitials("toolshed"), "To")
        XCTAssertEqual(crewInitials("x"), "X")
        XCTAssertEqual(crewDisplayName("trading"), "Trading")
        XCTAssertNotEqual(CrewStyle(hex: "#6B8F5A"), CrewStyle(hex: "#B97A56"))
    }

    func testRelativeTime() {
        let now = Date()
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-10), now: now), "now")
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-300), now: now), "5m")
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-3 * 3600), now: now), "3h")
        XCTAssertEqual(RelativeTime.short(now.addingTimeInterval(-2 * 86400), now: now), "2d")
    }
}

/// SSE framing and event decoding.
final class EventTests: XCTestCase {
    func testParserBuildsFrames() {
        var p = SSEParser()
        XCTAssertNil(p.feed(": ping"))
        XCTAssertNil(p.feed("id: 7"))
        XCTAssertNil(p.feed("event: assistant.delta"))
        XCTAssertNil(p.feed(#"data: {"type":"assistant.delta","text":"Hi"}"#))
        let frame = p.feed("")
        XCTAssertEqual(frame, SSEParser.Frame(event: "assistant.delta", id: "7", data: #"{"type":"assistant.delta","text":"Hi"}"#))
        XCTAssertNil(p.feed(""))
    }

    func testDecodesEventTypes() {
        func ev(_ s: String) -> ChatEvent { ChatEvent.decode(Data(s.utf8)) }
        XCTAssertEqual(ev(#"{"type":"assistant.delta","run_id":"r","text":"Hi"}"#), .delta(runId: "r", text: "Hi"))
        XCTAssertEqual(ev(#"{"type":"tool.started","run_id":"r","tool":"terminal"}"#), .toolStarted(runId: "r", tool: "terminal"))
        XCTAssertEqual(ev(#"{"type":"run.heartbeat","run_id":"r","idle_seconds":30.5}"#), .heartbeat(runId: "r", idleSeconds: 30.5))
        XCTAssertEqual(ev(#"{"type":"run.failed","run_id":"r","error":"boom"}"#), .failed(runId: "r", error: "boom"))
        XCTAssertEqual(ev(#"{"type":"assistant.reasoning","text":"…"}"#), .other)
        XCTAssertEqual(ev("not json"), .other)
    }
}

/// The thread's live state follows the event stream and clears when a run ends.
@MainActor
final class ChatThreadModelTests: XCTestCase {
    func testLiveRunLifecycle() {
        let model = ChatThreadModel(sessionId: "s1", api: APIClient(settings: SettingsStore(defaults: UserDefaults(suiteName: "t")!), tokens: TokenStore(service: "test")))
        XCTAssertFalse(model.running)
        model.apply(.toolStarted(runId: "r1", tool: "web_search"))
        XCTAssertTrue(model.running)
        XCTAssertEqual(model.status, "Using web_search…")
        model.apply(.toolCompleted(runId: "r1", tool: "web_search"))
        XCTAssertEqual(model.status, "Working…")
        model.apply(.delta(runId: "r1", text: "Hel"))
        model.apply(.delta(runId: "r1", text: "lo"))
        XCTAssertEqual(model.liveText, "Hello")
        XCTAssertEqual(model.status, "Writing…")
        // A new run's deltas start fresh.
        model.apply(.delta(runId: "r2", text: "New"))
        XCTAssertEqual(model.liveText, "New")
        model.apply(.completed(runId: "r2"))
        XCTAssertFalse(model.running)
        XCTAssertEqual(model.liveText, "")
        XCTAssertNil(model.status)
    }

    func testFailureShowsError() {
        let model = ChatThreadModel(sessionId: "s1", api: APIClient(settings: SettingsStore(defaults: UserDefaults(suiteName: "t")!), tokens: TokenStore(service: "test")))
        model.apply(.delta(runId: "r1", text: "partial"))
        model.apply(.failed(runId: "r1", error: "The run failed"))
        XCTAssertFalse(model.running)
        XCTAssertEqual(model.sendError, "The run failed")
    }
}
