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
final class SystemVoiceTTSClient: NSObject, AVSpeechSynthesizerDelegate {
    private let speechSynthesizer = AVSpeechSynthesizer()

    // AVSpeechSynthesizer.isSpeaking does NOT flip to true synchronously when speak()
    // returns — the audio engine spins up asynchronously — so a caller that polls
    // isPlaying right after speakText (the transient-cursor hide loop and the macro
    // "wait for TTS to finish" loop) would see false and exit early, fading the
    // overlay / advancing the macro mid-sentence. We track speaking state ourselves:
    // set it true the instant we enqueue an utterance and clear it on the
    // synthesizer's finish/cancel callback. This honors the "returns once playback
    // has STARTED" contract the AVAudioPlayer-backed network clients already satisfy.
    private var isSpeakingFlag = false

    /// Identifies the utterance the flag currently belongs to. When a new utterance
    /// interrupts an old one, the OLD utterance's didCancel callback must NOT clear
    /// the new utterance's flag — so we only clear when the finishing/cancelling
    /// utterance is still the active one.
    private var activeUtteranceID: ObjectIdentifier?

    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }

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
        activeUtteranceID = ObjectIdentifier(utterance)
        isSpeakingFlag = true
        speechSynthesizer.speak(utterance)
    }

    /// True from the moment speakText enqueues an utterance until the synthesizer
    /// reports it finished/cancelled, OR'd with the synthesizer's own flag as a
    /// backstop.
    var isPlaying: Bool {
        isSpeakingFlag || speechSynthesizer.isSpeaking
    }

    /// Stops any in-progress speech immediately.
    func stopPlayback() {
        activeUtteranceID = nil
        isSpeakingFlag = false
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - AVSpeechSynthesizerDelegate
    // Delivered by AVSpeechSynthesizer on the main thread; hop to the MainActor so
    // the isolated flag write is well-formed. We capture only the Sendable
    // ObjectIdentifier (not the utterance) and clear the flag only if it still
    // refers to the active utterance.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let finishedID = ObjectIdentifier(utterance)
        Task { @MainActor in
            if finishedID == self.activeUtteranceID {
                self.isSpeakingFlag = false
                self.activeUtteranceID = nil
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let cancelledID = ObjectIdentifier(utterance)
        Task { @MainActor in
            if cancelledID == self.activeUtteranceID {
                self.isSpeakingFlag = false
                self.activeUtteranceID = nil
            }
        }
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
