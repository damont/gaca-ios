import Foundation
import Observation
import SwiftUI

/// The agent's periodic check-in settings, as gaca-api holds them. Every change shows at once and is
/// sent straight away; if the server refuses it (a 422 with its reason, or no connection) the control
/// goes back to what it was and the reason shows. Ported from Android's SettingsViewModel.
@MainActor
@Observable
final class HeartbeatModel {
    var loading = false
    /// Nil until the first load succeeds.
    var settings: HeartbeatSettings?
    var error: String?

    func load(_ api: APIClient) async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            settings = try await api.heartbeatSettings()
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func change(_ change: HeartbeatChange, api: APIClient) {
        guard let before = settings else { return }
        settings = before.applying(change)
        error = nil
        Task {
            do {
                settings = try await api.updateHeartbeat(change)
            } catch {
                settings = before
                self.error = error.localizedDescription
            }
        }
    }

    func pause(hours: Int, api: APIClient) {
        change(HeartbeatChange(pausedUntil: Date.now.addingTimeInterval(TimeInterval(hours * 3600))), api: api)
    }

    /// Quiet until the quiet hours' own end, so "until morning" matches the schedule on screen.
    func pauseUntilMorning(api: APIClient) {
        guard let hour = settings?.quietEndHour else { return }
        change(HeartbeatChange(pausedUntil: HeartbeatText.nextMorning(hour: hour)), api: api)
    }

    func resume(api: APIClient) { change(HeartbeatChange(clearPause: true), api: api) }
}

/// "Heartbeat" in Settings. The user owns these limits: the agent can read them but never change them.
/// Quiet hours and the pause use this phone's time zone, which is sent with each save.
struct HeartbeatSection: View {
    @Environment(AppModel.self) private var model
    let heartbeat: HeartbeatModel

    var body: some View {
        Section {
            if let error = heartbeat.error {
                ErrorLine(text: error)
                if heartbeat.settings == nil {
                    Button("Try again") { Task { await heartbeat.load(model.api) } }
                }
            }
            if let settings = heartbeat.settings {
                rows(settings)
            } else if heartbeat.error == nil {
                ProgressView().frame(maxWidth: .infinity)
            }
        } header: {
            HStack {
                SectionLabel(text: "Heartbeat")
                if heartbeat.loading && heartbeat.settings != nil { Spacer(); ProgressView().controlSize(.small) }
            }
        } footer: {
            Text("How your agent checks in on its own: it looks around every half hour and tells you only what is worth it. You set the limits here; it can read them but never change them.")
        }
    }

    @ViewBuilder
    private func rows(_ settings: HeartbeatSettings) -> some View {
        Toggle("Check in for me", isOn: Binding(
            get: { settings.enabled },
            set: { save(HeartbeatChange(enabled: $0)) }
        ))
        .tint(Palette.accent)

        if settings.enabled {
            if settings.isPaused(), let until = settings.pausedUntil {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Paused")
                        Text("Until \(until.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    Button("Resume") { heartbeat.resume(api: model.api) }
                        .buttonStyle(.bordered).tint(Palette.accent)
                }
            } else {
                HStack {
                    Text("Pause for…")
                    Spacer()
                    Button("1 hour") { heartbeat.pause(hours: 1, api: model.api) }
                        .buttonStyle(.bordered).tint(Palette.accent)
                    Button("Until morning") { heartbeat.pauseUntilMorning(api: model.api) }
                        .buttonStyle(.bordered).tint(Palette.accent)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Quiet hours")
                    Spacer()
                    hourPicker("From", settings.quietStartHour) { save(HeartbeatChange(quietStartHour: $0)) }
                    Text("to").foregroundStyle(Palette.textSecondary)
                    hourPicker("To", settings.quietEndHour) { save(HeartbeatChange(quietEndHour: $0)) }
                }
                Text("Nothing runs then. Uses this phone's time zone (\(TimeZone.current.identifier)).")
                    .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }

            Stepper {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alerts a day")
                    Text(HeartbeatText.alertsPerDay(settings.maxAlertsPerDay))
                        .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                }
            } onIncrement: {
                guard settings.maxAlertsPerDay < HeartbeatText.maxAlertsPerDayLimit else { return }
                save(HeartbeatChange(maxAlertsPerDay: settings.maxAlertsPerDay + 1))
            } onDecrement: {
                guard settings.maxAlertsPerDay > 0 else { return }
                save(HeartbeatChange(maxAlertsPerDay: settings.maxAlertsPerDay - 1))
            }

            Picker(selection: Binding(
                get: { settings.minMinutesBetweenAlerts },
                set: { save(HeartbeatChange(minMinutesBetweenAlerts: $0)) }
            )) {
                ForEach(HeartbeatText.gapChoices(current: settings.minMinutesBetweenAlerts), id: \.self) { minutes in
                    Text(HeartbeatText.gap(minutes)).tag(minutes)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time between alerts")
                    Text("At least this long apart").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                }
            }
            .pickerStyle(.menu)
            .tint(Palette.accent)
        }
    }

    private func hourPicker(_ label: String, _ hour: Int, onPick: @escaping (Int) -> Void) -> some View {
        Menu {
            Picker(label, selection: Binding(get: { hour }, set: onPick)) {
                ForEach(0..<24, id: \.self) { h in Text(HeartbeatText.hour(h)).tag(h) }
            }
        } label: {
            Text(HeartbeatText.hour(hour))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Palette.chip))
        }
        .accessibilityLabel("\(label) \(HeartbeatText.hour(hour))")
    }

    private func save(_ change: HeartbeatChange) { heartbeat.change(change, api: model.api) }
}
