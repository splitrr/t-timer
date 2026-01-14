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
    
    private let cliNotificationName = Notification.Name("com.yourcompany.Timer.CLICommand")
    
    private let defaults = UserDefaults.standard
    private var lastMessageKey: String { "TimerApp.lastMessage" }

    private func applyCLIArguments(_ rawArgs: [String]) {
        // Parse tokens like "2h", "30m", "45s" and optional message in quotes or remaining tokens
        let args = Array(rawArgs.dropFirst())
        var hours: Int? = nil
        var minutes: Int? = nil
        var seconds: Int? = nil
        var message: String? = nil

        var messageParts: [String] = []
        for token in args {
            if token.hasSuffix("h"), let val = Int(token.dropLast()) { hours = val; continue }
            if token.hasSuffix("m"), let val = Int(token.dropLast()) { minutes = val; continue }
            if token.hasSuffix("s"), let val = Int(token.dropLast()) { seconds = val; continue }
            messageParts.append(token)
        }
        if !messageParts.isEmpty {
            message = messageParts.joined(separator: " ")
            if let msg = message, msg.hasPrefix("\"") && msg.hasSuffix("\"") && msg.count >= 2 {
                message = String(msg.dropFirst().dropLast())
            }
        } else {
            // No message provided; reuse last if available
            if let saved = defaults.string(forKey: lastMessageKey), !saved.isEmpty { message = saved }
        }

        // Apply to model (use existing values if not provided)
        if let h = hours { timerModel.hours = h }
        if let m = minutes { timerModel.minutes = m }
        if let s = seconds { timerModel.seconds = s }
        if let msg = message, !msg.isEmpty {
            timerModel.speechText = msg
            defaults.set(msg, forKey: lastMessageKey)
        }

        // Auto-start or restart if any duration provided or existing duration is non-zero
        let hasProvidedDuration = (hours != nil) || (minutes != nil) || (seconds != nil)
        let durationNonZero = (timerModel.hours > 0 || timerModel.minutes > 0 || timerModel.seconds > 0)
        if hasProvidedDuration || durationNonZero {
            // Reset and start (singleton behavior: reset current countdown)
            timerModel.stopTimer()
            timerModel.startTimer()
        }
    }

    init() {
        // No command-line parsing; app presents menu UI and focuses first field.

        // Listen for CLI commands from subsequent invocations (singleton behavior)
        DistributedNotificationCenter.default().addObserver(forName: cliNotificationName, object: nil, queue: .main) { [weak timerModel] note in
            guard let payload = note.userInfo?["args"] as? String else { return }
            let tokens = payload.split(separator: " ").map { String($0) }
            // Reconstruct a pseudo argv with executable name placeholder
            let argv = ["TimerApp"] + tokens
            // We cannot call instance methods from a static context without capturing self; instead post a local NotificationCenter event
            NotificationCenter.default.post(name: Notification.Name("TimerApp.ApplyCLI"), object: nil, userInfo: ["argv": argv])
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("TimerApp.ApplyCLI"), object: nil, queue: .main) { [weak self] note in
            guard let self = self, let argv = note.userInfo?["argv"] as? [String] else { return }
            self.applyCLIArguments(argv)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(timerModel)
                .onAppear {
                    // Register global hotkey
                    let hotKey = HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: HotKey.command | HotKey.option)
                    hotKeyManager.register(hotKey: hotKey) { [menuBarManager] in
                        DispatchQueue.main.async {
                            menuBarManager.toggle()
                        }
                    }

                    // Apply command-line args only once at first appearance
                    if !didApplyLaunchParams {
                        didApplyLaunchParams = true
                        let args = ProcessInfo.processInfo.arguments
                        applyCLIArguments(args)
                    }

                    // Ensure menu bar reflects current state
                    menuBarManager.updateMenuBar(with: timerModel)
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
            .onChange(of: timerModel.remainingSeconds) { _ in
                menuBarManager.updateMenuBar(with: timerModel)
            }
            .onChange(of: timerModel.isRunning) { _ in
                menuBarManager.updateMenuBar(with: timerModel)
            }
            .accessibilityLabel("Timer")
        }
        .menuBarExtraStyle(.window)
    }
}

