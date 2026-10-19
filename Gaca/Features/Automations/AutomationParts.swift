import SwiftUI

/// Times the way the automation screens say them (gaca-android util/Times.kt).
enum WhenText {
    /// "7:30 AM" in the phone's zone.
    static func clock(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    /// "Today 7:30 AM", "Tomorrow …", "Yesterday …", "Sat …" within a week, else "Oct 4 …".
    static func dayAndTime(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let label: String
        if calendar.isDate(date, inSameDayAs: now) {
            label = "Today"
        } else if calendar.isDateInTomorrow(date, relativeTo: now) {
            label = "Tomorrow"
        } else if calendar.isDateInYesterday(date, relativeTo: now) {
            label = "Yesterday"
        } else if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day, abs(days) < 7 {
            label = date.formatted(.dateTime.weekday(.abbreviated))
        } else {
            label = date.formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(label) \(clock(date))"
    }

    /// "12s", "1m 04s", "2m 00s".
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return total < 60 ? "\(total)s" : "\(total / 60)m \(String(format: "%02d", total % 60))s"
    }

    /// "Last run Today 7:30 AM · failed" / "Not run yet" for a list card.
    static func lastRun(_ a: Automation) -> String {
        guard let at = a.lastRun else { return "Not run yet" }
        let how: String
        switch a.lastRunStatus {
        case .failed: how = " · failed"
        case .running: how = " · running"
        default: how = ""
        }
        return "Last run \(dayAndTime(at))\(how)"
    }
}

private extension Calendar {
    func isDateInTomorrow(_ date: Date, relativeTo now: Date) -> Bool {
        guard let tomorrow = self.date(byAdding: .day, value: 1, to: now) else { return false }
        return isDate(date, inSameDayAs: tomorrow)
    }

    func isDateInYesterday(_ date: Date, relativeTo now: Date) -> Bool {
        guard let yesterday = self.date(byAdding: .day, value: -1, to: now) else { return false }
        return isDate(date, inSameDayAs: yesterday)
    }
}

/// A job's overall state as a pill: "OK", "Failed", "Paused", …
struct StatusPill: View {
    let status: AutomationStatus

    private var look: (label: String, bg: Color, ink: Color, icon: String?) {
        switch status {
        case .ok: return ("OK", Palette.successBg, Palette.successInk, "checkmark")
        case .failed: return ("Failed", SeverityStyle.of("urgent").background, Palette.urgentInk, "xmark")
        case .running: return ("Running", SeverityStyle.of("warn").background, Palette.textSecondary, nil)
        case .paused: return ("Paused", Palette.chip, Palette.textSecondary, nil)
        case .done: return ("Done", Palette.chip, Palette.textSecondary, nil)
        case .neverRun: return ("Not run yet", SeverityStyle.of("info").background, Palette.textSecondary, nil)
        }
    }

    var body: some View {
        let look = look
        HStack(spacing: 4) {
            if let icon = look.icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(look.label).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(look.ink)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(look.bg))
    }
}

/// The row of colored squares for the last runs, oldest left, newest right.
struct RunDots: View {
    let recent: [RunMark]

    var body: some View {
        if !recent.isEmpty {
            let failed = recent.filter { RunStatus(wire: $0.status) == .failed }.count
            HStack(spacing: 4) {
                ForEach(Array(recent.enumerated()), id: \.offset) { _, run in
                    RoundedRectangle(cornerRadius: 4).fill(color(RunStatus(wire: run.status))).frame(width: 18, height: 18)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Last \(recent.count) runs, \(failed) failed, newest last")
        }
    }

    private func color(_ status: RunStatus) -> Color {
        switch status {
        case .ok: return Palette.successDot
        case .failed: return SeverityStyle.of("urgent").dot
        case .running: return SeverityStyle.of("warn").dot
        }
    }
}

/// The round tick / cross / dot at the start of a run's row.
struct RunBadge: View {
    let status: RunStatus
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            switch status {
            case .ok:
                Circle().fill(Palette.successBg)
                Image(systemName: "checkmark").font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(Palette.successInk)
            case .failed:
                Circle().fill(SeverityStyle.of("urgent").background)
                Image(systemName: "xmark").font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(Palette.urgentInk)
            case .running:
                Circle().fill(SeverityStyle.of("warn").background)
                Circle().fill(SeverityStyle.of("warn").dot).frame(width: 8, height: 8)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status == .ok ? "Worked" : status == .failed ? "Failed" : "Running")
    }
}
