import SwiftUI

/// One automation: when it runs, "Run now", and its run history with each run's output.
/// A failed run can open a chat with the crew member about it.
struct AutomationDetailView: View {
    @Environment(AppModel.self) private var model
    let crew: String
    let id: String

    @State private var automation: Automation?
    /// Newest first.
    @State private var runs: [AutomationRun] = []
    /// Runs whose output is open. The newest run opens by itself when it failed.
    @State private var expanded: Set<String> = []
    @State private var loading = true
    @State private var error: String?
    /// Set when only the run history couldn't be read; the rest of the screen is still true.
    @State private var runsError: String?
    @State private var requestingRun = false
    @State private var runRequested = false
    @State private var startingChat = false

    /// "8 of 10" from the job's recent runs; nil with no history.
    private var successLine: String? {
        let done = (automation?.marks ?? []).filter { RunStatus(wire: $0.status) != .running }
        guard !done.isEmpty else { return nil }
        return "\(done.filter { RunStatus(wire: $0.status) == .ok }.count) of \(done.count)"
    }

    /// Median length of the finished runs, so one slow night doesn't skew it.
    private var typicalRun: String? {
        let seconds = runs.compactMap(\.durationSeconds).sorted()
        guard !seconds.isEmpty else { return nil }
        return WhenText.duration(seconds[seconds.count / 2])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if loading && automation == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if let automation {
                    summary(automation)
                    if let error { ErrorLine(text: error) }
                    SectionLabel(text: "Run history").padding(.horizontal, 4).padding(.top, 12)
                    if let runsError {
                        Text("Couldn't read the run history: \(runsError)").font(.system(size: 15)).foregroundStyle(Palette.textMeta)
                    } else if runs.isEmpty {
                        Text("No runs yet.").font(.system(size: 15)).foregroundStyle(Palette.textMeta).padding(4)
                    }
                    ForEach(runs) { run in
                        RunRow(run: run, open: expanded.contains(run.id), asking: startingChat,
                               toggle: { toggle(run.id) }, ask: { askAbout(run, in: automation) })
                    }
                } else {
                    EmptyState(systemImage: "exclamationmark.triangle", title: "Couldn't open this automation",
                               message: error ?? "Pull down to try again.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Palette.page)
        .navigationTitle(automation?.name ?? "Automation")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func summary(_ a: Automation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StatusPill(status: a.state)
                Text(a.schedule + (a.cronExpr.map { " · \($0)" } ?? ""))
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textSecondary)
            }
            Button(action: runNow) {
                ZStack {
                    if requestingRun { ProgressView().tint(Palette.onAccent) } else { Text("Run now").font(.system(size: 17, weight: .semibold)) }
                }
                .foregroundStyle(Palette.onAccent)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(Palette.accent))
            }
            .disabled(requestingRun)
            if runRequested {
                Text("Requested. It starts within about a minute — pull down to see it.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
            }
            HStack(spacing: 8) {
                stat("Success", successLine ?? "—")
                stat("Typical run", typicalRun ?? "—")
                stat("Next", a.nextRun.map { WhenText.dayAndTime($0) } ?? "—")
            }
            RunDots(recent: a.marks)
        }
        .padding(.top, 8)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            Text(value).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    private func toggle(_ runId: String) {
        if expanded.contains(runId) { expanded.remove(runId) } else { expanded.insert(runId) }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            guard let found = try await model.api.automations(crew: crew).automations.first(where: { $0.id == id }) else {
                automation = nil
                error = "This automation no longer exists."
                return
            }
            automation = found
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            return
        }
        do {
            let fresh = try await model.api.automationRuns(crew: crew, id: id)
            if expanded.isEmpty, let first = fresh.first, first.runStatus == .failed { expanded = [first.id] }
            runs = fresh
            runsError = nil
        } catch is CancellationError {
        } catch {
            runsError = error.localizedDescription
        }
    }

    private func runNow() {
        guard !requestingRun else { return }
        requestingRun = true
        runRequested = false
        error = nil
        Task {
            defer { requestingRun = false }
            do {
                automation = try await model.api.runAutomation(crew: crew, id: id)
                runRequested = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Opens a chat with the job's crew member about a failed run, the question already typed (not sent).
    private func askAbout(_ run: AutomationRun, in automation: Automation) {
        guard !startingChat else { return }
        startingChat = true
        error = nil
        Task {
            defer { startingChat = false }
            do {
                let session = try await model.api.createSession(crew: crew)
                let when = run.startedAt.map { WhenText.dayAndTime($0) } ?? "recently"
                var draft = "My \u{201C}\(automation.name)\u{201D} automation failed (\(when))."
                if let why = run.output { draft += " It said: \(why)" }
                draft += " What happened, and can you fix it?"
                model.push(.thread(session.id, draft: draft))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct RunRow: View {
    let run: AutomationRun
    let open: Bool
    let asking: Bool
    let toggle: () -> Void
    let ask: () -> Void

    var body: some View {
        let failed = run.runStatus == .failed
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    RunBadge(status: run.runStatus)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(run.startedAt.map { WhenText.dayAndTime($0) } ?? "Unknown time")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                        if !open, let output = run.output {
                            Text(output).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if let d = run.durationSeconds {
                        Text(WhenText.duration(d)).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    }
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textMeta)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Hides this run's output" : "Shows this run's output")
            if open {
                if let output = run.output {
                    Text(output)
                        .font(.system(size: 12, design: .monospaced))
                        .lineSpacing(4)
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.page))
                        .padding(.top, 10)
                } else {
                    Text("It had nothing to say.").font(.system(size: 13)).foregroundStyle(Palette.textMeta).padding(.top, 8)
                }
                if failed {
                    Button("Ask about this", action: ask)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: 44)
                        .disabled(asking)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(failed ? SeverityStyle.of("urgent").dot : Palette.border,
                                                            lineWidth: failed ? 1.5 : 0.5))
    }
}
