import SwiftUI

struct AlertDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let alertId: String

    @State private var alert: Alert?
    @State private var error: String?
    @State private var note = ""
    @State private var chosenCrew: String?
    @State private var working = false

    private var crewForChat: String? { alert?.crew ?? chosenCrew ?? model.defaultCrew?.name }

    var body: some View {
        Group {
            if let alert {
                content(alert)
            } else if let error {
                EmptyState(systemImage: "exclamationmark.triangle", title: "Couldn't load this alert", message: error)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.page)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let alert, ["new", "completed", "snoozed"].contains(alert.effectiveStatus) {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("1 hour") { snooze(hours: 1) }
                        Button("3 hours") { snooze(hours: 3) }
                        Button("Tomorrow, 9am") { snoozeTomorrow() }
                    } label: {
                        Label("Snooze", systemImage: "alarm")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func content(_ alert: Alert) -> some View {
        let severity = SeverityStyle.of(alert.severity)
        let crewStyle = model.style(for: alert.crew)
        let open = ["new", "completed", "snoozed", "delegated"].contains(alert.effectiveStatus)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(severity.dot).frame(width: 9, height: 9)
                        Text(severity.label)
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(severity.ink)
                    Text(alert.kind)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#4F565E"))
                        .padding(.horizontal, 9).padding(.vertical, 2)
                        .background(Capsule().fill(Palette.field))
                    if let crew = alert.crew { CrewTag(name: crew, style: crewStyle) }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(alert.title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                    Text("from \(alert.source) · \(RelativeTime.ago(alert.createdAt))")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textSecondary)
                }

                if let body = alert.body {
                    Text(body)
                        .font(.system(size: 17))
                        .lineSpacing(3)
                        .foregroundStyle(Color(hex: "#3E454C"))
                        .textSelection(.enabled)
                }

                if let ref = alert.artifact {
                    ArtifactCard(ref: ref, style: model.style(for: ref.crew ?? alert.crew)) { model.push(.artifact(ref.id)) }
                }

                if let links = alert.links, !links.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(links.enumerated()), id: \.offset) { index, link in
                            Button {
                                if let url = URL(string: link.url) { openURL(url) }
                            } label: {
                                HStack {
                                    Text(link.label ?? link.url).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Palette.accent)
                                .padding(.horizontal, 14).frame(minHeight: 46)
                            }
                            if index < links.count - 1 { Divider().overlay(Palette.divider).padding(.leading, 14) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))
                }

                if let resolution = alert.resolutionNote {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Note")
                        Text(resolution).font(.system(size: 16)).foregroundStyle(Palette.textPrimary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Palette.chip))
                }

                if let rows = alert.dataRows, !rows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            HStack(alignment: .top) {
                                Text(row.key).foregroundStyle(Palette.textSecondary)
                                Spacer(minLength: 12)
                                Text(row.value).multilineTextAlignment(.trailing).foregroundStyle(Palette.textPrimary)
                            }
                            .font(.system(size: 15))
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            if index < rows.count - 1 { Divider().overlay(Palette.divider) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))
                }

                if let actions = alert.suggestedActions, !actions.isEmpty, open {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Hermes suggests").padding(.horizontal, 2)
                        ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                            Button { takeToChat(actionIndex: index) } label: {
                                HStack {
                                    Text(action.label).multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Palette.onSuggest)
                                .padding(.horizontal, 14).frame(minHeight: 46)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.suggest))
                            }
                            .disabled(working)
                        }
                    }
                }

                if alert.sessionId == nil, alert.crew == nil, model.crew.count > 1, open {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Crew").padding(.horizontal, 2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(model.crew) { member in
                                    CrewPill(name: member.name, style: member.style, selected: crewForChat == member.name, showAvatar: true) {
                                        chosenCrew = member.name
                                    }
                                }
                            }
                        }
                    }
                }

                if open {
                    TextField("Add a note (optional)", text: $note, axis: .vertical)
                        .font(.system(size: 16))
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))
                }

                if let error { ErrorLine(text: error) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if open { actionBar(alert) }
        }
    }

    private func actionBar(_ alert: Alert) -> some View {
        let crewStyle = model.style(for: crewForChat)
        return VStack(spacing: 10) {
            Button {
                if let sessionId = alert.sessionId { model.push(.thread(sessionId)) } else { takeToChat(actionIndex: nil) }
            } label: {
                HStack(spacing: 8) {
                    if working { ProgressView().tint(.white) } else { Image(systemName: "bubble.left") }
                    Text(alert.sessionId == nil
                         ? "Chat with \(crewForChat.map(crewDisplayName) ?? "your crew") about this"
                         : "Open the chat")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(RoundedRectangle(cornerRadius: 14).fill(crewStyle.solid))
            }
            .disabled(working)
            HStack(spacing: 10) {
                Button { resolve(act: false) } label: {
                    Text("Ignore")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.field))
                }
                Button { resolve(act: true) } label: {
                    Label("I handled it", systemImage: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.accent))
                }
            }
            .disabled(working)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        .background(.bar)
    }

    private func load() async {
        do {
            if model.crew.isEmpty { try? await model.refreshCrew() }
            alert = try await model.api.alert(alertId)
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        working = true
        error = nil
        Task {
            defer { working = false }
            do { try await work() } catch { self.error = error.localizedDescription }
        }
    }

    private func resolve(act: Bool) {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        run {
            _ = act ? try await model.api.act(alertId, note: text.isEmpty ? nil : text)
                    : try await model.api.dismiss(alertId, note: text.isEmpty ? nil : text)
            await model.refreshInboxCount()
            dismiss()
        }
    }

    private func snooze(hours: Int) {
        run {
            _ = try await model.api.snooze(alertId, until: Date.now.addingTimeInterval(TimeInterval(hours * 3600)))
            await model.refreshInboxCount()
            dismiss()
        }
    }

    private func snoozeTomorrow() {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now))!
        let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
        run {
            _ = try await model.api.snooze(alertId, until: nine)
            await model.refreshInboxCount()
            dismiss()
        }
    }

    /// The API opens (or reuses) the alert's chat and drafts the first message; nothing is
    /// sent until the user sends it from the thread.
    private func takeToChat(actionIndex: Int?) {
        run {
            let out = try await model.api.takeToChat(alertId, AlertTakeToChat(suggestedActionIndex: actionIndex, crew: alert?.crew == nil ? crewForChat : nil))
            model.push(.thread(out.sessionId, draft: out.draft))
        }
    }
}
