import SwiftUI
import Foundation
import AudioToolbox
import AVFoundation

class TimerModel: ObservableObject {
    @Published var hours: Int = 0
    @Published var minutes: Int = 0
    @Published var seconds: Int = 0
    @Published var totalSeconds: Int = 0
    @Published var remainingSeconds: Int = 0
    @Published var isRunning: Bool = false
    @Published var speechText: String = "Timer ended"
    
    private let kHoursKey = "TimerModel.hours"
    private let kMinutesKey = "TimerModel.minutes"
    private let kSecondsKey = "TimerModel.seconds"
    private let kSpeechKey = "TimerModel.speechText"
    
    private var timer: Timer?
    
    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: kHoursKey) != nil { self.hours = defaults.integer(forKey: kHoursKey) }
        if defaults.object(forKey: kMinutesKey) != nil { self.minutes = defaults.integer(forKey: kMinutesKey) }
        if defaults.object(forKey: kSecondsKey) != nil { self.seconds = defaults.integer(forKey: kSecondsKey) }
        if let savedSpeech = defaults.string(forKey: kSpeechKey) { self.speechText = savedSpeech }
    }
    
    private func persistSettings() {
        let defaults = UserDefaults.standard
        defaults.set(hours, forKey: kHoursKey)
        defaults.set(minutes, forKey: kMinutesKey)
        defaults.set(seconds, forKey: kSecondsKey)
        defaults.set(speechText, forKey: kSpeechKey)
    }
    
    func startTimer() {
        guard hours > 0 || minutes > 0 || seconds > 0 else { return }
        
        totalSeconds = hours * 3600 + minutes * 60 + seconds
        remainingSeconds = totalSeconds
        isRunning = true
        persistSettings()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                self.tick()
            }
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        remainingSeconds = 0
    }
    
    func resetTimer() {
        stopTimer()
        remainingSeconds = 0
        persistSettings()
    }
    
    private func tick() {
        if remainingSeconds > 0 {
            remainingSeconds -= 1
        } else {
            stopTimer()
            speak(text: speechText)
        }
    }
    
    private func playBeep() {
        // Create a simple beep sound using system sound
        AudioServicesPlaySystemSound(kSystemSoundID_UserPreferredAlert)
    }
    private let speechSynth = AVSpeechSynthesizer()
    private func speak(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-us")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechSynth.speak(utterance)
    }
    var formattedTime: String {
        let hrs = remainingSeconds / 3600
        let mins = (remainingSeconds % 3600) / 60
        let secs = remainingSeconds % 60
        return String(format: "%02d:%02d:%02d", hrs, mins, secs)
    }
}
