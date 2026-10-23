import SwiftUI

/// The Automations tab: what the crew does on a schedule, whether the last run worked, and
/// when it runs next. Read live each visit (the API never caches it).
struct AutomationsView: View {
    @Environment(AppModel.self) private var model
    @State private var list: AutomationList?
    @State private var loading = true
    @State private var error: String?
    @State private var filter: Filter = .all

    enum Filter: CaseIterable { case all, failing, paused
        var label: String {
            switch self {
            case .all: return "All"
            case .failing: return "Failing"
            case .paused: return "Paused"
            }
        }
    }

    private var automations: [Automation] { list?.automations ?? [] }
    private var failingCount: Int { automations.filter(\.needsAttention).count }
    private var pausedCount: Int { automations.filter { $0.state == .paused }.count }

    private var shown: [Automation] {
        switch filter {
        case .all: return automations
        case .failing: return automations.filter(\.needsAttention)
        case .paused: return automations.filter { $0.state == .paused }
        }
    }

    private func count(_ f: Filter) -> Int {
        switch f {
        case .all: return automations.count
        case .failing: return failingCount
        case .paused: return pausedCount
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if list != nil && error == nil {
                    let n = automations.count
                    Text("\(n) \(n == 1 ? "job" : "jobs")" + (failingCount > 0 ? " · \(failingCount) need\(failingCount == 1 ? "s" : "") attention" : ""))
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 4)
                }
                if !automations.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases, id: \.self) { f in
                            Button { filter = f } label: {
                                Text("\(f.label) \(count(f))")
                                    .font(.system(size: 14, weight: filter == f ? .semibold : .regular))
                                    .foregroundStyle(filter == f ? Palette.onAccent : Palette.textPrimary)
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 36)
                                    .background(Capsule().fill(filter == f ? Palette.accent : Palette.chip))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(filter == f ? .isSelected : [])
                        }
                    }
                }
                if let error { ErrorLine(text: error) }
                if let unavailable = list?.unavailable, !unavailable.isEmpty {
                    ErrorLine(text: "Couldn't read \(unavailable.map(crewDisplayName).joined(separator: ", "))'s automations right now.")
                }
                if loading && list == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if shown.isEmpty && error == nil {
                    if automations.isEmpty {
                        EmptyState(mark: .wingsDown, title: "No automations yet",
                                   message: "Ask a crew member in chat to do something on a schedule.")
                    } else {
                        EmptyState(title: "Nothing here.")
                    }
                }
                ForEach(shown, id: \.key) { a in
                    NavigationLink(value: Route.automation(crew: a.owner, id: a.id)) {
                        AutomationCard(automation: a, style: model.style(for: a.crew))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Palette.page)
        .navigationTitle("Automations")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
        .refreshable { await load() }
        // Jobs run on their own, so look again on every visit.
        .onAppear { Task { await load() } }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            if model.crew.isEmpty { try? await model.refreshCrew() }
            list = try await model.api.automations()
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension Automation {
    /// Ids are only unique per crew member.
    var key: String { "\(owner)/\(id)" }
}

private struct AutomationCard: View {
    let automation: Automation
    let style: CrewStyle

    var body: some View {
        let a = automation
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(a.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                StatusPill(status: a.state)
            }
            HStack(spacing: 6) {
                if let crew = a.crew, !crew.isEmpty {
                    Text(crewDisplayName(crew)).fontWeight(.semibold).foregroundStyle(style.ink)
                    Text("·").foregroundStyle(Palette.textMeta)
                }
                Text(a.schedule).foregroundStyle(Palette.textSecondary)
            }
            .font(.system(size: 15))
            .padding(.top, 2)
            RunDots(recent: a.marks).padding(.top, 12)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(WhenText.lastRun(a))
                Spacer(minLength: 0)
                if let next = a.nextRun { Text("Next \(WhenText.dayAndTime(next))") }
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.textSecondary)
            .padding(.top, 10)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(a.needsAttention ? SeverityStyle.of("urgent").dot : Palette.border,
                                                            lineWidth: a.needsAttention ? 1.5 : 0.5))
        .contentShape(Rectangle())
    }
}
