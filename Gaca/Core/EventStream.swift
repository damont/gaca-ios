import Foundation

/// One GacaEvent off a session's SSE stream (gaca-api schemas/event.py). Clients switch on
/// `type`; unknown types are ignored so the API can add new ones without breaking the app.
enum ChatEvent: Sendable, Equatable {
    case delta(runId: String?, text: String)
    case toolStarted(runId: String?, tool: String)
    case toolCompleted(runId: String?, tool: String)
    case heartbeat(runId: String?, idleSeconds: Double)
    case completed(runId: String?)
    case failed(runId: String?, error: String)
    case other

    private struct Envelope: Decodable {
        let type: String
        let runId: String?
        let text: String?
        let tool: String?
        let idleSeconds: Double?
        let error: String?
    }

    static func decode(_ data: Data) -> ChatEvent {
        guard let e = try? APIClient.decoder.decode(Envelope.self, from: data) else { return .other }
        switch e.type {
        case "assistant.delta": return .delta(runId: e.runId, text: e.text ?? "")
        case "tool.started": return .toolStarted(runId: e.runId, tool: e.tool ?? "")
        case "tool.completed": return .toolCompleted(runId: e.runId, tool: e.tool ?? "")
        case "run.heartbeat": return .heartbeat(runId: e.runId, idleSeconds: e.idleSeconds ?? 0)
        case "run.completed": return .completed(runId: e.runId)
        case "run.failed": return .failed(runId: e.runId, error: e.error ?? "The run failed")
        default: return .other
        }
    }
}

/// Server-sent-events framing: accumulates `event:`/`id:`/`data:` lines until a blank line.
struct SSEParser {
    struct Frame: Equatable {
        var event: String?
        var id: String?
        var data: String
    }

    private var event: String?
    private var id: String?
    private var data: [String] = []

    /// Feed one line (without its newline). Returns a frame when a blank line ends one.
    mutating func feed(_ line: String) -> Frame? {
        if line.isEmpty {
            defer { event = nil; id = nil; data = [] }
            guard !data.isEmpty else { return nil }
            return Frame(event: event, id: id, data: data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil } // comment / keep-alive
        let (field, value) = Self.split(line)
        switch field {
        case "event": event = value
        case "id": id = value
        case "data": data.append(value)
        default: break
        }
        return nil
    }

    private static func split(_ line: String) -> (String, String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, "") }
        var value = line[line.index(after: colon)...]
        if value.first == " " { value = value.dropFirst() }
        return (String(line[..<colon]), String(value))
    }
}

/// A session's live event stream: connects from `resumeSeq` (the API tells us where), and
/// reconnects with Last-Event-ID after a drop, until the consuming task is cancelled.
struct EventStream {
    let api: APIClient
    let sessionId: String

    func events(from resumeSeq: Int) -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            let task = Task {
                var lastId = resumeSeq
                while !Task.isCancelled {
                    do {
                        var req = api.request("GET", "sessions/\(sessionId)/events")
                        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        req.setValue(String(lastId), forHTTPHeaderField: "Last-Event-ID")
                        req.timeoutInterval = 3600
                        let (bytes, response) = try await URLSession.shared.bytes(for: req)
                        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                            api.onUnauthorized?()
                            break
                        }
                        var parser = SSEParser()
                        // `lines` drops empty lines, so frame boundaries come from the
                        // `data:` line itself: every GacaEvent is a single data line.
                        for try await line in bytes.lines {
                            _ = parser.feed(line)
                            if line.hasPrefix("data:"), let frame = parser.feed("") {
                                if let id = frame.id.flatMap(Int.init) { lastId = id }
                                continuation.yield(ChatEvent.decode(Data(frame.data.utf8)))
                            }
                        }
                    } catch {
                        if Task.isCancelled { break }
                    }
                    try? await Task.sleep(for: .seconds(2))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
