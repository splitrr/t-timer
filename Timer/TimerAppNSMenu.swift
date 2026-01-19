import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine
import UserNotifications

@MainActor
class TimerMenuBarApp: NSObject, NSApplicationDelegate, @MainActor UNUserNotificationCenterDelegate {
    private let notificationCenter = UNUserNotificationCenter.current()
    private var statusItem: NSStatusItem!
    let timerModel = TimerModel()
    private var hotKeyManager = HotKeyManager()
    private var timerPopover: NSPopover?
    private var flashTimer: Timer?
    private var isFlashing = false
    private var isFlashOn = false
    private var menuBarUpdateCancellable: AnyCancellable?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupNotifications()
        setupMenuBar()
        setupHotKey()
        timerModel.backupMonitor.reapplyMarkerAccessFromSavedPath()
        timerModel.backupMonitor.start()
    }

    deinit {
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            configureStatusButton(button)
            button.image = NSImage(systemSymbolName: "timer.circle", accessibilityDescription: "Timer")
        }
        
        updateMenuBarAppearance()
        
        // Update menu bar when timer changes
        menuBarUpdateCancellable = timerModel.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                self?.updateMenuBarAppearance()
            }
        }
    }

    private func setupNotifications() {
        notificationCenter.delegate = self
        notificationCenter.getNotificationSettings { settings in
            NSLog("Notification settings: authorizationStatus=\(settings.authorizationStatus.rawValue)")
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
    
    private func setupHotKey() {
        let hotKey = HotKey(keyCode: UInt32(kVK_F20), modifiers: 0)
        let registered = hotKeyManager.register(hotKey: hotKey) { [weak self] in
            Task { @MainActor in
                self?.toggleTimerPanel()
            }
        }
        if !registered {
            NSLog("Hotkey registration failed; using fallback monitor")
        }
        registerFallbackKeyMonitor()
    }

    private func registerFallbackKeyMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            if event.keyCode == UInt16(kVK_F20) {
                Task { @MainActor in
                    self?.toggleTimerPanel()
                }
            }
        }

        if globalKeyMonitor == nil {
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
        }
        if localKeyMonitor == nil {
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handler(event)
                return event
            }
        }
    }
    
    @objc private func toggleTimerPanel() {
        if timerModel.didFinish {
            timerModel.didFinish = false
            stopFlashing()
        }
        if timerPopover?.isShown == true {
            timerPopover?.performClose(nil)
        } else {
            showTimerPopover()
        }
    }
    
    private func showTimerPopover() {
        guard let button = statusItem.button else { return }

        if timerPopover == nil {
            let contentView = ContentView().environmentObject(timerModel)
            let hostingController = NSHostingController(rootView: contentView)

            let popover = NSPopover()
            popover.contentViewController = hostingController
            popover.behavior = .transient
            popover.animates = true
            popover.contentSize = NSSize(width: 280, height: 200)
            timerPopover = popover
        }

        timerPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        timerModel.requestFocus()
    }
    
    private func updateMenuBarAppearance() {
        guard let button = statusItem.button else { return }
        configureStatusButton(button)

        if timerModel.isRunning {
            stopFlashing()
            button.image = NSImage(systemSymbolName: "timer.circle", accessibilityDescription: "Timer")
            setButtonTitle(button, text: timerModel.formattedTime, visible: true)
        } else if timerModel.didFinish {
            startFlashing()
        } else {
            stopFlashing()
            button.image = NSImage(systemSymbolName: "timer.circle", accessibilityDescription: "Timer")
            setButtonTitle(button, text: timerModel.formattedTime, visible: true)
        }
    }

    private func configureStatusButton(_ button: NSStatusBarButton) {
        button.target = self
        button.action = #selector(toggleTimerPanel)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.isEnabled = true
    }

    private func setButtonTitle(_ button: NSStatusBarButton, text: String, visible: Bool) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let color = visible ? NSColor.labelColor : NSColor.clear
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let title = " \(text)"
        button.attributedTitle = NSAttributedString(string: title, attributes: attributes)
    }

    private func startFlashing() {
        guard !isFlashing else { return }
        isFlashing = true
        isFlashOn = false
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.toggleFlash()
            }
        }
        toggleFlash()
    }

    private func stopFlashing() {
        isFlashing = false
        isFlashOn = false
        flashTimer?.invalidate()
        flashTimer = nil
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "timer.circle", accessibilityDescription: "Timer")
            setButtonTitle(button, text: timerModel.formattedTime, visible: true)
        }
    }

    private func toggleFlash() {
        guard let button = statusItem.button else { return }
        isFlashOn.toggle()
        button.image = NSImage(systemSymbolName: "timer.circle", accessibilityDescription: "Timer")
        setButtonTitle(button, text: timerModel.formattedTime, visible: isFlashOn)
    }
}

@main
struct TimerApp: App {
    @NSApplicationDelegateAdaptor(TimerMenuBarApp.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.timerModel)
        }
    }
}
