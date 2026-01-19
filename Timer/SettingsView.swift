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

    @State private var staleSecondsText = ""
    @State private var pollIntervalText = ""
    @State private var markerPathText = ""
    @State private var lastBackupText = ""
    @State private var lastBackupAgeText = ""
    @State private var lastBackupIsStale = false
    @State private var notificationStatusText = ""

    private var isStaleSecondsValid: Bool {
        Int(staleSecondsText).map { $0 >= BackupNotificationDefaults.staleSecondsMin } ?? false
    }

    private var isPollIntervalValid: Bool {
        Int(pollIntervalText).map { $0 >= BackupNotificationDefaults.pollIntervalMinSeconds } ?? false
    }

    private var staleSecondsHelperText: String {
        isStaleSecondsValid ? "" : "Enter a value of at least 1 second"
    }

    private var pollIntervalHelperText: String {
        isPollIntervalValid ? "" : "Enter a value of at least 1 second"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Backup notifications", isOn: $notificationsEnabled)

            VStack(alignment: .leading, spacing: 6) {
                Text("Warn if no backup for (seconds)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("\(BackupNotificationDefaults.staleSecondsDefault)", text: $staleSecondsText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isStaleSecondsValid ? Color.clear : Color.red, lineWidth: 1)
                    )
                    .onChange(of: staleSecondsText) { newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue {
                            staleSecondsText = filtered
                        }
                        if let value = Int(filtered), value >= BackupNotificationDefaults.staleSecondsMin {
                            staleSeconds = value
                        }
                    }
                if !staleSecondsHelperText.isEmpty {
                    Text(staleSecondsHelperText)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Check every (seconds)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("\(BackupNotificationDefaults.pollIntervalSecondsDefault)", text: $pollIntervalText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isPollIntervalValid ? Color.clear : Color.red, lineWidth: 1)
                    )
                    .onChange(of: pollIntervalText) { newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue {
                            pollIntervalText = filtered
                        }
                        if let value = Int(filtered), value >= BackupNotificationDefaults.pollIntervalMinSeconds {
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

            Spacer()
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            staleSecondsText = String(staleSeconds)
            pollIntervalText = String(pollIntervalSeconds)
            markerPathText = markerPath
            refreshLastBackupStatus()
            refreshNotificationStatus()
        }
        .onChange(of: staleSeconds) { newValue in
            if Int(staleSecondsText) != newValue {
                staleSecondsText = String(newValue)
            }
        }
        .onChange(of: pollIntervalSeconds) { newValue in
            if Int(pollIntervalText) != newValue {
                pollIntervalText = String(newValue)
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
