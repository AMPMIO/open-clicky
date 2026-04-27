//
//  LLMProvider.swift
//  leanring-buddy
//
//  Protocol abstraction for LLM backends (Anthropic, OpenRouter, OpenClaw).
//

import Foundation

/// Unified interface for LLM chat providers. Implementations handle
/// request formatting, auth, and response parsing for their respective APIs.
protocol LLMProvider {
    var displayName: String { get }

    /// Streaming chat with vision support. Calls `onTextChunk` on the main actor
    /// with the accumulated text so far each time a new chunk arrives.
    func chatStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        model: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval)

    /// Non-streaming chat with vision support.
    func chat(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        model: String
    ) async throws -> (text: String, duration: TimeInterval)
}
