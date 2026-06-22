//
//  ProviderManager.swift
//  leanring-buddy
//
//  Factory that instantiates the correct LLMProvider based on user configuration.
//

import Foundation

@MainActor
class ProviderManager: ObservableObject {
    @Published var configuration: ProviderConfiguration
    @Published private(set) var currentProvider: LLMProvider

    init() {
        let config = ProviderConfiguration()
        self.configuration = config
        self.currentProvider = Self.buildProvider(from: config)
    }

    func updateProvider() {
        currentProvider = Self.buildProvider(from: configuration)
    }

    /// True when the active provider is fully configured — i.e. the factory built
    /// a real provider rather than the `UnconfiguredProvider` stand-in. Derived
    /// from the same construction path used for requests, so readiness can't drift
    /// from what `buildProvider` actually produces (blank OpenClaw → localhost is
    /// ready; a malformed / remote-http endpoint is not).
    var isCurrentProviderReady: Bool {
        !(currentProvider is UnconfiguredProvider)
    }

    /// Capabilities of the active backend (vision / streaming / pointing), used to
    /// drive Settings hints and behavior.
    var currentProviderCapabilities: ProviderCapabilities {
        configuration.activeProvider.capabilities
    }

    func setActiveProvider(_ provider: APIProviderType) {
        configuration.activeProvider = provider
        updateProvider()
    }

    private static func buildProvider(from config: ProviderConfiguration) -> LLMProvider {
        switch config.activeProvider {
        case .workerProxy:
            guard config.workerBaseURL != ProviderConfiguration.defaultWorkerBaseURL,
                  let url = sanitizedURL(config.workerBaseURL, path: "/chat") else {
                return UnconfiguredProvider(
                    provider: "Worker Proxy",
                    reason: "Set your Worker URL in Settings."
                )
            }
            return AnthropicProvider(proxyURL: url.absoluteString)

        case .openRouter:
            let apiKey = config.openRouterAPIKey ?? ""
            guard !apiKey.isEmpty,
                  let url = sanitizedURL(ProviderConfiguration.defaultOpenRouterBaseURL, path: "/chat/completions") else {
                return UnconfiguredProvider(
                    provider: "OpenRouter",
                    reason: "Add your OpenRouter API key in Settings."
                )
            }
            return OpenAICompatibleProvider(
                displayName: "OpenRouter",
                baseURL: url,
                apiKey: apiKey,
                extraHeaders: [
                    "HTTP-Referer": "https://github.com/AMPMIO/open-clicky",
                    "X-Title": "Clicky"
                ]
            )

        case .openClaw:
            let token = config.openClawToken ?? ""
            let endpoint = config.openClawEndpoint.isEmpty
                ? "http://localhost:18789"
                : config.openClawEndpoint
            // OpenClaw exposes an OpenAI-compatible chat-completions endpoint.
            // The agent session endpoint (/api/sessions/.../messages) speaks a
            // different request/response shape the shared OpenAI parser cannot
            // read, so it must NOT be used here.
            guard let url = sanitizedURL(endpoint, path: "/v1/chat/completions") else {
                return UnconfiguredProvider(
                    provider: "OpenClaw",
                    reason: "The OpenClaw endpoint is not a valid URL."
                )
            }
            return OpenAICompatibleProvider(
                displayName: "OpenClaw",
                baseURL: url,
                apiKey: token
            )
        }
    }

    /// Builds a request URL from a user-supplied base + a known path. Trims a
    /// trailing slash on the base so we never produce `host//path`, and returns
    /// nil for malformed input instead of force-unwrapping `URL(string:)` (which
    /// crashes the app on bad Settings input).
    private static func sanitizedURL(_ base: String, path: String) -> URL? {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { return nil }
        let normalizedBase = trimmedBase.hasSuffix("/") ? String(trimmedBase.dropLast()) : trimmedBase
        guard let url = URL(string: normalizedBase + path),
              let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else { return nil }
        // Only http/https. Cleartext http is allowed only for loopback / .local
        // (matches the Info.plist ATS policy and the Settings validator), so a
        // remote VPS/subscription endpoint must use https or it is rejected.
        switch scheme {
        case "https":
            return url
        case "http":
            let lowerHost = host.lowercased()
            let isLoopback = lowerHost == "localhost" || lowerHost == "127.0.0.1"
                || lowerHost == "::1" || lowerHost.hasSuffix(".local")
            return isLoopback ? url : nil
        default:
            return nil
        }
    }
}

/// Stand-in provider used when the active backend is not yet configured (or its
/// endpoint is malformed). It throws a clear, user-facing error instead of the
/// app silently capturing screens and firing a guaranteed-to-fail request.
final class UnconfiguredProvider: LLMProvider {
    let displayName: String
    private let reason: String

    init(provider: String, reason: String) {
        self.displayName = provider
        self.reason = reason
    }

    func chatStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        model: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        throw ProviderError.notConfigured(provider: displayName, reason: reason)
    }
}
