import SwiftUI

/// What one crew member is set up to do. Setup is changed by talking to it, not here.
struct CrewDetailView: View {
    @Environment(AppModel.self) private var model
    let name: String
    @State private var profile: CrewProfile?
    @State private var error: String?
    @State private var showInstructions = false
    @State private var starting = false

    private var style: CrewStyle { profile.map { CrewStyle(hex: $0.color) } ?? model.style(for: name) }

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    CrewAvatar(name: name, style: style, size: 72)
                    HStack(spacing: 8) {
                        Text(crewDisplayName(name)).font(.system(size: 24, weight: .bold))
                        if profile?.isDefault == true {
                            Text("default").font(.system(size: 12, weight: .semibold)).foregroundStyle(style.ink)
                                .padding(.horizontal, 7).padding(.vertical, 1)
                                .background(Capsule().fill(style.tint))
                        }
                    }
                    if let profile {
                        let online = profile.status == "online"
                        HStack(spacing: 6) {
                            Circle().fill(online ? style.color : SeverityStyle.of("urgent").dot).frame(width: 8, height: 8)
                            Text((online ? "Online" : "Offline") + (profile.engine.map { " · \($0)" } ?? ""))
                        }
                        .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            if let error {
                Section { ErrorLine(text: error) }.listRowBackground(Color.clear)
            } else if profile == nil {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }

            if let profile {
                if let missing = profile.unavailable, !missing.isEmpty {
                    Text("Couldn't read: \(missing.joined(separator: ", ")). Pull down to retry.")
                        .font(.system(size: 14)).foregroundStyle(SeverityStyle.of("warn").ink)
                        .listRowBackground(Color.clear)
                }

                Section {
                    if profile.purpose?.isGeneric ?? true {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("A general assistant — nothing specific has been set up for \(crewDisplayName(name)).")
                            Text("Tell it in chat what it should focus on, and it can take that on as its job.")
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .font(.system(size: 16))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            if let summary = profile.purpose?.summary { Text(summary).font(.system(size: 16)) }
                            if let instructions = profile.purpose?.instructions {
                                Text(instructions)
                                    .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                                    .lineLimit(showInstructions ? nil : 4)
                                Button(showInstructions ? "Show less" : "Show full instructions") { showInstructions.toggle() }
                                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.accent)
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                } header: { SectionLabel(text: "Dedicated to") }

                Section {
                    row("Model", [profile.model?.name, profile.model?.provider].compactMap { $0 }.joined(separator: " · ").ifEmpty("—"))
                    row("Reachable through", (profile.channels ?? []).map { channel in
                        channel.name + (channel.needsAttention == true ? " (needs attention)" : channel.state == "connected" ? "" : " (disconnected)")
                    }.joined(separator: ", ").ifEmpty("—"))
                    row("Skills", "\(profile.skillCount ?? 0)" + ((profile.skillCategories ?? []).isEmpty ? "" : " in \(profile.skillCategories!.count) groups"))
                    row("Tools", (profile.toolsets ?? []).map(\.label).joined(separator: ", ").ifEmpty("—"))
                } header: { SectionLabel(text: "Setup") }

                Section {
                    let jobs = profile.jobs ?? []
                    if jobs.isEmpty {
                        Text("Nothing scheduled").foregroundStyle(Palette.textSecondary)
                    }
                    ForEach(jobs) { job in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(job.name).font(.system(size: 16))
                                if job.enabled == false {
                                    Text("paused").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                                        .padding(.horizontal, 7).padding(.vertical, 1).background(Capsule().fill(Palette.field))
                                }
                            }
                            Text(jobMeta(job)).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                        }
                    }
                } header: { SectionLabel(text: "Scheduled · \((profile.jobs ?? []).count)") }
            }
        }
        .listStyle(.insetGrouped)
        .gacaPage()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(action: changeInChat) {
                    HStack {
                        if starting { ProgressView().tint(.white) }
                        Text("Change this in chat")
                    }
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(style.solid))
                }
                .disabled(starting)
                Text("Setup is edited by talking to \(crewDisplayName(name)).")
                    .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            .background(.bar)
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.trailing)
        }
        .font(.system(size: 16))
    }

    private func jobMeta(_ job: CrewProfile.Job) -> String {
        var parts: [String] = []
        if let next = job.nextRun, job.enabled != false {
            parts.append("Next: " + next.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
        }
        if let status = job.lastStatus {
            parts.append(status == "ok" ? "Last run succeeded" : "Last run: \(status)")
        }
        if let kind = job.kind, kind != "agent" { parts.append("Runs a script, no AI") }
        return parts.isEmpty ? job.schedule : parts.joined(separator: " · ")
    }

    private func load() async {
        do {
            profile = try await model.api.crewProfile(name)
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = "Couldn't load this crew member. " + error.localizedDescription
        }
    }

    private func changeInChat() {
        starting = true
        Task {
            defer { starting = false }
            do {
                let session = try await model.api.createSession(crew: name)
                model.push(.thread(session.id, draft: "I'd like to change how you're set up: "))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
