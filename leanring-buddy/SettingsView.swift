//
//  SettingsView.swift
//  leanring-buddy
//
//  Provider configuration UI: select backend, enter API keys,
//  configure OpenClaw endpoint, test connection.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var providerManager: ProviderManager
    @ObservedObject var companionManager: CompanionManager
    @ObservedObject private var screenMemory = ScreenMemoryStore.shared
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
    @State private var showPurgeConfirmation = false
    @State private var excludeAppInput = ""
    @ObservedObject private var oauthManager = OAuthSignInManager.shared
    @ObservedObject private var macroStore = SpokenMacroStore.shared
    @State private var oauthClientID = ""
    @State private var oauthAuthorizeURL = ""
    @State private var oauthTokenURL = ""
    @State private var oauthScopes = ""
    @State private var oauthSignInError: String?
    @State private var isOAuthSigningIn = false

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

            Divider().background(DS.Colors.borderSubtle)

            pushToTalkSection

            speechToTextSection

            microphoneSection

            voiceSection

            Divider().background(DS.Colors.borderSubtle)

            handsOnSection

            terminalBridgeSection

            screenMemorySection

            liveCompanionSection

            watchModeSection

            macrosSection

            chatGPTSignInSection

            Divider().background(DS.Colors.borderSubtle)

            surfaceSection

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
                .foregroundColor(DS.Colors.textPrimary)
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

            Text("Model")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)

            TextField("qwen/qwen3-vl-235b-a22b-instruct", text: Binding(
                get: { providerManager.configuration.selectedModelID },
                set: { providerManager.configuration.selectedModelID = $0 }
            ))
                .textFieldStyle(.plain)
                .foregroundColor(DS.Colors.textPrimary)
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

            Text("Any OpenRouter model slug — use a VISION model so OpenClicky can see your screen + point (e.g. qwen/qwen3-vl-32b-instruct, z-ai/glm-4.6v).")
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
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
                .foregroundColor(DS.Colors.textPrimary)
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

    // MARK: - Hands-On Mode

    private var handsOnSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { companionManager.isHandsOnModeEnabled },
                set: { companionManager.setHandsOnModeEnabled($0) }
            )) {
                Text("Hands-On Mode (click for me)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Text(companionManager.hasAccessibilityPermission
                 ? "After you confirm by voice, Clicky can click an element for you. It never acts on destructive things."
                 : "Needs Accessibility permission to click on your behalf.")
                .font(.system(size: 10))
                .foregroundColor(companionManager.hasAccessibilityPermission ? DS.Colors.textTertiary : DS.Colors.warningText)
        }
    }

    // MARK: - Speech-to-Text (G2.1)

    /// Lets the user pick the speech-to-text backend. Apple Speech is the default —
    /// it's on-device and starts instantly, so a quick push-to-talk tap isn't lost
    /// while a cloud session connects.
    private var speechToTextSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Speech-to-text")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)

            Picker("", selection: Binding(
                get: { companionManager.selectedSTTProvider },
                set: { companionManager.setSelectedSTTProvider($0) }
            )) {
                ForEach(STTProviderKind.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .labelsHidden()

            Text(companionManager.selectedSTTProvider.caption)
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Voice / Text-to-Speech (G2.2)

    /// Lets the user pick the TTS backend and a voice for it, with a tap-to-preview
    /// per voice. ElevenLabs stays the default so the current pipeline is unchanged.
    /// Extracted into its own view so it can `@ObservedObject` the TTS manager and
    /// re-render when the active provider / playback state changes.
    private var voiceSection: some View {
        VoiceSettingsSection(ttsProviderManager: companionManager.ttsProviderManager)
    }

    /// Lets the user pick which microphone feeds dictation and confirm it with a live level
    /// meter. Extracted into its own view so it can `@ObservedObject` the dictation manager
    /// and re-render as the test meter's audio level updates.
    private var microphoneSection: some View {
        MicrophoneSettingsSection(buddyDictationManager: companionManager.buddyDictationManager)
    }

    /// Lets the user record their own push-to-talk hotkey. Extracted into its own view so it
    /// can own the live key-capture recorder state.
    private var pushToTalkSection: some View {
        PushToTalkShortcutSettingsSection()
    }

    // MARK: - On-screen Surface (Hub / Dock)

    private var surfaceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("On-screen surface")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)

            Picker("", selection: Binding(
                get: { companionManager.surfaceMode },
                set: { companionManager.setSurfaceMode($0) }
            )) {
                ForEach(SurfaceMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .labelsHidden()

            if companionManager.surfaceMode == .hub {
                Picker("", selection: Binding(
                    get: { companionManager.hubCorner },
                    set: { companionManager.setHubCorner($0) }
                )) {
                    ForEach(HubCorner.allCases, id: \.self) { corner in
                        Text(corner.label).tag(corner)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.mini)
                .labelsHidden()
            }

            Text("Hub: a glass dashboard in a corner that reveals on hover. Dock: a compact bar under the menu bar. Switch to compare them.")
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
        }
    }

    // MARK: - Terminal Bridge

    private var terminalBridgeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { companionManager.isTerminalBridgeEnabled },
                set: { companionManager.setTerminalBridgeEnabled($0) }
            )) {
                Text("Terminal Bridge (send to Claude Code)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Text("Dispatch a spoken request to a running terminal agent (Terminal/iTerm/Ghostty) after you confirm. Needs Accessibility + Automation permission.")
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
        }
    }

    // MARK: - Screen Memory

    private var screenMemorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { screenMemory.isEnabled },
                set: { screenMemory.setEnabled($0) }
            )) {
                Text("Screen Memory (local recall)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Text("Remembers what you've shown Clicky so you can ask about it later. Stored encrypted, on-device only.")
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)

            if screenMemory.isEnabled {
                Toggle(isOn: Binding(
                    get: { screenMemory.isPaused },
                    set: { screenMemory.setPaused($0) }
                )) {
                    Text("Pause recording")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                HStack(spacing: 6) {
                    TextField("Exclude an app by name…", text: $excludeAppInput)
                        .textFieldStyle(.plain)
                        .foregroundColor(DS.Colors.textPrimary)
                        .font(.system(size: 10))
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(DS.Colors.surface2))
                    Button("Add") {
                        let name = excludeAppInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty { screenMemory.excludeApp(name); excludeAppInput = "" }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Colors.blue400)
                }

                if !screenMemory.excludedApps.isEmpty {
                    Text("Never recorded: \(screenMemory.excludedApps.sorted().joined(separator: ", "))")
                        .font(.system(size: 9))
                        .foregroundColor(DS.Colors.textTertiary)
                }
            }

            if screenMemory.isEnabled && screenMemory.entryCount > 0 {
                Button(action: { showPurgeConfirmation = true }) {
                    Text("Clear \(screenMemory.entryCount) saved moment\(screenMemory.entryCount == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Colors.warningText)
                }
                .buttonStyle(.plain)
                .alert("Clear all screen memory?", isPresented: $showPurgeConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Clear All", role: .destructive) { screenMemory.purge() }
                } message: {
                    Text("This permanently deletes all saved moments. This can't be undone.")
                }
            }
        }
    }

    // MARK: - Live Companion

    private var liveCompanionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { companionManager.isLiveCompanionEnabled },
                set: { companionManager.setLiveCompanionEnabled($0) }
            )) {
                Text("Live Companion (hear system audio)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Text("Lets Clicky hear calls/tutorials playing on your Mac so it can answer about them. Uses Screen Recording; system-audio transcription goes through your Worker (set OPENAI_API_KEY on the Worker).")
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
        }
    }

    // MARK: - Spoken Macros

    private var macrosSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Spoken Macros")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)

            Text("Say \"record a macro called <name>\", say each step, then \"save macro\". Replay with \"run macro <name>\" (delete/list also work by voice).")
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)

            ForEach(macroStore.macros) { macro in
                HStack {
                    Text("\(macro.name) · \(macro.steps.count) step\(macro.steps.count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textSecondary)
                    Spacer()
                    Button(action: { macroStore.delete(named: macro.name) }) {
                        Text("Delete")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Colors.warningText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Watch Mode

    private var watchModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { companionManager.isWatchModeEnabled },
                set: { companionManager.setWatchModeEnabled($0) }
            )) {
                Text("Watch Mode (proactive nudges)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Text("Quietly watches your screen and offers the occasional brief heads-up (e.g. explaining an error). Off by default; rate-limited; only escalates on meaningful, actionable changes. Needs Screen Recording + a configured provider.")
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
        }
    }

    // MARK: - Sign in with ChatGPT (OAuth)

    private var chatGPTSignInSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sign in with ChatGPT (experimental)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)

            if oauthManager.isSignedIn {
                HStack {
                    Text("Signed in ✓")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textSecondary)
                    Spacer()
                    Button(action: {
                        oauthManager.signOut()
                        providerManager.configuration.oauthBoundProvider = nil
                        providerManager.updateProvider()
                    }) {
                        Text("Sign out")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Colors.warningText)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                oauthField("Client ID", text: $oauthClientID)
                oauthField("Authorize URL", text: $oauthAuthorizeURL)
                oauthField("Token URL", text: $oauthTokenURL)
                oauthField("Scopes (space-separated)", text: $oauthScopes)
                Button(action: signInWithOAuth) {
                    Text(isOAuthSigningIn ? "Signing in…" : "Sign in")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Colors.blue400)
                }
                .buttonStyle(.plain)
                .disabled(isOAuthSigningIn)
            }

            if let oauthSignInError {
                Text(oauthSignInError)
                    .font(.system(size: 9))
                    .foregroundColor(DS.Colors.warningText)
            }

            Text("Uses your OWN OAuth app (BYO client id + endpoints) — OpenClicky ships no credentials and impersonates nothing. Yields OpenAI-compatible models, not Opus; point your active OpenAI-compatible provider's endpoint at the API your OAuth app authorizes. The token becomes the Bearer, falling back to your API key when signed out. Redirect URI: openclicky://oauth-callback")
                .font(.system(size: 9))
                .foregroundColor(DS.Colors.textTertiary)
        }
        .onAppear {
            let config = providerManager.configuration.oauthConfig
            oauthClientID = config.clientID
            oauthAuthorizeURL = config.authorizeURL
            oauthTokenURL = config.tokenURL
            oauthScopes = config.scopes
        }
    }

    private func oauthField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .foregroundColor(DS.Colors.textPrimary)
            .font(.system(size: 10))
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(DS.Colors.surface2))
    }

    /// HTTPS-only (or loopback) endpoint check, reusing the app-wide URL policy so
    /// auth codes/tokens are never sent over plaintext remote HTTP.
    private static func oauthEndpointIsSecure(_ urlString: String) -> Bool {
        ProviderConfiguration.validatedURL(base: urlString, path: "") != nil
    }

    private func signInWithOAuth() {
        guard !isOAuthSigningIn else { return }
        var config = providerManager.configuration.oauthConfig
        config.clientID = oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        config.authorizeURL = oauthAuthorizeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        config.tokenURL = oauthTokenURL.trimmingCharacters(in: .whitespacesAndNewlines)
        config.scopes = oauthScopes.trimmingCharacters(in: .whitespacesAndNewlines)

        guard config.isComplete else {
            oauthSignInError = "Complete all OAuth fields before signing in."
            return
        }
        guard Self.oauthEndpointIsSecure(config.authorizeURL) else {
            oauthSignInError = "Authorize URL must be HTTPS (or localhost)."
            return
        }
        guard Self.oauthEndpointIsSecure(config.tokenURL) else {
            oauthSignInError = "Token URL must be HTTPS (or localhost)."
            return
        }

        providerManager.configuration.oauthConfig = config
        // Capture the bound provider BEFORE the round-trip — if the user switches
        // providers while the web auth session is open, the token must still bind to
        // the provider that was active when they started sign-in (OC-96).
        let boundProvider = providerManager.configuration.activeProvider
        // Only the OpenAI-compatible providers consume an OAuth bearer; signing in
        // under Worker Proxy would bind a token no provider ever uses.
        switch boundProvider {
        case .openRouter, .openClaw, .hermes:
            break
        case .workerProxy:
            oauthSignInError = "Choose OpenRouter, OpenClaw, or Hermes before signing in with OAuth."
            return
        }
        oauthSignInError = nil
        isOAuthSigningIn = true
        Task { @MainActor in
            defer { isOAuthSigningIn = false }
            do {
                try await oauthManager.signIn(config: config)
                providerManager.configuration.oauthBoundProvider = boundProvider
                providerManager.updateProvider()
            } catch {
                oauthSignInError = error.localizedDescription
            }
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
                    .foregroundColor(DS.Colors.textPrimary)
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
                    .foregroundColor(DS.Colors.textPrimary)
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

/// Voice / text-to-speech settings: a TTS-provider picker plus the active provider's
/// voice list. Tapping a voice cell selects it (persisted per provider) and instantly
/// auditions it with a short preview phrase; the selected voice is marked with a
/// checkmark and a highlight. Observes the TTS manager directly so the list updates
/// when the provider changes and cells reflect playback state.
struct VoiceSettingsSection: View {
    @ObservedObject var ttsProviderManager: TTSProviderManager

    /// The voice id currently auditioning, so its preview button can show a spinner.
    @State private var previewingVoiceID: String?
    @State private var voicePreviewError: String?

    var body: some View {
        let activeProvider = ttsProviderManager.activeProvider
        let voices = ttsProviderManager.availableVoices(for: activeProvider)
        let selectedVoiceID = ttsProviderManager.selectedVoiceID(for: activeProvider)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Voice")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)

            Picker("", selection: Binding(
                get: { activeProvider },
                set: { ttsProviderManager.setActiveProvider($0) }
            )) {
                ForEach(TTSProviderKind.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .labelsHidden()

            Text(activeProvider.caption)
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            // Voice list. Tapping a cell selects that voice (persisted) and auditions it;
            // the selected voice shows a checkmark + highlight. Tolerate an empty list
            // (e.g. no on-device voices installed) with a clear, non-empty message.
            if voices.isEmpty {
                Text("No voices available for \(activeProvider.displayName).")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(voices) { voice in
                        voiceRow(voice, isSelected: voice.identifier == selectedVoiceID, provider: activeProvider)
                    }
                }
            }

            if let voicePreviewError {
                Text(voicePreviewError)
                    .font(.system(size: 9))
                    .foregroundColor(DS.Colors.warningText)
            }
        }
    }

    private func voiceRow(_ voice: TTSVoiceOption, isSelected: Bool, provider: TTSProviderKind) -> some View {
        let isAuditioningThisVoice = previewingVoiceID == voice.identifier

        // One tap target per cell: tapping selects this voice and immediately auditions it.
        return Button(action: { selectAndPreviewVoice(voice, for: provider) }) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? DS.Colors.blue400 : DS.Colors.textTertiary)
                Text(voice.displayName)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? DS.Colors.textPrimary : DS.Colors.textSecondary)

                Spacer()

                // Play affordance — becomes a spinner while this voice is auditioning.
                if isAuditioningThisVoice {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.circle")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Colors.textSecondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())   // whole row is the tap target, not just the text
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.small)
                    .fill(isSelected ? DS.Colors.blue400.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        // Pointer cursor only while the cell is actually tappable — suppressed during an
        // audition when every cell is disabled, so the cursor never lies about clickability.
        .pointerCursor(isEnabled: previewingVoiceID == nil)
        // Disable all cells while one auditions so previews never overlap (the manager
        // starts a new preview without stopping a prior one).
        .disabled(previewingVoiceID != nil)
    }

    /// Persists the selection first (synchronously, so picking a voice always sticks even
    /// when the audition can't reach the Worker), then auditions the chosen voice.
    private func selectAndPreviewVoice(_ voice: TTSVoiceOption, for provider: TTSProviderKind) {
        ttsProviderManager.setSelectedVoiceID(voice.identifier, for: provider)
        previewVoice(voice.identifier, for: provider)
    }

    private func previewVoice(_ voiceID: String, for provider: TTSProviderKind) {
        guard previewingVoiceID == nil else { return }
        previewingVoiceID = voiceID
        voicePreviewError = nil
        Task { @MainActor in
            defer { previewingVoiceID = nil }
            do {
                try await ttsProviderManager.previewVoice(voiceID, for: provider)
            } catch {
                voicePreviewError = "Preview failed: \(error.localizedDescription.prefix(80))"
            }
        }
    }
}

/// Microphone input settings: a picker of the available input devices (plus "System
/// Default") and a "Test microphone" toggle that shows a live input-level meter so the
/// user can confirm the chosen device is picking up sound. Observes the dictation manager
/// so the meter repaints as the audio level updates and reflects test start/stop state.
private struct MicrophoneSettingsSection: View {
    @ObservedObject var buddyDictationManager: BuddyDictationManager

    @State private var availableDevices: [AvailableMicrophoneInputDevice] = []
    // The effective selection shown in the UI: nil means "System Default". Kept in local
    // state (initialized from the persisted UID) so the checkmark repaints on tap.
    @State private var selectedDeviceUID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Microphone")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)

            Text("Choose which microphone Clicky listens through for push-to-talk.")
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 2) {
                // "System Default" is always present so the user can revert to whatever the
                // OS picks (e.g. when their chosen mic is unplugged).
                deviceRow(uid: nil, name: "System Default")
                if availableDevices.isEmpty {
                    Text("No additional microphones detected.")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                        .padding(.horizontal, 6)
                } else {
                    ForEach(availableDevices) { device in
                        deviceRow(uid: device.uniqueID, name: device.localizedName)
                    }
                }
            }

            // Test mic: an explicit toggle so the mic only goes live when the user asks.
            // While active, a level meter shows live input so they can confirm it works.
            HStack(spacing: 10) {
                Button(action: toggleMicrophoneTest) {
                    HStack(spacing: 5) {
                        Image(systemName: buddyDictationManager.isMonitoringInputLevelForTest ? "stop.fill" : "mic.fill")
                            .font(.system(size: 10))
                        Text(buddyDictationManager.isMonitoringInputLevelForTest ? "Stop test" : "Test microphone")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(DS.Colors.blue400)
                }
                .buttonStyle(.plain)
                .pointerCursor()

                if buddyDictationManager.isMonitoringInputLevelForTest {
                    MicrophoneTestLevelMeter(audioPowerLevel: buddyDictationManager.currentAudioPowerLevel)
                }
            }
        }
        .onAppear { refreshAvailableMicrophoneDevices() }
        .onDisappear {
            // Never leave the mic hot once the settings panel closes.
            buddyDictationManager.stopInputLevelMonitoringForTest()
        }
    }

    private func deviceRow(uid: String?, name: String) -> some View {
        let isSelected = uid == selectedDeviceUID
        return Button(action: { selectInputDevice(uid: uid) }) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? DS.Colors.blue400 : DS.Colors.textTertiary)
                Text(name)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? DS.Colors.textPrimary : DS.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())   // whole row is the tap target, not just the text
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.small)
                    .fill(isSelected ? DS.Colors.blue400.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    /// Persists the chosen device (nil = system default) and updates the checkmark. If the
    /// test meter is live, restart it so it immediately reflects the newly chosen device.
    private func selectInputDevice(uid: String?) {
        BuddyDictationManager.selectedInputDeviceUID = uid
        selectedDeviceUID = uid
        if buddyDictationManager.isMonitoringInputLevelForTest {
            buddyDictationManager.stopInputLevelMonitoringForTest()
            buddyDictationManager.startInputLevelMonitoringForTest()
        }
    }

    private func toggleMicrophoneTest() {
        if buddyDictationManager.isMonitoringInputLevelForTest {
            buddyDictationManager.stopInputLevelMonitoringForTest()
        } else {
            // Re-enumerate so a mic plugged in while Settings stayed open shows up the moment
            // the user goes to test it — a cheap refresh in lieu of a CoreAudio hot-plug
            // listener (adversarial-review finding #3, the optional one).
            refreshAvailableMicrophoneDevices()
            buddyDictationManager.startInputLevelMonitoringForTest()
        }
    }

    /// Re-reads the available input devices and recomputes the effective selection: the
    /// persisted device is shown selected only if it's still present, else System Default —
    /// matching what capture actually does when a device is absent.
    private func refreshAvailableMicrophoneDevices() {
        availableDevices = BuddyDictationManager.availableMicrophoneInputDevices()
        let persistedUID = BuddyDictationManager.selectedInputDeviceUID
        selectedDeviceUID = availableDevices.contains { $0.uniqueID == persistedUID } ? persistedUID : nil
    }
}

/// A simple segmented level meter driven by the dictation manager's published audio power
/// level (0...1). Lit segments rise with input volume so the user can see the microphone
/// responding while testing.
private struct MicrophoneTestLevelMeter: View {
    let audioPowerLevel: CGFloat

    private let segmentCount = 18

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segmentCount, id: \.self) { segmentIndex in
                let segmentThreshold = CGFloat(segmentIndex) / CGFloat(segmentCount)
                RoundedRectangle(cornerRadius: 1)
                    .fill(audioPowerLevel >= segmentThreshold ? DS.Colors.blue400 : DS.Colors.blue400.opacity(0.15))
                    .frame(width: 4, height: 14)
            }
        }
        .animation(.easeOut(duration: 0.08), value: audioPowerLevel)
        .accessibilityLabel("Microphone input level")
    }
}

/// Push-to-talk shortcut settings: shows the active shortcut and lets the user record their
/// own (an arbitrary modifier combo, or a single modifier like Fn) or reset to the default.
private struct PushToTalkShortcutSettingsSection: View {
    @StateObject private var shortcutRecorder = PushToTalkShortcutRecorder()
    // Mirrored from BuddyPushToTalkShortcut so the row repaints after recording / resetting
    // (the persisted shortcut isn't a @Published source).
    @State private var currentShortcutDisplayText = BuddyPushToTalkShortcut.pushToTalkDisplayText
    @State private var hasCustomShortcut = BuddyPushToTalkShortcut.recordedShortcut != nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Push-to-talk shortcut")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)

            Text("Hold this to talk. Record your own — an arbitrary modifier combo, or a single modifier like Fn.")
                .font(.system(size: 10))
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(action: toggleRecording) {
                    HStack(spacing: 6) {
                        Image(systemName: shortcutRecorder.isRecording ? "circle.fill" : "keyboard")
                            .font(.system(size: 10))
                            .foregroundColor(shortcutRecorder.isRecording ? DS.Colors.blue400 : DS.Colors.textSecondary)
                        Text(shortcutRecorder.isRecording
                             ? "Press your shortcut… (esc to cancel)"
                             : currentShortcutDisplayText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.Colors.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: DS.CornerRadius.small)
                            .strokeBorder(
                                shortcutRecorder.isRecording ? DS.Colors.blue400 : DS.Colors.borderSubtle,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .pointerCursor()

                // Only offer "Reset" when a custom shortcut is set and we're not mid-record.
                if hasCustomShortcut && !shortcutRecorder.isRecording {
                    Button(action: resetToDefaultShortcut) {
                        Text("Reset")
                            .font(.system(size: 10))
                            .foregroundColor(DS.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }

            // Non-blocking caution: a lone common modifier (⌘/⌥/⌃/⇧) clashes with system
            // shortcuts like ⌘C. Still fully recordable — modifier-only hold is the intended
            // push-to-talk UX (the right-⌘ default is device-specific and won't trip this).
            if !shortcutRecorder.isRecording,
               BuddyPushToTalkShortcut.recordedShortcut?.isLoneCommonModifier == true {
                Text("This may interfere with system shortcuts like ⌘C.")
                    .font(.system(size: 9))
                    .foregroundColor(DS.Colors.warningText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            shortcutRecorder.onCapture = { recordedShortcut in
                BuddyPushToTalkShortcut.recordedShortcut = recordedShortcut
                refreshShortcutDisplay()
            }
        }
        // Never leave the global key monitors running once the section closes.
        .onDisappear { shortcutRecorder.cancel() }
    }

    private func toggleRecording() {
        if shortcutRecorder.isRecording {
            shortcutRecorder.cancel()
        } else {
            shortcutRecorder.startRecording()
        }
    }

    private func resetToDefaultShortcut() {
        BuddyPushToTalkShortcut.recordedShortcut = nil
        refreshShortcutDisplay()
    }

    private func refreshShortcutDisplay() {
        currentShortcutDisplayText = BuddyPushToTalkShortcut.pushToTalkDisplayText
        hasCustomShortcut = BuddyPushToTalkShortcut.recordedShortcut != nil
    }
}

/// Captures a push-to-talk shortcut from live keyboard input. Installs BOTH a local and a
/// global NSEvent monitor while recording: the local catches events when the (non-activating)
/// menu-bar panel is key, the global catches them when it isn't — so recording works
/// regardless of focus. A bare key (no modifiers) is rejected since it would fire push-to-talk
/// constantly; esc cancels.
@MainActor
final class PushToTalkShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false

    /// Called on the main thread with the captured shortcut.
    var onCapture: ((RecordedPushToTalkShortcut) -> Void)?

    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    // Peak set of modifiers held during the current recording, used to capture a modifier-only
    // shortcut (e.g. Fn) when the user releases everything without pressing a key.
    private var peakHeldModifiers: NSEvent.ModifierFlags = []

    func startRecording() {
        guard !isRecording else { return }
        peakHeldModifiers = []
        isRecording = true

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            // Consume the event (return nil) when handled, so the keystroke doesn't also act on
            // the UI (e.g. Space scrolling) while recording.
            return self.handle(event) ? nil : event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            // Global monitor can't consume events; just feed it to the same handler.
            _ = self?.handle(event)
        }
    }

    func cancel() {
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        if let globalEventMonitor { NSEvent.removeMonitor(globalEventMonitor) }
        localEventMonitor = nil
        globalEventMonitor = nil
        peakHeldModifiers = []
        isRecording = false
    }

    deinit {
        // Backstop to .onDisappear, which is unreliable for a popover hosted on the
        // non-activating menu-bar panel (dismissed via orderOut): never strand the monitors.
        // A leaked global monitor keeps routing every keystroke through the closure, so remove
        // both tokens here. (isRecording isn't reset — the object is being deallocated, and a
        // nonisolated deinit can't mutate a main-actor @Published anyway; the [weak self]
        // closures already no-op once self is gone.)
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
    }

    /// Returns true if the event was consumed (shortcut captured, esc cancelled, or a bare key
    /// ignored while recording).
    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }

        switch event.type {
        case .keyDown:
            if event.keyCode == 53 { // esc cancels
                cancel()
                return true
            }
            let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !modifierFlags.isEmpty else {
                // A bare key with no modifiers would trigger push-to-talk constantly — reject
                // it and keep listening.
                return true
            }
            finish(with: RecordedPushToTalkShortcut(
                modifierFlagsRawValue: modifierFlags.rawValue,
                keyCode: event.keyCode,
                keyLabel: Self.keyLabel(for: event)
            ))
            return true

        case .flagsChanged:
            let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !modifierFlags.isEmpty {
                peakHeldModifiers.formUnion(modifierFlags)
                return true
            }
            // All modifiers released with no key pressed → a modifier-only shortcut (e.g. Fn).
            if !peakHeldModifiers.isEmpty {
                finish(with: RecordedPushToTalkShortcut(
                    modifierFlagsRawValue: peakHeldModifiers.rawValue,
                    keyCode: nil,
                    keyLabel: nil
                ))
            }
            return true

        default:
            return false
        }
    }

    private func finish(with shortcut: RecordedPushToTalkShortcut) {
        cancel()
        onCapture?(shortcut)
    }

    private static func keyLabel(for event: NSEvent) -> String {
        if event.keyCode == BuddyPushToTalkShortcut.pushToTalkKeyCode { return "space" }
        if let characters = event.charactersIgnoringModifiers,
           !characters.isEmpty,
           characters != " " {
            return characters.uppercased()
        }
        return "key \(event.keyCode)"
    }
}
