import XCTest
@testable import Gaca

/// The composer's `/skill` commands — the same cases as gaca-android's SkillCommandTest.
final class SkillCommandTests: XCTestCase {
    private let lists = Skill(name: "gaca-lists", description: "Add to or read your lists", category: "Organize", useCount: 9)
    private let calendar = Skill(name: "google-calendar", description: "Read and edit your calendar", category: "Calendar")
    private let suggestions = Skill(name: "calendar-suggestions", description: "Turns emails into proposed events", category: "Calendar")
    private var all: [Skill] { [lists, calendar, suggestions] }

    func testABareSlashWordIsAQueryAnythingElseIsNot() {
        XCTAssertEqual(SkillCommand.slashQuery("/"), "")
        XCTAssertEqual(SkillCommand.slashQuery("/cal"), "cal")
        XCTAssertNil(SkillCommand.slashQuery("/cal now"))
        XCTAssertNil(SkillCommand.slashQuery("hello"))
    }

    func testNamesStartingWithTheQueryComeFirst() {
        XCTAssertEqual(Array(SkillCommand.match(all, query: "cal").prefix(2)), [suggestions, calendar])
        XCTAssertEqual(SkillCommand.match(all, query: ""), all)
        XCTAssertEqual(SkillCommand.match(all, query: "LISTS"), [lists])
    }

    func testDescriptionMatchesCount() {
        XCTAssertEqual(SkillCommand.match(all, query: "emails"), [suggestions])
    }

    func testPickingASkillPutsItsCommandFirstAndKeepsTheRest() {
        XCTAssertEqual(SkillCommand.insert(lists, into: ""), "/gaca-lists ")
        XCTAssertEqual(SkillCommand.insert(lists, into: "add milk"), "/gaca-lists add milk")
        XCTAssertEqual(SkillCommand.insert(lists, into: "/cal"), "/gaca-lists ")
        XCTAssertEqual(SkillCommand.insert(lists, into: "/cal add milk"), "/gaca-lists add milk")
    }

    func testALeadingSkillCommandIsSentAsThePlainRequest() {
        XCTAssertEqual(SkillCommand.expand("/gaca-lists add milk", skills: all), "Use the gaca-lists skill: add milk")
        XCTAssertEqual(SkillCommand.expand("/gaca-lists", skills: all), "Use the gaca-lists skill.")
        XCTAssertEqual(SkillCommand.expand("/GACA-LISTS   add milk", skills: all), "Use the gaca-lists skill: add milk")
    }

    func testTextThatIsNotAKnownSkillCommandGoesThroughUntouched() {
        XCTAssertEqual(SkillCommand.expand("/nonsense add milk", skills: all), "/nonsense add milk")
        XCTAssertEqual(SkillCommand.expand("what is /gaca-lists", skills: all), "what is /gaca-lists")
    }

    func testSkillsGroupByCategoryWithTheUncategorizedLast() {
        let loose = Skill(name: "misc", description: "", category: nil)
        let grouped = SkillCommand.grouped([loose, lists, calendar, suggestions])
        XCTAssertEqual(grouped.map(\.category), ["Organize", "Calendar", "Other"])
        XCTAssertEqual(grouped[1].skills, [calendar, suggestions])
    }

    func testDecodesSkillUseCountAndOlderServers() throws {
        let json = """
        [{"name":"a","description":"x","category":null,"use_count":4,"last_used_at":"2026-10-10T15:00:00+00:00"},
         {"name":"b","description":"y","category":"c"}]
        """
        let skills = try APIClient.decoder.decode([Skill].self, from: Data(json.utf8))
        XCTAssertEqual(skills.map(\.useCount), [4, nil])
    }
}
