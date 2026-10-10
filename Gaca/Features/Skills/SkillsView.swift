import SwiftUI

/// What each crew member can actually do — live from its own Hermes. Tap a skill to start
/// a chat that uses it.
struct SkillsView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: String?
    @State private var skills: [Skill] = []
    @State private var query = ""
    @State private var loading = true
    @State private var error: String?
    @State private var starting: String?

    private var member: CrewMember? { model.crew.first { $0.name == selected } ?? model.defaultCrew }

    private var groups: [(String, [Skill])] {
        let shown = query.isEmpty ? skills : skills.filter { $0.name.localizedCaseInsensitiveContains(query) }
        let grouped = Dictionary(grouping: shown) { $0.category ?? "" }
        return grouped.keys.sorted { a, b in
            if a.isEmpty { return false }
            if b.isEmpty { return true }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }.map { ($0.isEmpty ? "Other" : $0, grouped[$0]!.sorted { $0.name < $1.name }) }
    }

    var body: some View {
        List {
            if model.crew.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.crew) { m in
                            CrewPill(name: m.name, style: m.style, selected: m.name == member?.name, showAvatar: true) {
                                selected = m.name
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if let error { ErrorLine(text: error).listRowBackground(Color.clear) }
            if model.crew.isEmpty && !loading {
                EmptyState(title: "No crew configured yet — set one up in Settings first.").listRowBackground(Color.clear)
            } else if loading && skills.isEmpty {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if groups.isEmpty, let member {
                EmptyState(title: query.isEmpty ? "\(crewDisplayName(member.name)) has no skills installed right now." : "No skills match \u{201C}\(query)\u{201D}.")
                    .listRowBackground(Color.clear)
            }
            ForEach(groups, id: \.0) { category, items in
                Section {
                    ForEach(items) { skill in
                        Button { start(skill) } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(skill.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                                    if let d = skill.description, !d.isEmpty {
                                        Text(d).font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                if starting == skill.name { ProgressView() }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(starting != nil)
                        .accessibilityHint("Starts a chat that uses this skill")
                    }
                } header: { SectionLabel(text: category) }
            }
            if !skills.isEmpty, let member {
                Text("Tap a skill to start a chat that uses it. Skills live in Hermes — this list comes live from \(crewDisplayName(member.name))'s own Hermes.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .gacaPage()
        .navigationTitle("Skills")
        .searchable(text: $query, prompt: member.map { "Search \(crewDisplayName($0.name))'s skills" } ?? "Search skills")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
        .refreshable { await load() }
        .task(id: member?.name) { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            if model.crew.isEmpty { try await model.refreshCrew() }
            guard let member else { skills = []; return }
            skills = try await model.api.skills(member.name)
            error = nil
        } catch is CancellationError {
        } catch {
            skills = []
            self.error = error.localizedDescription
        }
    }

    private func start(_ skill: Skill) {
        guard let member else { return }
        starting = skill.name
        Task {
            defer { starting = nil }
            do {
                let session = try await model.api.createSession(crew: member.name)
                model.push(.thread(session.id, draft: "Use the \(skill.name) skill: "))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
