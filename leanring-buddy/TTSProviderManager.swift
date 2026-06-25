//
//  TTSProviderManager.swift
//  leanring-buddy
//
//  Owns the active text-to-speech provider and the user's per-provider voice
//  selection, and routes speaking through the chosen backend. Analogous to
//  ProviderManager for the LLM layer. ElevenLabs stays the default so the current
//  voice pipeline is unchanged unless the user picks another provider.
//

import AVFoundation
import Combine
import Foundation
import os

@MainActor
final class TTSProviderManager: ObservableObject {
    // MARK: - UserDefaults Keys

    private static let providerKey = "ttsProvider"
    /// Voice id is stored PER provider so switching backends never sends an
    /// ElevenLabs voice id to OpenAI (different id namespaces), mirroring how
    /// ProviderConfiguration stores the model id per LLM provider.
    private static let voiceKeyPrefix = "ttsVoiceID."

    // MARK: - Published State

    @Published private(set) var activeProvider: TTSProviderKind

    // MARK: - Backing Clients

    private let elevenLabsProvider: ElevenLabsTTSProvider
    private let openAIProvider: OpenAITTSProvider
    private let systemVoiceProvider: SystemVoiceTTSProvider

    init() {
        let storedRawValue = UserDefaults.standard.string(forKey: Self.providerKey)
        self.activeProvider = storedRawValue.flatMap(TTSProviderKind.init(rawValue:)) ?? .elevenLabs

        // Seed each network client with the configured Worker route, falling back to
        // the (https) placeholder — same approach CompanionManager used for the lone
        // ElevenLabs client. The route is refreshed before each speak (see speakText).
        let elevenLabsSeed = ProviderConfiguration.workerRouteURL("/tts")?.absoluteString
            ?? "\(ProviderConfiguration.defaultWorkerBaseURL)/tts"
        let openAISeed = ProviderConfiguration.workerRouteURL("/tts-openai")?.absoluteString
            ?? "\(ProviderConfiguration.defaultWorkerBaseURL)/tts-openai"

        self.elevenLabsProvider = ElevenLabsTTSProvider(client: ElevenLabsTTSClient(proxyURL: elevenLabsSeed))
        self.openAIProvider = OpenAITTSProvider(client: OpenAITTSClient(proxyURL: openAISeed))
        self.systemVoiceProvider = SystemVoiceTTSProvider(client: SystemVoiceTTSClient())
    }

    // MARK: - Provider / Voice Selection

    func setActiveProvider(_ provider: TTSProviderKind) {
        // Stop any audio from the previous provider so a switch doesn't leave two
        // voices overlapping.
        stopPlayback()
        activeProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey)
        ClickyTelemetry.pipeline.notice("TTS provider changed to \(provider.rawValue, privacy: .public)")
    }

    /// The voices the user can pick for `provider`.
    func availableVoices(for provider: TTSProviderKind) -> [TTSVoiceOption] {
        backingProvider(for: provider).availableVoices
    }

    /// The user's selected voice id for `provider`, or the provider's first available
    /// voice when nothing is stored yet (so a fresh install has a sensible default).
    func selectedVoiceID(for provider: TTSProviderKind) -> String? {
        if let stored = UserDefaults.standard.string(forKey: Self.voiceKeyPrefix + provider.rawValue),
           !stored.isEmpty {
            return stored
        }
        return backingProvider(for: provider).availableVoices.first?.identifier
    }

    func setSelectedVoiceID(_ voiceID: String, for provider: TTSProviderKind) {
        UserDefaults.standard.set(voiceID, forKey: Self.voiceKeyPrefix + provider.rawValue)
    }

    // MARK: - Speaking

    /// Whether `provider` needs a configured Worker route to speak. ElevenLabs and
    /// OpenAI proxy through the Worker; the on-device System Voice needs no network.
    static func requiresWorker(_ provider: TTSProviderKind) -> Bool {
        switch provider {
        case .elevenLabs, .openAI: return true
        case .systemVoice: return false
        }
    }

    /// Speaks `text` through the ACTIVE provider with the user's selected voice.
    /// Refreshes the network providers' Worker route first so a Settings URL change
    /// reaches TTS. Throws on backend failure (so the caller can fall back) and also
    /// throws — failing closed — if a network provider has no valid Worker route, so
    /// TTS text is never POSTed to the unconfigured placeholder host.
    func speakText(_ text: String) async throws {
        try ensureWorkerRouteReadyOrThrow(for: activeProvider)
        refreshWorkerRoutes()
        let provider = backingProvider(for: activeProvider)
        let voiceID = selectedVoiceID(for: activeProvider)
        try await provider.speakText(text, voiceIdentifier: voiceID)
    }

    /// Speaks a short preview phrase for `voiceID` on `provider`, used by the Settings
    /// voice picker's tap-to-preview buttons. Independent of the active selection so
    /// the user can audition a voice without committing to it.
    func previewVoice(_ voiceID: String, for provider: TTSProviderKind) async throws {
        try ensureWorkerRouteReadyOrThrow(for: provider)
        refreshWorkerRoutes()
        let previewPhrase = "hey, this is how i'll sound."
        try await backingProvider(for: provider).speakText(previewPhrase, voiceIdentifier: voiceID)
    }

    /// Throws a clear error when a Worker-backed provider has no valid route — fail
    /// closed instead of POSTing to the unconfigured placeholder. No-op for the
    /// on-device provider.
    private func ensureWorkerRouteReadyOrThrow(for provider: TTSProviderKind) throws {
        guard Self.requiresWorker(provider) else { return }
        let path = provider == .openAI ? "/tts-openai" : "/tts"
        guard ProviderConfiguration.workerRouteURL(path) != nil else {
            throw NSError(
                domain: "TTSProviderManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Set your Worker URL in Settings to use \(provider.displayName) voice."]
            )
        }
    }

    /// Whether the active provider is currently playing audio.
    var isPlaying: Bool {
        backingProvider(for: activeProvider).isPlaying
    }

    /// Stops playback across ALL providers (a switch or interruption shouldn't leave
    /// any backend still talking).
    func stopPlayback() {
        elevenLabsProvider.stopPlayback()
        openAIProvider.stopPlayback()
        systemVoiceProvider.stopPlayback()
    }

    // MARK: - Helpers

    private func backingProvider(for kind: TTSProviderKind) -> any TTSProvider {
        switch kind {
        case .elevenLabs: return elevenLabsProvider
        case .openAI: return openAIProvider
        case .systemVoice: return systemVoiceProvider
        }
    }

    /// Re-points the network clients at the currently-configured Worker route. No-op
    /// when the Worker URL is the unconfigured placeholder (the client keeps its seed
    /// and the request fails closed, surfacing a clear error).
    private func refreshWorkerRoutes() {
        if let elevenLabsURL = ProviderConfiguration.workerRouteURL("/tts") {
            elevenLabsProvider.updateProxyURL(elevenLabsURL.absoluteString)
        }
        if let openAIURL = ProviderConfiguration.workerRouteURL("/tts-openai") {
            openAIProvider.updateProxyURL(openAIURL.absoluteString)
        }
    }
}

// MARK: - Provider Adapters
//
// Thin adapters that conform the existing TTS clients to the TTSProvider protocol,
// normalizing their slightly different speakText signatures. Owning the protocol type
// in the manager keeps the speaking pipeline backend-agnostic.

@MainActor
final class ElevenLabsTTSProvider: TTSProvider {
    let displayName = TTSProviderKind.elevenLabs.displayName
    private let client: ElevenLabsTTSClient

    init(client: ElevenLabsTTSClient) {
        self.client = client
    }

    /// ElevenLabs has thousands of voices behind the user's account; the Worker holds
    /// the default voice id. Rather than fetch the full catalog, we offer the Worker
    /// default plus the most common public voices by id so the user has real choices.
    /// An empty `identifier` means "use the Worker's configured ELEVENLABS_VOICE_ID".
    var availableVoices: [TTSVoiceOption] {
        [
            TTSVoiceOption(identifier: "", displayName: "Worker default"),
            TTSVoiceOption(identifier: "21m00Tcm4TlvDq8ikWAM", displayName: "Rachel"),
            TTSVoiceOption(identifier: "AZnzlk1XvdvUeBnXmlld", displayName: "Domi"),
            TTSVoiceOption(identifier: "EXAVITQu4vr4xnSDxMaL", displayName: "Bella"),
            TTSVoiceOption(identifier: "ErXwobaYiN019PkySvjV", displayName: "Antoni"),
            TTSVoiceOption(identifier: "VR6AewLTigWG4xSOukaG", displayName: "Arnold"),
            TTSVoiceOption(identifier: "pNInz6obpgDQGcFmaJgB", displayName: "Adam"),
            TTSVoiceOption(identifier: "yoZ06aMxZJJ28mfd3POQ", displayName: "Sam")
        ]
    }

    func speakText(_ text: String, voiceIdentifier: String?) async throws {
        // Forward a non-empty voice id; nil/empty lets the Worker use its default voice.
        let voiceId = (voiceIdentifier?.isEmpty == false) ? voiceIdentifier : nil
        try await client.speakText(text, voiceId: voiceId)
    }

    var isPlaying: Bool { client.isPlaying }
    func stopPlayback() { client.stopPlayback() }
    func updateProxyURL(_ urlString: String) { client.updateProxyURL(urlString) }
}

@MainActor
final class OpenAITTSProvider: TTSProvider {
    let displayName = TTSProviderKind.openAI.displayName
    private let client: OpenAITTSClient

    init(client: OpenAITTSClient) {
        self.client = client
    }

    /// The fixed set of OpenAI TTS voices (gpt-4o-mini-tts).
    var availableVoices: [TTSVoiceOption] {
        ["alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse"].map { voiceName in
            TTSVoiceOption(identifier: voiceName, displayName: voiceName.capitalized)
        }
    }

    func speakText(_ text: String, voiceIdentifier: String?) async throws {
        // OpenAI requires a voice; default to "alloy" if somehow none is selected.
        let voice = (voiceIdentifier?.isEmpty == false) ? voiceIdentifier! : "alloy"
        try await client.speakText(text, voice: voice)
    }

    var isPlaying: Bool { client.isPlaying }
    func stopPlayback() { client.stopPlayback() }
    func updateProxyURL(_ urlString: String) { client.updateProxyURL(urlString) }
}

@MainActor
final class SystemVoiceTTSProvider: TTSProvider {
    let displayName = TTSProviderKind.systemVoice.displayName
    private let client: SystemVoiceTTSClient

    init(client: SystemVoiceTTSClient) {
        self.client = client
    }

    var availableVoices: [TTSVoiceOption] {
        SystemVoiceTTSClient.availableEnglishVoices()
    }

    func speakText(_ text: String, voiceIdentifier: String?) async throws {
        // On-device synthesis never throws on "network"; it just starts speaking.
        client.speakText(text, voiceIdentifier: voiceIdentifier)
    }

    var isPlaying: Bool { client.isPlaying }
    func stopPlayback() { client.stopPlayback() }
}
