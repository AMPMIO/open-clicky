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

    private static let tlsWarmupLock = NSLock()
    private static var warmedHosts: Set<String> = []

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

        warmUpTLSConnectionIfNeeded()
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

        for try await line in byteStream.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            guard jsonString != "[DONE]" else { break }

            guard let jsonData = jsonString.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = payload["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let delta = firstChoice["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }

            accumulatedText += content
            let currentText = accumulatedText
            await onTextChunk(currentText)
        }

        let duration = Date().timeIntervalSince(startTime)
        return (text: accumulatedText, duration: duration)
    }

    func chat(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        model: String
    ) async throws -> (text: String, duration: TimeInterval) {
        let startTime = Date()
        let request = try buildRequest(
            images: images,
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            userPrompt: userPrompt,
            model: model,
            stream: false
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let responseString = String(data: data, encoding: .utf8) ?? "Unknown error"
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ProviderError.apiError(statusCode: statusCode, message: responseString)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ProviderError.invalidResponseFormat
        }

        let duration = Date().timeIntervalSince(startTime)
        return (text: content, duration: duration)
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

    private func warmUpTLSConnectionIfNeeded() {
        guard let host = baseURL.host else { return }

        Self.tlsWarmupLock.lock()
        let alreadyWarmed = Self.warmedHosts.contains(host)
        if !alreadyWarmed {
            Self.warmedHosts.insert(host)
        }
        Self.tlsWarmupLock.unlock()

        guard !alreadyWarmed else { return }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/"
        components.query = nil
        guard let warmupURL = components.url else { return }

        var warmupRequest = URLRequest(url: warmupURL)
        warmupRequest.httpMethod = "HEAD"
        warmupRequest.timeoutInterval = 10
        session.dataTask(with: warmupRequest) { _, _, _ in }.resume()
    }
}

// MARK: - Errors

enum ProviderError: LocalizedError {
    case invalidResponse
    case invalidResponseFormat
    case apiError(statusCode: Int, message: String)
    case missingAPIKey(provider: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid HTTP response"
        case .invalidResponseFormat:
            return "Could not parse response format"
        case .apiError(let code, let message):
            return "API Error (\(code)): \(message)"
        case .missingAPIKey(let provider):
            return "No API key configured for \(provider)"
        }
    }
}
