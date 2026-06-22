# Changelog

## [Unreleased] — Opus Upgrade (Linear epics OC-1…OC-5)

### E1 — Stabilize: make it build & the providers actually work (epic OC-1)

Fixes the multi-provider fork so the app compiles, fresh installs are safe, and
every backend works. Grounded in the Codex adversarial review + the assessment workflow.

- **OC-13 — Fixed the build break.** Removed the dangling `_ = claudeAPI` in
  `CompanionManager.start()` (the refactor moved `ClaudeAPI` into `AnthropicProvider`,
  leaving an undefined symbol that prevented compilation). TLS warmup already runs in
  each provider's initializer. (`CompanionManager.swift`)
- **OC-14 — Fixed the OpenClaw provider.** It pointed at the agent *session* endpoint
  (`/api/sessions/main/messages`), which the shared OpenAI parser can't read, so it
  silently returned empty text. Now targets `/v1/chat/completions`. (`ProviderManager.swift`)
- **OC-15 — Safe fresh-install behavior.** Default provider is now `workerProxy` instead
  of a keyless direct OpenRouter call. Added `isActiveProviderConfigured`; the app no
  longer captures screens or fires a request until the active provider is configured,
  speaking a "set me up in Settings" hint instead. (`ProviderConfiguration.swift`,
  `CompanionManager.swift`)
- **OC-17 — Per-provider model selection.** `selectedModelID` is stored per provider, so
  switching backends never carries an incompatible model id across the boundary. Each
  provider has its own `defaultModelID`. (`ProviderConfiguration.swift`)
- **OC-21 — App Transport Security + endpoint validation.** Added `NSAppTransportSecurity`
  permitting cleartext only to loopback/`.local`; remote endpoints must use HTTPS. Settings
  validates the OpenClaw endpoint and Worker URL schemes with an inline warning.
  (`Info.plist`, `SettingsView.swift`)
- **OC-25 — Single source of truth for the Worker URL.** `ProviderConfiguration.workerBaseURLFromDefaults`
  is now read by TTS and the AssemblyAI token fetch, so the Settings "Worker URL" reaches
  chat, TTS, and transcription. Removed triplicated placeholder constants.
  (`ProviderConfiguration.swift`, `CompanionManager.swift`, `AssemblyAIStreamingTranscriptionProvider.swift`)
- **OC-29 — Removed the dead `/chat-openrouter` Worker route** and its `OPENROUTER_API_KEY`
  secret (an unauthenticated, secret-backed spend path the app never called; OpenRouter is
  BYO-key client-side). (`worker/src/index.ts`)
- **OC-35 — No force-unwrapped URLs.** Provider endpoints are built via a `sanitizedURL`
  helper returning an `UnconfiguredProvider` (clear error) instead of crashing on malformed
  Settings input; the AssemblyAI token URL is likewise guarded. (`ProviderManager.swift`,
  `AssemblyAIStreamingTranscriptionProvider.swift`)
- **OC-39 — Overlay teardown safety.** The welcome-text timer is tracked and cancelled on
  `.onDisappear`, and an `isViewTornDown` flag guards the welcome / pointing-hold /
  bubble-stream `asyncAfter` chains so a torn-down overlay can't keep mutating shared state.
  (`OverlayWindow.swift`)
- **OC-42 — Audio-tap data race.** The real-time audio tap captures its transcription
  session strongly at install time instead of reading the `@MainActor`
  `activeTranscriptionSession` from the audio render thread. (`BuddyDictationManager.swift`)
- **OC-45 — Triage of remaining confirmed findings.** Critical/high confirmed findings
  above are resolved; lower-severity items are tracked for follow-up.

> Build note: this target is built in Xcode (terminal `xcodebuild` is disallowed — it
> invalidates TCC permissions). Changes are reasoned + statically reviewed (CodeRabbit +
> Codex adversarial review); a clean Xcode build is the final gate.

## [Unreleased] - OpenRouter + OpenClaw Integration

### Added
- `LLMProvider.swift` — Protocol abstraction for LLM backends
- `OpenAICompatibleProvider.swift` — Unified streaming client for OpenRouter and OpenClaw (OpenAI chat completions format)
- `AnthropicProvider.swift` — Wrapper around existing ClaudeAPI for Worker Proxy mode
- `KeychainManager.swift` — Secure API key storage via macOS Keychain
- `ProviderConfiguration.swift` — Configuration model with UserDefaults + Keychain persistence
- `ProviderManager.swift` — Factory that instantiates the correct provider based on user settings

- `SettingsView.swift` — Settings UI for provider selection, API key entry, endpoint config, and connection testing
- Worker `POST /chat-openrouter` route — proxies to OpenRouter API with server-side key injection

### Changed
- `CompanionManager.swift` — Migrated from direct `ClaudeAPI` usage to `ProviderManager.currentProvider` calls. Model selection now delegates to `ProviderManager`.
- `CompanionPanelView.swift` — Model picker now shows provider-aware presets (Sonnet/Opus/Gemini for OpenRouter, etc.) plus custom model ID text field. Added settings gear button in footer with popover.
- `worker/src/index.ts` — Added `OPENROUTER_API_KEY` to Env interface, new `/chat-openrouter` route.

- `ModelCatalogService.swift` — Fetches, caches, and filters models from OpenRouter's `/api/v1/models` endpoint. Groups by provider, supports vision-only filtering.
- `VoiceProvider.swift` — Protocol stubs (`TTSProvider`, `STTProvider`) for future local TTS/STT (Whisper, Qwen3)

### Notes
- `ElementLocationDetector.swift` is defined but not currently called from the active codebase — no changes needed for now.
- `ClaudeAPI.swift` is preserved unchanged as the backend for `AnthropicProvider` (Worker Proxy mode).
