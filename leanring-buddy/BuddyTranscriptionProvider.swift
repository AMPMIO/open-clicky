//
//  BuddyTranscriptionProvider.swift
//  leanring-buddy
//
//  Shared protocol surface for voice transcription backends.
//

import AVFoundation
import Foundation

protocol BuddyStreamingTranscriptionSession: AnyObject {
    var finalTranscriptFallbackDelaySeconds: TimeInterval { get }
    func appendAudioBuffer(_ audioBuffer: AVAudioPCMBuffer)
    func requestFinalTranscript()
    func cancel()
}

protocol BuddyTranscriptionProvider {
    var displayName: String { get }
    var requiresSpeechRecognitionPermission: Bool { get }
    var isConfigured: Bool { get }
    var unavailableExplanation: String? { get }

    /// Whether a quick push-to-talk release that lands WHILE the session is still
    /// starting should abandon the session (cancel to an empty transcript) instead
    /// of finalizing whatever was captured.
    ///
    /// Cloud providers (AssemblyAI, OpenAI) need a network round-trip to start, so a
    /// release during that window means no audio was ever streamed — cancelling is
    /// correct. Apple Speech starts ~instantly on-device, so a release during start
    /// usually still captured a short utterance ("test"); cancelling it to empty is
    /// the live short-utterance bug. On-device returns false so the started session
    /// is allowed to finalize instead of being thrown away.
    var cancelsOnQuickReleaseDuringSessionStart: Bool { get }

    func startStreamingSession(
        keyterms: [String],
        onTranscriptUpdate: @escaping (String) -> Void,
        onFinalTranscriptReady: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws -> any BuddyStreamingTranscriptionSession
}

extension BuddyTranscriptionProvider {
    /// Default to the safe cloud behavior (cancel on quick release during start);
    /// the on-device Apple Speech provider opts out so short utterances survive.
    var cancelsOnQuickReleaseDuringSessionStart: Bool { true }
}

/// The user-selectable speech-to-text backends. Raw values match the legacy
/// Info.plist `VoiceTranscriptionProvider` strings so a value persisted there (or
/// in UserDefaults) resolves to the same provider.
enum STTProviderKind: String, CaseIterable {
    case appleSpeech = "apple"
    case assemblyAI = "assemblyai"
    case openAI = "openai"

    var displayName: String {
        switch self {
        case .appleSpeech: return "Apple Speech"
        case .assemblyAI: return "AssemblyAI"
        case .openAI: return "OpenAI"
        }
    }

    /// Short caption shown under the picker so the user understands the tradeoff.
    var caption: String {
        switch self {
        case .appleSpeech:
            return "On-device and instant — best for short push-to-talk. No network, no setup."
        case .assemblyAI:
            return "Cloud streaming via your Worker. Very accurate, but a short tap can be lost while it connects."
        case .openAI:
            return "Cloud, upload-on-release via your Worker. Accurate; adds a moment of latency."
        }
    }
}

enum BuddyTranscriptionProviderFactory {
    /// UserDefaults key for the user's persisted speech-to-text choice. Read FIRST
    /// (the Settings picker writes it); Info.plist is only the fallback default.
    static let sttProviderUserDefaultsKey = "sttProvider"

    /// The currently selected provider kind, resolving the persisted UserDefaults
    /// choice first and falling back to the Info.plist value, then to Apple Speech.
    /// Apple Speech is the default so short push-to-talk holds aren't lost to the
    /// cloud-session start race.
    static func selectedProviderKind() -> STTProviderKind {
        if let persistedRawValue = UserDefaults.standard.string(forKey: sttProviderUserDefaultsKey),
           let persistedKind = STTProviderKind(rawValue: persistedRawValue) {
            return persistedKind
        }

        let infoPlistRawValue = AppBundleConfiguration
            .stringValue(forKey: "VoiceTranscriptionProvider")?
            .lowercased()
        if let infoPlistRawValue, let infoPlistKind = STTProviderKind(rawValue: infoPlistRawValue) {
            return infoPlistKind
        }

        return .appleSpeech
    }

    static func makeDefaultProvider() -> any BuddyTranscriptionProvider {
        let provider = resolveProvider()
        print("🎙️ Transcription: using \(provider.displayName)")
        return provider
    }

    private static func resolveProvider() -> any BuddyTranscriptionProvider {
        let selectedKind = selectedProviderKind()

        let assemblyAIProvider = AssemblyAIStreamingTranscriptionProvider()
        let openAIProvider = OpenAIAudioTranscriptionProvider()

        if selectedKind == .appleSpeech {
            return AppleSpeechTranscriptionProvider()
        }

        if selectedKind == .assemblyAI {
            if assemblyAIProvider.isConfigured {
                return assemblyAIProvider
            }

            print("⚠️ Transcription: AssemblyAI selected but not configured, falling back")

            if openAIProvider.isConfigured {
                print("⚠️ Transcription: using OpenAI as fallback")
                return openAIProvider
            }

            print("⚠️ Transcription: using Apple Speech as fallback")
            return AppleSpeechTranscriptionProvider()
        }

        if selectedKind == .openAI {
            if openAIProvider.isConfigured {
                return openAIProvider
            }

            print("⚠️ Transcription: OpenAI selected but not configured, falling back")

            if assemblyAIProvider.isConfigured {
                print("⚠️ Transcription: using AssemblyAI as fallback")
                return assemblyAIProvider
            }

            print("⚠️ Transcription: using Apple Speech as fallback")
            return AppleSpeechTranscriptionProvider()
        }

        return AppleSpeechTranscriptionProvider()
    }
}
