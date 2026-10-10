import SwiftUI

/// A crew member's round avatar with two-letter initials.
struct CrewAvatar: View {
    let name: String
    let style: CrewStyle
    var size: CGFloat = 36

    var body: some View {
        Text(crewInitials(name))
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(style.color))
            .accessibilityHidden(true)
    }
}

/// A small pill naming a crew member, tinted in its color.
struct CrewTag: View {
    let name: String
    let style: CrewStyle

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(style.color).frame(width: 6, height: 6)
            Text(crewDisplayName(name))
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(style.ink)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(Capsule().fill(style.tint))
    }
}

/// A selectable crew pill (filters, pickers). Selected = solid crew color.
struct CrewPill: View {
    let name: String
    let style: CrewStyle
    let selected: Bool
    var showAvatar = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if showAvatar {
                    Text(crewInitials(name))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(selected ? Color.white.opacity(0.25) : style.color))
                } else {
                    Circle().fill(selected ? Color.white : style.color).frame(width: 8, height: 8)
                }
                Text(crewDisplayName(name))
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(selected ? .white : style.ink)
            .padding(.leading, showAvatar ? 6 : 12).padding(.trailing, 14)
            .frame(height: showAvatar ? 36 : 32)
            .background(Capsule().fill(selected ? style.solid : style.tint))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The neutral "All" pill that leads a row of crew pills.
struct AllPill: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Palette.onAccent : Palette.textSecondary)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Capsule().fill(selected ? Palette.accent : Palette.chip))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// An uppercase list section label in the iOS grouped style.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.sectionLabel)
            .tracking(0.4)
            .foregroundStyle(Palette.textSecondary)
    }
}

/// A one-line red error message.
struct ErrorLine: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(SeverityStyle.of("urgent").ink)
    }
}

/// A centered empty / failed state for a whole screen.
struct EmptyState: View {
    var systemImage: String? = nil
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Palette.suggest))
            }
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// The gear button every tab carries in its toolbar.
struct SettingsButton: View {
    var body: some View {
        NavigationLink(value: Route.settings) {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
    }
}

extension View {
    /// The shared page look: slate-tinted background behind lists and scroll views.
    func gacaPage() -> some View {
        scrollContentBackground(.hidden)
            .background(Palette.page)
    }
}

/// Short relative times like the Android app: "now", "5m", "3h", "2d", then a date.
enum RelativeTime {
    static func short(_ date: Date, now: Date = .now) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        if s < 7 * 86400 { return "\(Int(s / 86400))d" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
