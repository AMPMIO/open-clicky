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
}

struct ProviderConfiguration {
    // MARK: - Keychain Service IDs

    private static let openRouterKeyService = "com.clicky.openrouter-key"
    private static let openClawTokenService = "com.clicky.openclaw-token"

    // MARK: - UserDefaults Keys

    private static let providerKey = "activeAPIProvider"
    private static let openClawEndpointKey = "openClawEndpoint"
    private static let workerBaseURLKey = "workerBaseURL"
    private static let selectedModelKey = "selectedModelID"

    // MARK: - Defaults

    static let defaultWorkerBaseURL = "https://your-worker-name.your-subdomain.workers.dev"
    static let defaultOpenRouterBaseURL = "https://openrouter.ai/api/v1"
    static let defaultModel = "anthropic/claude-sonnet-4-6"

    // MARK: - Properties

    var activeProvider: APIProviderType {
        didSet { UserDefaults.standard.set(activeProvider.rawValue, forKey: Self.providerKey) }
    }

    var selectedModelID: String {
        didSet { UserDefaults.standard.set(selectedModelID, forKey: Self.selectedModelKey) }
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
        let providerRaw = defaults.string(forKey: Self.providerKey) ?? APIProviderType.openRouter.rawValue
        self.activeProvider = APIProviderType(rawValue: providerRaw) ?? .openRouter
        self.selectedModelID = defaults.string(forKey: Self.selectedModelKey) ?? Self.defaultModel
        self.workerBaseURL = defaults.string(forKey: Self.workerBaseURLKey) ?? Self.defaultWorkerBaseURL
        self.openClawEndpoint = defaults.string(forKey: Self.openClawEndpointKey) ?? ""
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
