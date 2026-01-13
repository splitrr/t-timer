import AppKit
import SwiftUI

class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    
    init() {
        setupMenuBar()
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "timer.circle", accessibilityDescription: "Timer")
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
}