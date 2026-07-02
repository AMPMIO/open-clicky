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

    func setActiveProvider(_ provider: APIProviderType) {
        configuration.activeProvider = provider
        updateProvider()
    }

    func setSelectedModel(_ modelID: String) {
        configuration.selectedModelID = modelID
    }

    private static func buildProvider(from config: ProviderConfiguration) -> LLMProvider {
        switch config.activeProvider {
        case .workerProxy:
            return AnthropicProvider(
                proxyURL: "\(config.workerBaseURL)/chat"
            )

        case .openRouter:
            let apiKey = config.openRouterAPIKey ?? ""
            let url = URL(string: "\(ProviderConfiguration.defaultOpenRouterBaseURL)/chat/completions")!
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
            let url = URL(string: "\(endpoint)/api/sessions/main/messages")!
            return OpenAICompatibleProvider(
                displayName: "OpenClaw",
                baseURL: url,
                apiKey: token
            )
        }
    }
}
