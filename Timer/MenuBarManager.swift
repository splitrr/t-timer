import AppKit
import SwiftUI

@MainActor
class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    
    init() {
        setupMenuBar()
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "timer.circle", accessibilityDescription: "Timer")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
        }
    }
    
    func updateMenuBar(with timerModel: TimerModel) {
        guard let button = statusItem?.button else { return }
        
        if timerModel.isRunning {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Timer Running")
            button.title = " \(timerModel.formattedTime)"
        } else {
            button.image = NSImage(systemSymbolName: "timer.circle", accessibilityDescription: "Timer")
            button.title = ""
        }
    }
    
    @objc private func statusItemClicked(_ sender: Any?) {
        // No-op here because MenuBarExtra handles the menu UI in SwiftUI side.
        // This is present so we can programmatically trigger the click.
    }

    func toggle() {
        guard let button = statusItem?.button else { return }
        // Programmatically trigger the button's action to open/close the menu/panel
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(#selector(statusItemClicked(_:)), to: self, from: button)
        // Also try to perform click to mimic user interaction in case action routing differs
        button.performClick(nil)
    }
}
