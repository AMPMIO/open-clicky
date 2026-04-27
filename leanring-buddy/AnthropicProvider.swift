//
//  AnthropicProvider.swift
//  leanring-buddy
//
//  Wraps the existing ClaudeAPI to conform to LLMProvider protocol.
//  Used for Worker Proxy mode (existing Anthropic-through-worker flow).
//

import Foundation

class AnthropicProvider: LLMProvider {
    let displayName = "Anthropic (Worker)"
    private let claudeAPI: ClaudeAPI

    init(proxyURL: String, model: String = "claude-sonnet-4-6") {
        self.claudeAPI = ClaudeAPI(proxyURL: proxyURL, model: model)
    }

    func chatStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        model: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        claudeAPI.model = model
        return try await claudeAPI.analyzeImageStreaming(
            images: images,
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            userPrompt: userPrompt,
            onTextChunk: onTextChunk
        )
    }

    func chat(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        model: String
    ) async throws -> (text: String, duration: TimeInterval) {
        claudeAPI.model = model
        return try await claudeAPI.analyzeImage(
            images: images,
            systemPrompt: systemPrompt,
            conversationHistory: conversationHistory,
            userPrompt: userPrompt
        )
    }
}
