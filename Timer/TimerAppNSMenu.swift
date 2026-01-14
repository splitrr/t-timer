import SwiftUI
import AppKit
import Carbon.HIToolbox

class TimerMenuBarApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timerModel = TimerModel()
    private var hotKeyManager = HotKeyManager()
    private var timerWindow: NSPanel?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotKey()
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "timer.circle", accessibilityDescription: "Timer")
            button.target = self
            button.action = #selector(toggleTimerPanel)
        }
        
        updateMenuBarAppearance()
        
        // Update menu bar when timer changes
        timerModel.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                self?.updateMenuBarAppearance()
            }
        }
    }
    
    private func setupHotKey() {
        let hotKey = HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: HotKey.command | HotKey.control | HotKey.option)
        hotKeyManager.register(hotKey: hotKey) { [weak self] in
            DispatchQueue.main.async {
                self?.toggleTimerPanel()
            }
        }
    }
    
    @objc private func toggleTimerPanel() {
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
                styleMask: [.titled, .closable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            timerWindow?.contentView = hostingView
            timerWindow?.title = "Timer"
            timerWindow?.level = .floating
            timerWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        
        if let window = timerWindow, let button = statusItem.button {
            let buttonFrame = button.frame
            let screenFrame = button.window?.screen?.frame ?? NSScreen.main?.frame ?? .zero
            
            let windowSize = window.frame.size
            let buttonCenter = NSPoint(
                x: buttonFrame.midX + (button.window?.frame.origin.x ?? 0),
                y: buttonFrame.minY + (button.window?.frame.origin.y ?? 0)
            )
            
            let windowOrigin = NSPoint(
                x: buttonCenter.x - windowSize.width / 2,
                y: buttonCenter.y - windowSize.height - 10
            )
            
            window.setFrameOrigin(windowOrigin)
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    private func updateMenuBarAppearance() {
        guard let button = statusItem.button else { return }
        
        if timerModel.isRunning {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Timer Running")
            button.title = " \(timerModel.formattedTime)"
        } else {
            button.image = NSImage(systemSymbolName: "timer.circle", accessibilityDescription: "Timer")
            button.title = ""
        }
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