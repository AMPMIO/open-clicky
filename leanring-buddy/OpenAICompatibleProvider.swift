//
//  OpenAICompatibleProvider.swift
//  leanring-buddy
//
//  Unified streaming client for OpenAI-compatible APIs (OpenRouter, OpenClaw).
//

import Foundation

class OpenAICompatibleProvider: LLMProvider {
    let displayName: String
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession
    private let extraHeaders: [String: String]

    init(displayName: String, baseURL: URL, apiKey: String, extraHeaders: [String: String] = [:]) {
        self.displayName = displayName
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.extraHeaders = extraHeaders

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.urlCache = nil
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)

        TLSWarmer.warm(baseURL, using: session)
    }

    // MARK: - LLMProvider

    func chatStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        model: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        let startTime = Date()
        let request = try buildRequest(
            images: images,
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            userPrompt: userPrompt,
            model: model,
            stream: true
        )

        let (byteStream, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorBodyChunks: [String] = []
            for try await line in byteStream.lines {
                errorBodyChunks.append(line)
            }
            let errorBody = errorBodyChunks.joined(separator: "\n")
            throw ProviderError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        var accumulatedText = ""
        var sawAnyContentChunk = false

        for try await line in byteStream.lines {
            // Accept both "data: {...}" and "data:{...}"; skip SSE comments (":..."),
            // keep-alives, and blank lines.
            guard line.hasPrefix("data:") else { continue }
            let payloadString = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard payloadString != "[DONE]" else { break }
            guard !payloadString.isEmpty else { continue }

            guard let jsonData = payloadString.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            // Surface a streamed error event instead of silently skipping it (some
            // backends return HTTP 200 then an {"error": ...} SSE frame).
            if let errorObject = payload["error"] as? [String: Any] {
                let message = (errorObject["message"] as? String) ?? "streaming error"
                throw ProviderError.apiError(statusCode: httpResponse.statusCode, message: message)
            }

            guard let choices = payload["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let delta = firstChoice["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }

            sawAnyContentChunk = true
            accumulatedText += content
            let currentText = accumulatedText
            await onTextChunk(currentText)
        }

        // Require at least one parsed content chunk. A stream of only role/finish
        // frames or a bare [DONE] — e.g. a non-OpenAI endpoint or a backend that
        // ignored `stream` and returned a plain JSON body — is a format mismatch,
        // not an empty success that silently skips TTS/pointing.
        guard sawAnyContentChunk else {
            throw ProviderError.invalidResponseFormat
        }

        let duration = Date().timeIntervalSince(startTime)
        return (text: accumulatedText, duration: duration)
    }

    // MARK: - Request Building

    private func buildRequest(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        model: String,
        stream: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        for (header, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }

        var messages: [[String: Any]] = []

        // System message
        messages.append(["role": "system", "content": systemPrompt])

        // Conversation history
        for (userText, assistantText) in conversationHistory {
            messages.append(["role": "user", "content": userText])
            messages.append(["role": "assistant", "content": assistantText])
        }

        // Current user message with images
        var contentParts: [[String: Any]] = []
        for image in images {
            let mediaType = detectImageMediaType(for: image.data)
            let base64 = image.data.base64EncodedString()
            let dataURI = "data:\(mediaType);base64,\(base64)"

            contentParts.append([
                "type": "image_url",
                "image_url": ["url": dataURI]
            ])
            contentParts.append([
                "type": "text",
                "text": image.label
            ])
        }
        contentParts.append([
            "type": "text",
            "text": userPrompt
        ])

        messages.append(["role": "user", "content": contentParts])

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": 1024,
            "stream": stream,
        ]

        // OpenRouter supports temperature; set reasonable default
        body["temperature"] = 0.7

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData

        let payloadMB = Double(bodyData.count) / 1_048_576.0
        print("[\(displayName)] request: \(String(format: "%.1f", payloadMB))MB, \(images.count) image(s), model: \(model)")

        return request
    }

    // MARK: - Helpers

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
}

// MARK: - Errors

enum ProviderError: LocalizedError {
    case invalidResponse
    case invalidResponseFormat
    case apiError(statusCode: Int, message: String)
    case notConfigured(provider: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid HTTP response"
        case .invalidResponseFormat:
            return "Could not parse response format"
        case .apiError(let code, let message):
            return "API Error (\(code)): \(message)"
        case .notConfigured(let provider, let reason):
            return "\(provider) isn't set up yet. \(reason)"
        }
    }
}
