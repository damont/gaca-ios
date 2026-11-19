import XCTest
@testable import Gaca

/// The derived rules ported from gaca-android (ArtifactSharingTest, HeartbeatTest, InviteLinkTest, CloudLinkTest…).
final class CloudTests: XCTestCase {
    private func artifact(_ extra: String = "") throws -> Artifact {
        let json = """
        {"id":"p1","title":"Budget","version":1,"rev":1,"updated_at":"2026-10-10T15:00:00+00:00"\(extra)}
        """
        return try APIClient.decoder.decode(Artifact.self, from: Data(json.utf8))
    }

    func testOlderServerArtifactIsALocalPageYouOwn() throws {
        let a = try artifact()
        XCTAssertTrue(a.isMine)
        XCTAssertFalse(a.isCloud)
        XCTAssertEqual(a.badges, [.private])
        XCTAssertTrue(a.canShare)
        XCTAssertTrue(a.canPublish)
        XCTAssertFalse(a.canBringHome)
        XCTAssertFalse(a.canLeave)
    }

    func testSharedWithMe() throws {
        let a = try artifact(#","home":"cloud","role":"editor","shared_by":"ada","member_count":3"#)
        XCTAssertFalse(a.isMine)
        XCTAssertTrue(a.matches(.shared))
        XCTAssertEqual(a.badges, [.shared])
        XCTAssertEqual(a.sharedByLine, "Shared by ada")
        XCTAssertFalse(a.canShare)
        XCTAssertTrue(a.canLeave)
    }

    func testOwnCloudPagePublished() throws {
        let a = try artifact(#","home":"cloud","role":"owner","member_count":2,"published_template_id":"t1""#)
        XCTAssertEqual(a.badges, [.shared, .published])
        XCTAssertEqual(a.peopleLine, "2 people")
        XCTAssertTrue(a.canBringHome)
        XCTAssertTrue(a.needsMemberAck)
        XCTAssertTrue(a.bringHomeWarning.hasPrefix("1 other person will lose access"))
    }

    func testUnknownRoleIsLeastAccess() throws {
        XCTAssertEqual(try artifact(#","role":"wizard""#).accessRole, .viewer)
    }

    func testMovingPageCannotBeShared() throws {
        let a = try artifact(#","moving":true"#)
        XCTAssertFalse(a.canShare)
        XCTAssertEqual(a.transferLine, "Moving to the cloud…")
    }

    func testInviteTokenParsing() {
        XCTAssertEqual(parseInviteToken("https://gaca.cloud/join/abcDEF123_-x"), "abcDEF123_-x")
        XCTAssertEqual(parseInviteToken("gaca://join/abcDEF123"), "abcDEF123")
        XCTAssertEqual(parseInviteToken("  abcDEF12345  "), "abcDEF12345")
        XCTAssertNil(parseInviteToken("gaca://artifact/abcDEF123"))
        XCTAssertNil(parseInviteToken("ftp://x/join/abcDEF123"))
        XCTAssertNil(parseInviteToken("short"))
        XCTAssertNil(parseInviteToken("two words here"))
        XCTAssertNil(parseInviteToken("https://x.dev/other/abcDEF123"))
    }

    func testHeartbeatBodyClearsPauseWithExplicitNull() throws {
        let data = try HeartbeatChange(clearPause: true).body(zone: TimeZone(identifier: "America/New_York")!)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertTrue(obj["paused_until"] is NSNull)
        XCTAssertEqual(obj["timezone"] as? String, "America/New_York")
        XCTAssertNil(obj["enabled"])
        let only = try JSONSerialization.jsonObject(with: HeartbeatChange(maxAlertsPerDay: 5).body()) as! [String: Any]
        XCTAssertEqual(only["max_alerts_per_day"] as? Int, 5)
        XCTAssertNil(only["paused_until"])
    }

    func testHeartbeatWording() {
        XCTAssertEqual(HeartbeatText.hour(0), "12 AM")
        XCTAssertEqual(HeartbeatText.hour(12), "12 PM")
        XCTAssertEqual(HeartbeatText.hour(22), "10 PM")
        XCTAssertEqual(HeartbeatText.gap(0), "No minimum")
        XCTAssertEqual(HeartbeatText.gap(60), "1 hour")
        XCTAssertEqual(HeartbeatText.gap(120), "2 hours")
        XCTAssertEqual(HeartbeatText.gap(90), "90 min")
        XCTAssertTrue(HeartbeatText.gapChoices(current: 45).contains(45))
        XCTAssertEqual(HeartbeatText.alertsPerDay(0), "None (urgent only)")
    }

    func testNextMorning() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let early = cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 5))!
        let late = cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 9))!
        XCTAssertEqual(cal.component(.day, from: HeartbeatText.nextMorning(now: early, hour: 7, calendar: cal)), 18)
        XCTAssertEqual(cal.component(.day, from: HeartbeatText.nextMorning(now: late, hour: 7, calendar: cal)), 19)
    }

    func testCloudLinkStatusDecodes() throws {
        let json = #"{"linked":false,"state":"pending","user_code":"ABCD-1234","verification_uri":"https://c/x","expires_at":"2026-11-18T12:00:00+00:00","interval":5}"#
        let s = try APIClient.decoder.decode(CloudLinkStatus.self, from: Data(json.utf8))
        XCTAssertEqual(s.kind, .pending)
        XCTAssertTrue(s.isConfigured)
        XCTAssertEqual(s.pendingAttempt?.userCode, "ABCD-1234")
        let none = try APIClient.decoder.decode(CloudLinkStatus.self, from: Data(#"{"linked":false,"state":"none","configured":false}"#.utf8))
        XCTAssertFalse(none.isConfigured)
        XCTAssertNil(none.pendingAttempt)
    }

    func testPollWait() throws {
        let p = try APIClient.decoder.decode(CloudLinkPoll.self, from: Data(#"{"status":"pending","interval":5,"retry_in":9}"#.utf8))
        XCTAssertEqual(p.waitSeconds(fallback: 3), 9)
        let q = try APIClient.decoder.decode(CloudLinkPoll.self, from: Data(#"{"status":"pending","interval":0}"#.utf8))
        XCTAssertEqual(q.waitSeconds(fallback: 3), 1)
    }

    func testMovePreviewWording() throws {
        let json = #"{"can_move":false,"blocked_because":"artifact_archived","problems":[{"item":"a"},"b",{"item":"a"}],"not_carried":{"versions_dropped":2,"crew":"ada","last_opened":true}}"#
        let p = try APIClient.decoder.decode(MovePreview.self, from: Data(json.utf8))
        XCTAssertEqual(p.blockedText, "Archived pages can't be moved. Unarchive it first. a; b.")
        XCTAssertEqual(p.lostLines.count, 3)
        XCTAssertEqual(p.keepDays, 30)
    }

    func testPublishReviewReadsTheCloudPreview() throws {
        let json = #"{"status":"passed","findings":[{"severity":"info","message":"i"},{"severity":"warn","message":"w"}],"content_hash":"h1","preview":{"listing":{"title":"T","tags":["x","y"]},"html":"<p>hi</p>","schemas":{"a":{},"b":{}}}}"#
        let report = try APIClient.decoder.decode(ValidationReport.self, from: Data(json.utf8))
        let review = PublishReview(report: report, fallbackTitle: "F")
        XCTAssertTrue(review.canPublish)
        XCTAssertEqual(review.preview.title, "T")
        XCTAssertEqual(review.preview.tags, ["x", "y"])
        XCTAssertEqual(review.preview.shapes, 2)
        XCTAssertEqual(report.sortedFindings.first?.text, "w")
        XCTAssertEqual(report.warnings, 1)
        let blocked = try APIClient.decoder.decode(ValidationReport.self, from: Data(#"{"findings":[{"severity":"block","message":"no"}],"content_hash":"h"}"#.utf8))
        XCTAssertFalse(PublishReview(report: blocked, fallbackTitle: "F").canPublish)
    }

    func testShareAndRemoveWording() {
        XCTAssertEqual(ShareOptions().summary, "Anyone who has the link can join as viewer. It works for 7 days and for up to 1 person.")
        XCTAssertEqual(removeCrewPrompt("ada", deletesProfile: true).confirm, "Delete")
        XCTAssertEqual(removeCrewPrompt("ada", deletesProfile: false).title, "Remove ada from the app?")
        XCTAssertEqual(crewLabel("ada", removed: true), "ada (removed)")
        XCTAssertEqual(JoinProblem(code: "invite_expired"), .linkDead)
        XCTAssertEqual(JoinProblem(code: "cloud_not_linked"), .notLinked)
    }
}
