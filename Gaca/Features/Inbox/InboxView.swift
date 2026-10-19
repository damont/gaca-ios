import SwiftUI

/// Triage: what needs you, what's snoozed or delegated, and what's done.
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: InboxTab = .attention
    @State private var crewFilter: String?
    @State private var alerts: [Alert] = []
    @State private var loading = true
    @State private var error: String?
    @State private var composing = false

    enum InboxTab: String, CaseIterable, Identifiable {
        case attention = "Attention", snoozed = "Snoozed", delegated = "Delegated", history = "History"
        var id: String { rawValue }
        var statuses: [String] {
            switch self {
            case .attention: return ["new", "completed"]
            case .snoozed: return ["snoozed"]
            case .delegated: return ["delegated"]
            case .history: return ["acted", "dismissed"]
            }
        }
        var swipeable: Bool { self == .attention || self == .snoozed }
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $tab) {
                    ForEach(InboxTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)

                if model.crew.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            AllPill(title: "All crew", selected: crewFilter == nil) { crewFilter = nil }
                            ForEach(model.crew) { member in
                                CrewPill(name: member.name, style: member.style, selected: crewFilter == member.name) {
                                    crewFilter = crewFilter == member.name ? nil : member.name
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
            .listRowSeparator(.hidden)

            if let error {
                ErrorLine(text: error).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }

            if loading && alerts.isEmpty {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else if alerts.isEmpty {
                Group {
                    if tab == .attention {
                        EmptyState(mark: .wingsDown, title: "Nothing needs you right now",
                                   message: "Hermes is watching. You'll hear from it when something does.")
                    } else {
                        EmptyState(title: "Nothing \(tab.rawValue.lowercased()) right now.")
                    }
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }

            ForEach(alerts) { alert in
                AlertRow(alert: alert, style: model.style(for: alert.crew))
                    .background(NavigationLink("", value: Route.alert(alert.id)).opacity(0))
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if tab.swipeable {
                            Button { resolve(alert, act: true) } label: { Label("Handled", systemImage: "checkmark") }
                                .tint(Palette.accent)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if tab.swipeable {
                            Button { resolve(alert, act: false) } label: { Label("Ignore", systemImage: "xmark") }
                                .tint(Color(hex: "#7A838C"))
                        }
                    }
            }

            if tab == .attention && !alerts.isEmpty {
                Text("Swipe right when it's handled, left to ignore")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .gacaPage()
        .navigationTitle("Alerts")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { composing = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("Start a delegation")
                SettingsButton()
            }
        }
        .sheet(isPresented: $composing, onDismiss: { Task { await load() } }) {
            NewDelegationSheet()
        }
        .refreshable { await load() }
        .task(id: "\(tab.rawValue)|\(crewFilter ?? "")") { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            if model.crew.isEmpty { try? await model.refreshCrew() }
            alerts = try await model.api.alerts(statuses: tab.statuses, crew: crewFilter)
            if tab == .attention && crewFilter == nil { model.inboxCount = alerts.count }
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resolve(_ alert: Alert, act: Bool) {
        withAnimation { alerts.removeAll { $0.id == alert.id } }
        Task {
            do {
                _ = act ? try await model.api.act(alert.id, note: nil) : try await model.api.dismiss(alert.id, note: nil)
            } catch {
                self.error = error.localizedDescription
            }
            await load()
        }
    }
}

struct AlertRow: View {
    let alert: Alert
    let style: CrewStyle

    var body: some View {
        let severity = SeverityStyle.of(alert.severity)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(severity.dot).frame(width: 9, height: 9).padding(.top, 6)
                Text(alert.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    if !(alert.links ?? []).isEmpty {
                        Image(systemName: "link").accessibilityLabel("Has a link")
                    }
                    if alert.artifactId != nil {
                        Image(systemName: "square.grid.2x2").accessibilityLabel("Has a page")
                    }
                    Text(RelativeTime.short(alert.createdAt))
                }
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
            }
            if let body = alert.body {
                Text(body)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#4F565E"))
                    .lineLimit(2)
                    .padding(.leading, 19)
            }
            HStack(spacing: 6) {
                Text(alert.kind)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#4F565E"))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.6)))
                if let crew = alert.crew { CrewTag(name: crew, style: style) }
                if alert.effectiveStatus == "completed" {
                    Text("\(alert.crew.map(crewDisplayName) ?? "Hermes") replied")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "#4F565E"))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(severity.dot.opacity(0.25)))
                }
            }
            .padding(.leading, 19)
            .padding(.top, 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(severity.background))
        .accessibilityElement(children: .combine)
    }
}
