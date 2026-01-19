import SwiftUI

struct ContentView: View {
    @EnvironmentObject var timerModel: TimerModel
    @FocusState private var focusMinutes: Bool
    
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
                                .submitLabel(.go)
                        }
                        
                        VStack {
                            Text("Minutes")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("0", value: $timerModel.minutes, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .multilineTextAlignment(.center)
                                .focused($focusMinutes)
                                .submitLabel(.go)
                        }
                        
                        VStack {
                            Text("Seconds")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("0", value: $timerModel.seconds, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .multilineTextAlignment(.center)
                                .submitLabel(.go)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Completion Message")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        TextField("Timer ended", text: $timerModel.speechText)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.go)
                    }
                }
            }
            
            HStack(spacing: 10) {
                if timerModel.isRunning {
                    Button("Stop") {
                        timerModel.stopTimer()
                        timerModel.requestFocus()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Start") {
                        timerModel.startTimer()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
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
            
            HStack(spacing: 8) {
                if #available(macOS 14.0, *) {
                    SettingsLink {
                        Label("Preferences", systemImage: "gearshape")
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                } else {
                    Button {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    } label: {
                        Label("Preferences", systemImage: "gearshape")
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Text("|")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .onSubmit {
            timerModel.startTimer()
        }
        .padding()
        .frame(width: 260)
        .onChange(of: timerModel.focusToken) { _ in
            if !timerModel.isRunning {
                focusMinutes = true
            }
        }
        .onChange(of: timerModel.isRunning) { isRunning in
            if !isRunning {
                Task { @MainActor in
                    focusMinutes = true
                }
            }
        }
        .onAppear { focusMinutes = true }
    }
}

