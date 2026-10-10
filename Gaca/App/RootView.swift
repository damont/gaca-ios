import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.auth {
            case .restoring:
                ProgressView().tint(Palette.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.page)
            case .signedOut:
                LoginView()
            case .signedIn:
                MainTabs()
            }
        }
        .task { await model.restore() }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            NavigationStack(path: $model.chatPath) {
                ChatHomeView().routes()
            }
            .tabItem { Label("Chat", systemImage: "bubble.left.fill") }
            .tag(AppTab.chat)

            NavigationStack(path: $model.todayPath) {
                TodayView().routes()
            }
            .tabItem { Label("Today", systemImage: "sun.max.fill") }
            .tag(AppTab.today)

            NavigationStack(path: $model.inboxPath) {
                InboxView().routes()
            }
            .tabItem { Label("Inbox", systemImage: "tray.fill") }
            .tag(AppTab.inbox)
            .badge(model.inboxCount)

            NavigationStack(path: $model.artifactsPath) {
                ArtifactsView().routes()
            }
            .tabItem { Label("Artifacts", systemImage: "square.grid.2x2.fill") }
            .tag(AppTab.artifacts)

            NavigationStack(path: $model.skillsPath) {
                SkillsView().routes()
            }
            .tabItem { Label("Skills", systemImage: "sparkle") }
            .tag(AppTab.skills)
        }
        .tint(Palette.accent)
        .task {
            try? await model.refreshCrew()
            await model.refreshInboxCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await model.refreshInboxCount() }
        }
    }
}

extension View {
    /// Every tab's stack can push any screen.
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .thread(let id, let draft): ChatThreadView(sessionId: id, prefill: draft)
            case .history: ChatHistoryView()
            case .alert(let id): AlertDetailView(alertId: id)
            case .artifact(let id): ArtifactViewer(artifactId: id)
            case .crew(let name): CrewDetailView(name: name)
            case .settings: SettingsView()
            }
        }
    }
}
