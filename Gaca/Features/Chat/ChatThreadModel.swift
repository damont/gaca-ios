import Foundation
import Observation

/// One chat thread: the transcript as the API stores it, plus whatever the live event
/// stream says is happening right now. The live part is purely transient display — once a
/// run finishes, the thread re-reads the server's copy (which carries the activity
/// summary) and drops what it streamed.
@MainActor
@Observable
final class ChatThreadModel {
    let sessionId: String
    private let api: APIClient

    var detail: SessionDetail?
    var loadError: String?
    var sendError: String?
    var sending = false
    /// A message just sent, shown until the server's copy arrives.
    var pending: PendingMessage?

    // Live run state, from the event stream.
    var running = false
    var liveText = ""
    var currentTool: String?
    var runStartedAt: Date?

    struct PendingMessage: Equatable {
        let text: String
        let photos: [PendingPhoto]
        let sentAt: Date
    }

    private var streamTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var liveRunId: String?

    init(sessionId: String, api: APIClient) {
        self.sessionId = sessionId
        self.api = api
    }

    var messages: [Message] { detail?.messages ?? [] }

    /// What to say under the crew member's name in the header.
    var status: String? {
        guard running else { return nil }
        if let currentTool { return "Using \(currentTool)…" }
        return liveText.isEmpty ? "Working…" : "Writing…"
    }

    func start() async {
        await reload()
        guard streamTask == nil, let detail else { return }
        running = detail.running ?? false
        runStartedAt = detail.runStartedAt
        let resume = detail.resumeSeq ?? 0
        let stream = EventStream(api: api, sessionId: sessionId).events(from: resume)
        streamTask = Task { [weak self] in
            for await event in stream {
                self?.apply(event)
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
    }

    func reload() async {
        do {
            let fresh = try await api.session(sessionId)
            detail = fresh
            loadError = nil
            // The server's copy of a just-sent message replaces the placeholder.
            if let pending, fresh.messages.contains(where: { $0.isUser && $0.createdAt >= pending.sentAt.addingTimeInterval(-30) }) {
                self.pending = nil
            }
            if fresh.running == false, liveRunId == nil { running = false }
        } catch is CancellationError {
        } catch {
            if detail == nil { loadError = error.localizedDescription }
        }
    }

    func apply(_ event: ChatEvent) {
        switch event {
        case .delta(let runId, let text):
            beginRun(runId)
            liveText += text
        case .toolStarted(let runId, let tool):
            beginRun(runId)
            currentTool = tool.isEmpty ? nil : tool
        case .toolCompleted(let runId, _):
            beginRun(runId)
            currentTool = nil
        case .heartbeat(let runId, _):
            beginRun(runId)
        case .completed:
            endRun()
            scheduleReload()
        case .failed(_, let error):
            endRun()
            sendError = error
            scheduleReload()
        case .other:
            break
        }
    }

    private func beginRun(_ runId: String?) {
        if runId != liveRunId {
            liveRunId = runId
            liveText = ""
            currentTool = nil
            if !running || runStartedAt == nil { runStartedAt = .now }
        }
        running = true
    }

    private func endRun() {
        running = false
        liveRunId = nil
        liveText = ""
        currentTool = nil
        runStartedAt = nil
    }

    /// Coalesces back-to-back completions (e.g. a replayed history) into one fetch.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    func send(text: String, photos: [PendingPhoto]) async -> Bool {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty || !photos.isEmpty else { return false }
        sending = true
        sendError = nil
        pending = PendingMessage(text: content, photos: photos, sentAt: .now)
        defer { sending = false }
        do {
            var ids: [String] = []
            for photo in photos {
                ids.append(try await api.uploadAttachment(sessionId, data: photo.jpeg, contentType: "image/jpeg").id)
            }
            _ = try await api.postMessage(sessionId, content: content, attachmentIds: ids)
            running = true
            if runStartedAt == nil { runStartedAt = .now }
            await reload()
            return true
        } catch {
            pending = nil
            sendError = error.localizedDescription
            return false
        }
    }
}
