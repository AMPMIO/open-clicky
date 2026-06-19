//
//  OpenRouterAPI.swift
//  leanring-buddy
//
//  Bring-your-own-key vision chat client for OpenRouter. OpenRouter exposes an
//  OpenAI-compatible Chat Completions endpoint that fronts hundreds of models
//  (Claude, GPT, Gemini, Llama, and more), so a single client lets the user
//  drive Clicky with whatever model they pick — using their own API key.
//
//  Unlike the bundled Claude client, this talks to OpenRouter directly rather
//  than through the Cloudflare Worker, because the API key belongs to the user.
//

import Foundation

/// Streaming OpenRouter chat client that conforms to `CompanionChatProvider`
/// so it is a drop-in replacement for the bundled Claude backend.
final class OpenRouterAPI: CompanionChatProvider {
    /// The user's OpenRouter API key. Mutable so settings changes take effect
    /// without rebuilding the client (and its cached TLS connection).
    var apiKey: String
    /// The OpenRouter model identifier, e.g. "anthropic/claude-sonnet-4.5" or "openai/gpt-4o".
    var model: String

    private let apiURL: URL
    private let session: URLSession

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
        self.apiURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

        // Match the bundled clients: cache TLS session tickets (.default, not
        // .ephemeral) so large image payloads don't trip transient handshake
        // failures, and disable on-disk caching of responses/credentials.
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.urlCache = nil
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)

        warmUpTLSConnection()
    }

    /// Sends a no-op HEAD request to the API host to establish and cache a TLS
    /// session so the first real call (with a large image payload) is faster.
    /// Failures are silently ignored — this is purely an optimization.
    private func warmUpTLSConnection() {
        var warmupRequest = URLRequest(url: apiURL)
        warmupRequest.httpMethod = "HEAD"
        warmupRequest.timeoutInterval = 10
        session.dataTask(with: warmupRequest) { _, _, _ in
            // Response doesn't matter — the TLS handshake is the goal
        }.resume()
    }

    /// Detects the MIME type of image data by inspecting the first bytes.
    /// Screen captures from ScreenCaptureKit are JPEG; clipboard images are PNG.
    /// The data URL must declare the matching media type or some models reject it.
    private func detectImageMediaType(for imageData: Data) -> String {
        if imageData.count >= 4 {
            let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
            let firstFourBytes = [UInt8](imageData.prefix(4))
            if firstFourBytes == pngSignature {
                return "image/png"
            }
        }
        return "image/jpeg"
    }

    func analyzeImageStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)] = [],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        let startTime = Date()

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw NSError(
                domain: "OpenRouterAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No OpenRouter API key set. Add your key in the Clicky panel."]
            )
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Optional OpenRouter attribution headers used for its app leaderboard.
        request.setValue("https://github.com/ampmio/open-clicky", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Open Clicky", forHTTPHeaderField: "X-Title")

        // Build messages array in OpenAI Chat Completions format.
        var messages: [[String: Any]] = []

        // System prompt goes first as its own message.
        messages.append([
            "role": "system",
            "content": systemPrompt
        ])

        for (userPlaceholder, assistantResponse) in conversationHistory {
            messages.append(["role": "user", "content": userPlaceholder])
            messages.append(["role": "assistant", "content": assistantResponse])
        }

        // Current turn: each labeled image followed by its text label, then the prompt.
        var contentBlocks: [[String: Any]] = []
        for image in images {
            contentBlocks.append([
                "type": "text",
                "text": image.label
            ])
            let mediaType = detectImageMediaType(for: image.data)
            contentBlocks.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:\(mediaType);base64,\(image.data.base64EncodedString())"
                ]
            ])
        }
        contentBlocks.append([
            "type": "text",
            "text": userPrompt
        ])
        messages.append(["role": "user", "content": contentBlocks])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "stream": true,
            "messages": messages
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        let payloadMB = Double(bodyData.count) / 1_048_576.0
        print("🌐 OpenRouter streaming request: \(String(format: "%.1f", payloadMB))MB, \(images.count) image(s), model \(model)")

        let (byteStream, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "OpenRouterAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorBodyChunks: [String] = []
            for try await line in byteStream.lines {
                errorBodyChunks.append(line)
            }
            let errorBody = errorBodyChunks.joined(separator: "\n")
            throw NSError(
                domain: "OpenRouterAPI",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(errorBody)"]
            )
        }

        // Parse the OpenAI-style SSE stream — each event is "data: {json}".
        var accumulatedResponseText = ""

        for try await line in byteStream.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))

            // End of stream marker
            guard jsonString != "[DONE]" else { break }

            guard let jsonData = jsonString.data(using: .utf8),
                  let eventPayload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = eventPayload["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let delta = firstChoice["delta"] as? [String: Any],
                  let textChunk = delta["content"] as? String,
                  !textChunk.isEmpty else {
                continue
            }

            accumulatedResponseText += textChunk
            let currentAccumulatedText = accumulatedResponseText
            await onTextChunk(currentAccumulatedText)
        }

        let duration = Date().timeIntervalSince(startTime)
        return (text: accumulatedResponseText, duration: duration)
    }
}
