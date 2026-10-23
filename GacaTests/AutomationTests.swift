import XCTest
@testable import Gaca

/// Automations' wire shapes and how their times read.
final class AutomationTests: XCTestCase {
    func testDecodesAutomationList() throws {
        let json = """
        {"automations":[{"id":"j1","name":"Morning brief","crew":"hermes","schedule":"Every day at 7:30 AM",
          "cron_expr":"30 7 * * *","status":"failed","last_status":"failed","last_run":"2026-10-16T11:30:00+00:00",
          "next_run":"2026-10-17T11:30:00+00:00","kind":"agent",
          "recent":[{"id":"r1","status":"ok","at":"2026-10-15T11:30:00+00:00"},{"id":"r2","status":"failed","at":null}]},
          {"id":"j2","name":"Prune","schedule":"Weekly","status":"paused"}],
         "unavailable":["trading"]}
        """
        let list = try APIClient.decoder.decode(AutomationList.self, from: Data(json.utf8))
        XCTAssertEqual(list.automations.count, 2)
        let a = list.automations[0]
        XCTAssertEqual(a.state, .failed)
        XCTAssertTrue(a.needsAttention)
        XCTAssertEqual(a.lastRunStatus, .failed)
        XCTAssertEqual(a.marks.map { RunStatus(wire: $0.status) }, [.ok, .failed])
        XCTAssertEqual(a.key, "hermes/j1")
        XCTAssertEqual(list.automations[1].state, .paused)
        XCTAssertEqual(list.automations[1].owner, "")
        XCTAssertEqual(list.unavailable, ["trading"])
    }

    func testUnknownStatusWordsReadAsOK() {
        XCTAssertEqual(RunStatus(wire: "skipped"), .ok)
        XCTAssertEqual(AutomationStatus(wire: "something-new"), .ok)
        XCTAssertEqual(AutomationStatus(wire: "never_run"), .neverRun)
    }

    func testDecodesRunsAndPicksTheirOutput() throws {
        let json = """
        [{"id":"r2","status":"failed","started_at":"2026-10-16T11:30:00+00:00","duration_seconds":64.2,
          "summary":"partial","error":"Timed out"},
         {"id":"r1","status":"ok","summary":"  "}]
        """
        let runs = try APIClient.decoder.decode([AutomationRun].self, from: Data(json.utf8))
        XCTAssertEqual(runs[0].output, "Timed out")
        XCTAssertNil(runs[1].output, "blank output is nothing to say")
        XCTAssertEqual(runs[0].runStatus, .failed)
    }

    func testDurations() {
        XCTAssertEqual(WhenText.duration(12), "12s")
        XCTAssertEqual(WhenText.duration(64.2), "1m 04s")
        XCTAssertEqual(WhenText.duration(120), "2m 00s")
        XCTAssertEqual(WhenText.duration(-3), "0s")
    }

    func testDayLabels() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 12))!
        func at(_ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: now)! }
        XCTAssertTrue(WhenText.dayAndTime(at(0), now: now).hasPrefix("Today "))
        XCTAssertTrue(WhenText.dayAndTime(at(1), now: now).hasPrefix("Tomorrow "))
        XCTAssertTrue(WhenText.dayAndTime(at(-1), now: now).hasPrefix("Yesterday "))
        XCTAssertTrue(WhenText.dayAndTime(at(3), now: now).hasPrefix(at(3).formatted(.dateTime.weekday(.abbreviated))))
        XCTAssertTrue(WhenText.dayAndTime(at(30), now: now).hasPrefix(at(30).formatted(.dateTime.month(.abbreviated).day())))
    }
}
