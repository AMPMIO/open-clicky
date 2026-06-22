//
//  SettingsView.swift
//  leanring-buddy
//
//  Provider configuration UI: select backend, enter API keys,
//  configure OpenClaw endpoint, test connection.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var providerManager: ProviderManager
    @State private var openRouterKeyInput: String = ""
    @State private var openClawTokenInput: String = ""
    @State private var openClawEndpointInput: String = ""
    @State private var workerURLInput: String = ""
    @State private var connectionTestResult: String?
    @State private var isTestingConnection: Bool = false
    @State private var openClawEndpointError: String?
    @State private var workerURLError: String?
    @State private var hermesEndpointInput: String = ""
    @State private var hermesTokenInput: String = ""
    @State private var hermesEndpointError: String?
    @State private var hermesActionMode: Bool = false
    @State private var hermesReadinessResult: String?
    @State private var isCheckingHermes: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                Spacer()
            }

            // Provider Selection
            providerPicker

            capabilitiesHint

            // Provider-specific fields
            switch providerManager.configuration.activeProvider {
            case .openRouter:
                openRouterSection
            case .openClaw:
                openClawSection
            case .hermes:
                hermesSection
            case .workerProxy:
                workerProxySection
            }

            // Connection test
            connectionTestSection

            Spacer()
        }
        .padding(16)
        .frame(width: 280)
        .background(DS.Colors.background)
        .onAppear {
            loadCurrentValues()
        }
    }

    // MARK: - Provider Picker

    private var providerPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Provider")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)

            HStack(spacing: 0) {
                ForEach(APIProviderType.allCases, id: \.self) { provider in
                    providerTab(provider)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
            )
        }
    }

    /// Small caption showing the active backend's capabilities (vision /
    /// streaming / pointing), so the user knows what to expect — e.g. that
    /// pointing on an agent backend depends on the underlying model.
    private var capabilitiesHint: some View {
        let caps = providerManager.currentProviderCapabilities
        let pointing = caps.reliablyEmitsPointTags ? "pointing supported" : "pointing depends on the model"
        return Text("vision \(caps.supportsVision ? "✓" : "✗") · streaming \(caps.supportsStreaming ? "✓" : "✗") · \(pointing)")
            .font(.system(size: 10))
            .foregroundColor(DS.Colors.textTertiary)
    }

    private func providerTab(_ provider: APIProviderType) -> some View {
        let isSelected = providerManager.configuration.activeProvider == provider
        return Button(action: {
            providerManager.setActiveProvider(provider)
        }) {
            Text(provider.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isSelected ? DS.Colors.textPrimary : DS.Colors.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - OpenRouter Section

    private var openRouterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OpenRouter API Key")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)

            SecureField("sk-or-...", text: $openRouterKeyInput)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DS.Colors.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                )
                .onChange(of: openRouterKeyInput) { newValue in
                    providerManager.configuration.openRouterAPIKey = newValue
                    providerManager.updateProvider()
                }
        }
    }

    // MARK: - OpenClaw Section

    private var openClawSection: some View {
        AgentEndpointSettingsView(
            endpointLabel: "OpenClaw Endpoint",
            endpointPlaceholder: "http://your-vps:18789",
            endpoint: $openClawEndpointInput,
            token: $openClawTokenInput,
            endpointError: openClawEndpointError,
            onEndpointChange: { newValue in
                openClawEndpointError = Self.endpointValidationError(newValue)
                providerManager.configuration.openClawEndpoint = newValue
                providerManager.updateProvider()
            },
            onTokenChange: { newValue in
                providerManager.configuration.openClawToken = newValue
                providerManager.updateProvider()
            }
        )
    }

    // MARK: - Hermes Section

    private var hermesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AgentEndpointSettingsView(
                endpointLabel: "Hermes Endpoint",
                endpointPlaceholder: "http://localhost:8642",
                endpoint: $hermesEndpointInput,
                token: $hermesTokenInput,
                endpointError: hermesEndpointError,
                onEndpointChange: { newValue in
                    hermesEndpointError = Self.endpointValidationError(newValue)
                    providerManager.configuration.hermesEndpoint = newValue
                    providerManager.updateProvider()
                },
                onTokenChange: { newValue in
                    providerManager.configuration.hermesToken = newValue
                    providerManager.updateProvider()
                }
            )

            // Mode toggle (answer+point vs computer-use)
            Toggle(isOn: $hermesActionMode) {
                Text("Allow on-screen actions (computer-use)")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .onChange(of: hermesActionMode) { newValue in
                providerManager.configuration.hermesActionModeEnabled = newValue
            }

            Text("Action mode needs the Hands-On actuation layer (coming soon). Until then, Hermes answers and points.")
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)

            // Readiness check: probe vision passthrough, POINT-tag preservation,
            // and whether the incoming system prompt is honored.
            Button(action: { runHermesReadinessCheck() }) {
                HStack(spacing: 6) {
                    if isCheckingHermes {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.seal").font(.system(size: 10))
                    }
                    Text("Run Readiness Check").font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(DS.Colors.surface3))
            }
            .buttonStyle(.plain)
            .disabled(isCheckingHermes)

            if let hermesReadinessResult {
                Text(hermesReadinessResult)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Probes the configured Hermes instance for the three integration risks that
    /// determine whether Clicky's pointing works: vision passthrough, raw-text +
    /// [POINT:] tag preservation, and whether the incoming system prompt is honored.
    private func runHermesReadinessCheck() {
        isCheckingHermes = true
        hermesReadinessResult = nil
        Task {
            // 1x1 transparent PNG so the request exercises the image_url vision path.
            let onePixelPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==") ?? Data()
            let probeSystemPrompt = "You are a diagnostic. Reply with exactly this and nothing else: READY [POINT:5,5:probe]"
            do {
                let (text, _) = try await providerManager.currentProvider.chatStreaming(
                    images: [(data: onePixelPNG, label: "test image (image dimensions: 1x1 pixels)")],
                    systemPrompt: probeSystemPrompt,
                    conversationHistory: [],
                    userPrompt: "run the diagnostic",
                    model: providerManager.configuration.selectedModelID,
                    onTextChunk: { _ in }
                )
                let respondedAtAll = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let honorsSystemPrompt = text.contains("READY")
                // Use the SAME parser Mode A uses, so the check reflects whether
                // pointing would actually animate — not just that "[POINT:" appears.
                let parsedCoordinate = CompanionManager.parsePointingCoordinates(from: text).coordinate
                await MainActor.run {
                    var lines: [String] = []
                    lines.append(respondedAtAll ? "✓ accepted image input (vision not deeply verified)" : "✗ empty / no response")
                    lines.append(honorsSystemPrompt ? "✓ honors the system prompt" : "✗ system prompt ignored or reformatted")
                    lines.append(parsedCoordinate != nil ? "✓ emits parseable [POINT:] tags — pointing works" : "✗ no parseable [POINT:] tag — pointing won't work")
                    hermesReadinessResult = lines.joined(separator: "\n")
                    isCheckingHermes = false
                }
            } catch {
                await MainActor.run {
                    hermesReadinessResult = "✗ \(error.localizedDescription.prefix(120))"
                    isCheckingHermes = false
                }
            }
        }
    }

    // MARK: - Worker Proxy Section

    private var workerProxySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Worker URL")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)

            TextField("https://your-worker.workers.dev", text: $workerURLInput)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DS.Colors.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                )
                .onChange(of: workerURLInput) { newValue in
                    workerURLError = Self.endpointValidationError(newValue)
                    providerManager.configuration.workerBaseURL = newValue
                    providerManager.updateProvider()
                }

            if let workerURLError {
                Text(workerURLError)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.warningText)
            }

            Text("Keys are stored on the Worker, not locally.")
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
        }
    }

    // MARK: - Connection Test

    private var connectionTestSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { testConnection() }) {
                HStack(spacing: 6) {
                    if isTestingConnection {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                    }
                    Text("Test Connection")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DS.Colors.surface3)
                )
            }
            .buttonStyle(.plain)
            .disabled(isTestingConnection)

            if let result = connectionTestResult {
                Text(result)
                    .font(.system(size: 10))
                    .foregroundColor(result.contains("Success") ? DS.Colors.blue400 : DS.Colors.textTertiary)
            }
        }
    }

    // MARK: - Helpers

    private func loadCurrentValues() {
        openRouterKeyInput = providerManager.configuration.openRouterAPIKey ?? ""
        openClawTokenInput = providerManager.configuration.openClawToken ?? ""
        openClawEndpointInput = providerManager.configuration.openClawEndpoint
        workerURLInput = providerManager.configuration.workerBaseURL
        hermesEndpointInput = providerManager.configuration.hermesEndpoint
        hermesTokenInput = providerManager.configuration.hermesToken ?? ""
        hermesActionMode = providerManager.configuration.hermesActionModeEnabled
        openClawEndpointError = Self.endpointValidationError(openClawEndpointInput)
        workerURLError = Self.endpointValidationError(workerURLInput)
        hermesEndpointError = Self.endpointValidationError(hermesEndpointInput)
    }

    /// Returns a user-facing warning if `endpoint` would be blocked by App
    /// Transport Security or is malformed. Remote hosts must use https; only
    /// loopback / .local hosts may use http (matches the Info.plist ATS policy).
    static func endpointValidationError(_ endpoint: String) -> String? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else {
            return "Enter a full URL like https://host:port"
        }
        switch scheme {
        case "https":
            return nil
        case "http":
            let lowerHost = host.lowercased()
            let isLoopback = lowerHost == "localhost" || lowerHost == "127.0.0.1" || lowerHost == "::1"
            return isLoopback ? nil : "Remote / .local endpoints must use https — http is allowed only for localhost."
        default:
            return "URL must start with http:// or https://"
        }
    }

    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil

        Task {
            do {
                let (text, duration) = try await providerManager.currentProvider.chatStreaming(
                    images: [],
                    systemPrompt: "Respond with exactly: OK",
                    conversationHistory: [],
                    userPrompt: "ping",
                    model: providerManager.configuration.selectedModelID,
                    onTextChunk: { _ in }
                )
                await MainActor.run {
                    connectionTestResult = "Success (\(String(format: "%.1f", duration))s): \(text.prefix(40))"
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionTestResult = "Error: \(error.localizedDescription.prefix(80))"
                    isTestingConnection = false
                }
            }
        }
    }
}

/// Reusable settings block for a self-hosted OpenAI-compatible agent backend:
/// an endpoint URL (with scheme validation) plus a bearer token. Shared by the
/// OpenClaw and Hermes provider sections.
struct AgentEndpointSettingsView: View {
    let endpointLabel: String
    let endpointPlaceholder: String
    @Binding var endpoint: String
    @Binding var token: String
    let endpointError: String?
    let onEndpointChange: (String) -> Void
    let onTokenChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(endpointLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)

                TextField(endpointPlaceholder, text: $endpoint)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DS.Colors.surface2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                    )
                    .onChange(of: endpoint) { newValue in onEndpointChange(newValue) }

                if let endpointError {
                    Text(endpointError)
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.warningText)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Bearer Token")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)

                SecureField("Token", text: $token)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DS.Colors.surface2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                    )
                    .onChange(of: token) { newValue in onTokenChange(newValue) }
            }
        }
    }
}
