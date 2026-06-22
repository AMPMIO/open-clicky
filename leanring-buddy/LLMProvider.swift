//
//  LLMProvider.swift
//  leanring-buddy
//
//  Protocol abstraction for LLM backends (Anthropic, OpenRouter, OpenClaw).
//

import Foundation

/// Static capability descriptor for an LLM backend. Drives UI affordances and
/// pipeline behavior (e.g. warn when the active backend may not support vision
/// or reliably honor the pointing protocol).
struct ProviderCapabilities {
    /// Whether the backend accepts screenshots as image input.
    let supportsVision: Bool
    /// Whether the backend streams tokens (SSE) vs. only returning a full reply.
    let supportsStreaming: Bool
    /// Whether models on this backend reliably honor the `[POINT:...]` protocol.
    /// True for the curated Anthropic/OpenRouter defaults; for open-ended agent
    /// backends (OpenClaw/Hermes) it depends on the underlying model the user
    /// configured, so the UI should warn that pointing may not work.
    let reliablyEmitsPointTags: Bool
}

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
}
