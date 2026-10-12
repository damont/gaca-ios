import MarkdownUI
import SwiftUI

/// A conversation with one crew member. Your messages are compact bubbles on the right;
/// the crew member's replies are full-width prose with what it did summarized above them
/// (see gaca/gaca-planning/chat/design.md).
struct ChatThreadView: View {
    @Environment(AppModel.self) private var app
    @State private var model: ChatThreadModel?
    @State private var text = ""
    @State private var photos: [PendingPhoto] = []
    @State private var alert: Alert?
    let sessionId: String
    var prefill: String? = nil

    private var crewName: String? { model?.detail?.crew }
    private var style: CrewStyle { app.style(for: crewName) }
    private var displayName: String { crewName.map(crewDisplayName) ?? "Chat" }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.page)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { header }
        }
        .toolbar(.hidden, for: .tabBar)
        .task {
            if model == nil {
                let m = ChatThreadModel(sessionId: sessionId, api: app.api)
                model = m
                if let prefill, text.isEmpty { text = prefill }
                if app.crew.isEmpty { try? await app.refreshCrew() }
                await m.start()
                if let alertId = m.detail?.alertId { alert = try? await app.api.alert(alertId) }
            }
        }
        .onAppear { app.visibleSessionId = sessionId }
        .onDisappear {
            if app.visibleSessionId == sessionId { app.visibleSessionId = nil }
            model?.stop()
            model = nil
        }
    }

    private var header: some View {
        Button {
            if let crewName { app.push(.crew(crewName)) }
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 6) {
                    if let crewName { CrewAvatar(name: crewName, style: style, size: 22) }
                    Text(displayName).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                }
                if let status = model?.status {
                    Text(status).font(.system(size: 12)).foregroundStyle(style.ink).lineLimit(1)
                } else if let title = model?.detail?.summary {
                    Text(title).font(.system(size: 12)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows what this crew member is set up to do")
    }

    @ViewBuilder
    private func content(_ model: ChatThreadModel) -> some View {
        if let error = model.loadError, model.detail == nil {
            EmptyState(systemImage: "exclamationmark.bubble", title: "Couldn't load this chat", message: error)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if let alert {
                            AlertContextCard(alert: alert) { app.push(.alert(alert.id)) }
                        }
                        if model.messages.isEmpty && model.pending == nil && !model.running {
                            Text("Say hello to \(displayName) to get started.")
                                .font(.system(size: 15))
                                .foregroundStyle(Palette.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }
                        ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                            if let label = DayDivider.label(for: message, previous: index > 0 ? model.messages[index - 1] : nil) {
                                DayDivider(text: label)
                            }
                            MessageView(message: message, crewName: crewName, style: style)
                        }
                        if let pending = model.pending {
                            UserBubble(text: pending.text, localPhotos: pending.photos.map(\.thumbnail), attachments: [])
                                .opacity(0.7)
                        }
                        if model.running {
                            LiveTurn(crewName: crewName, style: style, text: model.liveText,
                                     tool: model.currentTool, startedAt: model.runStartedAt)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await model.reload() }
                .onChange(of: model.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: model.liveText) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: model.pending) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    if let error = model.sendError {
                        ErrorLine(text: error).padding(.horizontal, 10)
                    }
                    Composer(text: $text, photos: $photos, placeholder: "Message \(displayName)…",
                             style: style, sending: model.sending) {
                        let t = text, p = photos
                        text = ""; photos = []
                        Task {
                            if await !model.send(text: t, photos: p) { text = t; photos = p }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .background(LinearGradient(colors: [Palette.page.opacity(0), Palette.page], startPoint: .top, endPoint: .center))
            }
        }
    }
}

extension AppModel {
    /// Push onto whichever tab is showing.
    func push(_ route: Route) {
        switch tab {
        case .chat: chatPath.append(route)
        case .today: todayPath.append(route)
        case .inbox: inboxPath.append(route)
        case .artifacts: artifactsPath.append(route)
        case .skills: skillsPath.append(route)
        }
    }
}

// MARK: - Messages

struct MessageView: View {
    let message: Message
    let crewName: String?
    let style: CrewStyle

    var body: some View {
        if message.isUser {
            UserBubble(text: message.text, localPhotos: [], attachments: message.attachments ?? [])
        } else {
            AssistantTurn(message: message, crewName: crewName, style: style)
        }
    }
}

struct UserBubble: View {
    let text: String
    let localPhotos: [UIImage]
    let attachments: [Attachment]

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(Array(localPhotos.enumerated()), id: \.offset) { _, image in
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 180, height: 120).clipShape(RoundedRectangle(cornerRadius: 16))
            }
            ForEach(attachments) { attachment in
                AuthorizedImage(path: attachment.url)
                    .frame(width: 180, height: 120).clipShape(RoundedRectangle(cornerRadius: 16))
            }
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20).fill(Palette.accent))
                    .textSelection(.enabled)
                    .contextMenu { Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text } }
            }
        }
        .frame(maxWidth: 300, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct AssistantTurn: View {
    @Environment(AppModel.self) private var app
    let message: Message
    let crewName: String?
    let style: CrewStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TurnHeader(crewName: crewName, style: style)
            if let activity = message.activity {
                ActivitySummary(activity: activity)
            }
            if !message.text.isEmpty {
                Markdown(message.text)
                    .markdownTheme(.gaca)
                    .textSelection(.enabled)
                    .contextMenu { Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text } }
            }
            ForEach(message.artifacts ?? []) { ref in
                ArtifactCard(ref: ref, style: app.style(for: ref.crew ?? crewName)) {
                    app.push(.artifact(ref.id))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TurnHeader: View {
    let crewName: String?
    let style: CrewStyle

    var body: some View {
        HStack(spacing: 8) {
            if let crewName { CrewAvatar(name: crewName, style: style, size: 22) }
            Text(crewName.map(crewDisplayName) ?? "Assistant")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(style.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Ran terminal 3× · 41s" — the API's summary of what the crew member did; tap for the list.
struct ActivitySummary: View {
    let activity: MessageActivity
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    Text(activity.label)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.activity))
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Hides the tools" : "Shows each tool it used")
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(activity.tools, id: \.name) { tool in
                        HStack(spacing: 6) {
                            Image(systemName: (tool.errors ?? 0) > 0 ? "exclamationmark.triangle" : "wrench.and.screwdriver")
                                .font(.system(size: 11))
                            Text(tool.name).font(.system(size: 13, design: .monospaced))
                            if tool.count > 1 { Text("×\(tool.count)").font(.system(size: 13)) }
                            if let errors = tool.errors, errors > 0 { Text("· \(errors) failed").font(.system(size: 13)) }
                        }
                        .foregroundStyle(Palette.textSecondary)
                    }
                }
                .padding(.leading, 10)
            }
        }
    }
}

/// The reply that's being written right now: a live "what it's doing" row, then the text
/// as it streams in.
struct LiveTurn: View {
    let crewName: String?
    let style: CrewStyle
    let text: String
    let tool: String?
    let startedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TurnHeader(crewName: crewName, style: style)
            if text.isEmpty || tool != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 8) {
                        FlightMark(color: style.ink)
                        Text(tool.map { "Using \($0)" } ?? "Working").fontWeight(.semibold).foregroundStyle(style.ink)
                        if let startedAt {
                            Text(Self.elapsed(from: startedAt, to: context.date))
                                .monospacedDigit().foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12).fill(style.tint))
                }
                .accessibilityElement(children: .combine)
            }
            if !text.isEmpty {
                Markdown(text + " ▍").markdownTheme(.gaca)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return s < 60 ? "\(s)s" : "\(s / 60)m \(String(format: "%02d", s % 60))s"
    }
}

/// The Gaca mark in flight, in the crew's colour, gliding while a run is working.
/// Holds still when Reduce Motion is on.
struct FlightMark: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false
    var body: some View {
        Image("Mark-in-flight-mono")
            .renderingMode(.template)
            .resizable().scaledToFit()
            .frame(width: 18, height: 18)
            .foregroundStyle(color)
            .rotationEffect(.degrees(up ? 3 : -4))
            .offset(y: up ? -1.5 : 1.5)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: up)
            .onAppear { up = !reduceMotion }
            .accessibilityHidden(true)
    }
}

/// A page the crew member made, linked from its reply.
struct ArtifactCard: View {
    let ref: ArtifactRef
    let style: CrewStyle
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(style.ink)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10).fill(style.tint))
                VStack(alignment: .leading, spacing: 1) {
                    Text(ref.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                    Text(ref.missing == true ? "This page is no longer available" : (ref.description ?? "Page"))
                        .font(.system(size: 13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textMeta)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(ref.missing == true)
    }
}

/// The alert a chat was opened from, pinned at the top of the thread.
struct AlertContextCard: View {
    let alert: Alert
    let open: () -> Void

    var body: some View {
        let severity = SeverityStyle.of(alert.severity)
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: "bell")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(severity.ink)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9).fill(severity.background))
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(severity.label.uppercased()) ALERT · \(RelativeTime.short(alert.createdAt))")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5).foregroundStyle(severity.ink)
                    Text(alert.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textMeta)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the alert")
    }
}

/// "Today 8:42 AM" between messages more than an hour apart.
struct DayDivider: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.textMeta)
            .frame(maxWidth: .infinity)
    }

    static func label(for message: Message, previous: Message?) -> String? {
        if let previous, message.createdAt.timeIntervalSince(previous.createdAt) < 3600 { return nil }
        let date = message.createdAt
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Today \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday \(time)" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}

/// A chat photo: its URL is relative to the API and needs the bearer token.
struct AuthorizedImage: View {
    @Environment(AppModel.self) private var app
    let path: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Palette.chip
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(Palette.textMeta)
            }
        }
        .task(id: path) {
            if let data = try? await app.api.attachmentData(path) { image = UIImage(data: data) }
        }
        .accessibilityLabel("Photo")
    }
}

extension MarkdownUI.Theme {
    /// Reply prose: 16pt body, tight lists, quiet code.
    @MainActor static let gaca = Theme()
        .text {
            ForegroundColor(Palette.textPrimary)
            FontSize(16)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            BackgroundColor(Palette.activity)
        }
        .link { ForegroundColor(Palette.accent); UnderlineStyle(.single) }
        .strong { FontWeight(.semibold) }
        .heading1 { config in config.label.markdownTextStyle { FontWeight(.bold); FontSize(20) }.markdownMargin(top: 8, bottom: 4) }
        .heading2 { config in config.label.markdownTextStyle { FontWeight(.bold); FontSize(18) }.markdownMargin(top: 8, bottom: 4) }
        .heading3 { config in config.label.markdownTextStyle { FontWeight(.semibold); FontSize(17) }.markdownMargin(top: 6, bottom: 2) }
        .paragraph { config in config.label.lineSpacing(4).markdownMargin(top: 0, bottom: 8) }
        .listItem { config in config.label.markdownMargin(top: 2) }
        .codeBlock { config in
            ScrollView(.horizontal) {
                config.label.markdownTextStyle { FontFamilyVariant(.monospaced); FontSize(.em(0.85)) }
                    .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.activity))
            .markdownMargin(top: 4, bottom: 8)
        }
        .blockquote { config in
            config.label.foregroundStyle(Palette.textSecondary).padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(Palette.border).frame(width: 3) }
        }
}
