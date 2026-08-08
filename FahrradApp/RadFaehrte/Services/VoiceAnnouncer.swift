//
//  VoiceAnnouncer.swift
//  RadFaehrte
//

import AVFoundation

/// Liest Abbiege-Ansagen per Sprachsynthese vor - nutzt denselben Auslösepunkt wie das
/// Watch-Haptik-Signal (`ContentView.checkTurnAnnouncementTrigger`), damit Vibration und Ansage
/// für dieselbe Abbiegung gleichzeitig kommen. Bewusst eigene Klasse statt `AVSpeechSynthesizer`
/// direkt in `ContentView` zu halten, damit die Audio-Session-Konfiguration an einer Stelle
/// gekapselt ist.
final class VoiceAnnouncer {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "de-DE")

    /// `.duckOthers` senkt kurz die Lautstärke anderer Audioquellen (z. B. Musik/Podcast) statt sie
    /// stummzuschalten oder zu unterbrechen - impliziert laut Apple-Doku bereits `.mixWithOthers`.
    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: .duckOthers)
        try? session.setActive(true)
    }

    /// Aktiviert die Audio-Session schon bei Navigationsstart, statt erst faul beim ersten
    /// `speak()`-Aufruf (Nutzer-Meldung 2026-08-05: Sprachausgabe war an, blieb bei der ersten
    /// Abbiegung aber stumm, ging danach wieder). Wird eine `AVAudioSession` zum ersten Mal
    /// aktiviert und im selben Moment schon gesprochen, kann iOS die allererste Äußerung
    /// verschlucken, weil die Audio-Route (Lautsprecher/Bluetooth/...) noch nicht steht - ohne
    /// Fehler, einfach lautlos. Von `ContentView.startNavigating()` aufgerufen, damit die Session
    /// schon steht, bevor die erste echte Ansage unterwegs kommt.
    func prepare() {
        activateAudioSession()
    }

    /// Bricht eine noch laufende Ansage sofort ab, statt die neue dahinter einzureihen -
    /// `AVSpeechSynthesizer` reiht neue Ansagen sonst nur in eine Warteschlange ein
    /// (`speak(_:)` unterbricht nicht selbst), wodurch sich bei dicht aufeinanderfolgenden
    /// Abbiegungen ein Rückstau bilden und die aktuellere Ansage (z. B. "Jetzt ...") erst deutlich
    /// verspätet zu hören sein kann.
    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        activateAudioSession()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
