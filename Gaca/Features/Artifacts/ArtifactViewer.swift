import SwiftUI
import WebKit

/// Shows one artifact page. The API serves the page already wrapped (a sandbox policy that
/// cuts it off from the network, the theme, and the SDK); the page talks to the app only
/// through `window.app`, whose data calls the app forwards untouched to the API.
struct ArtifactViewer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    let artifactId: String

    @State private var artifact: Artifact?
    @State private var html: String?
    @State private var error: String?
    @State private var reloadToken = 0
    @State private var resumeToken = 0
    @State private var toast: String?
    @State private var confirmDelete = false
    /// The chat made for this page the first time it asked (see `ask`).
    @State private var askedSessionId: String?

    var body: some View {
        ZStack {
            Palette.page.ignoresSafeArea()
            if let html {
                ArtifactWebView(html: html, reloadToken: reloadToken, resumeToken: resumeToken) { call in
                    await handle(call)
                }
                .ignoresSafeArea(edges: .bottom)
            } else if let error {
                EmptyState(systemImage: "exclamationmark.triangle", title: "Couldn't open this page", message: error)
            } else {
                ProgressView()
            }
            if let toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Palette.accent.opacity(0.95)))
                        .padding(.bottom, 30)
                }
                .transition(.opacity)
            }
        }
        .navigationTitle(artifact?.title ?? "Page")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Reload", systemImage: "arrow.clockwise") { Task { await load() } }
                    Button("Archive", systemImage: "archivebox") {
                        Task {
                            _ = try? await model.api.patchArtifact(artifactId, ArtifactPatch(archived: true))
                            dismiss()
                        }
                    }
                    Button("Delete…", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        .confirmationDialog("Delete this page?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await model.api.deleteArtifact(artifactId)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The page and everything it stored will be gone for good. Archive it instead to just tidy it away.")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { resumeToken += 1 }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            async let meta = model.api.artifact(artifactId)
            async let page = model.api.artifactPage(artifactId)
            artifact = try await meta
            html = try await page
            reloadToken += 1
            error = nil
            try? await model.api.markArtifactOpened(artifactId)
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// One `window.app.*` call from the page. UI requests are handled here; data requests
    /// go straight to the API, which validates and dispatches them.
    private func handle(_ call: BridgeCall) async -> BridgeReply {
        switch call.method {
        case "ask":
            let text = String((call.args["text"] as? String ?? "").prefix(4000))
            await ask(text)
            return .ok("null")
        case "openUrl":
            guard let raw = call.args["url"] as? String, let url = URL(string: raw),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                return .failure(status: 400, message: "only http(s) addresses can be opened")
            }
            openURL(url)
            return .ok("null")
        case "toast":
            show(String((call.args["message"] as? String ?? "").prefix(200)))
            return .ok("null")
        default:
            do {
                let data = try await model.api.artifactCall(artifactId, method: call.method, args: call.argsJSON)
                let body = String(decoding: data, as: UTF8.self)
                return .ok(body.isEmpty ? "null" : body)
            } catch APIError.http(let status, let detail) {
                return .failure(status: status, message: detail ?? "request failed (\(status))")
            } catch {
                return .failure(status: 0, message: error.localizedDescription)
            }
        }
    }

    /// "Ask about this page": opens the chat the page came from with the text drafted.
    private func ask(_ text: String) async {
        do {
            let sessionId: String
            if let existing = artifact?.sessionId ?? askedSessionId {
                sessionId = existing
            } else {
                // The first ask makes the chat; asking again reuses it instead of piling up empty chats.
                let created = try await model.api.createSession(crew: artifact?.crew, title: artifact?.title).id
                askedSessionId = created
                sessionId = created
            }
            model.push(.thread(sessionId, draft: text))
        } catch {
            show(error.localizedDescription)
        }
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { if toast == message { toast = nil } }
        }
    }
}

struct BridgeCall {
    let id: String
    let method: String
    let args: [String: Any]
    let argsJSON: Data
}

enum BridgeReply {
    case ok(String)
    case failure(status: Int, message: String)
}

/// A locked-down WKWebView: no persistent storage, no navigation away from the page, and
/// one message handler (`gaca`) the SDK posts its calls to.
struct ArtifactWebView: UIViewRepresentable {
    let html: String
    let reloadToken: Int
    let resumeToken: Int
    let onCall: @MainActor (BridgeCall) async -> BridgeReply

    func makeCoordinator() -> Coordinator { Coordinator(onCall: onCall) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "gaca")
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = UIColor(Palette.page)
        web.scrollView.backgroundColor = UIColor(Palette.page)
        context.coordinator.web = web
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let c = context.coordinator
        c.onCall = onCall
        if c.loadedToken != reloadToken {
            c.loadedToken = reloadToken
            web.loadHTMLString(html, baseURL: nil)
        }
        if c.resumedToken != resumeToken {
            c.resumedToken = resumeToken
            web.evaluateJavaScript("window.__gaca&&window.__gaca.resume&&window.__gaca.resume()")
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "gaca")
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onCall: @MainActor (BridgeCall) async -> BridgeReply
        weak var web: WKWebView?
        var loadedToken = -1
        var resumedToken = 0

        init(onCall: @escaping @MainActor (BridgeCall) async -> BridgeReply) {
            self.onCall = onCall
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let id = body["id"] as? String, let method = body["method"] as? String else { return }
            let args = body["args"] as? [String: Any] ?? [:]
            let json = (try? JSONSerialization.data(withJSONObject: args)) ?? Data("{}".utf8)
            let call = BridgeCall(id: id, method: method, args: args, argsJSON: json)
            Task {
                let reply = await onCall(call)
                resolve(id, reply)
            }
        }

        private func resolve(_ id: String, _ reply: BridgeReply) {
            let ok: Bool, payload: String
            switch reply {
            case .ok(let json): ok = true; payload = json
            case .failure(let status, let message):
                ok = false
                let obj: [String: Any] = ["status": status, "message": message]
                payload = String(decoding: (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8), as: UTF8.self)
            }
            let script = "window.__gaca&&window.__gaca.resolve(\(Self.quote(id)),\(ok),\(Self.quote(payload)))"
            web?.evaluateJavaScript(script)
        }

        /// A JS string literal (JSON string encoding is valid JS).
        static func quote(_ s: String) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
            let array = String(decoding: data, as: UTF8.self)
            return String(array.dropFirst().dropLast())
        }

        // The page itself loads; anything else — a link tap, a form, a script redirect — is
        // stopped, and http(s) links open in Safari instead.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if action.navigationType == .other, action.request.url?.absoluteString == "about:blank" { return .allow }
            if let url = action.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
               action.navigationType == .linkActivated {
                await UIApplication.shared.open(url)
            }
            return .cancel
        }
    }
}
