//
//  SystemVoiceTTSClient.swift
//  leanring-buddy
//
//  On-device text-to-speech via AVSpeechSynthesizer. Free, instant, works offline,
//  and needs no Worker. Used both as a selectable TTS provider and as the lowest-
//  latency option for voice previews in Settings.
//

import AVFoundation
import Foundation

@MainActor
final class SystemVoiceTTSClient {
    private let speechSynthesizer = AVSpeechSynthesizer()

    /// Speaks `text` with the macOS voice identified by `voiceIdentifier` (an
    /// `AVSpeechSynthesisVoice.identifier`; nil uses the system default voice).
    /// Returns once playback has STARTED so the calling pipeline can move to its
    /// "responding" state, matching the network TTS clients' behavior.
    func speakText(_ text: String, voiceIdentifier: String?) {
        // Cut off any in-progress utterance so a new request speaks immediately.
        speechSynthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        if let voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        }
        speechSynthesizer.speak(utterance)
    }

    /// Whether the synthesizer is currently speaking.
    var isPlaying: Bool {
        speechSynthesizer.isSpeaking
    }

    /// Stops any in-progress speech immediately.
    func stopPlayback() {
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    /// The English macOS voices available for selection, sorted by name. We filter to
    /// English so the picker isn't an overwhelming list of every installed language;
    /// the app's responses are English. Falls back to all voices if none are English.
    static func availableEnglishVoices() -> [TTSVoiceOption] {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let englishVoices = allVoices.filter { $0.language.hasPrefix("en") }
        let voicesToOffer = englishVoices.isEmpty ? allVoices : englishVoices

        return voicesToOffer
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { voice in
                // Include the locale so the user can tell similarly-named voices apart
                // (e.g. "Samantha (en-US)" vs a regional variant).
                TTSVoiceOption(identifier: voice.identifier, displayName: "\(voice.name) (\(voice.language))")
            }
    }
}
