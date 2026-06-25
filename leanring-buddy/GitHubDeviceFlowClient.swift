//
//  GitHubDeviceFlowClient.swift
//  leanring-buddy
//
//  Stateless networking for GitHub's OAuth Device Flow plus the identity-confirmation
//  call. It talks DIRECTLY to github.com / api.github.com: Device Flow uses no client
//  secret, so there is nothing sensitive to proxy and the whole connector ships app-side
//  with a public client id. (Secret-requiring providers like Notion/Linear will instead
//  route through a Worker OAuth broker in a later slice — that's why this client is
//  GitHub-specific rather than a generic OAuth client.)
//
//  The polling LOOP and all state live in IntegrationsManager; this type only performs
//  the three discrete network steps and reports their results.
//

import Foundation

struct GitHubDeviceFlowClient {

    // MARK: - Endpoints

    private static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    private static let accessTokenURL = URL(string: "https://github.com/login/oauth/access_token")!
    private static let authenticatedUserURL = URL(string: "https://api.github.com/user")!

    private let urlSession: URLSession

    init(urlSession: URLSession = URLSession(configuration: .ephemeral)) {
        self.urlSession = urlSession
    }

    // MARK: - Step 1: request a device + user code

    struct DeviceCodeGrant: Equatable {
        let deviceCode: String
        let userCode: String
        let verificationURL: URL
        /// Seconds until the device code expires and the user must restart.
        let expiresInSeconds: Int
        /// Minimum seconds GitHub allows between token polls.
        let pollIntervalSeconds: Int
    }

    /// Requests a device + user code for `clientID` with the given OAuth `scope`.
    func requestDeviceCode(clientID: String, scope: String) async throws -> DeviceCodeGrant {
        let request = formPOSTRequest(
            url: Self.deviceCodeURL,
            fields: ["client_id": clientID, "scope": scope]
        )
        let payload = try await decodedJSONObject(for: request)

        guard let deviceCode = payload["device_code"] as? String,
              let userCode = payload["user_code"] as? String,
              let verificationURLString = payload["verification_uri"] as? String,
              let verificationURL = URL(string: verificationURLString) else {
            throw integrationError(from: payload, fallback: "GitHub returned an unexpected device-code response.")
        }

        // expires_in / interval come back as JSON numbers; fall back to GitHub's documented
        // defaults if a field is ever missing so we never divide-by-zero or hang forever.
        let expiresInSeconds = intValue(payload["expires_in"]) ?? 900
        let pollIntervalSeconds = intValue(payload["interval"]) ?? 5

        return DeviceCodeGrant(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURL: verificationURL,
            expiresInSeconds: expiresInSeconds,
            pollIntervalSeconds: pollIntervalSeconds
        )
    }

    // MARK: - Step 2: poll for the access token

    /// The outcome of one poll of GitHub's token endpoint. The caller loops on `.pending`
    /// / `.slowDown` honoring the interval and stops on any terminal case.
    enum AccessTokenPollResult: Equatable {
        case authorized(accessToken: String)
        case authorizationPending
        case slowDown(newIntervalSeconds: Int)
        case accessDenied
        case codeExpired
    }

    func pollForAccessToken(clientID: String, deviceCode: String) async throws -> AccessTokenPollResult {
        let request = formPOSTRequest(
            url: Self.accessTokenURL,
            fields: [
                "client_id": clientID,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ]
        )
        let payload = try await decodedJSONObject(for: request)

        if let accessToken = payload["access_token"] as? String, !accessToken.isEmpty {
            return .authorized(accessToken: accessToken)
        }

        switch payload["error"] as? String {
        case "authorization_pending":
            return .authorizationPending
        case "slow_down":
            // GitHub asks us to back off and includes a new minimum interval.
            return .slowDown(newIntervalSeconds: intValue(payload["interval"]) ?? 10)
        case "access_denied":
            return .accessDenied
        case "expired_token":
            return .codeExpired
        default:
            throw integrationError(from: payload, fallback: "GitHub rejected the authorization request.")
        }
    }

    // MARK: - Step 3: confirm identity

    /// Fetches the authenticated user's login (e.g. "octocat") to display as the connected
    /// account and to verify the freshly issued token actually works.
    func fetchAuthenticatedUserLogin(accessToken: String) async throws -> String {
        var request = URLRequest(url: Self.authenticatedUserURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub's API rejects requests without a User-Agent.
        request.setValue("Clicky", forHTTPHeaderField: "User-Agent")

        let payload = try await decodedJSONObject(for: request)
        guard let login = payload["login"] as? String else {
            throw integrationError(from: payload, fallback: "Couldn't read your GitHub account.")
        }
        return login
    }

    // MARK: - Request / decoding helpers

    private func formPOSTRequest(url: URL, fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Ask for JSON; without this header GitHub replies form-encoded.
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Clicky", forHTTPHeaderField: "User-Agent")
        request.httpBody = formEncodedBody(fields)
        return request
    }

    private func formEncodedBody(_ fields: [String: String]) -> Data {
        var allowedCharacters = CharacterSet.alphanumerics
        allowedCharacters.insert(charactersIn: "-._~") // RFC 3986 unreserved set.
        let encodedPairs = fields.map { key, value -> String in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        return encodedPairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    private func decodedJSONObject(for request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await urlSession.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            // Surface GitHub's own error body when present (it usually carries
            // "message"/"error"); otherwise report the status code.
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw integrationError(from: body, fallback: "GitHub returned HTTP \(httpResponse.statusCode).")
        }
        guard let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw NSError(
                domain: "GitHubDeviceFlowClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "GitHub returned an unreadable response."]
            )
        }
        return payload
    }

    /// Reads an Int from a JSON value that may arrive as a number or a string.
    private func intValue(_ value: Any?) -> Int? {
        if let intNumber = value as? Int { return intNumber }
        if let doubleNumber = value as? Double { return Int(doubleNumber) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    /// Builds an error preferring GitHub's own "error_description" / "message", falling back
    /// to a friendly default so the UI never shows an empty failure.
    private func integrationError(from payload: [String: Any]?, fallback: String) -> NSError {
        let message = (payload?["error_description"] as? String)
            ?? (payload?["message"] as? String)
            ?? (payload?["error"] as? String)
            ?? fallback
        return NSError(
            domain: "GitHubDeviceFlowClient",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
