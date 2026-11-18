import SwiftUI

/// Why a cloud step (share, publish, the gallery) can't go ahead, in plain words, and whether Settings can fix it.
struct CloudBlock: Equatable {
    let message: String
    let canOpenSettings: Bool

    /// Before sharing or publishing: is this server linked to GACA Cloud, with a link that can change things?
    /// `doing` reads "shared" / "published", `todo` reads "share" / "publish".
    static func check(_ api: APIClient, doing: String, todo: String) async throws -> CloudBlock? {
        let link = try await api.cloudLink()
        if !link.isConfigured { return notSetUp(doing) }
        if link.kind == .invalid { return stoppedWorking(todo) }
        if !link.isLinked { return CloudBlock(message: "Link your server to GACA Cloud first (Settings), then come back to \(todo).", canOpenSettings: true) }
        if link.scope == "read" { return readOnly(todo) }
        return nil
    }

    /// The stable error codes that mean the cloud link is the problem, not this page.
    static func from(_ error: Error, doing: String, todo: String) -> CloudBlock? {
        switch (error as? APIError)?.code {
        case "cloud_not_configured": return notSetUp(doing)
        case "cloud_not_linked": return CloudBlock(message: "Link your server to GACA Cloud first (Settings), then come back to \(todo).", canOpenSettings: true)
        case "cloud_link_invalid": return stoppedWorking(todo)
        case "cloud_link_read_only": return readOnly(todo)
        default: return nil
        }
    }

    private static func notSetUp(_ doing: String) -> CloudBlock {
        CloudBlock(message: "GACA Cloud isn't set up on this server, so pages can't be \(doing) yet.", canOpenSettings: false)
    }
    private static func stoppedWorking(_ todo: String) -> CloudBlock {
        CloudBlock(message: "The cloud stopped accepting your server's link. Link it again in Settings, then come back to \(todo).", canOpenSettings: true)
    }
    private static func readOnly(_ todo: String) -> CloudBlock {
        CloudBlock(message: "Your cloud link is read-only, so it can't \(todo). Unlink and link again in Settings.", canOpenSettings: true)
    }
}

extension Error {
    /// The server's words, plus a reassurance when it says the page here was not touched (`local_data_changed: false`).
    var transferMessage: String {
        var text = localizedDescription
        if case .http(_, _, _, let info?)? = self as? APIError, case .bool(false)? = info["local_data_changed"] {
            text += " Your page here was not changed."
        }
        return text
    }
}

/// A spinner with a sentence beside it, for a step that is running.
struct SheetWorking: View {
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Palette.accent)
            Text(text).font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// One finding from a cloud check: Problem / Warning / Note, then what it says.
struct SheetFindingRow: View {
    let finding: Finding

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tag)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(finding.level == .block ? SeverityStyle.of("urgent").ink : Palette.textMeta)
            Text(finding.text + (finding.location.map { " (\($0))" } ?? ""))
                .font(.system(size: 14))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var tag: String {
        switch finding.level {
        case .block: return "Problem"
        case .warn: return "Warning"
        case .info: return "Note"
        }
    }
}

/// The headline over a check's findings.
func sheetCheckHeadline(_ report: ValidationReport, stops: String) -> String {
    if report.blocked { return "The check found problems that stop this page being \(stops)." }
    let w = report.warnings
    if w > 0 { return "The check passed with \(plural(w, "warning"))." }
    return "The check found no problems."
}

/// A tinted box that frames a confirmation or a warning.
struct SheetNoteBox<Content: View>: View {
    var tint: Color = Palette.chip.opacity(0.6)
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(tint))
    }
}

/// The solid accent button the sheets use for the step that changes something.
struct SheetPrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? Palette.onAccent : Palette.textMeta)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(enabled ? Palette.accent : Palette.chip))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// What a blocked cloud step shows: the reason, then Open Settings or Try again.
struct CloudBlockView: View {
    let block: CloudBlock
    let openSettings: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(block.message).font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
            if block.canOpenSettings {
                SheetPrimaryButton(title: "Open Settings", action: openSettings)
            } else {
                Button("Try again", action: retry).foregroundStyle(Palette.accent)
            }
        }
    }
}

extension Template {
    /// After a publish: the cloud checks every template before it shows.
    var publishedMessage: String {
        switch status {
        case "checking": return "Published. The cloud is still checking it, so it may take a moment to appear."
        case "blocked": return "The cloud's check blocked it, so it is not visible to anyone."
        default: return "Published."
        }
    }
}
