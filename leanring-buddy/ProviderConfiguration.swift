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
    case hermes

    var displayName: String {
        switch self {
        case .workerProxy: return "Worker Proxy"
        case .openRouter: return "OpenRouter"
        case .openClaw: return "OpenClaw"
        case .hermes: return "Hermes"
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
        case .hermes: return "hermes-agent"
        }
    }

    /// Capability descriptor used to drive UI affordances and pipeline behavior.
    /// Agent backends (OpenClaw/Hermes) can't guarantee POINT-tag support because
    /// it depends on the underlying model the user configured behind them.
    var capabilities: ProviderCapabilities {
        switch self {
        case .workerProxy:
            return ProviderCapabilities(supportsVision: true, supportsStreaming: true, reliablyEmitsPointTags: true)
        case .openRouter:
            return ProviderCapabilities(supportsVision: true, supportsStreaming: true, reliablyEmitsPointTags: true)
        case .openClaw:
            return ProviderCapabilities(supportsVision: true, supportsStreaming: true, reliablyEmitsPointTags: false)
        case .hermes:
            // Hermes is model-agnostic — vision + pointing depend on the model the
            // user configured behind it, so don't promise reliable pointing.
            return ProviderCapabilities(supportsVision: true, supportsStreaming: true, reliablyEmitsPointTags: false)
        }
    }
}

struct ProviderConfiguration {
    // MARK: - Keychain Service IDs

    private static let openRouterKeyService = "com.clicky.openrouter-key"
    private static let openClawTokenService = "com.clicky.openclaw-token"
    private static let hermesTokenService = "com.clicky.hermes-token"

    // MARK: - UserDefaults Keys

    private static let providerKey = "activeAPIProvider"
    private static let openClawEndpointKey = "openClawEndpoint"
    private static let hermesEndpointKey = "hermesEndpoint"
    private static let hermesActionModeKey = "hermesActionModeEnabled"
    private static let workerBaseURLKey = "workerBaseURL"
    private static let oauthConfigKey = "oauthConfig"
    /// Selected model is stored PER provider so switching backends never sends an
    /// incompatible model id (e.g. an OpenRouter slug to the Anthropic route).
    private static let selectedModelKeyPrefix = "selectedModelID."

    // MARK: - Defaults

    static let defaultWorkerBaseURL = "https://your-worker-name.your-subdomain.workers.dev"
    static let defaultOpenRouterBaseURL = "https://openrouter.ai/api/v1"
    /// Default Nous Hermes Agent API server bind address.
    static let defaultHermesEndpoint = "http://localhost:8642"

    /// Single source of truth for the configured Worker base URL, readable
    /// without a ProviderConfiguration instance. TTS and transcription read this
    /// so the Settings "Worker URL" field reaches every Worker route, not just chat.
    static var workerBaseURLFromDefaults: String {
        UserDefaults.standard.string(forKey: workerBaseURLKey) ?? defaultWorkerBaseURL
    }

    /// Single endpoint-URL policy used everywhere (chat, TTS, transcription, and
    /// the agent providers): trims a trailing slash, allows only http/https, and
    /// permits cleartext http ONLY for true loopback. Returns nil for malformed
    /// or non-loopback-cleartext URLs so callers fail closed.
    static func validatedURL(base: String, path: String) -> URL? {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard let url = URL(string: normalized + path),
              let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else { return nil }
        switch scheme {
        case "https":
            return url
        case "http":
            let lowerHost = host.lowercased()
            return (lowerHost == "localhost" || lowerHost == "127.0.0.1" || lowerHost == "::1") ? url : nil
        default:
            return nil
        }
    }

    /// Validated URL for a Worker route (e.g. "/chat", "/tts", "/transcribe-token"),
    /// or nil if the configured Worker URL is malformed, non-loopback cleartext, or
    /// still the unconfigured placeholder. Treating the placeholder as "no Worker"
    /// makes TTS/transcription fail closed instead of posting to an unintended host.
    static func workerRouteURL(_ path: String) -> URL? {
        let base = workerBaseURLFromDefaults
        guard base != defaultWorkerBaseURL else { return nil }
        return validatedURL(base: base, path: path)
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

    var hermesEndpoint: String {
        didSet { UserDefaults.standard.set(hermesEndpoint, forKey: Self.hermesEndpointKey) }
    }

    /// User-supplied OAuth app config for "Sign in with ChatGPT"-style auth.
    /// Non-secret (client id + endpoints); the resulting tokens live in the
    /// Keychain via OAuthSignInManager.
    var oauthConfig: OAuthConfig {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.oauthConfigKey),
                  let config = try? JSONDecoder().decode(OAuthConfig.self, from: data) else {
                return OAuthConfig()
            }
            return config
        }
        set {
            guard let encoded = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(encoded, forKey: Self.oauthConfigKey)
        }
    }

    /// When true, Hermes is allowed to perform on-screen actions (computer-use)
    /// rather than only answering + pointing. The actuation layer itself ships
    /// with Hands-On Mode (F1); this flag is the user's opt-in.
    var hermesActionModeEnabled: Bool {
        didSet { UserDefaults.standard.set(hermesActionModeEnabled, forKey: Self.hermesActionModeKey) }
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
        self.hermesEndpoint = defaults.string(forKey: Self.hermesEndpointKey) ?? ""
        self.hermesActionModeEnabled = defaults.bool(forKey: Self.hermesActionModeKey)
    }

    // MARK: - Per-provider model storage

    private static func storedModelID(for provider: APIProviderType) -> String {
        UserDefaults.standard.string(forKey: selectedModelKeyPrefix + provider.rawValue)
            ?? provider.defaultModelID
    }

    private static func storeModelID(_ modelID: String, for provider: APIProviderType) {
        UserDefaults.standard.set(modelID, forKey: selectedModelKeyPrefix + provider.rawValue)
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

    var hermesToken: String? {
        get { KeychainManager.retrieve(service: Self.hermesTokenService) }
        set {
            if let token = newValue, !token.isEmpty {
                _ = KeychainManager.save(key: token, service: Self.hermesTokenService)
            } else {
                KeychainManager.delete(service: Self.hermesTokenService)
            }
        }
    }
}
