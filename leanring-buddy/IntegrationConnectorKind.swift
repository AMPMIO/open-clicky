//
//  IntegrationConnectorKind.swift
//  leanring-buddy
//
//  The catalog of external services Clicky can connect to (GitHub, Notion, Linear,
//  Google). This is purely the SET of connectors shown in Settings and their display
//  metadata — it says nothing about whether a given connector is currently connected
//  (that lives in IntegrationConnection / IntegrationsManager). Analogous to how
//  TTSProviderKind / STTProviderKind enumerate the selectable backends.
//
//  Raw values are persisted (they form UserDefaults keys and Keychain service names),
//  so renaming a case requires a migration.
//

import Foundation

enum IntegrationConnectorKind: String, CaseIterable, Identifiable, Codable {
    case github
    case notion
    case linear
    case google

    var id: String { rawValue }

    /// Human-facing name shown on the connector card in Settings.
    var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .notion: return "Notion"
        case .linear: return "Linear"
        case .google: return "Google"
        }
    }

    /// SF Symbol shown on the connector card. None of these brands ship an official SF
    /// Symbol, so we use a recognizable generic glyph per service rather than bundling
    /// brand artwork.
    var symbolName: String {
        switch self {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .notion: return "doc.text"
        case .linear: return "line.3.horizontal"
        case .google: return "magnifyingglass"
        }
    }

    /// Whether this connector is actually wired up in the current build. Only GitHub
    /// (via OAuth Device Flow) ships in this first slice; the rest render as a
    /// non-interactive "Coming soon" card so the catalog communicates the full roadmap
    /// without pretending the connector works yet.
    var isAvailable: Bool {
        switch self {
        case .github: return true
        case .notion, .linear, .google: return false
        }
    }

    /// Why a not-yet-available connector is deferred — shown so the roadmap is honest
    /// about what each one needs. (Notion/Linear require a client secret, so they wait
    /// on the Worker OAuth broker; Google needs a verified GCP OAuth client.)
    var comingSoonReason: String? {
        switch self {
        case .github: return nil
        case .notion, .linear: return "Needs the Worker OAuth broker"
        case .google: return "Needs a verified Google OAuth client"
        }
    }

    /// The Keychain SERVICE under which this connector's access token is stored. Tokens
    /// live ONLY in the Keychain — never in UserDefaults or logs — and are isolated per
    /// connector so one connector can never read another's token.
    var keychainTokenService: String {
        "com.clicky.integration-token.\(rawValue)"
    }
}
