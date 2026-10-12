import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var disconnecting = false
    @State private var agent: AgentStatus?
    @State private var error: String?
    @State private var adding = false
    @State private var editing: CrewMember?
    @State private var removing: CrewMember?
    @State private var changingHost = false
    @State private var newHost = ""

    var body: some View {
        List {
            Section {
                if let agent {
                    if agent.connected {
                        Button {
                            newHost = agent.host ?? ""
                            changingHost = true
                        } label: {
                            HStack {
                                HStack(spacing: 8) {
                                    Circle().fill(Color(hex: "#5B8A4A")).frame(width: 8, height: 8)
                                    Text("Connected").foregroundStyle(Palette.textPrimary)
                                }
                                Spacer()
                                Text(agent.host ?? "").foregroundStyle(Palette.textSecondary).lineLimit(1)
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textMeta)
                            }
                        }
                    } else {
                        ConnectAgentForm { list in
                            model.apply(list)
                            Task { await load() }
                        }
                    }
                } else {
                    ProgressView()
                }
            } header: {
                SectionLabel(text: "Agent")
            } footer: {
                if agent?.connected == true {
                    Text("The one Hermes connection your crew runs on. Tap to move it to a new host.")
                } else if agent != nil {
                    Text("Connect the Hermes box your crew will run on. This creates your first crew member.")
                }
            }

            if agent?.connected == true {
                Section {
                    ForEach(model.crew) { member in
                        NavigationLink(value: Route.crew(member.name)) {
                            HStack(spacing: 12) {
                                CrewAvatar(name: member.name, style: member.style, size: 34)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 7) {
                                        Text(crewDisplayName(member.name)).font(.system(size: 16))
                                        if member.isDefault {
                                            Text("default").font(.system(size: 12, weight: .semibold)).foregroundStyle(member.style.ink)
                                                .padding(.horizontal, 7).padding(.vertical, 1)
                                                .background(Capsule().fill(member.style.tint))
                                        }
                                    }
                                    Text("port \(member.port)").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { removing = member } label: { Label("Remove", systemImage: "trash") }
                            Button { editing = member } label: { Label("Edit", systemImage: "pencil") }.tint(Color(hex: "#7A838C"))
                        }
                        .swipeActions(edge: .leading) {
                            if !member.isDefault {
                                Button { crewAction { try await model.api.setDefaultCrewMember(member.name) } } label: {
                                    Label("Make default", systemImage: "star")
                                }
                                .tint(member.style.solid)
                            }
                        }
                    }
                    Button { adding = true } label: {
                        Label("Add crew member", systemImage: "plus.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                } header: {
                    SectionLabel(text: "Your crew")
                } footer: {
                    Text("Swipe a crew member to make it the default, edit or remove it.")
                }
            }

            if let error {
                Section { ErrorLine(text: error) }
            }

            Section {
                HStack {
                    Text("Paired with")
                    Spacer()
                    Text(model.api.settings.serverLabel ?? "—").foregroundStyle(Palette.textSecondary)
                }
                Button("Disconnect from this server", role: .destructive) { disconnecting = true }
                    .frame(maxWidth: .infinity)
            } header: {
                SectionLabel(text: "Server")
            } footer: {
                Text("Disconnecting tells the server to forget this iPhone. To connect again, run gaca-api pair on the server.")
            }

            Section {
                AboutFooter()
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .gacaPage()
        .navigationTitle("Settings")
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $adding) { AddCrewSheet() }
        .sheet(item: $editing) { member in EditCrewSheet(member: member) }
        .confirmationDialog(removing.map { "Remove \(crewDisplayName($0.name))?" } ?? "",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let member = removing { crewAction { try await model.api.removeCrewMember(member.name) } }
            }
        } message: {
            Text("Its chats stay, but you won't be able to talk to it until it's added again.")
        }
        .alert("Move agent", isPresented: $changingHost) {
            TextField("Host", text: $newHost).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Move") { crewAction { try await model.api.updateAgentHost(newHost.trimmingCharacters(in: .whitespaces)) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The address of the box Hermes now runs on.")
        }
        .refreshable { await load() }
        .confirmationDialog("Disconnect from this server?", isPresented: $disconnecting, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await model.disconnect() } }
        } message: {
            Text("This iPhone stops receiving alerts and chats until you pair it again.")
        }
        .task { await load() }
    }

    private func load() async {
        do {
            agent = try await model.api.agentStatus()
            try await model.refreshCrew()
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func crewAction(_ work: @escaping () async throws -> CrewList) {
        Task {
            do {
                model.apply(try await work())
                await load()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// The mark, the app's name and its version, at the foot of Settings.
private struct AboutFooter: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 6) {
            BrandMark.wingsLevel.image(width: 64).padding(.bottom, 4)
            Text("Gaca for iPhone").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.accent)
            Text(version).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// First-time setup: connect the Hermes box (creates the first crew member).
struct ConnectAgentForm: View {
    @Environment(AppModel.self) private var model
    let onConnected: (CrewList) -> Void
    @State private var host = ""
    @State private var port = "8642"
    @State private var apiKey = ""
    @State private var name = "default"
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        TextField("Host (e.g. hermes.local)", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled()
        TextField("Port", text: $port).keyboardType(.numberPad)
        SecureField("API key", text: $apiKey)
        TextField("First crew member's name", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
        if let error { ErrorLine(text: error) }
        Button {
            guard let p = Int(port) else { error = "The port must be a number."; return }
            busy = true
            Task {
                defer { busy = false }
                do {
                    onConnected(try await model.api.connectAgent(AgentConnect(host: host, port: p, apiKey: apiKey, name: name)))
                } catch {
                    self.error = error.localizedDescription
                }
            }
        } label: {
            HStack { if busy { ProgressView() }; Text("Connect agent").fontWeight(.semibold) }
        }
        .disabled(busy || host.isEmpty || apiKey.isEmpty || name.isEmpty)
    }
}

struct EditCrewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let member: CrewMember
    @State private var port = ""
    @State private var apiKey = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Port", text: $port).keyboardType(.numberPad)
                SecureField("API key (re-enter to change)", text: $apiKey)
                if let error { ErrorLine(text: error) }
            }
            .navigationTitle("Edit \(crewDisplayName(member.name))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let p = Int(port), !apiKey.isEmpty else {
                            error = "A valid port and a key (re-entered) are both required."
                            return
                        }
                        Task {
                            do {
                                model.apply(try await model.api.updateCrewMember(member.name, CrewMemberUpdate(port: p, apiKey: apiKey)))
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { port = String(member.port) }
        }
        .tint(Palette.accent)
        .presentationDetents([.medium])
    }
}
