import SwiftUI

/// The daily briefing your agent posts each morning. Display only.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var briefing: Briefing?
    @State private var loading = true
    @State private var error: String?
    /// Every automation, for the "Scheduled today" card; empty when they can't be read (the card then hides).
    @State private var automations: [Automation] = []

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private static let wireDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                dayBar
                if loading && briefing == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if error != nil {
                    EmptyState(systemImage: "exclamationmark.triangle", title: "Couldn't load the briefing.", message: "Pull down to try again.")
                } else if let briefing, briefing.summary != nil || !(briefing.sections ?? []).isEmpty {
                    if let summary = briefing.summary {
                        Text(summary)
                            .font(.system(size: 17))
                            .lineSpacing(3)
                            .foregroundStyle(Palette.onSuggest)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Palette.suggest))
                    }
                    if isToday { ScheduledCard(automations: automations) }
                    ForEach(briefing.sections ?? []) { section in
                        SectionCard(section: section) { link in
                            if let url = URL(string: link) { openURL(url) }
                        }
                    }
                } else {
                    if isToday { ScheduledCard(automations: automations) }
                    EmptyState(mark: .wingsDown,
                               title: isToday ? "No briefing yet today." : "No briefing for this day.",
                               message: isToday ? "Your agent posts one each morning — pull down to check again." : nil)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Palette.page)
        .navigationTitle("Today")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
        .refreshable {
            async let automations: Void = loadAutomations()
            await load()
            await automations
        }
        .task(id: day) { await load() }
        .task { await loadAutomations() }
    }

    private var dayBar: some View {
        HStack {
            Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
            if !isToday {
                Button("Back to today") { day = Calendar.current.startOfDay(for: .now) }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
            Spacer()
            HStack(spacing: 4) {
                dayButton("chevron.left", label: "Previous day", by: -1)
                dayButton("chevron.right", label: "Next day", by: 1).disabled(isToday).opacity(isToday ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 4)
    }

    private func dayButton(_ icon: String, label: String, by days: Int) -> some View {
        Button {
            day = Calendar.current.date(byAdding: .day, value: days, to: day)!
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 44, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.field))
        }
        .accessibilityLabel(label)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            briefing = try await model.api.briefing(date: Self.wireDay.string(from: day))
            error = nil
        } catch APIError.http(status: 404, _) {
            briefing = nil
            error = nil
        } catch is CancellationError {
        } catch {
            briefing = nil
            self.error = error.localizedDescription
        }
    }
}

extension TodayView {
    /// Best-effort and separate from the briefing: a failure just leaves the card out.
    private func loadAutomations() async {
        if let list = try? await model.api.automations() { automations = list.automations }
    }
}

/// "Scheduled today": the automations that have run so far today, failures first and highlighted,
/// how many worked, and what runs next. Tap a row for that job's history.
private struct ScheduledCard: View {
    @Environment(AppModel.self) private var model
    let automations: [Automation]

    private var ranToday: [Automation] {
        automations
            .filter { $0.lastRun.map(Calendar.current.isDateInToday) ?? false }
            .sorted { a, b in
                let af = a.lastRunStatus == .failed, bf = b.lastRunStatus == .failed
                if af != bf { return af }
                return (a.lastRun ?? .distantPast) < (b.lastRun ?? .distantPast)
            }
    }

    private var next: (Automation, Date)? {
        automations
            .filter { $0.state != .paused && $0.state != .done }
            .compactMap { a in a.nextRun.map { (a, $0) } }
            .min { $0.1 < $1.1 }
    }

    var body: some View {
        let ran = ranToday
        if !ran.isEmpty || next != nil {
            let failed = ran.filter { $0.lastRunStatus == .failed }.count
            let worked = ran.filter { $0.lastRunStatus == .ok }.count
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "clock").font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.accent)
                    Text("Scheduled today").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.accent)
                    Spacer()
                    if !ran.isEmpty {
                        Text("\(worked) of \(ran.count) ran OK")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(failed > 0 ? Palette.urgentInk : Palette.successInk)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(failed > 0 ? SeverityStyle.of("urgent").background : Palette.successBg))
                    }
                }
                .padding(.bottom, 4)
                ForEach(ran, id: \.key) { a in
                    let bad = a.lastRunStatus == .failed
                    Button { model.push(.automation(crew: a.owner, id: a.id)) } label: {
                        HStack(spacing: 12) {
                            RunBadge(status: a.lastRunStatus ?? .ok)
                            Text(a.name).font(.system(size: 16)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                            Spacer(minLength: 8)
                            Text((bad ? "Failed · " : "") + (a.lastRun.map(WhenText.clock) ?? ""))
                                .font(.system(size: 14))
                                .foregroundStyle(bad ? Palette.urgentInk : Palette.textSecondary)
                        }
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 10).fill(bad ? SeverityStyle.of("urgent").background : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, -8)
                }
                HStack {
                    if let (a, at) = next {
                        Text("Next: \(a.name) · \(WhenText.dayAndTime(at))")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Button("All automations ›") {
                        model.tab = .automations
                        model.automationsPath = []
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Palette.surface))
        }
    }
}

private struct SectionCard: View {
    let section: Briefing.Section
    let open: (String) -> Void

    private var icon: String {
        switch section.kind {
        case "calendar": return "calendar"
        case "weather": return "sun.max"
        case "news": return "newspaper"
        case "sports": return "sportscourt"
        case "tasks": return "checklist"
        default: return "sparkle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.accent)
                Text(section.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.accent)
                Spacer()
            }
            if let headline = section.headline {
                Text(headline).font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
            }
            let items = section.items ?? []
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                ItemRow(item: item, open: open)
                if index < items.count - 1 { Divider().overlay(Palette.divider) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.surface))
    }
}

private struct ItemRow: View {
    let item: Briefing.Item
    let open: (String) -> Void

    private var dot: Color {
        switch item.priority {
        case "high": return SeverityStyle.of("urgent").dot
        case "low": return Palette.border
        default: return SeverityStyle.of("warn").dot
        }
    }

    var body: some View {
        let meta = [item.time, item.location].compactMap { $0 }.joined(separator: " · ")
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(dot).frame(width: 8, height: 8).padding(.top, 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 16)).foregroundStyle(Palette.textPrimary)
                if !meta.isEmpty { Text(meta).font(.system(size: 14)).foregroundStyle(Palette.textSecondary) }
                if let body = item.body { Text(body).font(.system(size: 14)).foregroundStyle(Palette.textSecondary) }
                if let link = item.link {
                    Button("Open link") { open(link) }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
