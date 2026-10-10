import SwiftUI

/// Every past chat, searchable and filterable by crew member, grouped by when.
struct ChatHistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var sessions: [Session] = []
    @State private var query = ""
    @State private var crewFilter: String?
    @State private var loading = true
    @State private var error: String?

    private var filtered: [Session] {
        sessions.filter { s in
            (crewFilter == nil || s.crew == crewFilter) && (query.isEmpty || [s.summary, s.title, s.preview, s.crew]
                .compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    private var groups: [(String, [Session])] {
        let cal = Calendar.current
        let weekAgo = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: .now))!
        var today: [Session] = [], week: [Session] = [], earlier: [Session] = []
        for s in filtered {
            if cal.isDateInToday(s.activityDate) { today.append(s) }
            else if s.activityDate >= weekAgo { week.append(s) }
            else { earlier.append(s) }
        }
        return [("Today", today), ("This week", week), ("Earlier", earlier)].filter { !$0.1.isEmpty }
    }

    var body: some View {
        List {
            if model.crew.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        AllPill(title: "All", selected: crewFilter == nil) { crewFilter = nil }
                        ForEach(model.crew) { member in
                            CrewPill(name: member.name, style: member.style, selected: crewFilter == member.name) {
                                crewFilter = crewFilter == member.name ? nil : member.name
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if let error { ErrorLine(text: error).listRowBackground(Color.clear) }
            if loading && sessions.isEmpty {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if filtered.isEmpty {
                EmptyState(title: sessions.isEmpty ? "No conversations yet." : (query.isEmpty ? "No chats with this crew member." : "No chats match \u{201C}\(query)\u{201D}."))
                    .listRowBackground(Color.clear)
            }
            ForEach(groups, id: \.0) { title, items in
                Section {
                    ForEach(items) { session in
                        NavigationLink(value: Route.thread(session.id)) {
                            SessionRow(session: session, style: model.style(for: session.crew))
                        }
                    }
                } header: { SectionLabel(text: title) }
            }
        }
        .listStyle(.insetGrouped)
        .gacaPage()
        .navigationTitle("History")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search chats")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            sessions = try await model.api.sessions()
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
