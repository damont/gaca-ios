import SwiftUI

/// The sheet behind the composer's sparkle button: the few most used (the list arrives most used
/// first), search, and "See all skills" for the full list grouped by category. Searching also
/// switches to the grouped list, filtered.
struct SkillsSheet: View {
    let skills: [Skill]
    let onPick: (Skill) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showAll = false
    @State private var detent: PresentationDetent = .medium

    static let topCount = 5

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            List {
                if searching || showAll {
                    let shown = searching ? SkillCommand.match(skills, query: query) : skills
                    if shown.isEmpty {
                        Text("No skill matches \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}.")
                            .foregroundStyle(Palette.textMeta)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(SkillCommand.grouped(shown), id: \.category) { group in
                        Section {
                            ForEach(group.skills) { row($0) }
                        } header: { SectionLabel(text: group.category) }
                    }
                } else if skills.isEmpty {
                    Text("No skills to show yet.").foregroundStyle(Palette.textMeta).listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(skills.prefix(Self.topCount)) { row($0) }
                    } header: { SectionLabel(text: skills.contains { ($0.useCount ?? 0) > 0 } ? "Most used" : "Skills") }
                    if skills.count > Self.topCount {
                        Button {
                            showAll = true
                            detent = .large
                        } label: {
                            Text("See all skills").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity)
                        }
                        .foregroundStyle(Palette.accent)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .gacaPage()
            .navigationTitle(showAll && !searching ? "All skills" : "Skills")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search skills")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .onChange(of: query) { _, _ in if searching { detent = .large } }
    }

    private func row(_ skill: Skill) -> some View {
        Button { onPick(skill) } label: { SkillRow(skill: skill) }
            .buttonStyle(.plain)
    }
}

/// The "/" picker: a short card above the composer listing the skills that match what follows the slash.
struct SlashSkillList: View {
    let skills: [Skill]
    let query: String
    let onPick: (Skill) -> Void
    let onSeeAll: () -> Void

    var body: some View {
        let matches = Array(SkillCommand.match(skills, query: query).prefix(4))
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(text: "Skills").padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 2)
                ForEach(matches) { skill in
                    Button { onPick(skill) } label: {
                        SkillRow(skill: skill, slash: true).padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }
                Button("See all skills ›", action: onSeeAll)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.border, lineWidth: 0.5))
            .shadow(color: Palette.accent.opacity(0.12), radius: 10, y: 4)
        }
    }
}

private struct SkillRow: View {
    let skill: Skill
    var slash = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.suggest))
            VStack(alignment: .leading, spacing: 1) {
                Text(slash ? "/\(skill.name)" : skill.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if let d = skill.description, !d.isEmpty {
                    Text(d).font(.system(size: 14)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}
