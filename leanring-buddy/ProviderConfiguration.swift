//
//  ProviderConfiguration.swift
//  leanring-buddy
//
//  Configuration model for LLM provider selection and credentials.
//

import Foundation

enum APIProviderType: String, CaseIterable, Codable {
    case workerProxy
    case openRouter
    case openClaw

    var displayName: String {
        switch self {
        case .workerProxy: return "Worker Proxy"
        case .openRouter: return "OpenRouter"
        case .openClaw: return "OpenClaw"
        }
    }

    /// The model id to use for this provider before the user picks one.
    /// Each provider has its own namespace (Anthropic short ids via the Worker,
    /// OpenRouter slugs for OpenRouter/OpenClaw), so they must not be shared.
    var defaultModelID: String {
        switch self {
        case .workerProxy: return "claude-sonnet-4-6"
        case .openRouter: return "anthropic/claude-sonnet-4-6"
        case .openClaw: return "anthropic/claude-sonnet-4-6"
        }
    }
}

struct ProviderConfiguration {
    // MARK: - Keychain Service IDs

    private static let openRouterKeyService = "com.clicky.openrouter-key"
    private static let openClawTokenService = "com.clicky.openclaw-token"

    // MARK: - UserDefaults Keys

    private static let providerKey = "activeAPIProvider"
    private static let openClawEndpointKey = "openClawEndpoint"
    private static let workerBaseURLKey = "workerBaseURL"
    /// Selected model is stored PER provider so switching backends never sends an
    /// incompatible model id (e.g. an OpenRouter slug to the Anthropic route).
    private static let selectedModelKeyPrefix = "selectedModelID."

    // MARK: - Defaults

    static let defaultWorkerBaseURL = "https://your-worker-name.your-subdomain.workers.dev"
    static let defaultOpenRouterBaseURL = "https://openrouter.ai/api/v1"

    /// Single source of truth for the configured Worker base URL, readable
    /// without a ProviderConfiguration instance. TTS and transcription read this
    /// so the Settings "Worker URL" field reaches every Worker route, not just chat.
    static var workerBaseURLFromDefaults: String {
        UserDefaults.standard.string(forKey: workerBaseURLKey) ?? defaultWorkerBaseURL
    }

    // MARK: - Properties

    var activeProvider: APIProviderType {
        didSet { UserDefaults.standard.set(activeProvider.rawValue, forKey: Self.providerKey) }
    }

    /// The model id for the CURRENTLY ACTIVE provider. Reads/writes a
    /// per-provider UserDefaults entry so each backend remembers its own model
    /// and provider switches never carry a model id across the boundary.
    var selectedModelID: String {
        get { Self.storedModelID(for: activeProvider) }
        set { Self.storeModelID(newValue, for: activeProvider) }
    }

    var workerBaseURL: String {
        didSet { UserDefaults.standard.set(workerBaseURL, forKey: Self.workerBaseURLKey) }
    }

    var openClawEndpoint: String {
        didSet { UserDefaults.standard.set(openClawEndpoint, forKey: Self.openClawEndpointKey) }
    }

    // MARK: - Init (loads from UserDefaults)

    init() {
        let defaults = UserDefaults.standard
        // Default to the Worker proxy (the documented "keys live on the server"
        // path) rather than a keyless direct OpenRouter call on a fresh install.
        let providerRaw = defaults.string(forKey: Self.providerKey) ?? APIProviderType.workerProxy.rawValue
        self.activeProvider = APIProviderType(rawValue: providerRaw) ?? .workerProxy
        self.workerBaseURL = defaults.string(forKey: Self.workerBaseURLKey) ?? Self.defaultWorkerBaseURL
        self.openClawEndpoint = defaults.string(forKey: Self.openClawEndpointKey) ?? ""
    }

    // MARK: - Per-provider model storage

    private static func storedModelID(for provider: APIProviderType) -> String {
        UserDefaults.standard.string(forKey: selectedModelKeyPrefix + provider.rawValue)
            ?? provider.defaultModelID
    }

    private static func storeModelID(_ modelID: String, for provider: APIProviderType) {
        UserDefaults.standard.set(modelID, forKey: selectedModelKeyPrefix + provider.rawValue)
    }

    // MARK: - Configuration state

    /// Whether the active provider has everything it needs to make a request.
    /// Used to avoid capturing the user's screens and then firing a
    /// guaranteed-to-fail call (e.g. OpenRouter with no key, Worker with the
    /// placeholder URL still in place).
    var isActiveProviderConfigured: Bool {
        switch activeProvider {
        case .workerProxy:
            return !workerBaseURL.isEmpty && workerBaseURL != Self.defaultWorkerBaseURL
        case .openRouter:
            return !(openRouterAPIKey ?? "").isEmpty
        case .openClaw:
            return !openClawEndpoint.isEmpty
        }
    }

    // MARK: - Keychain Accessors

    var openRouterAPIKey: String? {
        get { KeychainManager.retrieve(service: Self.openRouterKeyService) }
        set {
            if let key = newValue, !key.isEmpty {
                _ = KeychainManager.save(key: key, service: Self.openRouterKeyService)
            } else {
                KeychainManager.delete(service: Self.openRouterKeyService)
            }
        }
    }

    var openClawToken: String? {
        get { KeychainManager.retrieve(service: Self.openClawTokenService) }
        set {
            if let token = newValue, !token.isEmpty {
                _ = KeychainManager.save(key: token, service: Self.openClawTokenService)
            } else {
                KeychainManager.delete(service: Self.openClawTokenService)
            }
        }
    }
}
