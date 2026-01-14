import SwiftUI
import AppKit
import Carbon.HIToolbox

@main
struct TimerApp: App {
    @StateObject private var timerModel = TimerModel()
    @State private var flashToggle = false
    @State private var shouldFlash = false
    @State private var didApplyLaunchParams = false

    private let menuBarManager = MenuBarManager()
    private let hotKeyManager = HotKeyManager()

    init() {
        // No command-line parsing; app presents menu UI and focuses first field.
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(timerModel)
                .onAppear {
                    let hotKey = HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: HotKey.command | HotKey.option)
                    hotKeyManager.register(hotKey: hotKey) { [menuBarManager] in
                        DispatchQueue.main.async {
                            menuBarManager.toggle()
                        }
                    }
                }
        } label: {
            HStack {
                Image(systemName: timerModel.isRunning ? "timer" : "timer.circle")
                if timerModel.isRunning {
                    Text(timerModel.formattedTime)
                        .font(.system(.caption, design: .monospaced))
                        .id(timerModel.formattedTime)
                } else {
                    let atZero = timerModel.formattedTime == "0:00:00"
                        || timerModel.formattedTime == "0:0:0"
                        || timerModel.formattedTime == "00:00:00"
                    if atZero {
                        Text("0:00:00")
                            .font(.system(.caption, design: .monospaced))
                            .opacity(flashToggle ? 1 : 0)
                            .onAppear { shouldFlash = true }
                    }
                }
            }
            .onChange(of: timerModel.isRunning) { newVal in
                if newVal { shouldFlash = false }
            }
            .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                if shouldFlash {
                    flashToggle.toggle()
                } else {
                    flashToggle = true
                }
            }
            .accessibilityLabel("Timer")
        }
        .menuBarExtraStyle(.window)
    }
}

