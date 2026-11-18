import SwiftUI
import UIKit

/// An email an agent wrote, laid out like a piece of paper (gaca-android ui/common/DraftCard.kt).
/// Hermes can only read mail, so nothing here sends: "Open in mail" hands the API-built mailto link
/// to the mail app (recipient, subject and body filled in) and the person reviews and sends it there.
/// `title` labels the card ("Draft"); pass nil when the row above already says what it is, so the
/// title is not repeated right under it.
struct DraftCard: View {
    @Environment(\.openURL) private var openURL
    let draft: AlertDraft
    var title: String? = nil
    var showNotSentNote = true
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                if let title {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Palette.chip)
                }
                let to = draft.to?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let subject = draft.subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !to.isEmpty || !subject.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if !to.isEmpty { headerLine("To", to) }
                        if !subject.isEmpty { headerLine("Subject", subject, bold: true) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    Rectangle().fill(Palette.chip).frame(height: 1)
                }
                Text(draft.body)
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if let mailto = draft.mailto, let url = URL(string: mailto) {
                Button { openURL(url) } label: {
                    Label("Open in mail to review and send", systemImage: "arrow.up.right.square")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.accent))
                }
                .buttonStyle(.plain)
            }
            Button {
                UIPasteboard.general.string = draft.textToCopy
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy text", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.accent, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .task(id: copied) {
                guard copied else { return }
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
            if showNotSentNote {
                Text("Not sent. Hermes can only read your mail, so your mail app opens with this filled in and you send it yourself.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerLine(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .fontWeight(bold ? .bold : .regular)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
        }
        .font(.system(size: 15))
    }
}
