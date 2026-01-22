import Foundation
import Foundation
import UserNotifications

enum BackupNotificationDefaults {
    static let notificationsEnabledKey = "backupNotificationsEnabled"
    static let staleSecondsKey = "backupStaleSeconds"
    static let pollIntervalSecondsKey = "backupPollIntervalSeconds"
    static let missingSinceKey = "backupMissingSince"
    static let markerPathKey = "backupMarkerPath"

    static let notificationsEnabledDefault = true
    static let staleSecondsDefault = 86_400
    static let pollIntervalSecondsDefault = 300
    static let markerRelativePathDefault = "Parallels/.backup-staging/.last-successful-run"

    static let staleSecondsMin = 1
    static let pollIntervalMinSeconds = 1
}

struct BackupNotificationDiagnostics {
    let lastCheckTime: String
    let notificationsEnabled: String
    let staleThreshold: String
    let pollInterval: String
    let resolvedMarkerPath: String
    let markerStatus: String
    let markerText: String
    let markerDate: String
    let markerAgeSeconds: String
    let markerAgeText: String
    let staleDecision: String
    let missingSince: String
    let lastNotificationKey: String
    let lastNotificationAttempt: String
    let lastNotificationError: String

    static let empty = BackupNotificationDiagnostics(
        lastCheckTime: "n/a",
        notificationsEnabled: "n/a",
        staleThreshold: "n/a",
        pollInterval: "n/a",
        resolvedMarkerPath: "n/a",
        markerStatus: "n/a",
        markerText: "n/a",
        markerDate: "n/a",
        markerAgeSeconds: "n/a",
        markerAgeText: "n/a",
        staleDecision: "n/a",
        missingSince: "n/a",
        lastNotificationKey: "n/a",
        lastNotificationAttempt: "n/a",
        lastNotificationError: "n/a"
    )
}

@MainActor
final class BackupNotificationMonitor {
    private let notificationCenter = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var settingsObserver: NSObjectProtocol?
    private var lastNotificationKey: String?
    private var resolvedMarkerURL: URL?
    private var lastMarkerSource = "n/a"
    private var lastNotificationAttempt = "n/a"
    private var lastNotificationError = "n/a"
    private var lastCheckMarker: (text: String, date: Date?)?
    private var lastCheckResolvedURL: URL?
    private var lastCheckMarkerStatus = "n/a"
    private var lastCheckAgeSeconds: Double?
    private var lastCheckAgeText: String?
    private var lastCheckStaleDecision = "n/a"
    private var lastCheckMissingSince: Double?
    private let isoFormatter = ISO8601DateFormatter()

    @MainActor
    var diagnostics: BackupNotificationDiagnostics = .empty
    var onDiagnosticsUpdate: ((BackupNotificationDiagnostics) -> Void)?

    private let markerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    private var appSupportMarkerURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "VibeMenuApp"
        let dir = base.appendingPathComponent(bundleIdentifier, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            NSLog("Unable to create Application Support directory: \(error.localizedDescription)")
        }
        return dir.appendingPathComponent(".last-successful-run")
    }

    private func readMarker(at url: URL?, logFailures: Bool) -> (text: String, date: Date?)? {
        guard let url else { return nil }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            if logFailures {
                NSLog("Backup notifications: unable to read marker file at \(url.path)")
            }
            return nil
        }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parsedDate = markerFormatter.date(from: trimmed)
        if parsedDate == nil {
            NSLog("Backup notifications: marker text did not parse as date (expected yyyy-MM-dd): \(trimmed)")
        }
        return (trimmed, parsedDate)
    }

    private func mirrorMarkerToAppSupport(_ text: String) {
        do {
            try text.write(to: appSupportMarkerURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Unable to mirror marker to Application Support: \(error.localizedDescription)")
        }
    }

    private func updateDiagnostics(
        status: String,
        marker: (text: String, date: Date?)? = nil,
        resolvedURL: URL? = nil,
        staleDecision: String = "n/a",
        ageSeconds: Double? = nil,
        ageText: String? = nil,
        missingSince: Double? = nil,
        notificationAttempt: String = "n/a",
        notificationError: String = "n/a"
    ) {
        let now = Date()
        let resolvedPath = resolvedURL?.path ?? resolveMarkerURL()?.path ?? "n/a"
        let markerText = marker?.text ?? "n/a"
        let markerDateValue = marker?.date
        let markerDateText = markerDateValue.map { isoFormatter.string(from: $0) } ?? "n/a"
        let markerAge = ageSeconds.map { String(format: "%.0f", $0) } ?? "n/a"
        let markerAgeText = ageText ?? "n/a"
        let missingSinceText: String
        if let missingSince {
            missingSinceText = String(format: "%.0f", missingSince)
        } else {
            let recorded = defaults.double(forKey: BackupNotificationDefaults.missingSinceKey)
            missingSinceText = recorded > 0 ? String(format: "%.0f", recorded) : "n/a"
        }

        let snapshot = BackupNotificationDiagnostics(
            lastCheckTime: isoFormatter.string(from: now),
            notificationsEnabled: notificationsEnabled ? "true" : "false",
            staleThreshold: String(staleSeconds),
            pollInterval: String(pollIntervalSeconds),
            resolvedMarkerPath: resolvedPath,
            markerStatus: status,
            markerText: markerText,
            markerDate: markerDateText,
            markerAgeSeconds: markerAge,
            markerAgeText: markerAgeText,
            staleDecision: staleDecision,
            missingSince: missingSinceText,
            lastNotificationKey: lastNotificationKey ?? "n/a",
            lastNotificationAttempt: notificationAttempt,
            lastNotificationError: notificationError
        )

        diagnostics = snapshot
        NSLog("Backup notifications: diagnostics updated status=\(status) decision=\(staleDecision) notif=\(notificationAttempt)")
        onDiagnosticsUpdate?(snapshot)
    }

    init() {
        registerDefaultsIfNeeded()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTimer()
            }
        }
    }

    deinit {
        timer?.invalidate()
        timer = nil
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start() {
        NSLog("Backup notifications: start monitoring")
        requestAuthorizationIfNeeded()
        refreshTimer()
    }

    func runDiagnosticsCheck() {
        checkBackupStatus()
    }

    func updateMarkerURL(_ url: URL?) {
        resolvedMarkerURL = nil
        guard let url else {
            defaults.removeObject(forKey: BackupNotificationDefaults.markerPathKey)
            NSLog("Backup notifications: marker path cleared")
            refreshTimer()
            return
        }
        defaults.set(url.path, forKey: BackupNotificationDefaults.markerPathKey)
        NSLog("Backup notifications: marker path set to \(url.path)")
        refreshTimer()
    }

    func fetchLastBackup() -> (text: String, date: Date?, ageText: String?) {
        if let marker = loadMarker() {
            let ageText = marker.date.flatMap { Self.relativeDaysText(from: $0) }
            return (marker.text, marker.date, ageText)
        }
        return ("Unknown", nil, nil)
    }

    func appSupportMarkerPath() -> String {
        appSupportMarkerURL.path
    }

    func sendTestNotification() {
        NSLog("Backup notifications: request test notification")
        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            if settings.authorizationStatus == .notDetermined {
                Task { @MainActor in
                    self.requestAuthorizationIfNeeded { granted in
                        guard granted else { return }
                        self.notificationCenter.getNotificationSettings { updatedSettings in
                            Task { @MainActor in
                                self.deliverTestNotificationIfAllowed(settings: updatedSettings)
                            }
                        }
                    }
                }
                return
            }
            Task { @MainActor in
                self.deliverTestNotificationIfAllowed(settings: settings)
            }
        }
    }

    private func deliverTestNotificationIfAllowed(settings: UNNotificationSettings) {
        guard isAuthorized(settings.authorizationStatus) else {
            NSLog("Backup notifications: authorization not granted")
            return
        }
        guard settings.alertSetting == .enabled || settings.notificationCenterSetting == .enabled else {
            NSLog("Backup notifications: alerts disabled in System Settings")
            return
        }
        scheduleTestNotification()
    }

    private func scheduleTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Backup notifications"
        content.body = "Test notification."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "backup-test", content: content, trigger: nil)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: ["backup-test"])
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["backup-test"])
        notificationCenter.add(request) { error in
            if let error = error {
                NSLog("Backup notifications: failed to deliver test notification: \(error.localizedDescription)")
            } else {
                NSLog("Backup notifications: delivered test notification")
            }
        }
    }

    private func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    private var notificationsEnabled: Bool {
        defaults.bool(forKey: BackupNotificationDefaults.notificationsEnabledKey)
    }

    private var staleSeconds: Int {
        defaults.integer(forKey: BackupNotificationDefaults.staleSecondsKey)
    }

    private var pollIntervalSeconds: Int {
        defaults.integer(forKey: BackupNotificationDefaults.pollIntervalSecondsKey)
    }

    private func refreshTimer() {
        resolvedMarkerURL = nil
        timer?.invalidate()
        timer = nil

        guard notificationsEnabled else {
            lastNotificationKey = nil
            clearMissingSince()
            updateDiagnostics(status: "notifications disabled")
            NSLog("Backup notifications: disabled")
            return
        }

        let interval = pollIntervalSeconds
        guard interval >= BackupNotificationDefaults.pollIntervalMinSeconds else {
            updateDiagnostics(status: "poll interval invalid")
            NSLog("Backup notifications: poll interval invalid (\(interval))")
            return
        }

        let newTimer = Timer(timeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkBackupStatus()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        newTimer.tolerance = min(TimeInterval(interval) * 0.1, 30)
        timer = newTimer

        NSLog("Backup notifications: polling every \(interval)s")
        checkBackupStatus()
    }

    private func checkBackupStatus() {
        guard notificationsEnabled else {
            updateDiagnostics(status: "notifications disabled")
            return
        }

        let thresholdSeconds = staleSeconds
        guard thresholdSeconds >= BackupNotificationDefaults.staleSecondsMin else {
            updateDiagnostics(status: "invalid stale threshold")
            return
        }

        let resolvedURL = resolveMarkerURL()
        let marker = loadMarker()
        NSLog("Backup notifications: marker status=\(marker?.text ?? "missing") source=\(lastMarkerSource) path=\(resolvedURL?.path ?? "n/a")")
        let lastSuccessText: String
        let notificationKey: String
        let isStale: Bool
        let ageText: String?
        var ageSeconds: Double?
        var staleDecision = "n/a"
        var missingSinceValue: Double?

        if let marker = marker, let markerDate = marker.date {
            lastSuccessText = marker.text
            notificationKey = "date:\(marker.text)"
            ageSeconds = Date().timeIntervalSince(markerDate)
            isStale = ageSeconds.map { $0 >= Double(thresholdSeconds) } ?? true
            ageText = Self.relativeDaysText(from: markerDate)
            clearMissingSince()
            staleDecision = isStale ? "stale" : "fresh"
            NSLog("Backup notifications: parsed marker date \(markerDate) ageSeconds=\(ageSeconds ?? -1) stale=\(isStale)")
        } else {
            lastSuccessText = marker?.text ?? "unknown"
            notificationKey = "missing"
            isStale = isMissingBeyondThreshold(thresholdSeconds: thresholdSeconds)
            ageText = nil
            missingSinceValue = defaults.double(forKey: BackupNotificationDefaults.missingSinceKey)
            staleDecision = isStale ? "missing+stale" : "missing+waiting"
            NSLog("Backup notifications: marker missing/invalid; missingSince=\(missingSinceValue ?? -1) stale=\(isStale)")
        }

        lastCheckMarker = marker
        lastCheckResolvedURL = resolvedURL
        lastCheckMarkerStatus = lastMarkerSource
        lastCheckAgeSeconds = ageSeconds
        lastCheckAgeText = ageText
        lastCheckStaleDecision = staleDecision
        lastCheckMissingSince = missingSinceValue

        updateDiagnostics(
            status: lastMarkerSource,
            marker: marker,
            resolvedURL: resolvedURL,
            staleDecision: staleDecision,
            ageSeconds: ageSeconds,
            ageText: ageText,
            missingSince: missingSinceValue,
            notificationAttempt: lastNotificationAttempt,
            notificationError: lastNotificationError
        )

        if isStale {
            NSLog("Backup notifications: stale detected; sending notification")
            sendNotificationIfNeeded(lastSuccess: lastSuccessText, key: notificationKey, ageText: ageText)
        } else {
            NSLog("Backup notifications: backup OK; no notification")
        }
    }

    private func loadMarker() -> (text: String, date: Date?)? {
        let resolvedURL = resolveMarkerURL()
        let resolvedMarker = readMarker(at: resolvedURL, logFailures: true)
        if let resolvedMarker {
            lastMarkerSource = "resolved"
            mirrorMarkerToAppSupport(resolvedMarker.text)
            return resolvedMarker
        }
        let fallbackMarker = readMarker(at: appSupportMarkerURL, logFailures: false)
        if fallbackMarker != nil {
            lastMarkerSource = "fallback"
        } else {
            lastMarkerSource = "missing"
        }
        return fallbackMarker
    }

    private func resolveMarkerURL() -> URL? {
        if let cached = resolvedMarkerURL {
            return cached
        }
        let configuredPath = defaults.string(forKey: BackupNotificationDefaults.markerPathKey)
        let relativePath = configuredPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = relativePath?.isEmpty == false ? relativePath! : BackupNotificationDefaults.markerRelativePathDefault
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else {
            url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path)
        }
        resolvedMarkerURL = url
        return url
    }

    private func isMissingBeyondThreshold(thresholdSeconds: Int) -> Bool {
        let now = Date().timeIntervalSince1970
        let recorded = defaults.double(forKey: BackupNotificationDefaults.missingSinceKey)
        if recorded <= 0 {
            defaults.set(now, forKey: BackupNotificationDefaults.missingSinceKey)
            return false
        }
        return now - recorded >= Double(thresholdSeconds)
    }

    private func clearMissingSince() {
        let recorded = defaults.double(forKey: BackupNotificationDefaults.missingSinceKey)
        guard recorded != 0 else { return }
        defaults.set(0, forKey: BackupNotificationDefaults.missingSinceKey)
    }

    private func sendNotificationIfNeeded(lastSuccess: String, key: String, ageText: String?) {
        let notificationKey = "stale:\(key)"
        guard lastNotificationKey != notificationKey else {
            NSLog("Backup notifications: skipping duplicate notification \(notificationKey)")
            lastNotificationAttempt = "skipped duplicate"
            updateDiagnostics(
                status: lastMarkerSource,
                marker: lastCheckMarker,
                resolvedURL: lastCheckResolvedURL,
                staleDecision: lastCheckStaleDecision,
                ageSeconds: lastCheckAgeSeconds,
                ageText: lastCheckAgeText,
                missingSince: lastCheckMissingSince,
                notificationAttempt: lastNotificationAttempt,
                notificationError: lastNotificationError
            )
            return
        }
        lastNotificationKey = notificationKey
        lastNotificationAttempt = "scheduled"
        lastNotificationError = "n/a"

        let content = UNMutableNotificationContent()
        content.title = "VM Backup status"
        let ageSuffix = ageText.map { " (\($0))" } ?? ""
        content.body = "Last successful backup: \(lastSuccess)\(ageSuffix)"
        content.sound = .default

        let request = UNNotificationRequest(identifier: "backup-stale", content: content, trigger: nil)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: ["backup-stale"])
        notificationCenter.add(request) { [weak self] error in
            guard let self else { return }
            let attempt: String
            let errorText: String
            if let error = error {
                attempt = "failed"
                errorText = error.localizedDescription
                NSLog("Backup notifications: failed to deliver backup stale notification: \(error.localizedDescription)")
            } else {
                attempt = "delivered"
                errorText = "none"
                NSLog("Backup notifications: delivered backup stale notification")
            }
            Task { @MainActor in
                self.lastNotificationAttempt = attempt
                self.lastNotificationError = errorText
                self.updateDiagnostics(
                    status: self.lastMarkerSource,
                    marker: self.lastCheckMarker,
                    resolvedURL: self.lastCheckResolvedURL,
                    staleDecision: self.lastCheckStaleDecision,
                    ageSeconds: self.lastCheckAgeSeconds,
                    ageText: self.lastCheckAgeText,
                    missingSince: self.lastCheckMissingSince,
                    notificationAttempt: self.lastNotificationAttempt,
                    notificationError: self.lastNotificationError
                )
            }
        }
    }

    private func requestAuthorizationIfNeeded(completion: ((Bool) -> Void)? = nil) {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                NSLog("Backup notifications: authorization error: \(error.localizedDescription)")
            } else if !granted {
                NSLog("Backup notifications: authorization not granted")
            } else {
                NSLog("Backup notifications: authorization granted")
            }
            completion?(granted)
        }
    }

    func reapplyMarkerAccessFromSavedPath() {
        if let path = defaults.string(forKey: BackupNotificationDefaults.markerPathKey), !path.isEmpty {
            updateMarkerURL(URL(fileURLWithPath: path))
        }
    }

    private static func relativeDaysText(from date: Date) -> String? {
        let daysValue = Calendar.current.dateComponents([.day], from: date, to: Date()).day
        guard let daysValue else { return nil }
        let days = max(daysValue, 0)
        return "\(days) day\(days == 1 ? "" : "s") ago"
    }

    private func registerDefaultsIfNeeded() {
        if defaults.object(forKey: BackupNotificationDefaults.notificationsEnabledKey) == nil {
            defaults.set(
                BackupNotificationDefaults.notificationsEnabledDefault,
                forKey: BackupNotificationDefaults.notificationsEnabledKey
            )
        }
        if defaults.object(forKey: BackupNotificationDefaults.staleSecondsKey) == nil {
            defaults.set(
                BackupNotificationDefaults.staleSecondsDefault,
                forKey: BackupNotificationDefaults.staleSecondsKey
            )
        }
        if defaults.object(forKey: BackupNotificationDefaults.pollIntervalSecondsKey) == nil {
            defaults.set(
                BackupNotificationDefaults.pollIntervalSecondsDefault,
                forKey: BackupNotificationDefaults.pollIntervalSecondsKey
            )
        }
        if defaults.object(forKey: BackupNotificationDefaults.missingSinceKey) == nil {
            defaults.set(0, forKey: BackupNotificationDefaults.missingSinceKey)
        }
        if defaults.object(forKey: BackupNotificationDefaults.markerPathKey) == nil {
            defaults.set(
                BackupNotificationDefaults.markerRelativePathDefault,
                forKey: BackupNotificationDefaults.markerPathKey
            )
        }
    }
}

