//
//  VoiceProvider.swift
//  leanring-buddy
//
//  Protocol stubs for TTS and STT providers. Current implementations
//  (ElevenLabs, AssemblyAI) remain unchanged. These protocols define
//  the interface for future local providers (Whisper, Qwen3 TTS).
//

import Foundation

/// Text-to-speech provider interface.
protocol TTSProvider {
    var displayName: String { get }
    func synthesize(text: String) async throws -> Data
}

/// Speech-to-text provider interface.
protocol STTProvider {
    var displayName: String { get }
    func transcribe(audioData: Data) async throws -> String
}
