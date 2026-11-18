import Foundation
import Observation
import SwiftUI

/// Why the last link attempt ended without linking.
enum CloudLinkEnd { case expired, denied }

/// The "GACA Cloud" section's state. The app never talks to the cloud: it asks its own server to link
/// (its `cloud/link` routes), shows the short code the server was given, and polls the server until the
/// person has approved the code in a browser. The link and its token stay on the server.
/// Ported from Android's CloudLinkViewModel.
@MainActor
@Observable
final class CloudLinkModel {
    var loading = false
    /// Nil until the first load succeeds.
    var status: CloudLinkStatus?
    /// Set while a link is in progress: the code to confirm on the cloud page.
    var attempt: CloudLinkAttempt?
    var starting = false
    var ended: CloudLinkEnd?
    /// Asking "Unlink?" (and, after the server held it back, what would be cut off).
    var confirmingUnlink = false
    var unlinkBlock: UnlinkBlock?
    var busy = false
    /// What the server said when it finished unlinking (it may say the cloud could not confirm).
    var notice: String?
    var error: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    func load(_ api: APIClient) async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let status = try await api.cloudLink()
            self.status = status
            if let attempt, attempt.expiresAt > .now {
                // Came back to Settings while a code we started is still showing: keep waiting for it.
                if pollTask == nil { startPolling(attempt, api: api, firstDelay: 0) }
            } else if status.kind == .pending, let pending = status.pendingAttempt, pending.expiresAt > .now {
                // Left Settings mid-link? The server remembers the code: show it again and keep polling.
                attempt = pending
                startPolling(pending, api: api, firstDelay: 0)
            } else if attempt != nil {
                attempt = nil
                ended = .expired
            }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Leaving the screen stops the polling; the code stays so it can be shown again on return.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func startLinking(_ api: APIClient) {
        guard !starting else { return }
        starting = true
        error = nil
        ended = nil
        notice = nil
        Task {
            defer { starting = false }
            do {
                let attempt = try await api.startCloudLink().attempt()
                self.attempt = attempt
                startPolling(attempt, api: api, firstDelay: attempt.intervalSeconds)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Stop waiting. The server forgets the unfinished attempt on its own when its code expires.
    func cancelLinking(_ api: APIClient) {
        stop()
        attempt = nil
        error = nil
        Task { await load(api) }
    }

    /// Ask the server again right now (after a poll failed, e.g. the phone was offline).
    func checkAgain(_ api: APIClient) {
        guard let attempt else { return }
        error = nil
        startPolling(attempt, api: api, firstDelay: 0)
    }

    private func startPolling(_ attempt: CloudLinkAttempt, api: APIClient, firstDelay: Int) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var wait = firstDelay
            while !Task.isCancelled {
                if wait > 0 {
                    do { try await Task.sleep(for: .seconds(wait)) } catch { return }
                }
                guard let self else { return }
                if attempt.expiresAt <= .now {
                    self.finish(.expired)
                    return
                }
                let poll: CloudLinkPoll
                do {
                    poll = try await api.pollCloudLink()
                } catch is CancellationError {
                    return
                } catch {
                    if Task.isCancelled { return }
                    // Stay on the code; the person can tap "Check again" when they are back online.
                    self.error = error.localizedDescription
                    self.pollTask = nil
                    return
                }
                if Task.isCancelled { return }
                switch poll.status {
                case "linked":
                    self.attempt = nil
                    self.error = nil
                    self.pollTask = nil
                    self.status = CloudLinkStatus(linked: true, state: "linked", handle: poll.handle, accountId: poll.accountId,
                                                  linkedAt: poll.linkedAt, scope: poll.scope)
                    // The poll answer is brief; the full status carries the agent switch and the rest.
                    await self.load(api)
                    return
                case "expired":
                    self.finish(.expired)
                    return
                case "denied":
                    self.finish(.denied)
                    return
                default:
                    wait = poll.waitSeconds(fallback: attempt.intervalSeconds)
                }
            }
        }
    }

    private func finish(_ end: CloudLinkEnd) {
        attempt = nil
        ended = end
        pollTask = nil
    }

    /// The switch moves at once; if the server says no it goes back and the reason shows.
    func setAgentAccess(_ enabled: Bool, api: APIClient) {
        guard let before = status else { return }
        var moved = before
        moved.agentAccess = enabled
        status = moved
        error = nil
        Task {
            do {
                var saved = try await api.setCloudAgentAccess(enabled)
                if saved.configured == nil { saved.configured = before.configured }
                status = saved
            } catch {
                status = before
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: Unlinking

    func askUnlink() {
        unlinkBlock = nil
        error = nil
        confirmingUnlink = true
    }

    func dismissUnlink() {
        confirmingUnlink = false
        unlinkBlock = nil
    }

    /// `force` is only sent after the person has seen what unlinking anyway would cut off.
    func unlink(force: Bool, api: APIClient) {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                switch try await api.unlinkCloud(force: force) {
                case .done(let message):
                    confirmingUnlink = false
                    unlinkBlock = nil
                    notice = message.isEmpty ? nil : message
                    await load(api)
                case .blocked(let block):
                    unlinkBlock = block
                    // The first dialog closed when its button was tapped; ask again with what would be cut off.
                    confirmingUnlink = true
                }
            } catch {
                confirmingUnlink = false
                unlinkBlock = nil
                self.error = error.localizedDescription
            }
        }
    }

    func dismissNotice() {
        notice = nil
        ended = nil
    }
}

/// Wording shared with Android (CloudLinkSection.kt).
enum CloudLinkText {
    static let intro = "Link your server to a GACA Cloud account to share pages with other people or publish them. Your phone never talks to the cloud itself; your own server does, on your behalf."
    static let unlink = "This server will forget the link and the cloud will stop accepting it. Pages that only live on this server are not affected."

    /// Plain-words version of what the server told us it would cut off.
    static func blocked(_ block: UnlinkBlock) -> String {
        var parts: [String] = []
        if block.owned > 0 { parts.append("\(block.owned) of your own") }
        if block.shared > 0 { parts.append("\(block.shared) shared with you") }
        if block.inProgress > 0 { parts.append("\(block.inProgress) move\(block.inProgress == 1 ? "" : "s") still running") }
        let what = parts.isEmpty ? "Some pages live in the cloud or a move is not finished." : "In the cloud: \(parts.joined(separator: ", "))."
        return "\(what) If you unlink, this app can no longer open them until you link again (they stay safe in the cloud). To keep access, cancel and bring your own pages home first."
    }

    static func linkedLine(_ status: CloudLinkStatus) -> String {
        var parts = [status.handle.map { "Account \($0)" } ?? "Account linked"]
        if let at = status.linkedAt { parts.append("since \(at.formatted(date: .abbreviated, time: .shortened))") }
        return parts.joined(separator: " · ")
    }

    static func notLinkedLine(_ status: CloudLinkStatus) -> String {
        if !status.isConfigured { return "GACA Cloud isn't set up on this server, so linking isn't available." }
        switch status.kind {
        case .invalid: return "The cloud no longer accepts this server's link. Link again to keep sharing."
        case .pending: return "A link was started but its code ran out. Start again to get a fresh code."
        default: return "Not linked."
        }
    }
}

/// "GACA Cloud" in Settings: link this server to a cloud account (needed to share pages, publish them,
/// or join someone else's).
struct CloudLinkSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Bindable var cloud: CloudLinkModel

    var body: some View {
        Section {
            content
            if let notice = cloud.notice {
                Button { cloud.dismissNotice() } label: {
                    Text(notice).font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                }
            }
            if let error = cloud.error {
                ErrorLine(text: error)
                if cloud.status == nil && cloud.attempt == nil {
                    Button("Try again") { Task { await cloud.load(model.api) } }
                }
            }
        } header: {
            HStack {
                SectionLabel(text: "GACA Cloud")
                if cloud.loading || cloud.starting { Spacer(); ProgressView().controlSize(.small) }
            }
        } footer: {
            Text(CloudLinkText.intro)
        }
        .alert(cloud.unlinkBlock == nil ? "Unlink GACA Cloud?" : "Some pages live in the cloud",
               isPresented: Binding(get: { cloud.confirmingUnlink }, set: { if !$0 { cloud.confirmingUnlink = false } })) {
            let block = cloud.unlinkBlock
            Button(block == nil ? "Unlink" : "Unlink anyway", role: .destructive) {
                cloud.unlink(force: block != nil, api: model.api)
            }
            Button("Cancel", role: .cancel) { cloud.dismissUnlink() }
        } message: {
            Text(cloud.unlinkBlock.map(CloudLinkText.blocked) ?? CloudLinkText.unlink)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let attempt = cloud.attempt {
            VStack(alignment: .leading, spacing: 8) {
                Text("Approve this code in your browser").font(.system(size: 16, weight: .semibold))
                Text(attempt.userCode)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.accent)
                    .textSelection(.enabled)
                Text("Open the page below, sign in, and check that it shows this code. This screen updates by itself when you are done.")
                    .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                HStack(spacing: 8) {
                    Button("Open the page") {
                        if let url = URL(string: attempt.verificationUri) { openURL(url) }
                    }
                    .buttonStyle(.borderedProminent).tint(Palette.accent)
                    Button("Cancel") { cloud.cancelLinking(model.api) }
                        .buttonStyle(.bordered).tint(Palette.accent)
                    if cloud.error != nil {
                        Button("Check again") { cloud.checkAgain(model.api) }
                            .buttonStyle(.bordered).tint(Palette.accent)
                    }
                }
                if cloud.error == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for you to approve it…").font(.system(size: 13)).foregroundStyle(Palette.textMeta)
                    }
                }
            }
            .padding(.vertical, 4)
        } else if let status = cloud.status {
            if status.isLinked {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Linked").font(.system(size: 16, weight: .semibold))
                    Text(CloudLinkText.linkedLine(status)).font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                    if status.scope == "read" {
                        Text("This link is read-only: it can list and read, but cannot move, share or publish. Unlink and link again to change that.")
                            .font(.system(size: 13)).foregroundStyle(Palette.textMeta).padding(.top, 4)
                    }
                }
                Toggle(isOn: Binding(get: { status.agentsMayUse }, set: { cloud.setAgentAccess($0, api: model.api) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Let my agent use the cloud")
                        Text("Off by default. When on, your agents can see and use your cloud pages. Sharing and publishing always need your tap in this app.")
                            .font(.system(size: 13)).foregroundStyle(Palette.textMeta)
                    }
                }
                .tint(Palette.accent)
                Button("Unlink", role: .destructive) { cloud.askUnlink() }
                    .disabled(cloud.busy)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(CloudLinkText.notLinkedLine(status)).foregroundStyle(Palette.textSecondary)
                    if let ended = cloud.ended {
                        Text(ended == .denied ? "The code was not approved." : "That code ran out of time.")
                            .font(.system(size: 14)).foregroundStyle(SeverityStyle.of("urgent").ink)
                    }
                }
                if status.isConfigured {
                    Button {
                        cloud.startLinking(model.api)
                    } label: {
                        Text(status.kind == .invalid ? "Link again" : "Link GACA Cloud")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.accent)
                    }
                    .disabled(cloud.starting)
                }
            }
        } else if cloud.error == nil {
            ProgressView().frame(maxWidth: .infinity)
        }
    }
}
