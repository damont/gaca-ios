import SwiftUI

/// Hand your crew something to do, rather than waiting for it to notice on its own.
struct NewDelegationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var instruction = ""
    @State private var crew: String?
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var target: String? { crew ?? model.defaultCrew?.name }
    private var valid: Bool { !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && target != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Start something your crew should handle, rather than waiting for it to notice on its own.")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 4)

                    TextField("What should your crew do?", text: $instruction, axis: .vertical)
                        .lineLimit(6...12)
                        .font(.system(size: 17))
                        .focused($focused)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))

                    if model.crew.isEmpty {
                        Text("No crew configured yet — set one up in Settings first.")
                            .font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
                    } else if model.crew.count == 1, let only = model.crew.first {
                        Text("Sends to \(crewDisplayName(only.name))")
                            .font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: "Sends to").padding(.horizontal, 4)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(model.crew) { member in
                                        CrewPill(name: member.name, style: member.style, selected: target == member.name, showAvatar: true) {
                                            crew = member.name
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if let error { ErrorLine(text: error) }
                }
                .padding(16)
            }
            .background(Palette.page)
            .navigationTitle("New delegation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if sending { ProgressView() } else {
                        Button("Start", action: start).fontWeight(.semibold).disabled(!valid)
                    }
                }
            }
            .onAppear { focused = true }
        }
        .tint(Palette.accent)
        .presentationDragIndicator(.visible)
    }

    private func start() {
        guard let target else { return }
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true
        error = nil
        Task {
            defer { sending = false }
            do {
                _ = try await model.api.startDelegation(instruction: text, crew: target)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
