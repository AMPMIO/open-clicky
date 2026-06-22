# Changelog

## [Unreleased] — Feature wave (F1–F7, Linear epics OC-6…OC-12)

> These are net-new features that lean on Accessibility actuation, system audio, OAuth, and
> terminal automation — authored + statically reviewed (CodeRabbit + Codex) but pending an
> on-device Xcode build/run (no terminal `xcodebuild`). Treat as first implementations.

### F1 — Hands-On Mode (epic OC-6)

Upgrades the companion from pointing-only to optionally *doing* a step, gated by explicit voice confirmation.

- **OC-33 — Accessibility actuation layer.** New `AccessibilityActuator` resolves a global
  screen point to an `AXUIElement` (`AXUIElementCopyElementAtPosition`) and performs
  `kAXPressAction` / `AXValue` set, with an AppKit→Quartz (bottom-left→top-left) coordinate
  conversion and an `AXIsProcessTrusted` permission gate. (`AccessibilityActuator.swift` new)
- **OC-38 — `[ACT:press:x,y:label[:screenN]]` protocol + parser.** `CompanionManager.parseActionTag`
  mirrors the POINT parser; a shared `appKitGlobalLocation(forScreenshotCoordinate:in:)` helper
  maps screenshot pixels → AppKit global for both pointing and actuation. (`CompanionManager.swift`)
- **OC-40 — Confirm-before-act + cancel.** When the model proposes an action, Clicky points at
  the target and asks for confirmation; the next utterance executes it (affirmation), cancels it
  (negation), or is treated as a fresh request. The press only runs after explicit confirmation.
  (`CompanionManager.swift`)
- **OC-44 — Guardrails.** Opt-in toggle (`isHandsOnModeEnabled`, off by default — the kill
  switch) surfaced in Settings; requires Accessibility permission; the system prompt forbids
  proposing destructive/irreversible actions (delete/send/pay/quit). (`CompanionManager.swift`,
  `SettingsView.swift`, `CompanionPanelView.swift`)

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

### E2 — Cleanup / de-bloat (epic OC-2)

Removed scaffolding-ahead-of-need surfaced by the ponytail audit (~415 lines).

- **OC-16 — Deleted dead files:** `VoiceProvider.swift` (unused TTS/STT protocol stubs,
  zero conformers), `ModelCatalogService.swift` (never referenced; the picker uses
  hardcoded presets), and `OpenAIAPI.swift` (pre-existing unused vision client). The
  Xcode project uses file-system-synchronized groups, so no `project.pbxproj` edits were
  needed.
- **OC-19 — Removed the never-thrown `ProviderError.missingAPIKey`** case (superseded by
  `notConfigured`). (`OpenAICompatibleProvider.swift`)
- **OC-22 — Dropped the non-streaming `chat()` path.** It existed only to power the
  Settings "Test Connection" button; that now calls `chatStreaming` with an empty chunk
  handler. Removed `chat()` from the `LLMProvider` protocol, `OpenAICompatibleProvider`,
  `AnthropicProvider`, and `UnconfiguredProvider`. (`LLMProvider.swift`, `SettingsView.swift`, et al.)
- **OC-27 — Extracted a single `TLSWarmer` helper.** The per-host TLS-warmup-via-HEAD
  pattern was duplicated in `ClaudeAPI` and `OpenAICompatibleProvider`; both now call
  `TLSWarmer.warm(_:using:)`. (`TLSWarmer.swift` new, `ClaudeAPI.swift`, `OpenAICompatibleProvider.swift`)
- **OC-31 — Collapsed `setSelectedModel` forwarding** to a single path
  (`CompanionManager.setSelectedModel`); removed the redundant `ProviderManager`
  pass-through. (`CompanionManager.swift`, `ProviderManager.swift`)
- **OC-34 — Updated the CLAUDE.md/AGENTS.md Key Files table** to add the multi-provider
  layer (LLMProvider, ProviderManager, ProviderConfiguration, AnthropicProvider,
  OpenAICompatibleProvider, KeychainManager, SettingsView, TLSWarmer) and drop the deleted
  `OpenAIAPI.swift`.

### E1 hardening — Codex adversarial review follow-ups (OC-69, OC-70, OC-71)

- **OC-69 — Aligned provider readiness with the factory.** Replaced
  `ProviderConfiguration.isActiveProviderConfigured` with `ProviderManager.isCurrentProviderReady`
  (`!(currentProvider is UnconfiguredProvider)`), so readiness can't drift from what
  `buildProvider` produces: blank OpenClaw (→ localhost default) is allowed, while a
  malformed / remote-http endpoint blocks screen capture. (`ProviderManager.swift`,
  `ProviderConfiguration.swift`, `CompanionManager.swift`)
- **OC-70 — Centralized + normalized Worker route URLs.** Added
  `ProviderConfiguration.workerRouteURLString(_:)` (trailing-slash safe), used by TTS and
  transcription; `ElevenLabsTTSClient.updateProxyURL` refreshes the endpoint before each
  speak so it tracks Settings changes without a restart (no more stale/placeholder URL or
  `//tts`). (`ProviderConfiguration.swift`, `ElevenLabsTTSClient.swift`, `CompanionManager.swift`,
  `AssemblyAIStreamingTranscriptionProvider.swift`)
- **OC-71 — Audio-tap failure cleanup.** If `AVAudioEngine.start()` throws after the tap +
  session are installed, the tap is removed and the just-opened session cancelled before
  rethrowing, so a failed start can't leak a retained transcription session/websocket.
  (`BuddyDictationManager.swift`)

### E3 — Close the HeyClicky gap (epic OC-3)

- **OC-18 — App-specific tutoring.** The live system prompt now appends an
  `activeAppGuidanceAddendum()` derived from the frontmost app (Figma, DaVinci, FL Studio,
  After Effects, Xcode, code editors), so guidance is tailored to what the user is doing.
  (`CompanionManager.swift`)
- **OC-20 — Onboarding copy refresh.** The first-run prompt now nudges an app/screen
  question ("ask me about what's on your screen") instead of a generic "introduce yourself."
  (`CompanionManager.swift`)
- **OC-24 — Pulsing halo** on the pointing cursor (shipped in commit 377e34d).
- **OC-72 — App-context made conditional (Codex follow-up).** The app addendum no longer
  asserts the frontmost app authoritatively (it's a global guess that can desync from the
  captured screen); it's now phrased "only if the screenshot actually shows X … otherwise
  go by what you see," so it can't bias pointing to the wrong app/screen. (`CompanionManager.swift`)

### E4 — Provider foundation refactor (epic OC-4)

- **OC-23 / OC-36 — Provider capability model.** Added `ProviderCapabilities`
  (vision / streaming / reliable-pointing) and `APIProviderType.capabilities`, exposed via
  `ProviderManager.currentProviderCapabilities`. Agent backends (OpenClaw/Hermes) report
  `reliablyEmitsPointTags = false` since pointing depends on the underlying model. Settings
  shows a per-provider capability hint. (`LLMProvider.swift`, `ProviderConfiguration.swift`,
  `ProviderManager.swift`, `SettingsView.swift`)
- **OC-26 — Hardened the shared OpenAI-compatible client.** SSE parsing now accepts
  `data:{...}` (no space), skips comments/keep-alives/blank lines, and trims payloads
  before decoding. (`OpenAICompatibleProvider.swift`)
- **OC-30 — Reusable agent-endpoint Settings component.** Extracted
  `AgentEndpointSettingsView` (endpoint + scheme validation + bearer token) from the
  OpenClaw section so OpenClaw and Hermes share one UI. (`SettingsView.swift`)
- **OC-73 — SSE parser fails loudly (Codex follow-up).** `chatStreaming` now surfaces
  streamed `error` frames as `apiError` and throws `invalidResponseFormat` when a stream
  produces no recognizable content and never sends `[DONE]`, instead of reporting empty
  "success" on an errored/non-OpenAI stream. (`OpenAICompatibleProvider.swift`)
- **OC-74 — Model-aware capabilities (deferred).** Capabilities are currently provider-level;
  making them resolve from the selected model (and gating capture on confirmed vision) is
  tracked as a follow-up.

### E5 — Hermes (Nous Research Hermes Agent) integration (epic OC-5) [headline]

Route work to the user's own Nous Hermes Agent instead of a hosted LLM, closing the
agent-mode gap vs the commercial HeyClicky using the user's own agent.

- **OC-28 — `.hermes` provider.** A `.hermes` `APIProviderType` that reuses
  `OpenAICompatibleProvider` against `<endpoint>/v1/chat/completions` with model `hermes-agent`
  — same `image_url` vision + `choices[].delta.content` SSE path as OpenRouter/OpenClaw.
  (`ProviderConfiguration.swift`, `ProviderManager.swift`)
- **OC-32 — Pluggable deployment.** Hermes endpoint (default `http://localhost:8642`) in
  UserDefaults + token in Keychain; blank endpoint falls back to localhost; remote endpoints
  must use HTTPS (E1 ATS). Settings fields via the shared `AgentEndpointSettingsView`. Covers
  local / self-hosted VPS / subscription. (`ProviderConfiguration.swift`, `ProviderManager.swift`, `SettingsView.swift`)
- **OC-37 — Readiness Check.** A Settings diagnostic that probes the live instance and
  reports the three integration risks: vision request accepted, `[POINT:]` tags preserved,
  and whether the incoming system prompt is honored. (`SettingsView.swift`)
- **OC-41 — Mode A (answer + point).** Hermes runs through the existing
  voice→screenshot→stream→TTS→POINT pipeline unchanged (the full system prompt incl. POINT
  instructions is sent), so it answers and points like the Claude path once selected.
- **OC-49 — Settings UI + mode toggle + docs.** Hermes section with endpoint/token, a
  computer-use mode toggle, the Readiness Check, and an in-UI note about action mode.
- **OC-46 — Mode B (computer-use): scaffolded, actuation deferred.** The opt-in toggle +
  `hermesActionModeEnabled` flag are wired, but performing on-screen actions requires the
  Hands-On actuation layer (F1 / OC-6), which is a later wave — so action mode currently
  falls back to answer+point and the UI says so. **OC-46 stays open, blocked on F1.**

### E5 hardening — Codex adversarial review follow-ups (OC-76–79)

- **OC-76 — Agent backends require an explicit token (security).** A blank Hermes/OpenClaw
  config no longer builds a "ready" provider — `buildProvider` returns `UnconfiguredProvider`
  unless a bearer token is set, so the voice pipeline can't capture screens and POST them to
  whatever process binds the default local port. (`ProviderManager.swift`)
- **OC-77 — Cleartext only for true loopback (security).** Dropped `.local` from the http
  allowlist in both `ProviderManager.sanitizedURL` and `SettingsView` validation — `.local`
  can resolve to another LAN machine, so it (and any non-loopback host) must use https or the
  bearer token + screenshots would go in plaintext. (`ProviderManager.swift`, `SettingsView.swift`)
- **OC-78 — Honest Hermes readiness check.** The probe now parses the reply with the same
  `CompanionManager.parsePointingCoordinates` Mode A uses (requiring a real coordinate),
  requires the exact diagnostic token, and labels the vision line honestly. (`SettingsView.swift`)
- **OC-79 — SSE requires content for success.** `chatStreaming` now requires at least one
  parsed content chunk; a bare `[DONE]` / contentless stream throws `invalidResponseFormat`
  instead of reporting empty success. (`OpenAICompatibleProvider.swift`)
- **OC-80 — Centralized cleartext policy across ALL Worker routes (security).** The
  loopback-only-cleartext rule was only on the chat path; TTS + transcription built URLs by
  raw concatenation. Now there's one `ProviderConfiguration.validatedURL` policy used by chat
  (`ProviderManager.sanitizedURL`), TTS, and transcription — and TTS/transcription fail closed
  (skip rather than POST) when the Worker URL is non-loopback cleartext or malformed.
  (`ProviderConfiguration.swift`, `ProviderManager.swift`, `CompanionManager.swift`, `AssemblyAIStreamingTranscriptionProvider.swift`)
- **OC-81 — Unconfigured Worker placeholder fails closed (security).** `workerRouteURL` now
  returns nil for the default placeholder URL, so a user who configures OpenRouter/OpenClaw/
  Hermes but leaves the Worker URL unset no longer sends TTS/transcription traffic to the
  placeholder host — chat, TTS, and transcription all treat the placeholder as "no Worker."
  (`ProviderConfiguration.swift`)

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
