import SwiftUI

/// Share one page by link (gaca-android ShareSheet). Pick what people can do; a private page is first moved to the
/// cloud, confirmed with what would be left behind; then the cloud checks it; one more tap creates the link, which is
/// shown once. A page already in the cloud skips the move. Each step that changes something is confirmed.
struct ShareSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let artifact: Artifact
    /// Tells the list to refresh once the page has moved (or anything else changed).
    var onChanged: () -> Void = {}

    enum Phase {
        case loading
        case blocked(CloudBlock)
        /// A private page that can't move to the cloud, so it can't be shared.
        case cannotMove(String)
        /// Role, expiry and uses; for a private page also where the move is confirmed.
        case setup
        case moving
        case checking
        case review(ValidationReport)
        case creating
        case done(InviteLink)
    }

    @State private var phase: Phase = .loading
    @State private var options = ShareOptions()
    @State private var preview: MovePreview?
    @State private var acknowledged = false
    @State private var inCloud = false
    @State private var error: String?

    private var busy: Bool {
        switch phase { case .moving, .creating: return true; default: return false }
    }

    private var canContinue: Bool {
        guard case .setup = phase else { return false }
        if inCloud { return true }
        guard let preview, preview.movable else { return false }
        return !preview.needsAck || acknowledged
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                    if let error { ErrorLine(text: error) }
                }
                .padding(20)
            }
            .background(Palette.page)
            .navigationTitle("Share \u{201C}\(artifact.title)\u{201D}")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .done = phase {} else { Button("Cancel") { dismiss() }.disabled(busy) }
                }
                if case .done = phase {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
                }
            }
        }
        .tint(Palette.accent)
        .interactiveDismissDisabled(busy)
        .presentationDragIndicator(.visible)
        .task {
            inCloud = artifact.isCloud
            await load()
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading: SheetWorking(text: "Getting ready…")
        case .blocked(let block):
            CloudBlockView(block: block, openSettings: openSettings) { Task { await load() } }
        case .cannotMove(let reason):
            Text(reason).font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
        case .setup: setup
        case .moving: SheetWorking(text: "Moving the page to the cloud and checking the copy. This can take a little while; keep the app open.")
        case .checking: SheetWorking(text: "Checking the page…")
        case .review(let report): review(report)
        case .creating: SheetWorking(text: "Creating the link…")
        case .done(let invite): done(invite)
        }
    }

    // MARK: Steps

    @ViewBuilder private var setup: some View {
        SectionLabel(text: "What can they do?")
        Picker("Role", selection: $options.role) {
            ForEach(ShareRole.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        Text(options.role.canDo).font(.system(size: 14)).foregroundStyle(Palette.textSecondary)

        HStack {
            Text("Link works for").foregroundStyle(Palette.textPrimary)
            Spacer()
            Picker("Link works for", selection: $options.expiryDays) {
                ForEach(ShareOptions.expiryChoices, id: \.self) { Text(plural($0, "day")).tag($0) }
            }
        }
        HStack {
            Text("Up to").foregroundStyle(Palette.textPrimary)
            Spacer()
            Picker("Up to", selection: $options.maxUses) {
                ForEach(ShareOptions.useChoices, id: \.self) { Text(plural($0, "person", "people")).tag($0) }
            }
        }

        if !inCloud, let preview {
            SheetNoteBox(tint: SeverityStyle.of("warn").background) {
                Text("First, this page moves to the cloud").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                Text("Sharing needs the page and its data to live in your GACA Cloud account. It keeps its id and shows up the same here. A sealed backup of the copy on your server is kept for \(plural(preview.keepDays, "day")).")
                    .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                if !preview.lostLines.isEmpty {
                    Text("The cloud does not keep:").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                    ForEach(preview.lostLines, id: \.self) {
                        Text("•  \($0)").font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                    }
                }
                if preview.needsAck {
                    Toggle("I've seen what is left behind", isOn: $acknowledged)
                        .font(.system(size: 15))
                        .tint(Palette.accent)
                }
            }
        }

        SheetPrimaryButton(title: inCloud ? "Check the page" : "Move to the cloud and check", enabled: canContinue, action: continueToChecks)
    }

    @ViewBuilder private func review(_ report: ValidationReport) -> some View {
        Text(sheetCheckHeadline(report, stops: "shared"))
            .font(.system(size: 15))
            .foregroundStyle(report.blocked ? SeverityStyle.of("urgent").ink : Palette.textPrimary)
        ForEach(Array(report.sortedFindings.enumerated()), id: \.offset) { SheetFindingRow(finding: $0.element) }
        if !report.blocked {
            SheetNoteBox {
                Text("You are about to create a link").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                Text(options.summary).font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
                Text("Treat it like a password. You can't see it again after this.").font(.system(size: 13)).foregroundStyle(Palette.textMeta)
            }
            SheetPrimaryButton(title: "Create link") { createLink(report) }
        }
        Button(report.blocked ? "Back" : "Change options") { phase = .setup; error = nil }
            .foregroundStyle(Palette.accent)
    }

    @ViewBuilder private func done(_ invite: InviteLink) -> some View {
        Text("Your link is ready").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.textPrimary)
        if let url = invite.url, !url.isEmpty {
            Text(url)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Palette.accent)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.chip.opacity(0.6)))
            Text(options.summary).font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
            Text("This is the only time it is shown. Copy it now.").font(.system(size: 13)).foregroundStyle(Palette.textMeta)
            HStack(spacing: 12) {
                SheetPrimaryButton(title: copied ? "Copied" : "Copy link") {
                    UIPasteboard.general.string = url
                    copied = true
                }
                ShareLink(item: url) {
                    Label("Send…", systemImage: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
                }
            }
        } else {
            Text("The cloud made the link but didn't send it back, so it can't be shown. Make a new one.")
                .font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
        }
    }

    @State private var copied = false

    // MARK: Actions

    private func load() async {
        phase = .loading
        error = nil
        do {
            if let block = try await CloudBlock.check(model.api, doing: "shared", todo: "share") {
                phase = .blocked(block)
            } else if inCloud {
                phase = .setup
            } else {
                let p = try await model.api.movePreview(artifact.id)
                preview = p
                phase = p.movable ? .setup : .cannotMove(p.blockedText ?? "This page can't be moved to the cloud.")
            }
        } catch is CancellationError {
        } catch {
            phase = .blocked(CloudBlock.from(error, doing: "shared", todo: "share")
                             ?? CloudBlock(message: error.localizedDescription, canOpenSettings: false))
        }
    }

    private func continueToChecks() {
        guard canContinue else { return }
        let moving = !inCloud
        let ack = acknowledged
        run(moving ? .moving : .checking) {
            if moving {
                _ = try await model.api.moveToCloud(artifact.id, acknowledged: ack)
                inCloud = true
                onChanged()
                phase = .checking
            }
            return .review(try await model.api.shareCheck(artifact.id))
        } onError: { .setup }
    }

    private func createLink(_ report: ValidationReport) {
        guard !report.blocked else { return }
        let opts = options
        run(.creating) {
            .done(try await model.api.createInvite(artifact.id, opts))
        } onError: { .review(report) }
    }

    /// Shows `during`, then the phase the step returns; on failure says why and goes to `onError` (or to the
    /// Settings hint when the cloud link is the problem).
    private func run(_ during: Phase, _ step: @escaping () async throws -> Phase, onError: @escaping () -> Phase) {
        phase = during
        error = nil
        Task {
            do {
                phase = try await step()
            } catch is CancellationError {
                phase = onError()
            } catch {
                if let block = CloudBlock.from(error, doing: "shared", todo: "share") {
                    phase = .blocked(block)
                } else {
                    self.error = error.transferMessage
                    phase = onError()
                }
                onChanged() // a failed move may still have changed where the page lives
            }
        }
    }

    private func openSettings() {
        dismiss()
        model.push(.settings)
    }
}
