# OpenClicky

OpenClicky is a fork of [Clicky](https://github.com/farzaa/clicky) — the AI buddy that lives
next to your cursor, sees your screen, talks to you, and points at things — **rebuilt to run on
any model and on your own agent**, with new hands-on capabilities.

It keeps everything the original does (menu-bar app, push-to-talk, screenshots → vision model,
spoken replies, the blue cursor that flies to `[POINT:x,y]` elements across monitors, Cloudflare
Worker proxy) and adds the upgrades below.

> Status: the multi-provider + Hermes + stabilization work (below) is reviewed and on the
> `feature/opus-upgrade-e1-e5` branch. The new capability features are a follow-up wave on
> `feature/opus-features-f1-f7`. Everything is built for Xcode — run it there (don't
> `xcodebuild` from the terminal; it resets macOS TCC permissions).

## What this fork adds

### 🔌 Bring your own model — multi-provider LLM layer
The original is Claude-only through the Worker. OpenClicky adds a provider abstraction
(`LLMProvider` + `ProviderManager`) with a Settings UI to pick a backend:

- **Worker Proxy** — Claude via the Cloudflare Worker (keys stay server-side, like upstream).
- **OpenRouter** — bring your own key, use essentially any frontier model.
- **OpenClaw** — route to a self-hosted OpenAI-compatible agent.
- **Hermes** — route to your own **[Nous Research Hermes Agent](https://github.com/NousResearch/hermes-agent)** (see below).

Provider credentials live in the macOS Keychain; each provider remembers its own model.

### 🤖 Nous Hermes Agent integration (the headline)
Point OpenClicky at *your own* Hermes agent — local, a self-hosted VPS, or the Nous
subscription — so the thing answering (and, optionally, doing the work) in the background is
**your agent**, not a hosted LLM. It reuses the OpenAI-compatible client (`/v1/chat/completions`,
Bearer token, SSE, image vision), with a **Readiness Check** that verifies vision passthrough,
`[POINT:]`-tag preservation, and system-prompt honoring against your instance.

### 🔒 Security & stabilization
The fork's provider work was hardened via adversarial review:
- Fixed a build break and a broken OpenClaw endpoint; safe fresh-install defaults (no screen
  capture before a provider is configured).
- App Transport Security: cleartext only to true loopback; remote/`.local` agent endpoints must
  use HTTPS — so your token + screenshots never go over plaintext.
- Agent backends require an explicit token before they're "ready"; the Worker's unauthenticated
  spend route was removed; SSE failures surface instead of returning empty "success".

### ✋ New capability features (follow-up wave)
- **Hands-On Mode** — after you confirm by voice, Clicky can *click* an element (macOS
  Accessibility), not just point. Exact-phrase confirmation, a destructive-action denylist, and
  stale-target checks gate every action.
- **Terminal Agent Bridge** — say what you want and Clicky pastes it into your running
  **Claude Code** terminal session (Terminal/iTerm/Ghostty), after you confirm.
- **Screen Memory** — opt-in, on-device, **encrypted** recall: ask "what was that license key I
  saw earlier?" and it answers from past screens (Vision OCR + NLEmbedding, all local).
- **Live Companion** — captures system audio so Clicky can hear a call/tutorial *and* see the
  screen, to answer "what did they just ask?" or summarize the last few minutes.

All new features are **off by default** and opt-in from Settings.

## Get started

The fastest path is still [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — clone
this repo, read `CLAUDE.md`, and have it walk you through the Worker + Xcode setup.

### Prerequisites
- macOS 14.2+ (ScreenCaptureKit), Xcode 15+, Node.js 18+ (for the Worker)
- A [Cloudflare](https://cloudflare.com) account (free tier) for Worker mode, **and/or** just an
  [OpenRouter](https://openrouter.ai) key / a Hermes / OpenClaw endpoint for the other providers
- For voice: [AssemblyAI](https://www.assemblyai.com) (STT) and [ElevenLabs](https://elevenlabs.io) (TTS) keys on the Worker

### 1. Cloudflare Worker (for Worker-proxy mode + voice)
```bash
cd worker
npm install
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY
```
Set the ElevenLabs voice id in `wrangler.toml` under `[vars]`, then `npx wrangler deploy`. It
gives you a URL like `https://your-worker-name.your-subdomain.workers.dev`.

The Worker now serves three routes — `/chat`, `/tts`, `/transcribe-token`. (The old
`/chat-openrouter` route was removed; OpenRouter mode is client-side BYO-key.)

### 2. Open in Xcode and run
```bash
open leanring-buddy.xcodeproj
```
Select the `leanring-buddy` scheme (the typo is intentional/legacy), set your signing team, and
**Cmd + R**. The app lives in the menu bar.

### 3. Configure a provider in Settings
Open the panel → gear icon → **Settings**:
- **Worker Proxy:** paste your Worker URL (it now feeds chat, TTS, and transcription).
- **OpenRouter:** paste your key and pick a model.
- **OpenClaw / Hermes:** paste the endpoint + bearer token (remote endpoints must be HTTPS); run
  the Hermes **Readiness Check** to confirm pointing will work.

### Permissions
- **Microphone** — push-to-talk · **Accessibility** — global shortcut + Hands-On clicking
- **Screen Recording / Screen Content** — screenshots + (Live Companion) system audio
- **Automation** — only if you use the Terminal Agent Bridge

## Architecture
Read `CLAUDE.md` for the full breakdown. Short version: menu-bar app, push-to-talk → screenshot →
the **selected provider** (Claude/OpenRouter/OpenClaw/Hermes) via streaming SSE → ElevenLabs TTS,
with `[POINT:x,y:label:screenN]` tags driving the cursor, and new `[ACT:...]` / `[RUN:...]` tags
driving confirmed actions. See `CHANGELOG.md` for the full list of changes in this fork.

## Project structure
```
leanring-buddy/               # Swift source
  CompanionManager.swift         # Central state machine + pipeline
  LLMProvider / ProviderManager / ProviderConfiguration / *Provider.swift   # Multi-provider layer
  SettingsView.swift             # Provider + feature configuration UI
  AccessibilityActuator.swift    # Hands-On Mode clicking
  TerminalAgentBridge.swift      # Drive a terminal agent by voice
  ScreenMemoryStore.swift        # Encrypted on-device recall
  SystemAudioCaptureService.swift# Live Companion system audio
  OverlayWindow.swift            # Blue cursor overlay
worker/src/index.ts            # Cloudflare Worker proxy (/chat, /tts, /transcribe-token)
CLAUDE.md / CHANGELOG.md       # Architecture doc + change log
```

## Credits
Built on [Clicky](https://github.com/farzaa/clicky) by [@farzatv](https://x.com/farzatv) (MIT).
This fork adds the multi-provider layer, Hermes integration, security hardening, and the new
hands-on features.
