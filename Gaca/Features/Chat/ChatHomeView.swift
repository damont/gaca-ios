import SwiftUI

/// The Chat tab: pick who to talk to, see recent chats, and start typing right away.
/// Nothing exists on the server until the first send.
struct ChatHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var sessions: [Session] = []
    @State private var picked: String?
    @State private var text = ""
    @State private var photos: [PendingPhoto] = []
    @State private var sending = false
    @State private var loading = true
    @State private var error: String?

    private var pickedMember: CrewMember? {
        model.crew.first { $0.name == picked } ?? model.defaultCrew
    }

    var body: some View {
        List {
            if model.crew.count > 1 {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(model.crew) { member in
                                crewChoice(member)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    SectionLabel(text: "New chat with")
                }
            }

            if let error {
                Section { ErrorLine(text: error) }.listRowBackground(Color.clear)
            }

            Section {
                if loading && sessions.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                } else if sessions.isEmpty {
                    Group {
                        if let member = pickedMember {
                            EmptyState(mark: .wingsLevel, title: "No chats yet",
                                       message: "Say something to \(crewDisplayName(member.name)) below and it'll get to work.")
                        } else {
                            EmptyState(title: "No crew configured yet", message: "Set one up in Settings first.")
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(sessions.prefix(6)) { session in
                        NavigationLink(value: Route.thread(session.id)) {
                            SessionRow(session: session, style: model.style(for: session.crew))
                        }
                    }
                }
            } header: {
                HStack {
                    SectionLabel(text: "Recent")
                    Spacer()
                    if !sessions.isEmpty {
                        NavigationLink("See all", value: Route.history)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .gacaPage()
        .contentMargins(.bottom, 90, for: .scrollContent)
        .navigationTitle("Chat")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(value: Route.history) { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search all chats")
                SettingsButton()
            }
        }
        .safeAreaInset(edge: .bottom) {
            Composer(text: $text, photos: $photos,
                     placeholder: "Message \(pickedMember.map { crewDisplayName($0.name) } ?? "your crew")…",
                     style: pickedMember?.style ?? .neutral,
                     sending: sending, onSend: send)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .disabled(model.crew.isEmpty)
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func crewChoice(_ member: CrewMember) -> some View {
        let selected = member.name == pickedMember?.name
        return Button {
            picked = member.name
        } label: {
            VStack(spacing: 7) {
                CrewAvatar(name: member.name, style: member.style, size: 54)
                    .overlay(Circle().stroke(selected ? member.style.color : .clear, lineWidth: 2.5).padding(-5))
                    .opacity(selected ? 1 : 0.55)
                Text(crewDisplayName(member.name))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? member.style.ink : Palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 68)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chat with \(crewDisplayName(member.name))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            async let crew: Void = model.refreshCrew()
            async let list = model.api.sessions()
            _ = try await crew
            sessions = try await list
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func send() {
        guard let member = pickedMember else { return }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let toUpload = photos
        sending = true
        error = nil
        Task {
            defer { sending = false }
            do {
                let session = try await model.api.createSession(crew: member.name)
                var ids: [String] = []
                for photo in toUpload {
                    ids.append(try await model.api.uploadAttachment(session.id, data: photo.jpeg, contentType: "image/jpeg").id)
                }
                _ = try await model.api.postMessage(session.id, content: content, attachmentIds: ids)
                text = ""
                photos = []
                model.chatPath.append(.thread(session.id))
                sessions = (try? await model.api.sessions()) ?? sessions
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// One chat in a list: avatar, headline, preview, crew, "from an alert".
struct SessionRow: View {
    let session: Session
    let style: CrewStyle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CrewAvatar(name: session.crew ?? "?", style: style, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.summary ?? session.title ?? "New chat")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(RelativeTime.short(session.activityDate))
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textMeta)
                }
                if let preview = session.preview {
                    Text(preview)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let crew = session.crew {
                        Text(crewDisplayName(crew)).foregroundStyle(style.ink)
                    }
                    if session.alertId != nil {
                        Text("·").foregroundStyle(Palette.textMeta)
                        Image(systemName: "bell").font(.system(size: 10, weight: .semibold))
                        Text("from an alert").fontWeight(.medium)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 3)
            }
        }
        .padding(.vertical, 4)
    }
}
