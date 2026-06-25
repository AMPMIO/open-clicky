//
//  OpenAITTSClient.swift
//  leanring-buddy
//
//  Posts text to the Cloudflare Worker `/tts-openai` route, which proxies OpenAI's
//  TTS API (gpt-4o-mini-tts) with the server-held key, then plays the returned MP3
//  through the system audio output. Mirrors ElevenLabsTTSClient so the TTS provider
//  layer can swap them interchangeably.
//

import AVFoundation
import Foundation

@MainActor
final class OpenAITTSClient {
    private var proxyURL: URL
    private let session: URLSession

    /// The audio player for the current TTS playback. Kept alive so the audio
    /// finishes playing even if the caller doesn't hold a reference.
    private var audioPlayer: AVAudioPlayer?

    init(proxyURL: String) {
        self.proxyURL = URL(string: proxyURL)!

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    /// Sends `text` to the Worker's OpenAI TTS route with the selected `voice`
    /// (one of: alloy, ash, ballad, coral, echo, sage, shimmer, verse) and plays
    /// the resulting audio. Throws on network or decoding errors. Cancellation-safe.
    func speakText(_ text: String, voice: String) async throws {
        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "voice": voice
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenAITTS", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OpenAITTS", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "OpenAI TTS error (\(httpResponse.statusCode)): \(errorBody)"])
        }

        try Task.checkCancellation()

        let player = try AVAudioPlayer(data: data)
        self.audioPlayer = player
        player.play()
        print("🔊 OpenAI TTS: playing \(data.count / 1024)KB audio")
    }

    /// Updates the proxy endpoint so playback isn't pinned to a stale/placeholder
    /// URL when the Worker URL changes in Settings. Ignores invalid strings.
    func updateProxyURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            self.proxyURL = url
        }
    }

    /// Whether TTS audio is currently playing back.
    var isPlaying: Bool {
        audioPlayer?.isPlaying ?? false
    }

    /// Stops any in-progress playback immediately.
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}
