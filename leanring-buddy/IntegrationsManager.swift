//
//  IntegrationsManager.swift
//  leanring-buddy
//
//  Owns the live connection state for every external-service connector and orchestrates
//  the GitHub OAuth Device Flow handshake. Analogous to ProviderManager (LLM) and
//  TTSProviderManager (voice): a single @MainActor ObservableObject the Settings UI binds
//  to, with the actual network steps delegated to a stateless client.
//
//  Security boundary: access tokens live ONLY in the Keychain (per-connector service,
//  see IntegrationConnectorKind.keychainTokenService). This manager persists only the
//  non-sensitive IntegrationConnection record (kind / accountLabel / connectedAt) as JSON
//  in UserDefaults, and never logs a token or username.
//
//  Scope of this slice (OC-118 / G6.1): GitHub via Device Flow only. No CompanionManager
//  wiring and no Worker — connecting stores a token and confirms identity; using that
//  token for context/MCP is deferred (Tier 1/2).
//

import Combine
import Foundation
import os

@MainActor
final class IntegrationsManager: ObservableObject {
    static let shared = IntegrationsManager()

    // MARK: - Storage keys

    /// Single UserDefaults key holding the JSON array of persisted (token-free) connections.
    private static let connectionsDefaultsKey = "integrationConnections"

    /// Info.plist key holding the GitHub OAuth App client id. Device Flow uses NO client
    /// secret, so this id is non-sensitive and safe to ship; it's read from the bundle
    /// (not hardcoded) so it can be set per build without editing source.
    private static let gitHubClientIDInfoPlistKey = "GitHubOAuthClientID"

    /// Smallest scope that still lets us read the user's login for "Connected as @user".
    private static let gitHubScope = "read:user"

    // MARK: - Published state

    /// Live state per connector — what the Settings cards render from. A connector absent
    /// from this map is treated as `.disconnected`.
    @Published private(set) var connectionStates: [IntegrationConnectorKind: IntegrationConnectionState] = [:]

    // MARK: - Dependencies

    private let gitHubClient = GitHubDeviceFlowClient()

    /// In-flight Device Flow tasks keyed by connector, so a connect can be cancelled
    /// (disconnect / re-tap) without leaking a background poll loop.
    private var activeConnectTasks: [IntegrationConnectorKind: Task<Void, Never>] = [:]

    private init() {
        restorePersistedConnections()
    }

    // MARK: - Public API

    func connectionState(for kind: IntegrationConnectorKind) -> IntegrationConnectionState {
        connectionStates[kind] ?? .disconnected
    }

    /// Whether a stored token exists for `kind` (drives connected vs. connect rendering).
    func isConnected(_ kind: IntegrationConnectorKind) -> Bool {
        if case .connected = connectionState(for: kind) { return true }
        return false
    }

    /// Begins connecting `kind`. Only GitHub is implemented in this slice; other kinds are
    /// no-ops (their cards render as "Coming soon" and never call this).
    func connect(_ kind: IntegrationConnectorKind) {
        guard kind == .github else { return }
        // Replace any in-flight attempt for this connector so re-tapping restarts cleanly.
        activeConnectTasks[kind]?.cancel()
        let connectTask = Task { [weak self] in
            await self?.runGitHubDeviceFlow()
        }
        activeConnectTasks[kind] = connectTask
    }

    /// Cancels an in-progress handshake for `kind` and returns it to disconnected. This is
    /// "cancel the connect", not "sign out" — it never deletes an already-stored token, so
    /// it won't clobber a connector that was already connected.
    func cancelConnect(_ kind: IntegrationConnectorKind) {
        activeConnectTasks[kind]?.cancel()
        activeConnectTasks[kind] = nil
        if case .connected = connectionState(for: kind) {
            return
        }
        connectionStates[kind] = .disconnected
    }

    /// Disconnects `kind`: cancels any handshake, deletes the Keychain token, and removes
    /// the persisted record. After this the token is gone from the device.
    func disconnect(_ kind: IntegrationConnectorKind) {
        activeConnectTasks[kind]?.cancel()
        activeConnectTasks[kind] = nil
        KeychainManager.delete(service: kind.keychainTokenService)
        removePersistedConnection(kind)
        connectionStates[kind] = .disconnected
        ClickyTelemetry.oauth.notice("Integration disconnected: \(kind.rawValue, privacy: .public)")
    }

    // MARK: - GitHub Device Flow orchestration

    private func runGitHubDeviceFlow() async {
        let kind = IntegrationConnectorKind.github

        guard let clientID = Self.gitHubClientID(), !clientID.isEmpty else {
            connectionStates[kind] = .failed(
                message: "Add \(Self.gitHubClientIDInfoPlistKey) to the app's Info.plist to enable GitHub."
            )
            return
        }

        connectionStates[kind] = .connecting
        do {
            let grant = try await gitHubClient.requestDeviceCode(clientID: clientID, scope: Self.gitHubScope)
            try Task.checkCancellation()

            connectionStates[kind] = .awaitingUserAuthorization(
                userCode: grant.userCode,
                verificationURL: grant.verificationURL
            )
            ClickyTelemetry.oauth.notice("GitHub device code issued; awaiting user authorization.")

            let accessToken = try await pollGitHubUntilAuthorized(clientID: clientID, grant: grant)
            try Task.checkCancellation()

            // Save the token to the Keychain BEFORE confirming identity, so a transient
            // failure of GET /user still leaves a usable, persisted connection rather than
            // dropping a token the user just authorized.
            connectionStates[kind] = .connecting
            guard KeychainManager.save(key: accessToken, service: kind.keychainTokenService) else {
                connectionStates[kind] = .failed(message: "Couldn't save the GitHub token to the Keychain.")
                return
            }

            // Identity confirmation is best-effort: a connection without a resolved login is
            // still valid, just shown without the "@user" label.
            let login = try? await gitHubClient.fetchAuthenticatedUserLogin(accessToken: accessToken)
            persistConnection(IntegrationConnection(kind: kind, accountLabel: login, connectedAt: Date()))
            connectionStates[kind] = .connected(accountLabel: login)
            ClickyTelemetry.oauth.notice("GitHub connected.")
        } catch is CancellationError {
            // cancelConnect already reset the state; nothing to do.
            return
        } catch {
            connectionStates[kind] = .failed(message: error.localizedDescription)
            ClickyTelemetry.oauth.error("GitHub connect failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Polls GitHub's token endpoint until the user authorizes, the code expires, or the
    /// attempt is cancelled. Honors GitHub's interval and `slow_down` back-off, and bounds
    /// total time by the grant's `expiresInSeconds` so it can never loop forever.
    private func pollGitHubUntilAuthorized(
        clientID: String,
        grant: GitHubDeviceFlowClient.DeviceCodeGrant
    ) async throws -> String {
        var pollIntervalSeconds = max(grant.pollIntervalSeconds, 1)
        var remainingSeconds = grant.expiresInSeconds

        while remainingSeconds > 0 {
            try await Task.sleep(for: .seconds(pollIntervalSeconds))
            try Task.checkCancellation()
            remainingSeconds -= pollIntervalSeconds

            let pollResult = try await gitHubClient.pollForAccessToken(clientID: clientID, deviceCode: grant.deviceCode)
            switch pollResult {
            case .authorized(let accessToken):
                return accessToken
            case .authorizationPending:
                continue
            case .slowDown(let newIntervalSeconds):
                // Back off as instructed; never go below our current interval.
                pollIntervalSeconds = max(newIntervalSeconds, pollIntervalSeconds + 1)
            case .accessDenied:
                throw NSError(
                    domain: "IntegrationsManager",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "You denied the GitHub authorization."]
                )
            case .codeExpired:
                throw NSError(
                    domain: "IntegrationsManager",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "The GitHub code expired before you authorized. Try again."]
                )
            }
        }

        throw NSError(
            domain: "IntegrationsManager",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for GitHub authorization. Try again."]
        )
    }

    private static func gitHubClientID() -> String? {
        AppBundleConfiguration.stringValue(forKey: gitHubClientIDInfoPlistKey)
    }

    // MARK: - Persistence (non-sensitive records only)

    private func restorePersistedConnections() {
        for connection in loadPersistedConnections() {
            connectionStates[connection.kind] = .connected(accountLabel: connection.accountLabel)
        }
    }

    private func loadPersistedConnections() -> [IntegrationConnection] {
        guard let data = UserDefaults.standard.data(forKey: Self.connectionsDefaultsKey),
              let decoded = try? JSONDecoder().decode([IntegrationConnection].self, from: data) else {
            return []
        }
        return decoded
    }

    private func savePersistedConnections(_ connections: [IntegrationConnection]) {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        UserDefaults.standard.set(data, forKey: Self.connectionsDefaultsKey)
    }

    /// Upserts a connection record (one per kind).
    private func persistConnection(_ connection: IntegrationConnection) {
        var connections = loadPersistedConnections().filter { $0.kind != connection.kind }
        connections.append(connection)
        savePersistedConnections(connections)
    }

    private func removePersistedConnection(_ kind: IntegrationConnectorKind) {
        let connections = loadPersistedConnections().filter { $0.kind != kind }
        savePersistedConnections(connections)
    }
}
