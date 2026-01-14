import SwiftUI
import AppKit

@main
struct TimerApp: App {
    @StateObject private var timerModel = TimerModel()
    @State private var flashToggle = false
    @State private var shouldFlash = false

    init() {
        // Single-instance guard: if another instance of this bundle is running, exit immediately
        let runningSameBundle = NSWorkspace.shared.runningApplications.contains { app in
            guard app.processIdentifier != getpid() else { return false }
            return app.bundleIdentifier == Bundle.main.bundleIdentifier && app.isFinishedLaunching
        }

        // Parse command line arguments for hours, minutes, seconds, message, and auto-start
        let args = CommandLine.arguments
        var h: Int? = nil
        var m: Int? = nil
        var s: Int? = nil
        var message: String? = nil
        var autoStart = false
        var printPathOnly = false

        func intValue(after flag: String) -> Int? {
            guard let idx = args.firstIndex(of: flag), args.indices.contains(args.index(after: idx)) else { return nil }
            return Int(args[args.index(after: idx)])
        }
        func stringValue(after flag: String) -> String? {
            guard let idx = args.firstIndex(of: flag), args.indices.contains(args.index(after: idx)) else { return nil }
            return args[args.index(after: idx)]
        }

        // Existing long/short flags
        h = intValue(after: "--hours") ?? intValue(after: "-h")
        m = intValue(after: "--minutes") ?? intValue(after: "-m")
        s = intValue(after: "--seconds") ?? intValue(after: "-s")
        message = stringValue(after: "--message") ?? stringValue(after: "-msg")
        autoStart = args.contains("--start") || args.contains("-start")
        printPathOnly = args.contains("--print-path") || args.contains("-pp")

        // Compact query support: --query/-q "25m30s \"Tea ready\"" or "1h 5m 10s \"Msg\""
        if let q = stringValue(after: "--query") ?? stringValue(after: "-q") {
            // Extract quoted message at the end if present
            var query = q.trimmingCharacters(in: .whitespacesAndNewlines)
            var extractedMessage: String? = nil
            if let firstQuote = query.firstIndex(of: "\"") {
                // message is from first quote to last quote
                if let lastQuote = query.lastIndex(of: "\"") , lastQuote > firstQuote {
                    let msgRange = query.index(after: firstQuote)..<lastQuote
                    extractedMessage = String(query[msgRange])
                    // Remove the quoted message from the query string
                    let prefix = query[..<firstQuote]
                    let suffix = query[query.index(after: lastQuote)...]
                    query = (prefix + suffix).trimmingCharacters(in: .whitespaces)
                }
            }
            // Now parse time tokens like 1h, 5m, 30s or a bare number (defaults to minutes)
            // Split on whitespace to get tokens; also handle concatenated like 25m30s by scanning
            func parseTimeTokens(from str: String) -> (Int, Int, Int) {
                var hours = 0, minutes = 0, seconds = 0
                let wsSeparated = str.split(whereSeparator: { $0.isWhitespace })
                let tokens = wsSeparated.isEmpty ? [Substring(str)] : wsSeparated
                let unitSet: Set<Character> = ["h","m","s","H","M","S"]
                for tokenSub in tokens {
                    let token = String(tokenSub)
                    // Scan the token for number+unit sequences, e.g., 1h30m45s
                    var numBuffer = ""
                    for ch in token {
                        if ch.isNumber { numBuffer.append(ch) }
                        else if unitSet.contains(ch) {
                            let val = Int(numBuffer) ?? 0
                            switch ch.lowercased() {
                            case "h": hours += val
                            case "m": minutes += val
                            case "s": seconds += val
                            default: break
                            }
                            numBuffer = ""
                        } else {
                            // ignore other chars
                        }
                    }
                    // If token is a bare number with no unit, treat it as minutes
                    if !numBuffer.isEmpty {
                        minutes += Int(numBuffer) ?? 0
                    }
                }
                return (hours, minutes, seconds)
            }

            let (qh, qm, qs) = parseTimeTokens(from: query)
            if qh > 0 { h = qh }
            if qm > 0 { m = qm }
            if qs > 0 { s = qs }
            if let extractedMessage { message = extractedMessage }
        }

        // If requested, print the current executable path and exit immediately
        if printPathOnly {
            if let exe = Bundle.main.executablePath {
                print(exe)
            } else {
                // Fallback: derive from bundle URL
                let fallback = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS").appendingPathComponent((Bundle.main.infoDictionary?["CFBundleExecutable"] as? String) ?? "").path
                print(fallback)
            }
            // Terminate quickly to avoid launching UI when only printing path
            exit(0)
        }

        // Apply parsed values to defaults so the StateObject sees them on first render
        let defaults = UserDefaults.standard
        if let h { defaults.set(h, forKey: "TimerModel.hours") }
        if let m { defaults.set(m, forKey: "TimerModel.minutes") }
        if let s { defaults.set(s, forKey: "TimerModel.seconds") }
        if let message { defaults.set(message, forKey: "TimerModel.speechText") }
        // Flag for auto-start handoff to a running instance
        defaults.set(autoStart, forKey: "TimerModel.autoStart")

        // If another instance is already running, hand off via defaults and exit
        if runningSameBundle {
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }

        let model = timerModel

        // Capture values to avoid capturing self in an escaping closure
        let applyH = h
        let applyM = m
        let applyS = s
        let applyMessage = message
        let shouldAutoStart = autoStart

        // Apply values to the model on main actor and conditionally start without capturing self
        Task { @MainActor in
            if let applyH { model.hours = applyH }
            if let applyM { model.minutes = applyM }
            if let applyS { model.seconds = applyS }
            if let applyMessage { model.speechText = applyMessage }
            if shouldAutoStart {
                model.startTimer()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(timerModel)
                .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                    let defaults = UserDefaults.standard
                    let newH = defaults.object(forKey: "TimerModel.hours") as? Int
                    let newM = defaults.object(forKey: "TimerModel.minutes") as? Int
                    let newS = defaults.object(forKey: "TimerModel.seconds") as? Int
                    let newMsg = defaults.string(forKey: "TimerModel.speechText")
                    let shouldAutoStart = defaults.bool(forKey: "TimerModel.autoStart")
                    Task { @MainActor in
                        if let newH { timerModel.hours = newH }
                        if let newM { timerModel.minutes = newM }
                        if let newS { timerModel.seconds = newS }
                        if let newMsg { timerModel.speechText = newMsg }
                        if shouldAutoStart {
                            timerModel.startTimer()
                        }
                    }
                }
        } label: {
            HStack {
                Image(systemName: timerModel.isRunning ? "timer" : "timer.circle")
                // Show time when running, or flash 0:00:00 when finished
                if timerModel.isRunning {
                    Text(timerModel.formattedTime)
                        .font(.system(.caption, design: .monospaced))
                        .id(timerModel.formattedTime)
                } else {
                    // Determine if we are at zero and should flash
                    let atZero = timerModel.formattedTime == "0:00:00" || timerModel.formattedTime == "0:0:0" || timerModel.formattedTime == "00:00:00"
                    if atZero {
                        Text("0:00:00")
                            .font(.system(.caption, design: .monospaced))
                            .opacity(flashToggle ? 1 : 0)
                            .onAppear {
                                shouldFlash = true
                            }
                    }
                }
            }
            .onChange(of: timerModel.isRunning) { newVal in
                // Stop flashing when a new run starts
                if newVal {
                    shouldFlash = false
                }
            }
            .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                // Toggle flashing only when we should flash (timer completed)
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

