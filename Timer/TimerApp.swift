import SwiftUI

@main
struct TimerApp: App {
    @StateObject private var timerModel = TimerModel()
    
    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(timerModel)
        } label: {
            HStack {
                Image(systemName: timerModel.isRunning ? "timer" : "timer.circle")
                if timerModel.isRunning {
                    Text(timerModel.formattedTime)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .accessibilityLabel("Timer")
        }
        .menuBarExtraStyle(.window)
    }
}
