import SwiftUI

struct ContentView: View {
    @EnvironmentObject var timerModel: TimerModel
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Timer")
                .font(.title2)
                .fontWeight(.semibold)
            
            if timerModel.isRunning {
                VStack(spacing: 10) {
                    Text("Time Remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(timerModel.formattedTime)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
            } else {
                VStack(spacing: 15) {
                    Text("Set Timer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 10) {
                        VStack {
                            Text("Hours")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("0", value: $timerModel.hours, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .multilineTextAlignment(.center)
                        }
                        
                        VStack {
                            Text("Minutes")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("0", value: $timerModel.minutes, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .multilineTextAlignment(.center)
                        }
                        
                        VStack {
                            Text("Seconds")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("0", value: $timerModel.seconds, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .multilineTextAlignment(.center)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Completion Message")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        TextField("Timer ended", text: $timerModel.speechText)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            
            HStack(spacing: 10) {
                if timerModel.isRunning {
                    Button("Stop") {
                        timerModel.stopTimer()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button("Start") {
                        timerModel.startTimer()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(timerModel.hours == 0 && timerModel.minutes == 0 && timerModel.seconds == 0)
                    
                    if timerModel.remainingSeconds > 0 {
                        Button("Reset") {
                            timerModel.resetTimer()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 250)
    }
}
