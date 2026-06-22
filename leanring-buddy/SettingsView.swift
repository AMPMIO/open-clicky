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

            // Provider-specific fields
            switch providerManager.configuration.activeProvider {
            case .openRouter:
                openRouterSection
            case .openClaw:
                openClawSection
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
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OpenClaw Endpoint")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)

                TextField("http://your-vps:18789", text: $openClawEndpointInput)
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
                    .onChange(of: openClawEndpointInput) { newValue in
                        openClawEndpointError = Self.endpointValidationError(newValue)
                        providerManager.configuration.openClawEndpoint = newValue
                        providerManager.updateProvider()
                    }

                if let openClawEndpointError {
                    Text(openClawEndpointError)
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.warningText)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Bearer Token")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)

                SecureField("Token", text: $openClawTokenInput)
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
                    .onChange(of: openClawTokenInput) { newValue in
                        providerManager.configuration.openClawToken = newValue
                        providerManager.updateProvider()
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
        openClawEndpointError = Self.endpointValidationError(openClawEndpointInput)
        workerURLError = Self.endpointValidationError(workerURLInput)
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
            let isLoopback = lowerHost == "localhost" || lowerHost == "127.0.0.1"
                || lowerHost == "::1" || lowerHost.hasSuffix(".local")
            return isLoopback ? nil : "Remote endpoints must use https — http is blocked except for localhost."
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
