//
//  TTSProvider.swift
//  leanring-buddy
//
//  Protocol abstraction for text-to-speech backends (ElevenLabs, OpenAI TTS,
//  on-device AVSpeechSynthesizer). Mirrors the LLMProvider abstraction: a small
//  protocol the speaking pipeline talks to, with concrete implementations behind it.
//

import Foundation

/// The user-selectable text-to-speech backends. Raw values are persisted in
/// UserDefaults, so renaming a case requires a migration.
enum TTSProviderKind: String, CaseIterable {
    case elevenLabs
    case openAI
    case systemVoice

    var displayName: String {
        switch self {
        case .elevenLabs: return "ElevenLabs"
        case .openAI: return "OpenAI"
        case .systemVoice: return "System Voice"
        }
    }

    /// Short caption shown under the picker so the user understands the tradeoff.
    var caption: String {
        switch self {
        case .elevenLabs:
            return "Most natural-sounding, via your Worker. The default."
        case .openAI:
            return "Fast and expressive, via your Worker (needs OPENAI_API_KEY on the Worker)."
        case .systemVoice:
            return "On-device and instant — free, works offline, no Worker needed."
        }
    }
}

/// A selectable voice for a given TTS provider. The `identifier` is what the
/// backend expects: an ElevenLabs voice id, an OpenAI voice name, or a macOS
/// `AVSpeechSynthesisVoice` identifier.
struct TTSVoiceOption: Identifiable, Equatable {
    let identifier: String
    let displayName: String

    var id: String { identifier }
}

/// Unified interface for text-to-speech providers. Implementations handle request
/// formatting, auth, and audio playback for their respective backends.
@MainActor
protocol TTSProvider {
    var displayName: String { get }

    /// The voices the user can pick for this provider. May be empty (e.g. while the
    /// on-device voice list is loading) — callers should tolerate that.
    var availableVoices: [TTSVoiceOption] { get }

    /// Speaks `text` aloud using `voiceIdentifier` (a value from `availableVoices`;
    /// nil means "use the provider's default voice"). Throws on network/decoding
    /// errors. Cancellation-safe.
    func speakText(_ text: String, voiceIdentifier: String?) async throws

    /// Whether audio from this provider is currently playing back. Used by the
    /// transient-cursor scheduler to know when speech has finished.
    var isPlaying: Bool { get }

    /// Stops any in-progress playback immediately.
    func stopPlayback()
}
