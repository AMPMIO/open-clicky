# Changelog

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

### Planned (In Progress)
- ModelCatalogService for dynamic OpenRouter model list
- ElementLocationDetector graceful fallback for non-Anthropic providers
- Voice provider protocols (future local TTS/STT)
