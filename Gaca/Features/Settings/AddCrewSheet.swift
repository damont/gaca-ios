import SwiftUI

/// Add another crew member to the connected agent. When gaca-api can create one on the
/// Hermes box itself (`can_create`), a name is all it needs; otherwise you give the port
/// and key of one you set up by hand.
struct AddCrewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color: String?
    @State private var port = ""
    @State private var apiKey = ""
    @State private var busy = false
    @State private var error: String?

    static let swatches = ["#4E7093", "#6B8F5A", "#B97A56", "#8A6A9E", "#3F8E93", "#B0923F"]

    private var manual: Bool { !model.canCreateCrew }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (!manual || (Int(port) != nil && !apiKey.isEmpty))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("toolshed", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: { SectionLabel(text: "Name") }

                if manual {
                    Section {
                        TextField("Port", text: $port).keyboardType(.numberPad)
                        SecureField("API key", text: $apiKey)
                    } header: { SectionLabel(text: "Connection") }
                }

                Section {
                    HStack(spacing: 10) {
                        swatch(nil)
                        ForEach(Self.swatches, id: \.self) { swatch($0) }
                    }
                    .padding(.vertical, 6)
                } header: {
                    SectionLabel(text: "Color")
                } footer: {
                    Text(color == nil ? "Auto-assigned by the server — tap a swatch to pick one instead."
                                      : "This color will be used instead of an auto-assigned one.")
                }

                if let error { Section { ErrorLine(text: error) } }
            }
            .navigationTitle("Add crew member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button("Add", action: add).fontWeight(.semibold).disabled(!valid)
                    }
                }
            }
        }
        .tint(Palette.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func swatch(_ hex: String?) -> some View {
        let selected = color == hex
        let size: CGFloat = selected ? 40 : 34
        return Button { color = hex } label: {
            ZStack {
                Circle().fill(hex.map { Color(hex: $0) } ?? Palette.field)
                if hex == nil {
                    Text("?").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.accent)
                } else if selected {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .overlay(Circle().stroke(selected ? (hex.map { Color(hex: $0) } ?? Palette.accent) : .clear, lineWidth: 2).padding(-4))
        }
        .buttonStyle(.plain)
        .frame(width: 42, height: 42)
        .accessibilityLabel(hex == nil ? "Auto color" : "Color \(hex!)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func add() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let body = CrewMemberCreate(name: name.trimmingCharacters(in: .whitespaces).lowercased(), color: color,
                                            port: manual ? Int(port) : nil, apiKey: manual ? apiKey : nil)
                model.apply(try await model.api.addCrewMember(body))
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
