import SwiftUI

/// Publish a page to the gallery: write the listing, see exactly what would go out, confirm, publish.
/// Uses POST /artifacts/{id}/publish-check and /publish, which work for a private page and a cloud page alike
/// (the server sends only the page and its shapes, never data), so a private page stays private.
struct PublishSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let artifact: Artifact
    var onChanged: () -> Void = {}

    enum Phase {
        case loading
        case blocked(CloudBlock)
        case form
        case checking
        /// The cloud's preview of exactly this listing. One more tap publishes it.
        case review(PublishReview, PublishListing)
        case publishing
        case done(Template)
    }

    @State private var phase: Phase = .loading
    @State private var listing: PublishListing
    @State private var error: String?

    init(artifact: Artifact, onChanged: @escaping () -> Void = {}) {
        self.artifact = artifact
        self.onChanged = onChanged
        _listing = State(initialValue: PublishListing(title: artifact.title))
    }

    private var busy: Bool { if case .publishing = phase { return true } else { return false } }

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
            .navigationTitle(artifact.publishedId != nil ? "Publish a new version" : "Publish to the gallery")
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
        .task { await load() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading: SheetWorking(text: "Getting ready…")
        case .blocked(let block): CloudBlockView(block: block, openSettings: openSettings) { Task { await load() } }
        case .form: form
        case .checking: SheetWorking(text: "Checking what would be published…")
        case .review(let review, let previewed): self.review(review, previewed)
        case .publishing: SheetWorking(text: "Publishing…")
        case .done(let template):
            Text(template.publishedMessage).font(.system(size: 15)).foregroundStyle(Palette.textPrimary)
            SheetPrimaryButton(title: "Done") { dismiss() }
        }
    }

    // MARK: Steps

    @ViewBuilder private var form: some View {
        Text("Publishing makes a public copy of the page and its shapes. Your data is never published.")
            .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Title")
            TextField("Title", text: $listing.title)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surface))
            if listing.cleanTitle.count > 120 {
                ErrorLine(text: "Keep the title to 120 characters.")
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Description (optional)")
            TextField("What it is for", text: $listing.description, axis: .vertical)
                .lineLimit(2...6)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surface))
            Text("Written fresh for the public. Your page's own description is not used.")
                .font(.system(size: 13)).foregroundStyle(Palette.textMeta)
            if (listing.cleanDescription?.count ?? 0) > 500 {
                ErrorLine(text: "Keep the description to 500 characters.")
            }
        }
        SectionLabel(text: "Where does it show up?")
        Picker("Where", selection: $listing.visibility) {
            ForEach(PublishVisibility.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        Text(listing.visibility.explain).font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
        SheetPrimaryButton(title: "Preview what goes out", enabled: listing.isValid, action: check)
    }

    @ViewBuilder private func review(_ review: PublishReview, _ previewed: PublishListing) -> some View {
        let report = review.report
        Text(review.hash == nil && !report.blocked
             ? "The cloud didn't give a preview to confirm, so nothing can be published."
             : sheetCheckHeadline(report, stops: "published"))
            .font(.system(size: 15))
            .foregroundStyle(review.canPublish ? Palette.textPrimary : SeverityStyle.of("urgent").ink)
        ForEach(Array(report.sortedFindings.enumerated()), id: \.offset) { SheetFindingRow(finding: $0.element) }

        let p = review.preview
        SheetNoteBox {
            Text("What the public will see").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textPrimary)
            Text(p.title).font(.system(size: 15)).foregroundStyle(Palette.textPrimary)
            Text(p.description ?? "No description").font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
            Text(previewMeta(p)).font(.system(size: 12)).foregroundStyle(Palette.textMeta)
            Text("It is shown with no data in it.").font(.system(size: 13)).foregroundStyle(Palette.textMeta)
        }

        if review.canPublish {
            SheetNoteBox {
                Text("You are about to publish").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                Text(previewed.summary).font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
            }
            SheetPrimaryButton(title: "Publish") { publish(review, previewed) }
        }
        Button(review.canPublish ? "Change the listing" : "Back") { phase = .form; error = nil }
            .foregroundStyle(Palette.accent)
    }

    private func previewMeta(_ p: PublishPreview) -> String {
        var parts = ["page \(p.pageSizeText)", plural(p.shapes, "shape")]
        if let license = p.license { parts.append("license \(license)") }
        if !p.tags.isEmpty { parts.append(p.tags.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func load() async {
        phase = .loading
        error = nil
        do {
            phase = try await CloudBlock.check(model.api, doing: "published", todo: "publish").map { .blocked($0) } ?? .form
        } catch is CancellationError {
        } catch {
            phase = .blocked(CloudBlock.from(error, doing: "published", todo: "publish")
                             ?? CloudBlock(message: error.localizedDescription, canOpenSettings: false))
        }
    }

    private func check() {
        let current = listing
        guard current.isValid else { return }
        run(.checking) {
            .review(try await model.api.publishCheck(artifact.id, current), current)
        } onError: { .form }
    }

    private func publish(_ review: PublishReview, _ previewed: PublishListing) {
        guard review.canPublish, let hash = review.hash else { return }
        run(.publishing) {
            let template = try await model.api.publish(artifact.id, previewed, hash: hash)
            onChanged()
            return .done(template)
        } onError: { .review(review, previewed) }
    }

    private func run(_ during: Phase, _ step: @escaping () async throws -> Phase, onError: @escaping () -> Phase) {
        phase = during
        error = nil
        Task {
            do {
                phase = try await step()
            } catch is CancellationError {
                phase = onError()
            } catch {
                if let block = CloudBlock.from(error, doing: "published", todo: "publish") {
                    phase = .blocked(block)
                } else if (error as? APIError)?.code == "preview_mismatch" {
                    // The page or the listing changed between the preview and the tap: nothing was published.
                    self.error = "The page changed since you previewed it, so nothing was published. Preview it again."
                    phase = .form
                } else {
                    self.error = error.localizedDescription
                    phase = onError()
                }
            }
        }
    }

    private func openSettings() {
        dismiss()
        model.push(.settings)
    }
}
