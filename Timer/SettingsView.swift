import SwiftUI
import AppKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var timerModel: TimerModel
    @AppStorage(BackupNotificationDefaults.notificationsEnabledKey)
    private var notificationsEnabled = BackupNotificationDefaults.notificationsEnabledDefault
    @AppStorage(BackupNotificationDefaults.staleSecondsKey)
    private var staleSeconds = BackupNotificationDefaults.staleSecondsDefault
    @AppStorage(BackupNotificationDefaults.pollIntervalSecondsKey)
    private var pollIntervalSeconds = BackupNotificationDefaults.pollIntervalSecondsDefault
    @AppStorage(BackupNotificationDefaults.markerPathKey)
    private var markerPath = BackupNotificationDefaults.markerRelativePathDefault

    @State private var staleHoursText = ""
    @State private var pollIntervalHoursText = ""
    @State private var markerPathText = ""
    @State private var lastBackupText = ""
    @State private var lastBackupAgeText = ""
    @State private var lastBackupIsStale = false
    @State private var notificationStatusText = ""
    @State private var diagnostics = BackupNotificationDiagnostics.empty
    @State private var diagnosticsExpanded = true

    private let secondsPerHour = 3600.0

    private var isStaleHoursValid: Bool {
        secondsFromHoursText(staleHoursText).map { $0 >= BackupNotificationDefaults.staleSecondsMin } ?? false
    }

    private var isPollIntervalValid: Bool {
        secondsFromHoursText(pollIntervalHoursText).map { $0 >= BackupNotificationDefaults.pollIntervalMinSeconds } ?? false
    }

    private var staleHoursHelperText: String {
        isStaleHoursValid ? "" : "Enter a value greater than 0 hours"
    }

    private var pollIntervalHelperText: String {
        isPollIntervalValid ? "" : "Enter a value greater than 0 hours"
    }

    private func filteredHoursInput(_ text: String) -> String {
        var output = ""
        var hasDecimal = false
        for character in text {
            if character.isNumber {
                output.append(character)
            } else if character == ".", !hasDecimal {
                hasDecimal = true
                output.append(character)
            }
        }
        return output
    }

    private func trimmedHoursText(_ hours: Double) -> String {
        let format = hours < 1 ? "%.4f" : "%.2f"
        var text = String(format: format, hours)
        while text.contains(".") && (text.last == "0" || text.last == ".") {
            if text.last == "." {
                text.removeLast()
                break
            }
            text.removeLast()
        }
        return text
    }

    private func hoursText(fromSeconds seconds: Int) -> String {
        trimmedHoursText(Double(seconds) / secondsPerHour)
    }

    private func hoursText(fromSecondsText text: String) -> String {
        guard let seconds = Double(text) else { return text }
        return "\(trimmedHoursText(seconds / secondsPerHour)) h"
    }

    private func secondsFromHoursText(_ text: String) -> Int? {
        guard let hours = Double(text) else { return nil }
        return Int((hours * secondsPerHour).rounded())
    }

    private func refreshLastBackupStatus() {
        let last = timerModel.backupMonitor.fetchLastBackup()
        lastBackupText = last.text
        lastBackupAgeText = last.ageText ?? ""
        if let date = last.date {
            let ageSeconds = Date().timeIntervalSince(date)
            lastBackupIsStale = ageSeconds >= 7 * 24 * 60 * 60
        } else {
            lastBackupIsStale = true
        }
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let alertEnabled = settings.alertSetting == .enabled
            let centerEnabled = settings.notificationCenterSetting == .enabled
            let statusText: String
            func withDelivery(_ base: String) -> String {
                if alertEnabled && centerEnabled {
                    return base
                }
                if alertEnabled {
                    return "\(base) (alerts only)"
                }
                if centerEnabled {
                    return "\(base) (center only)"
                }
                return "\(base) (alerts disabled)"
            }
            switch settings.authorizationStatus {
            case .authorized:
                statusText = withDelivery("Authorized")
            case .denied:
                statusText = "Denied"
            case .provisional:
                statusText = withDelivery("Provisional")
            case .ephemeral:
                statusText = "Ephemeral"
            case .notDetermined:
                statusText = "Not determined"
            @unknown default:
                statusText = "Unknown"
            }
            DispatchQueue.main.async {
                notificationStatusText = statusText
            }
        }
    }

    private func diagnosticRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .frame(width: 120, alignment: .leading)
            Text(value.isEmpty ? "n/a" : value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Backup notifications", isOn: $notificationsEnabled)

            VStack(alignment: .leading, spacing: 6) {
                Text("Warn if no backup for (hours)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(hoursText(fromSeconds: BackupNotificationDefaults.staleSecondsDefault), text: $staleHoursText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isStaleHoursValid ? Color.clear : Color.red, lineWidth: 1)
                    )
                    .onChange(of: staleHoursText) { newValue in
                        let filtered = filteredHoursInput(newValue)
                        if filtered != newValue {
                            staleHoursText = filtered
                        }
                        if let value = secondsFromHoursText(filtered), value >= BackupNotificationDefaults.staleSecondsMin {
                            staleSeconds = value
                        }
                    }
                if !staleHoursHelperText.isEmpty {
                    Text(staleHoursHelperText)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Check every (hours)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(hoursText(fromSeconds: BackupNotificationDefaults.pollIntervalSecondsDefault), text: $pollIntervalHoursText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isPollIntervalValid ? Color.clear : Color.red, lineWidth: 1)
                    )
                    .onChange(of: pollIntervalHoursText) { newValue in
                        let filtered = filteredHoursInput(newValue)
                        if filtered != newValue {
                            pollIntervalHoursText = filtered
                        }
                        if let value = secondsFromHoursText(filtered), value >= BackupNotificationDefaults.pollIntervalMinSeconds {
                            pollIntervalSeconds = value
                        }
                    }
                if !pollIntervalHelperText.isEmpty {
                    Text(pollIntervalHelperText)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Marker file path")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(markerPathText.isEmpty ? BackupNotificationDefaults.markerRelativePathDefault : markerPathText)
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                Button("Choose marker file") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = false
                    panel.showsHiddenFiles = true
                    if panel.runModal() == .OK {
                        if let url = panel.url {
                            markerPathText = url.path
                            markerPath = url.path
                            timerModel.backupMonitor.updateMarkerURL(url)
                            refreshLastBackupStatus()
                        }
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
                Text("Defaults to ~/\(BackupNotificationDefaults.markerRelativePathDefault)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Fallback marker path: \(timerModel.backupMonitor.appSupportMarkerPath())")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Last backup")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(lastBackupText.isEmpty ? "Unknown" : lastBackupText)
                    .font(.subheadline)
                    .foregroundColor(lastBackupIsStale ? .red : .primary)
                if !lastBackupAgeText.isEmpty {
                    Text("Last backup \(lastBackupAgeText)")
                        .font(.caption)
                        .foregroundColor(lastBackupIsStale ? .red : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Notification status")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(notificationStatusText.isEmpty ? "Checking..." : notificationStatusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Button("Send test notification") {
                timerModel.backupMonitor.sendTestNotification()
                refreshNotificationStatus()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Diagnostics")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(diagnosticsExpanded ? "Hide" : "Show") {
                        diagnosticsExpanded.toggle()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }

                if diagnosticsExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        diagnosticRow(label: "Last check", value: diagnostics.lastCheckTime)
                        diagnosticRow(label: "Notifications", value: diagnostics.notificationsEnabled)
                        diagnosticRow(label: "Stale threshold", value: hoursText(fromSecondsText: diagnostics.staleThreshold))
                        diagnosticRow(label: "Poll interval", value: hoursText(fromSecondsText: diagnostics.pollInterval))
                        diagnosticRow(label: "Marker path", value: diagnostics.resolvedMarkerPath)
                        diagnosticRow(label: "Marker source", value: diagnostics.markerStatus)
                        diagnosticRow(label: "Marker text", value: diagnostics.markerText)
                        diagnosticRow(label: "Marker date", value: diagnostics.markerDate)
                        diagnosticRow(label: "Marker age (s)", value: diagnostics.markerAgeSeconds)
                        diagnosticRow(label: "Marker age", value: diagnostics.markerAgeText)
                        diagnosticRow(label: "Decision", value: diagnostics.staleDecision)
                        diagnosticRow(label: "Missing since", value: diagnostics.missingSince)
                        diagnosticRow(label: "Last notif key", value: diagnostics.lastNotificationKey)
                        diagnosticRow(label: "Last notif attempt", value: diagnostics.lastNotificationAttempt)
                        diagnosticRow(label: "Last notif error", value: diagnostics.lastNotificationError)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)

                    HStack(spacing: 10) {
                        Button("Force check now") {
                            timerModel.backupMonitor.runDiagnosticsCheck()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Refresh view") {
                            diagnostics = timerModel.backupMonitor.diagnostics
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            staleHoursText = hoursText(fromSeconds: staleSeconds)
            pollIntervalHoursText = hoursText(fromSeconds: pollIntervalSeconds)
            markerPathText = markerPath
            refreshLastBackupStatus()
            refreshNotificationStatus()
            diagnostics = timerModel.backupMonitor.diagnostics
            timerModel.backupMonitor.onDiagnosticsUpdate = { updated in
                DispatchQueue.main.async {
                    diagnostics = updated
                }
            }
        }
        .onChange(of: staleSeconds) { newValue in
            if (secondsFromHoursText(staleHoursText) ?? newValue) != newValue {
                staleHoursText = hoursText(fromSeconds: newValue)
            }
        }
        .onChange(of: pollIntervalSeconds) { newValue in
            if (secondsFromHoursText(pollIntervalHoursText) ?? newValue) != newValue {
                pollIntervalHoursText = hoursText(fromSeconds: newValue)
            }
        }
        .onChange(of: markerPath) { newValue in
            if markerPathText != newValue {
                markerPathText = newValue
            }
            refreshLastBackupStatus()
        }
    }
}
