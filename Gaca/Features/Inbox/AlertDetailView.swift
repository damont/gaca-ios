import SwiftUI

/// One alert. This screen only shows what the API says (`alert.actions`, `alert.workflow`) and sends the
/// taps back: which actions can be tapped, what they read as, which buttons close the alert, and what the
/// status line says are all the API's decisions, so every app behaves the same (gaca-android AlertDetailScreen).
struct AlertDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    let alertId: String

    @State private var alert: Alert?
    @State private var error: String?
    /// True while an action tap is being sent.
    @State private var busy = false
    @State private var openingChat = false
    @State private var closing = false

    /// Read the alert again every few seconds while the API says an action is running.
    private static let pollInterval: Duration = .seconds(3)

    private var working: Bool { alert?.flow.currentPhase == "working" }

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
        // Runs on every appear, so coming back from the chat reads the alert again (it may have moved).
        .task { await load() }
        // Polls only while an action runs; stops once the API says it settled, and on leaving the screen.
        .task(id: working) {
            guard working else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                if Task.isCancelled { return }
                guard let fresh = try? await model.api.alert(alertId) else { continue }
                alert = fresh
                if fresh.flow.currentPhase != "working" { return }
            }
        }
        // Coming back from the mail app: read it again.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private func content(_ alert: Alert) -> some View {
        let flow = alert.flow
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error { ErrorLine(text: error) }

                statusRow(alert)

                VStack(alignment: .leading, spacing: 6) {
                    Text(alert.title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                    Text("from \(alert.source) · \(RelativeTime.ago(alert.createdAt))")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textSecondary)
                }

                if let body = alert.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(body)
                        .font(.system(size: 17))
                        .lineSpacing(3)
                        .foregroundStyle(Color(hex: "#3E454C"))
                        .textSelection(.enabled)
                }

                if let ref = alert.artifact {
                    ArtifactCard(ref: ref, style: model.style(for: ref.crew ?? alert.crew)) { model.push(.artifact(ref.id)) }
                }

                if !alert.webLinks.isEmpty { linkList(alert.webLinks) }

                if let rows = alert.dataRows, !rows.isEmpty { dataRows(rows) }

                if !alert.actionList.isEmpty { actionsSection(alert) }

                chatEntry(alert)

                if !flow.closeChoices.isEmpty {
                    closeSection(flow)
                } else if let note = flow.closedNote {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
                        Text(note).font(.system(size: 15))
                    }
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable { await refresh() }
    }

    // MARK: Status

    /// Where the alert stands when the API has something to say (else its severity), plus kind and crew chips.
    private func statusRow(_ alert: Alert) -> some View {
        let flow = alert.flow
        let severity = SeverityStyle.of(alert.severity)
        return HStack(spacing: 8) {
            if let label = flow.phaseLabel {
                let closed = flow.currentPhase == "closed"
                let colors: (bg: Color, ink: Color) = switch flow.currentPhase {
                case "closed": alert.status == "done_by_gaca" ? (Palette.successBg, Palette.successInk) : (Palette.chip, Palette.textSecondary)
                case "waiting_on_you": (Palette.suggest, Palette.accent)
                default: (Palette.chip, Palette.textSecondary)
                }
                let when = closed ? alert.statusChangedAt.map { " · \(RelativeTime.ago($0))" } ?? "" : ""
                Text(label + when)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.ink)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 10).fill(colors.bg))
            } else {
                HStack(spacing: 6) {
                    Circle().fill(severity.dot).frame(width: 9, height: 9)
                    Text(severity.label)
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(severity.ink)
            }
            Text(alert.kind)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#4F565E"))
                .padding(.horizontal, 9).padding(.vertical, 2)
                .background(Capsule().fill(Palette.field))
                .lineLimit(1)
            // Which crew member posted this: also who the chat opens with.
            if let crew = alert.crew { CrewTag(name: crew, style: model.style(for: crew), removed: alert.isCrewRemoved) }
        }
    }

    private func linkList(_ links: [AlertLink]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(links.enumerated()), id: \.offset) { index, link in
                Button {
                    if let url = URL(string: link.url) { openURL(url) }
                } label: {
                    HStack {
                        Text(link.title).lineLimit(1)
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

    private func dataRows(_ rows: [Alert.DataRow]) -> some View {
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

    // MARK: Actions

    private func actionsSection(_ alert: Alert) -> some View {
        let flow = alert.flow
        // The big "Add all" button is only for one still to tap or running; once it has finished or failed
        // it reads like any other row (a result, not a dead button).
        let isBig: (AlertAction) -> Bool = { $0.isProminent && ($0.runState == "idle" || $0.runState == "running") }
        let big = alert.actionList.filter(isBig)
        let rows = alert.actionList.filter { !isBig($0) }
        return VStack(alignment: .leading, spacing: 10) {
            if flow.actionsHeading != nil || flow.progressLabel != nil {
                HStack {
                    if let heading = flow.actionsHeading { SectionLabel(text: heading) }
                    Spacer()
                    if let progress = flow.progressLabel {
                        Text(progress)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.successInk)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.successBg))
                    }
                }
                .padding(.horizontal, 2)
            }
            ForEach(rows) { actionRow($0) }
            ForEach(big) { bigActionButton($0) }
        }
    }

    @ViewBuilder
    private func actionRow(_ action: AlertAction) -> some View {
        switch action.runState {
        case "running":
            rowCard(Palette.suggest) {
                tile(Palette.page) { ProgressView().tint(Palette.accent) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                    if let note = action.note {
                        Text(note).font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case "done":
            let result = action.result
            VStack(alignment: .leading, spacing: 10) {
                rowCard(Palette.successBg) {
                    tile(Palette.successDot) {
                        Image(systemName: "checkmark").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.onAccent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.label).font(.system(size: 15, weight: .semibold))
                        if let summary = result?.summary { Text(summary).font(.system(size: 14)) }
                    }
                    .foregroundStyle(Palette.successInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let link = result?.links?.first(where: \.isWeb), let url = URL(string: link.url) {
                        Button { openURL(url) } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 17))
                                .foregroundStyle(Palette.successInk)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Open \(link.title)")
                    }
                }
                // No title: the row right above already says what it is.
                if let draft = result?.draft { DraftCard(draft: draft, title: nil) }
            }
        case "failed":
            let urgent = SeverityStyle.of("urgent")
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 12) {
                    tile(Palette.urgentInk) {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 18, weight: .semibold)).foregroundStyle(urgent.background)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Couldn't: \(action.label)").font(.system(size: 15, weight: .semibold))
                        if let message = action.result?.error { Text(message).font(.system(size: 14)) }
                    }
                    .foregroundStyle(Palette.urgentInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { run(action.index) } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.urgentInk)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .overlay(Capsule().stroke(Palette.urgentInk, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .disabled(!action.runnable || busy)
                .opacity(action.runnable ? 1 : 0.55)
            }
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 12, trailing: 12))
            .background(RoundedRectangle(cornerRadius: 14).fill(urgent.background))
        default:
            Button { run(action.index) } label: {
                rowCard(Palette.suggest) {
                    tile(Palette.page) {
                        Image(systemName: Self.icon(for: action.kind)).font(.system(size: 17)).foregroundStyle(Palette.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                        if let detail = action.detail {
                            Text(detail).font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    Text(action.button)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 13).padding(.vertical, 5)
                        .overlay(Capsule().stroke(Palette.accent, lineWidth: 1.5))
                }
            }
            .buttonStyle(.plain)
            .disabled(!action.runnable || busy)
            .opacity(action.runnable ? 1 : 0.55)
        }
    }

    private func bigActionButton(_ action: AlertAction) -> some View {
        Button { run(action.index) } label: {
            HStack(spacing: 8) {
                if action.runState == "running" {
                    ProgressView().tint(Palette.onAccent)
                } else {
                    Image(systemName: "plus")
                    Text(action.label)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.accent))
        }
        .buttonStyle(.plain)
        .disabled(!action.runnable || busy)
        .opacity(action.runnable && !busy ? 1 : 0.55)
    }

    private func rowCard<Content: View>(_ background: Color, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) { content() }
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 12))
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(background))
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private func tile<Content: View>(_ background: Color, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 10).fill(background))
    }

    private static func icon(for kind: String?) -> String {
        guard let kind else { return "checkmark.circle" }
        if kind.hasPrefix("calendar") { return "calendar" }
        if kind.hasPrefix("email") { return "envelope" }
        return "checkmark.circle"
    }

    // MARK: Chat and close

    /// "Chat about this": the chat already carries the alert, so this just opens it.
    private func chatEntry(_ alert: Alert) -> some View {
        let flow = alert.flow
        let prominent = flow.chatProminent
        return Button { openChat() } label: {
            HStack(spacing: 12) {
                Group {
                    if openingChat {
                        ProgressView().tint(prominent ? Palette.onAccent : Palette.accent)
                    } else {
                        Image(systemName: "bubble.left").font(.system(size: 19))
                    }
                }
                .foregroundStyle(prominent ? Palette.onAccent : Palette.accent)
                .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat about this")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(prominent ? Palette.onAccent : Palette.textPrimary)
                    if !flow.chatHint.isEmpty {
                        Text(flow.chatHint)
                            .font(.system(size: 14))
                            .foregroundStyle(prominent ? Palette.suggest : Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(prominent ? Palette.onAccent : Palette.textSecondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 14).fill(Palette.accent)
                } else {
                    RoundedRectangle(cornerRadius: 14).stroke(Palette.border, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(openingChat)
    }

    /// The buttons the API offers for closing the alert, and its note on what closing means.
    private func closeSection(_ flow: AlertWorkflow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Palette.border).frame(height: 1)
            if let heading = flow.closeHeading { SectionLabel(text: heading).padding(.top, 4) }
            HStack(spacing: 8) {
                ForEach(flow.closeChoices, id: \.reason) { option in
                    let primary = option.primary ?? false
                    Button { close(option.reason) } label: {
                        Text(option.label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(primary ? Palette.accent : Palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background {
                                if primary {
                                    RoundedRectangle(cornerRadius: 14).stroke(Palette.accent, lineWidth: 1.5)
                                } else {
                                    RoundedRectangle(cornerRadius: 14).fill(Palette.chip)
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(closing)
                }
            }
            if let hint = flow.closeHint {
                Text(hint).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Taps

    private func load() async {
        do {
            if model.crew.isEmpty { try? await model.refreshCrew() }
            alert = try await model.api.alert(alertId)
            error = nil
        } catch is CancellationError {
        } catch {
            // Keep what is on screen if there is something; the message shows above it.
            self.error = error.localizedDescription
        }
    }

    /// Read it again, keeping what is on screen if that fails.
    private func refresh() async {
        if let fresh = try? await model.api.alert(alertId) { alert = fresh }
    }

    /// A 409 means it moved underneath us (closed, or something else is running): read it again.
    private static func isStale(_ error: Error) -> Bool { (error as? APIError)?.status == 409 }

    private func run(_ index: Int) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                alert = try await model.api.runAlertAction(alertId, index: index)
            } catch {
                if Self.isStale(error) { await refresh() } else { self.error = error.localizedDescription }
            }
        }
    }

    private func close(_ reason: String) {
        guard !closing else { return }
        closing = true
        error = nil
        Task {
            defer { closing = false }
            do {
                _ = try await model.api.closeAlert(alertId, reason: reason)
                await model.refreshInboxCount()
                dismiss()
            } catch {
                if Self.isStale(error) { await refresh() } else { self.error = error.localizedDescription }
            }
        }
    }

    /// The API opens (or reuses) the alert's chat; the chat carries the alert, so the box starts empty
    /// unless the API gave a draft.
    private func openChat() {
        guard !openingChat else { return }
        openingChat = true
        error = nil
        Task {
            defer { openingChat = false }
            do {
                let out = try await model.api.takeToChat(alertId, AlertTakeToChat())
                alert = out.alert
                model.push(.thread(out.sessionId, draft: out.draft))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
