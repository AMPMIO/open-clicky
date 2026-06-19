//
//  CompanionChatProvider.swift
//  leanring-buddy
//
//  Provider-agnostic surface for the vision chat backend that powers Clicky's
//  spoken responses. Both the Cloudflare-Worker-proxied Claude client and the
//  bring-your-own-key OpenRouter client conform to this so CompanionManager can
//  swap the underlying LLM without changing the response pipeline.
//

import Foundation

/// Identifies which LLM backend drives the companion's responses.
enum CompanionLLMProvider: String {
    /// The default Cloudflare-Worker-proxied Claude backend that ships with the app.
    case clickyCloud = "claude"
    /// A user-supplied OpenRouter account, called directly with the user's own API key.
    case openRouter = "openrouter"
}

/// A streaming vision chat backend. Implementations send one or more labeled
/// screenshots plus the conversation so far and stream back the assistant's text.
protocol CompanionChatProvider: AnyObject {
    /// The model identifier this provider will use for the next request.
    var model: String { get set }

    /// Sends a vision request with streaming. Calls `onTextChunk` on the main
    /// actor each time more text is available so the UI can render progressively.
    /// Returns the full accumulated text and total request duration.
    func analyzeImageStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval)
}
