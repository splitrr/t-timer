import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine

@MainActor
class TimerMenuBarApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var timerModel = TimerModel()
    private var hotKeyManager = HotKeyManager()
    private var timerWindow: NSPanel?
    private var flashTimer: Timer?
    private var isFlashing = false
    private var isFlashOn = false
    private var menuBarUpdateCancellable: AnyCancellable?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotKey()
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
    
    private func setupHotKey() {
        let hotKey = HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: HotKey.command | HotKey.option)
        let registered = hotKeyManager.register(hotKey: hotKey) { [weak self] in
            DispatchQueue.main.async {
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
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.contains([.command, .option]), event.charactersIgnoringModifiers?.lowercased() == "t" {
                self?.toggleTimerPanel()
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
        if let window = timerWindow, window.isVisible {
            window.orderOut(nil)
        } else {
            showTimerPanel()
        }
    }
    
    private func showTimerPanel() {
        if timerWindow == nil {
            let contentView = ContentView().environmentObject(timerModel)
            let hostingView = NSHostingView(rootView: contentView)
            
            timerWindow = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )

            timerWindow?.contentView = hostingView
            timerWindow?.title = "Timer"
            timerWindow?.level = .floating
            timerWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            timerWindow?.isReleasedWhenClosed = false
            timerWindow?.delegate = self
        }

        if let window = timerWindow, let button = statusItem.button {
            let windowSize = window.frame.size
            let buttonFrame = button.window?.convertToScreen(button.frame) ?? NSScreen.main?.visibleFrame ?? .zero
            let visibleFrame = button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

            var windowOrigin = NSPoint(
                x: buttonFrame.midX - windowSize.width / 2,
                y: buttonFrame.minY - windowSize.height - 10
            )

            windowOrigin.x = max(visibleFrame.minX, min(windowOrigin.x, visibleFrame.maxX - windowSize.width))
            windowOrigin.y = max(visibleFrame.minY, min(windowOrigin.y, visibleFrame.maxY - windowSize.height))

            window.setFrameOrigin(windowOrigin)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            timerModel.requestFocus()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == timerWindow else { return }
        timerWindow = nil
        updateMenuBarAppearance()
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
            configureStatusButton(button)
            button.image = NSImage(systemSymbolName: "timer.circle", accessibilityDescription: "Timer")
            setButtonTitle(button, text: timerModel.formattedTime, visible: true)
        }
    }

    private func toggleFlash() {
        guard let button = statusItem.button else { return }
        configureStatusButton(button)
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
            EmptyView()
        }
    }
}