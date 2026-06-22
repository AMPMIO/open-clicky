//
//  OAuthSignInManager.swift
//  leanring-buddy
//
//  Configurable OAuth 2.0 Authorization-Code-with-PKCE sign-in for the
//  OpenAI-compatible provider ("Sign in with ChatGPT"-style).
//
//  Honest scope (OC-60 spike): riding a ChatGPT *subscription* from a third-party
//  app means reusing a first-party client's credentials, which OpenAI does not
//  sanction for third-party use. So this ships as a GENERIC flow — the user
//  supplies their OWN OAuth app (client id + endpoints); no credentials are
//  hardcoded, nothing is impersonated. The resulting access token is used as the
//  Bearer for the OpenAI-compatible provider, and the app falls back to a pasted
//  API key when the user isn't signed in. Yields OpenAI-compatible models, not
//  Anthropic Opus (Anthropic blocks subscription-based third-party access).
//

import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

/// User-supplied OAuth app configuration (non-secret; stored in UserDefaults).
struct OAuthConfig: Codable, Equatable {
    var clientID: String = ""
    var authorizeURL: String = ""
    var tokenURL: String = ""
    var redirectURI: String = "openclicky://oauth-callback"
    var scopes: String = ""

    var isComplete: Bool {
        !clientID.isEmpty && !authorizeURL.isEmpty && !tokenURL.isEmpty && !redirectURI.isEmpty
    }
}

private struct StoredOAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
}

enum OAuthSignInError: LocalizedError {
    case notConfigured
    case cancelled
    case noAuthCode
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "OAuth isn't configured (client id + authorize/token URLs)."
        case .cancelled: return "Sign-in was cancelled."
        case .noAuthCode: return "No authorization code was returned."
        case .tokenExchangeFailed(let detail): return "Token exchange failed (\(detail))."
        }
    }
}

@MainActor
final class OAuthSignInManager: NSObject, ObservableObject {
    static let shared = OAuthSignInManager()
    private static let tokenService = "com.clicky.oauth-tokens"

    @Published private(set) var isSignedIn: Bool

    private var webAuthSession: ASWebAuthenticationSession?

    private override init() {
        isSignedIn = KeychainManager.retrieve(service: Self.tokenService) != nil
        super.init()
    }

    /// Runs the PKCE authorization-code flow and stores the resulting tokens.
    func signIn(config: OAuthConfig) async throws {
        guard config.isComplete, let authorizeBase = URL(string: config.authorizeURL) else {
            throw OAuthSignInError.notConfigured
        }
        let codeVerifier = Self.randomCodeVerifier()
        let codeChallenge = Self.codeChallenge(for: codeVerifier)

        var components = URLComponents(url: authorizeBase, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(contentsOf: [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: config.scopes),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ])
        components?.queryItems = queryItems

        guard let authorizeURL = components?.url,
              let callbackScheme = URL(string: config.redirectURI)?.scheme else {
            throw OAuthSignInError.notConfigured
        }

        let authorizationCode: String = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authorizeURL, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error {
                    let isCancel = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    continuation.resume(throwing: isCancel ? OAuthSignInError.cancelled : error)
                    return
                }
                guard let callbackURL,
                      let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: OAuthSignInError.noAuthCode)
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            self.webAuthSession = session
            session.start()
        }

        let tokens = try await exchangeAuthorizationCode(authorizationCode, codeVerifier: codeVerifier, config: config)
        persist(tokens)
    }

    /// Returns a valid access token (refreshing if near expiry), or nil if not
    /// signed in / refresh failed — callers then fall back to an API key.
    func currentAccessToken(config: OAuthConfig) async -> String? {
        guard let tokens = loadTokens() else { return nil }
        if let expiresAt = tokens.expiresAt, expiresAt.timeIntervalSinceNow < 60 {
            guard let refreshToken = tokens.refreshToken,
                  let refreshed = try? await refreshTokens(refreshToken: refreshToken, config: config) else {
                return nil
            }
            persist(refreshed)
            return refreshed.accessToken
        }
        return tokens.accessToken
    }

    /// Non-refreshing read of the stored access token, for synchronous provider
    /// construction. May be expired; the async path above handles refresh.
    func storedAccessToken() -> String? {
        loadTokens()?.accessToken
    }

    func signOut() {
        KeychainManager.delete(service: Self.tokenService)
        isSignedIn = false
    }

    // MARK: - Token endpoints

    private func exchangeAuthorizationCode(_ code: String, codeVerifier: String, config: OAuthConfig) async throws -> StoredOAuthTokens {
        try await postToken(config: config, params: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientID,
            "code_verifier": codeVerifier,
        ])
    }

    private func refreshTokens(refreshToken: String, config: OAuthConfig) async throws -> StoredOAuthTokens {
        try await postToken(config: config, params: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID,
        ])
    }

    private func postToken(config: OAuthConfig, params: [String: String]) async throws -> StoredOAuthTokens {
        guard let url = URL(string: config.tokenURL) else { throw OAuthSignInError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OAuthSignInError.tokenExchangeFailed(String(data: data, encoding: .utf8) ?? "http error")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw OAuthSignInError.tokenExchangeFailed("missing access_token")
        }
        let refreshToken = (json["refresh_token"] as? String) ?? loadTokens()?.refreshToken
        let expiresAt = (json["expires_in"] as? Double).map { Date(timeIntervalSinceNow: $0) }
        return StoredOAuthTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    // MARK: - Storage

    private func persist(_ tokens: StoredOAuthTokens) {
        guard let data = try? JSONEncoder().encode(tokens),
              let raw = String(data: data, encoding: .utf8) else { return }
        _ = KeychainManager.save(key: raw, service: Self.tokenService)
        isSignedIn = true
    }

    private func loadTokens() -> StoredOAuthTokens? {
        guard let raw = KeychainManager.retrieve(service: Self.tokenService),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StoredOAuthTokens.self, from: data)
    }

    // MARK: - PKCE helpers

    private static func randomCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

extension OAuthSignInManager: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Menu-bar app has no main window; use the key window or a transient anchor.
        MainActor.assumeIsolated { NSApp.keyWindow ?? ASPresentationAnchor() }
    }
}

private extension Data {
    /// Base64URL without padding, per RFC 7636 (PKCE).
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
