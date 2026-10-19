import Foundation

/// Skills in the composer: typing `/` lists them, picking one puts `/skill-name ` at the start
/// of the message, and sending turns that into the plain request the crew member has always read.
/// Mirrors gaca-android's ui/skills/SkillCommand.kt.
enum SkillCommand {
    /// What's typed after the leading "/", or nil when the message isn't just a bare `/word` so far.
    static func slashQuery(_ text: String) -> String? {
        guard text.hasPrefix("/") else { return nil }
        let rest = text.dropFirst()
        return rest.contains(where: \.isWhitespace) ? nil : String(rest)
    }

    /// The skills to list for `query`: names starting with it first, then names or descriptions containing it.
    static func match(_ skills: [Skill], query: String) -> [Skill] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return skills }
        let starts = skills.filter { $0.name.lowercased().hasPrefix(q) }
        let contains = skills.filter { s in
            !starts.contains(s) && (s.name.lowercased().contains(q) || (s.description ?? "").lowercased().contains(q))
        }
        return starts + contains
    }

    /// Puts `/name ` at the start of `text`, replacing a `/word` already there; the rest of the message stays.
    static func insert(_ skill: Skill, into text: String) -> String {
        var rest = Substring(text)
        if text.hasPrefix("/") {
            rest = text.firstIndex(of: " ").map { text[text.index(after: $0)...] } ?? ""
        }
        return "/\(skill.name) " + rest.drop(while: \.isWhitespace)
    }

    /// What actually gets sent: a leading `/skill-name rest` becomes "Use the skill-name skill: rest",
    /// the same request a tapped skill always produced. Anything that doesn't start with `/` and one of
    /// this crew member's skills goes through untouched.
    static func expand(_ text: String, skills: [Skill]) -> String {
        guard text.hasPrefix("/") else { return text }
        let name = text.dropFirst().prefix { !$0.isWhitespace }
        guard let skill = skills.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return text }
        let rest = text.dropFirst(1 + name.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? "Use the \(skill.name) skill." : "Use the \(skill.name) skill: \(rest)"
    }

    /// Category → its skills, in the order the list arrived; skills with no category come last as "Other".
    static func grouped(_ skills: [Skill]) -> [(category: String, skills: [Skill])] {
        var order: [String] = []
        var byCategory: [String: [Skill]] = [:]
        var other: [Skill] = []
        for skill in skills {
            guard let category = skill.category, !category.trimmingCharacters(in: .whitespaces).isEmpty else {
                other.append(skill)
                continue
            }
            if byCategory[category] == nil { order.append(category) }
            byCategory[category, default: []].append(skill)
        }
        var groups = order.map { (category: $0, skills: byCategory[$0]!) }
        if !other.isEmpty { groups.append((category: "Other", skills: other)) }
        return groups
    }
}
