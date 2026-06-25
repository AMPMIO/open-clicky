# Changelog

## [Unreleased] — Wave 2: Fix, Speed, Parity & Differentiation (G1–G8)

> The core loop works on-device (right-⌘ push-to-talk → screenshot → Qwen3-VL via OpenRouter →
> spoken answer + pointing). Wave 2 fixes the rough edges, adds speed + Settings parity vs the
> commercial HeyClicky, and adds differentiators. Branch `feature/opus-features-f1-f7`; CI
> `build-check` is the compile gate (terminal `xcodebuild` is disallowed). "Shipped" = merged to
> the branch + CI green; on-device Xcode run is the final gate.

### G1 — Fix the core experience ✅ (shipped)

- **Right-⌘ push-to-talk + double-tap latch.** Switched the global shortcut to the right Command
  key (the user's NuPhy Fn emits no hardware event), detected via the raw device bit. Double-
  tapping right-⌘ latches recording on (hold-to-talk → tap-to-stop), hold-vs-tap disambiguated.
  Removed the keystroke-logging diagnostics (security). (`GlobalPushToTalkShortcutMonitor.swift`,
  `BuddyDictationManager.swift`, `CompanionManager.swift`)
- **Hands-On Mode actuates.** Added few-shot `[ACT:press:x,y:label:screenN]` examples to the
  system prompt and re-anchored `parseActionTag` to tolerate trailing punctuation while still
  forcing the tag last; narrowed the destructive-action denylist so common buttons (close/quit)
  aren't blocked; added `ClickyTelemetry.handsOn` diagnostics. (`CompanionManager.swift`)
- **Short utterances no longer silently dropped.** The empty-final-transcript guard now logs +
  surfaces feedback instead of dropping; latch/deferred-stop timing hardened per adversarial
  review. (Root cause fully addressed by G2's on-device STT default.) (`BuddyDictationManager.swift`)
- Hardened per an adversarial review pass. (commits bd5d603, 85e8fb3, 460f93d)

### G2 — Speed: on-device STT + configurable TTS ✅ (shipped)

- **G2.1 On-device STT default.** Apple Speech is now the default transcription provider so a
  short push-to-talk hold ("go") isn't lost to the cloud session-start race. Added
  `cancelsOnQuickReleaseDuringSessionStart` (cloud cancels a release during connect; on-device
  keeps the capture) and a UserDefaults-first provider choice (Info.plist as fallback).
  (`BuddyTranscriptionProvider.swift`, `AppleSpeechTranscriptionProvider.swift`, `BuddyDictationManager.swift`)
- **G2.2 Configurable TTS layer.** New `TTSProvider` protocol + `TTSProviderManager` with
  ElevenLabs (default), OpenAI TTS (new Worker `/tts-openai` route, server-held key), and
  on-device `AVSpeechSynthesizer` backends. Per-provider voice selection, tap-to-preview,
  per-request ElevenLabs voice id, fail-closed when a network provider has no Worker route.
  (`TTSProvider.swift`, `TTSProviderManager.swift`, `OpenAITTSClient.swift`, `SystemVoiceTTSClient.swift`,
  `ElevenLabsTTSClient.swift`, `worker/src/index.ts`, `SettingsView.swift`) (commit 44e03f8)
- **G2 adversarial review fixes.** `/tts-openai`: input char cap (→413) + 30s `AbortController`
  timeout + clear 500 when `OPENAI_API_KEY` is unset (no more `Bearer undefined`). SystemVoice
  `isPlaying` now tracked via the synth delegate (with an `ObjectIdentifier` guard) so the
  overlay-hide / macro-wait loops don't exit before audio plays. (commit 12fe167) Three
  pre-existing legacy-`NSSpeechSynthesizer` findings deferred to **OC-110** (fix after G8 merges).

### G4 — On-screen surface: Hub / Dock ✅ (shipped)

- **Persistent surface.** `SurfacePanelManager` adds an always-visible, borderless, non-activating,
  all-Spaces panel in two presentations switchable in Settings (Off / **Hub** / Dock): a corner
  dashboard (configurable corner, liquid-glass via `.ultraThinMaterial`, hover-to-reveal pill↔card)
  and a notch Dock. `sharingType = .none`. (`SurfacePanelManager.swift`, `SettingsView.swift`,
  `CompanionManager.swift`) (commit 3150919)

### G5 — Agents panel ✅ (shipped)

- **Run model + panel.** `AgentRunManager` (`@Published runs` capped at 20; stages
  starting/processing/awaiting-confirmation/executing/complete/failed) and `AgentsPanel` cards
  (title + agent + stage dot, expandable log), surfaced live in the Hub. (`AgentRunManager.swift`,
  `AgentsPanel.swift`, `SurfacePanelManager.swift`, `CompanionManager.swift`) (commits fe46714, 71bd414)

### G3 — Settings parity ✅ (voice + mic pickers + shortcut recorder; shipped)

- **G3.3 voice picker + preview (OC-108).** Settings grid of voices for the active TTS provider
  with tap-to-audition (`previewVoice`, persist-before-preview), checkmark selection, pointer
  cursors, empty-state. `setSelectedVoiceID` now sends `objectWillChange` so the selection repaints.
  (`SettingsView.swift`, `TTSProviderManager.swift`)
- **G3.2 mic picker + test meter (OC-109).** Microphone input picker (CoreAudio enumeration,
  device UID persisted) + a "test mic" level meter sharing the single `audioEngine` (mutually
  exclusive with dictation). Adversarial-review fixes: uninitialize the input AU before setting
  `kAudioOutputUnitProperty_CurrentDevice` (so switching works past session 1), rebind to the
  system default input when a saved device is absent (guarded by `hasBoundCustomInputDevice` so the
  default-mic flow stays an untouched no-op), re-enumerate on test-toggle. **On-device validation
  pending** for the custom-mic AVAudioEngine re-init path. (`SettingsView.swift`,
  `BuddyDictationManager.swift`) (merged in 2fb80a8)

- **G3.1 user-configurable PTT shortcut recorder (OC-104).** Record-your-own hotkey in Settings
  (record control + Reset, local+global NSEvent capture), persisted as `RecordedPushToTalkShortcut`
  JSON, read by the CGEvent-tap matcher + panel display. Default stays right-⌘; non-blocking caution
  on lone-modifier shortcuts. Review fixes: modifier-drop release for key+modifier, masked-equality
  for modifier-only, deinit monitor cleanup. (`SettingsView.swift`, `BuddyDictationManager.swift`)
  (merged in b529f78)

### In progress

- **G8 — Circle-to-point reference gesture (OC-107, OC1).** Hold PTT + circle a screen region to
  ask "what's *this*?"; the overlay captures the gesture and sends the annotated screenshot.
  CI-green; applying 6 adversarial-review fixes (incl. the mouse-capture-freeze guard) before merge.
- **G7 — Onboarding & polish (OC2).** Example prompts + "Open Agent" affordance + DS polish.

### Filed for later

- **OC-105** — multi-monitor cursor/overlay doesn't follow onto a secondary display.
- **OC-106** — `[POINT]`/`[ACT]` coordinates land off-target (proposed Accessibility-snapping fix).
- **OC-110** — unify the legacy `NSSpeechSynthesizer` into TTS stop/state (G2 review follow-up).

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

### F7 — Terminal Agent Bridge (epic OC-12)

Voice → dispatch a request into a running terminal coding agent (e.g. a Claude Code session). Builds on F1's confirm-before-act pattern.

- **OC-62 — Terminal targeting.** New `TerminalAgentBridge` finds a running, supported terminal
  (Terminal / iTerm / Ghostty), preferring the frontmost one. (`TerminalAgentBridge.swift` new)
- **OC-65 — `[RUN:prompt]` intent + confirm + injection.** The model composes the prompt; Clicky
  asks for spoken confirmation, then activates the terminal and pastes the prompt + Return via the
  pasteboard + System Events (restoring the user's clipboard after). `parseRunTag` +
  `resolveTerminalConfirmation` in CompanionManager; opt-in toggle (`isTerminalBridgeEnabled`).
  (`CompanionManager.swift`, `SettingsView.swift`, `Info.plist` Apple Events usage)
- **OC-68 — Status read-back (best-effort).** `readVisibleText(from:)` scrapes the focused
  terminal's AX value when available. (`TerminalAgentBridge.swift`)

### Action-safety hardening — Codex F1 review follow-ups (OC-82–85, hardens F1 + F7)

- **OC-82 — Exact-phrase confirmation grammar.** Replaced substring matching (which let
  "okay, what will you click?" fire an action) with a normalized exact-phrase
  `confirmationVerdict`; anything ambiguous never executes. (`CompanionManager.swift`)
- **OC-83 — Kill switch cancels pending actions.** Turning Hands-On / Terminal Bridge off now
  clears any pending action, and the resolvers refuse to act when the feature is off.
- **OC-84 — Runtime destructive-action denylist.** `isDestructiveActionLabel` blocks queuing a
  click whose label looks destructive (delete/send/pay/quit/…), regardless of the prompt — it
  points + warns instead.
- **OC-85 — Stale-action revalidation (TOCTOU).** Pending clicks capture the frontmost app +
  timestamp and are refused at execution if the app changed or the proposal is stale (>30s;
  terminal dispatch >60s).
- **OC-86 — Terminal dispatch fails closed to the frontmost terminal (Codex F7).**
  `targetTerminal()` only returns the frontmost supported terminal (no fallback), and
  `sendPrompt` re-verifies it's still frontmost immediately before pasting — so a prompt can't
  land in a background shell/SSH/tab. (`TerminalAgentBridge.swift`)
- **OC-87 — Transactional clipboard restore (Codex F7).** Restore is gated on
  `pasteboard.changeCount` (never clobbers what the user copied during the paste window) and
  always clears our prompt even when the original clipboard was empty (no leak).
  (`TerminalAgentBridge.swift`)

### F2 — Screen Memory (epic OC-7)

On-device, opt-in recall of what Clicky has seen — answer "what was that … earlier?" by voice.

- **OC-43 — Encrypted local store.** New `ScreenMemoryStore` persists each turn (cursor
  screenshot + transcript + reply) under Application Support, encrypted with AES-GCM (CryptoKit)
  using a Keychain-held key; capped at 500 entries. (`ScreenMemoryStore.swift` new)
- **OC-48 — On-device OCR + embeddings.** Vision `VNRecognizeTextRequest` OCRs each screenshot
  and `NLEmbedding` embeds transcript+OCR for semantic recall (keyword-overlap fallback). All local.
- **OC-51 — Voice recall → inject.** A recall-style question (`isRecallQuery`) retrieves the
  top-k past moments by cosine similarity and injects their screenshots as extra vision context.
  (`CompanionManager.swift`) *(Pointing back at a past-moment thumbnail is a follow-up.)*
- **OC-54 — Privacy controls.** Off by default; Settings toggle, per-app exclude list, pause,
  and a one-tap purge of all saved moments. (`SettingsView.swift`, `ScreenMemoryStore.swift`)

#### F2 privacy hardening — Codex review follow-ups (OC-88–91)

- **OC-88 — Recall relevance threshold.** Past screenshots are only injected above a similarity
  threshold, so an ordinary current-screen question can't attach unrelated old screens.
- **OC-89 — In-flight recording respects controls.** A generation token captured at record time
  is re-validated (plus enabled/paused) before persisting, so a disable/pause/purge cancels
  recordings still mid-OCR. (`ScreenMemoryStore.swift`)
- **OC-90 — Pause + per-app exclude UI.** The Settings section now actually exposes a pause
  toggle and an add-app-to-exclude control with the current exclude list. (`SettingsView.swift`)
- **OC-91 — Persistence fails closed + sweeps orphans.** If the Keychain key can't be persisted,
  nothing is written (no undecryptable data); orphaned `.enc` images are swept on launch.

Lets Clicky hear what's playing on the Mac (a call, tutorial, video) AND see the screen.

- **OC-50 — System-audio capture.** New `SystemAudioCaptureService` uses ScreenCaptureKit
  (`SCStreamConfiguration.capturesAudio`, excludes Clicky's own output) to capture system audio,
  converting CMSampleBuffers to PCM16 mono. Bot-free, no kernel extension. (`SystemAudioCaptureService.swift` new)
- **OC-53 — Transcription.** On-demand one-shot transcription of the buffered audio via OpenAI
  Whisper (reuses the `OpenAIAPIKey`), building a WAV with the existing `BuddyWAVFileBuilder`.
- **OC-58 / OC-61 — Fusion + summary.** When Live Companion is on, a rolling ~3-min audio buffer
  is transcribed and folded into the prompt alongside the screenshots, so "what did they just
  ask?" / "summarize the last few minutes" work. (`CompanionManager.swift`)
- Opt-in toggle in Settings (off by default; needs Screen Recording + a Worker with
  `OPENAI_API_KEY`). (`SettingsView.swift`)

#### F4 security/privacy hardening — Codex review follow-ups (OC-92–94)

- **OC-92 (critical) — System audio stays within the proxy.** Transcription no longer posts
  straight to OpenAI with an on-device key; the app uploads the WAV to a new Worker
  `/transcribe-audio` route that holds the OpenAI key server-side. (`worker/src/index.ts`,
  `SystemAudioCaptureService.swift`)
- **OC-93 — Ambient audio is untrusted.** The transcript is wrapped in a delimited UNTRUSTED
  block and a system instruction forbids treating it as the user's request or letting it trigger
  Hands-On/Terminal actions. (`CompanionManager.swift`)
- **OC-94 — Capture lifecycle.** Disabling mid-startup now stops the stream, late callbacks are
  dropped once disabled, and a failed start rolls the toggle back. (`CompanionManager.swift`)
- **OC-95 — Robust audio conversion (AVAudioConverter)** is tracked as a follow-up.

### F3 — Watch Mode (epic OC-8)

Opt-in, quiet, proactive nudges — Clicky watches the screen and occasionally offers a brief
heads-up (e.g. explaining an error). Off by default.

- **OC-47 — Change-detection gate.** A debounced poll (every 12s) computes a perceptual
  average-hash (8×8 grayscale) of the cursor screen and skips static screens by Hamming distance.
  *(ponytail: a poll + aHash gate instead of a continuous low-fps SCStream — same "ignore static
  screens" outcome, far less machinery.)* (`WatchModeSupport.swift` new)
- **OC-52 — Cheap first-pass gate.** Before escalating to the vision model, a fast Vision OCR pass
  checks for actionable keywords (error/failed/exception/…), so the full model is only invoked
  when something useful is likely on screen.
- **OC-55 — Proactive surfacing.** A confirmed nudge is spoken via the existing transient-cursor +
  system-voice path (`speakSystemMessage`) — quiet, no popup. (`CompanionManager.swift`)
- **OC-57 — Guardrails.** Off by default, rate-limited (≥90s between nudges), only runs while idle
  and with a ready provider, and never points/acts in this mode. Settings toggle. (`SettingsView.swift`)

#### F3 hardening — Codex review follow-ups (OC-99–100)

- **OC-99 — Cancellable, single-flight ticks.** The watch tick is a tracked task (one at a time),
  cancelled on disable/stop/push-to-talk, and re-checks enabled/idle/cancelled around every await;
  a per-escalation backoff (≥30s) caps provider calls regardless of NUDGE/NONE.
- **OC-100 — No baseline blind spot.** The analyzed-frame hash updates only when a frame is
  actually escalated, so a persistent error appearing during the cooldown isn't mistaken for a
  static screen afterward. (`CompanionManager.swift`)

### F5 — Spoken Macros (epic OC-10)

Record a named workflow by voice and replay it later — built on F1's actuation.

- **OC-56 / OC-59 — Record + store.** "record a macro called <name>" starts recording; each
  following utterance becomes a step; "save macro" stores it. Named macros persist via
  `SpokenMacroStore`. (`SpokenMacroStore.swift` new)
- **OC-64 — Replay.** "run macro <name>" replays each step through the normal companion pipeline
  in order, so every step re-resolves against the LIVE screen (point/act), with Hands-On
  confirmation still gating any action. *(ponytail: plain-instruction steps, not recorded AX
  events — robust to layout changes.)* (`CompanionManager.swift`)
- **OC-66 — Manage.** By voice: run / delete / list; Settings lists saved macros with a delete
  button. (`SettingsView.swift`)

#### F5 hardening — Codex review follow-ups (OC-101–102)

- **OC-101 — Replay isolation + real completion.** Replays carry a UUID identity (a late-cancelled
  replay can't clear a newer one's state) and each step now awaits its actual pipeline completion
  before advancing, instead of inferring it from timers.
- **OC-102 — Confirmed deletion.** "delete macro" checks the macro exists, then requires a yes/no
  voice confirmation before deleting — a misheard command can't destroy a saved workflow.
  (`CompanionManager.swift`)

### F6 — Sign in with ChatGPT (OAuth) (epic OC-11)

- **OC-60 — Feasibility spike (go/no-go).** Riding a ChatGPT *subscription* from a third-party
  app requires reusing a first-party client's OAuth credentials (the ones Codex CLI uses), which
  OpenAI does not sanction for third-party use. Conclusion: **no-go on impersonation** — ship a
  generic BYO-OAuth-app flow instead. Honest limit: yields OpenAI-compatible models, **not
  Anthropic Opus** (Anthropic blocks subscription-based third-party access).
- **OC-63 — OAuth 2.0 + PKCE sign-in.** New `OAuthSignInManager` runs the authorization-code +
  PKCE flow via the native `ASWebAuthenticationSession`, stores access/refresh tokens in the
  Keychain, and auto-refreshes near expiry. No credentials are hardcoded. (`OAuthSignInManager.swift` new)
- **OC-67 — Provider wiring + fallback.** When signed in, the OAuth access token becomes the
  Bearer for the active OpenAI-compatible provider (OpenRouter/OpenClaw/Hermes), falling back to
  the pasted API key when signed out. Settings adds a sign-in section (client id + endpoints +
  scopes). (`ProviderManager.swift`, `ProviderConfiguration.swift`, `SettingsView.swift`)

#### F6 hardening — Codex review follow-ups (OC-96–98)

- **OC-96 (critical) — Scoped token.** The OAuth bearer is bound to the provider active at
  sign-in and only used for that provider, so it can never be sent to a different provider's
  endpoint (credential-leak fix).
- **OC-97 — No stale tokens.** An expired stored token is treated as absent (so the pasted API
  key is used) and a background refresh is kicked off.
- **OC-98 — Flow hardening.** Adds a session-bound `state` (verified on callback) + OAuth `error`
  handling, checks `ASWebAuthenticationSession.start()` (resumes with an error instead of
  hanging), and registers the `openclicky://` callback scheme. (`OAuthSignInManager.swift`,
  `ProviderManager.swift`, `ProviderConfiguration.swift`, `Info.plist`)

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
