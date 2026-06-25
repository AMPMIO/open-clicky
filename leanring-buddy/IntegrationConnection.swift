//
//  IntegrationConnection.swift
//  leanring-buddy
//
//  State for a single connector. Two layers, intentionally separate:
//
//  • IntegrationConnection — the PERSISTED, non-sensitive record (stored as JSON in
//    UserDefaults by IntegrationsManager). It records only that a connection exists and
//    who it belongs to. The access token is NEVER stored here; it lives only in the
//    Keychain (see IntegrationConnectorKind.keychainTokenService).
//
//  • IntegrationConnectionState — the LIVE, in-memory state the Settings UI binds to,
//    including the transient OAuth Device Flow handshake states that are never persisted.
//
//  Keeping them apart means a restart restores "connected as @user" instantly (read one
//  small JSON blob, no Keychain hit per render) while the multi-step connect handshake
//  stays purely runtime.
//

import Foundation

/// The persisted record of an established connection. Present in storage only while the
/// connector is connected — disconnecting deletes both this record and the Keychain token.
struct IntegrationConnection: Codable, Equatable {
    let kind: IntegrationConnectorKind

    /// The account label to display, e.g. a GitHub login like "octocat". Optional because
    /// the token can be stored a moment before the identity-confirmation call (GET /user)
    /// resolves the label.
    var accountLabel: String?

    /// When the connection was established. Kept for display and future token-age checks.
    var connectedAt: Date
}

/// The live state of one connector, including the transient steps of the OAuth Device
/// Flow handshake. This is what the Settings cards render from; it is not persisted.
enum IntegrationConnectionState: Equatable {
    /// No token stored — the connector shows a "Connect" affordance.
    case disconnected

    /// Device Flow has issued a user code; the user must enter it at the verification URL.
    /// The UI surfaces the code and an "Open" button while we poll in the background.
    case awaitingUserAuthorization(userCode: String, verificationURL: URL)

    /// The user authorized (or we're confirming identity); a brief spinner state between
    /// authorization and a resolved account label.
    case connecting

    /// A token is stored. `accountLabel` is the confirmed identity (e.g. GitHub login),
    /// or nil if the identity call hasn't resolved yet.
    case connected(accountLabel: String?)

    /// The connect attempt failed (timeout, denied, network, or misconfiguration). Carries
    /// a user-facing message; the UI offers a retry.
    case failed(message: String)
}
