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

@MainActor
final class BackupNotificationMonitor {
    private let notificationCenter = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var settingsObserver: NSObjectProtocol?
    private var lastNotificationKey: String?
    private var resolvedMarkerURL: URL?
    
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
                NSLog("Unable to read marker file at \(url.path)")
            }
            return nil
        }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (trimmed, markerFormatter.date(from: trimmed))
    }

    private func mirrorMarkerToAppSupport(_ text: String) {
        do {
            try text.write(to: appSupportMarkerURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Unable to mirror marker to Application Support: \(error.localizedDescription)")
        }
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
        requestAuthorizationIfNeeded()
        refreshTimer()
    }

    func updateMarkerURL(_ url: URL?) {
        resolvedMarkerURL = nil
        guard let url else {
            defaults.removeObject(forKey: BackupNotificationDefaults.markerPathKey)
            refreshTimer()
            return
        }
        defaults.set(url.path, forKey: BackupNotificationDefaults.markerPathKey)
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
            return
        }

        let interval = pollIntervalSeconds
        guard interval >= BackupNotificationDefaults.pollIntervalMinSeconds else {
            return
        }

        let newTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkBackupStatus()
            }
        }
        newTimer.tolerance = min(TimeInterval(interval) * 0.1, 30)
        timer = newTimer

        checkBackupStatus()
    }

    private func checkBackupStatus() {
        guard notificationsEnabled else { return }

        let staleSeconds = staleSeconds
        guard staleSeconds >= BackupNotificationDefaults.staleSecondsMin else { return }

        let marker = loadMarker()
        NSLog("Backup marker: \(marker?.text ?? "missing")")
        let lastSuccessText: String
        let notificationKey: String
        let isStale: Bool
        let ageText: String?

        if let marker = marker, let markerDate = marker.date {
            lastSuccessText = marker.text
            notificationKey = "date:\(marker.text)"
            let ageSeconds = Date().timeIntervalSince(markerDate)
            isStale = ageSeconds >= Double(staleSeconds)
            ageText = Self.relativeDaysText(from: markerDate)
            clearMissingSince()
        } else {
            lastSuccessText = marker?.text ?? "unknown"
            notificationKey = "missing"
            isStale = isMissingBeyondThreshold(thresholdSeconds: staleSeconds)
            ageText = nil
        }

        if isStale {
            NSLog("Backup stale, sending notification")
            sendNotificationIfNeeded(lastSuccess: lastSuccessText, key: notificationKey, ageText: ageText)
        } else {
            NSLog("Backup OK, no notification")
            lastNotificationKey = nil
        }
    }

    private func loadMarker() -> (text: String, date: Date?)? {
        let resolvedMarker = readMarker(at: resolveMarkerURL(), logFailures: true)
        if let resolvedMarker {
            mirrorMarkerToAppSupport(resolvedMarker.text)
            return resolvedMarker
        }
        return readMarker(at: appSupportMarkerURL, logFailures: false)
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
        defaults.removeObject(forKey: BackupNotificationDefaults.missingSinceKey)
    }

    private func sendNotificationIfNeeded(lastSuccess: String, key: String, ageText: String?) {
        let notificationKey = "stale:\(key)"
        guard lastNotificationKey != notificationKey else { return }
        lastNotificationKey = notificationKey

        let content = UNMutableNotificationContent()
        content.title = "Backup stale"
        let ageSuffix = ageText.map { " (\($0))" } ?? ""
        content.body = "Last successful backup: \(lastSuccess)\(ageSuffix)"
        content.sound = .default

        let request = UNNotificationRequest(identifier: "backup-stale", content: content, trigger: nil)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: ["backup-stale"])
        notificationCenter.add(request) { error in
            if let error = error {
                NSLog("Failed to deliver backup stale notification: \(error.localizedDescription)")
            }
        }
    }

    private func requestAuthorizationIfNeeded() {
        notificationCenter.requestAuthorization(options: [.alert]) { granted, error in
            if let error = error {
                NSLog("Notification authorization error: \(error.localizedDescription)")
            } else if !granted {
                NSLog("Notification authorization not granted.")
            }
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
