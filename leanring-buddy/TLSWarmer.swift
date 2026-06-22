//
//  TLSWarmer.swift
//  leanring-buddy
//
//  Shared helper that pre-establishes a TLS session to a host with a no-op
//  background HEAD request, so the first real (large image) request doesn't pay
//  for a cold TLS handshake. Used by ClaudeAPI and OpenAICompatibleProvider.
//

import Foundation

/// Warms TLS connections once per host. The TLS session ticket is host-scoped,
/// so hitting the root path is enough; failures are ignored (pure optimization).
enum TLSWarmer {
    private static let lock = NSLock()
    private static var warmedHosts: Set<String> = []

    /// Sends a background HEAD to the host root the first time a given host is
    /// seen. Subsequent calls for the same host are no-ops.
    static func warm(_ url: URL, using session: URLSession) {
        guard let host = url.host else { return }

        lock.lock()
        let alreadyWarmed = warmedHosts.contains(host)
        if !alreadyWarmed { warmedHosts.insert(host) }
        lock.unlock()

        guard !alreadyWarmed else { return }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        guard let warmupURL = components.url else { return }

        var request = URLRequest(url: warmupURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        session.dataTask(with: request) { _, _, _ in }.resume()
    }
}
