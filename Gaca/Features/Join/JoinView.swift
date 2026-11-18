import SwiftUI

/// "Add a shared page" (gaca-android JoinScreen): paste an invite link, see what it would add, then Trust and add.
/// The token lives only in this screen's memory, goes only to the person's own server, and is never logged.
/// A `gaca://join/<token>` link arrives through `AppModel.pendingJoinLink` and is looked at straight away.
struct JoinView: View {
    @Environment(AppModel.self) private var model

    enum Phase {
        case enter
        case looking
        /// Nothing is added until the person taps Trust and add.
        case review(InvitePreview)
        case joining
        case joined(Redeemed, title: String)
        /// The server isn't linked to a cloud account, so no link can be looked at.
        case needsLink
    }

    @State private var input = ""
    @State private var phase: Phase = .enter
    @State private var error: String?
    /// The secret part of the link being looked at.
    @State private var token: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
                if let error { ErrorLine(text: error) }
            }
            .padding(20)
        }
        .background(Palette.page)
        .navigationTitle("Add a shared page")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Palette.accent)
        .onAppear(perform: takePendingLink)
        .onChange(of: model.pendingJoinLink) { _, _ in takePendingLink() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .enter: enter
        case .looking: SheetWorking(text: "Looking at the link…")
        case .review(let preview): review(preview)
        case .joining: SheetWorking(text: "Adding it…")
        case .joined(let page, let title):
            Text("Added \u{201C}\(title)\u{201D}").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.textPrimary)
            Text("It's in your Artifacts, under Shared with me.").font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
            if let id = page.id, !id.isEmpty {
                SheetPrimaryButton(title: "Open it") { model.openArtifact(id) }
            }
            Button("Done") { model.artifactsPath.removeAll() }.foregroundStyle(Palette.accent)
        case .needsLink:
            Text("Link your server to GACA Cloud first (in Settings), then come back and paste the link again.")
                .font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
            SheetPrimaryButton(title: "Open Settings") { model.push(.settings) }
        }
    }

    @ViewBuilder private var enter: some View {
        Text("Someone can share a page with you by sending a link. Paste it here to see what it is before you add it.")
            .font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
        TextField("Paste the invite link", text: $input, axis: .vertical)
            .lineLimit(2...4)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surface))
            .onChange(of: input) { _, _ in error = nil }
        HStack(spacing: 12) {
            SheetPrimaryButton(title: "Look at it", enabled: !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: lookUp)
            PasteButton(payloadType: String.self) { strings in
                if let text = strings.first { input = text }
            }
            .labelStyle(.titleAndIcon)
        }
    }

    @ViewBuilder private func review(_ preview: InvitePreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview.title).font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.textPrimary)
            Label("Shared by \(preview.invitedBy?.name ?? "someone")", systemImage: "person.2")
                .font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
            Text(preview.roleLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.chip))
            Text(preview.youCan).font(.system(size: 15)).foregroundStyle(Palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))

        if preview.isMember {
            Text("You're already in this page. Adding it again changes nothing.")
                .font(.system(size: 13)).foregroundStyle(Palette.textMeta)
        } else {
            SheetNoteBox(tint: SeverityStyle.of("warn").background) {
                Text("Only add pages from people you trust").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                Text("Once added, it appears in your list and opens in this app like your own pages. You'll be in it as \(preview.roleLabel.lowercased()).")
                    .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
            }
        }
        SheetPrimaryButton(title: preview.isMember ? "Open it" : "Trust and add") { trustAndAdd(preview) }
        Button("Cancel", action: cancel).foregroundStyle(Palette.accent)
    }

    // MARK: Actions

    /// A link that arrived by tapping: look at it straight away (and forget it in the app model).
    private func takePendingLink() {
        guard let link = model.pendingJoinLink else { return }
        model.pendingJoinLink = nil
        input = link
        lookUp()
    }

    private func lookUp() {
        guard let parsed = parseInviteToken(input) else {
            error = "That doesn't look like an invite link. Paste the whole link you were sent."
            return
        }
        token = parsed
        phase = .looking
        error = nil
        Task {
            do {
                phase = .review(try await model.api.previewInvite(token: parsed))
            } catch {
                fail(error, back: .enter)
            }
        }
    }

    /// The explicit tap. For a page you're already in, joining again is a no-op that tells us its id.
    private func trustAndAdd(_ preview: InvitePreview) {
        guard let t = token else { return }
        phase = .joining
        error = nil
        Task {
            do {
                let page = try await model.api.redeemInvite(token: t)
                token = nil
                input = ""
                let title = (page.title?.isEmpty == false ? page.title : nil) ?? preview.title
                if preview.isMember, let id = page.id, !id.isEmpty {
                    model.openArtifact(id)
                } else {
                    phase = .joined(page, title: title)
                }
            } catch {
                fail(error, back: .review(preview))
            }
        }
    }

    private func cancel() {
        token = nil
        input = ""
        error = nil
        phase = .enter
    }

    private func fail(_ error: Error, back: Phase) {
        if error is CancellationError { phase = back; return }
        switch JoinProblem(code: (error as? APIError)?.code) {
        case .notLinked:
            phase = .needsLink
            self.error = nil
        case .linkDead:
            token = nil
            phase = .enter
            self.error = JoinProblem.linkDeadText
        case .other:
            phase = back
            self.error = error.localizedDescription
        }
    }
}
