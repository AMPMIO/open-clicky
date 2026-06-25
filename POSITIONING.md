# AskMaus — Positioning & North Star

> **AskMaus** is a macOS companion that lives by your cursor: hold to talk, it sees your screen, points at what matters, and hands the doing to *your own* AI agent.
>
> *Maus is German for mouse — it's your AI mouse companion.*

This document is our north star. It exists to keep us honest about **what makes AskMaus different** as the "AI on your screen" category fills up, and to seed the landing page, marketing, and roadmap. It is a living document — update it as the product and the field move.

---

## 1. The one-liner

**For macOS power users who want AI that *acts*, not just answers — AskMaus is a voice-and-vision companion that points at what you mean and delegates real work to an agent you own.**

Not a chatbot in a box. Not an always-on recorder. A small presence by your cursor that you talk to, that sees what you see, and that can reach into your tools — and your own agent — to get things done.

---

## 2. North Star — what we are actually building

Most "AI on your screen" tools are **answer engines**: you ask about what's on screen, you get text back. That race is commoditizing fast and will be won by whoever bundles it for free (Google).

AskMaus is aiming one layer past that: **the embodiment layer for your own agent.**

- It is the **face** (a companion you talk to, that points and speaks back).
- It is the **eyes** (it sees your actual screen, every monitor, on demand).
- It is the **hands** (it routes "do this for me" to *your* agent — Hermes today, OpenClaw next — which executes on your machine, with your tools wired in).

The further-out vision: **AskMaus is where your personal agent touches your desktop** — reachable from anywhere (talk to your agent on your phone → it acts on your Mac through AskMaus). No competitor is structurally positioned to do this, because they don't separate the agent from the app or let you own either.

---

## 3. Who it's for (and who it isn't)

**For:** macOS power users, developers, privacy-conscious people, and anyone who already runs their own models/agents (OpenRouter, Hermes, OpenClaw, local). People who want to *own* their AI stack, not rent a hosted black box.

**Not for (yet):** the mainstream non-technical user who won't manage an API key — that's HeyClicky's and Google's lane, and we don't try to out-fund them there. Not for Windows/Linux users (macOS-native by design — for now).

This is a wedge, not a TAM grab. We win a defensible niche on depth, then expand.

---

## 4. The core insight

> The category is splitting into **"AI that explains your screen"** (crowded, commoditizing, bundle-bait) and **"AI that does things on your behalf"** (emerging, hard, defensible).
>
> AskMaus is the only product sitting in the **intersection**: voice + vision + *points at things* + *acts via an agent you own* + *pulls live context from your tools*. Nobody else does all of it — and the pieces that make it hard to copy are exactly the pieces we've already built.

---

## 5. Differentiation pillars (the deeper axes)

Beyond the obvious four (voice / vision / points-acts / BYO model), here is the fuller surface where we overlap or pull away from the field:

| # | Axis | The field | AskMaus |
|---|------|-----------|---------|
| 1 | **Spatial output** | Answer in a text capsule (AIPointer), or nothing | A cursor that **flies to and points at** the exact UI element — spatial guidance, not just text |
| 2 | **Presence / personality** | Utilities — a box that appears and vanishes | A **companion with a face** (the maus), a persistent on-screen Hub/Dock, a voice. Emotional, brand-forward, ownable |
| 3 | **Input gesture** | Hotkey + type | Push-to-talk **voice-first** + the **circle-to-point** gesture ("circle a region, ask 'what's this?'") — no analog anywhere |
| 4 | **Action depth** | None → convenience tool-calls (AIPointer's 7) → hosted computer-use (Simular) | Delegates to **your own agent** that runs multi-step tasks, with a live Agents run panel |
| 5 | **Agent sovereignty** | Hosted agent on the vendor's infra | **Your agent, your infra, your model** (Hermes/OpenClaw). No lock-in, no data hand-off |
| 6 | **Integrations / context** | None (pointing tools have zero) | **MCP marketplace** — GitHub/Notion/Linear/Google. Answer "what's this ticket's status?" with *live* data while pointing at it |
| 7 | **Mobile reach** | Desktop-only, full stop | **Reach your desktop agent from your phone** (Telegram → Hermes → acts on your Mac via AskMaus). The unlock no one else can copy |
| 8 | **Privacy posture** | Always-on screen recording (Rewind, Highlight, Invoko, Screenpipe) | **Push-to-talk: it only looks when you ask.** Intentional capture, not ambient surveillance. Keys proxied through *your* Cloudflare Worker |
| 9 | **On-device option** | Cloud STT/TTS | Apple **on-device** STT default + system TTS — works offline, nothing leaves the machine |
| 10 | **Model flexibility** | Hosted-locked (Clicky, Google) | **BYO**: Claude via Worker, OpenRouter/Qwen, your own agent. Swap freely |
| 11 | **Runtime** | Electron (~300MB, AIPointer) | Native **Swift/SwiftUI/AppKit** — fast, light, proper menu-bar citizen, real multi-monitor |
| 12 | **Openness** | Hosted closed (Clicky/Google) or source-available | OSS lineage (Clicky/OpenClicky fork) — extensible via MCP; community-flankable |

The two that "clicked" while writing this — worth treating as first-class:

- **Presence/personality (axis 2):** every competitor is a *tool*. AskMaus can be a *companion* — a little maus that lives by your cursor, points, talks, has a Hub. The name was made for this. "It's not a tool, it's a companion" is a positioning no utility can take from us cheaply.
- **"Only looks when you ask" (axis 8):** as the field drifts toward always-on screen recording, **push-to-talk is a trust feature**, not just an interaction model. We should say it out loud: *AskMaus doesn't watch your screen — it looks when you ask, and the model is yours.*

---

## 6. Competitive landscape

| Product | Category | Platform | Voice | Sees screen | Points / Acts | BYO model | Integrations | Open? | Pricing |
|---|---|---|---|---|---|---|---|---|---|
| **AskMaus** | Voice+vision companion + agent | macOS | ✅ PTT (3 STT) | ✅ full / multi-mon | ✅ points / ✅ acts (your agent) | ✅ | ✅ MCP | OSS lineage | TBD |
| **AIPointer** | Cursor-crop Q&A | Mac/Win/Linux | ✅ | ✅ cursor crop | ❌ / barely | ✅ | ❌ | BSL-1.1 | Free (BYO key) |
| **HeyClicky** | Always-on voice menu-bar | macOS | ✅ always-on | ✅ on demand | ~ / ❌ | ❌ hosted | ❌ | ❌ (forked from MIT Clicky) | $0–64/mo |
| **Google "AI Pointer"** | Gemini cursor assistant | Chrome / Googlebook | ✅ | ✅ cursor region | ❌ | ❌ Gemini | ❌ | ❌ | Bundled |
| **Simular / Sai** | Desktop computer-use agent | macOS (+Win soon) | ❌ | ✅ | ✅✅ acts | ❌ | partial | partial (Agent-S) | enterprise |
| **Screenpipe** | Always-on screen memory + agents | Mac/Win/Linux | ~ | ✅ 24/7 record | ✅ via plugins | ✅ | MCP | ✅ 19k★ | $25–50/mo |
| **Highlight / Invoko** | Screen-aware Q&A | Mac (+Win) | ~ | ✅ always-on | ❌ | ❌ | some | ❌ | ~$20–49/mo |
| **Cluely** | Stealth meeting/interview overlay | Mac/Win | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | $20–149/mo |
| **Rewind / Limitless** | Screen + meeting memory | macOS (+wearable) | ✅ | ✅ passive | ❌ | ❌ | ❌ | ❌ | ~$20/mo |
| **Cursor** | AI code editor (adjacent) | Mac/Win/Linux | ❌ | ✅ code only | ✅ code edits | ✅ | ❌ | ❌ | $0–40/mo |

*(Funding/figures — e.g. HeyClicky's a16z raise, Simular's ~$21.5M, Google's May-2026 launch — came from a web sweep and are directionally right; verify before quoting publicly.)*

### The three competitors that actually matter

- **Google DeepMind "AI Pointer"** (the existential one): Gemini-powered, captures a region around the cursor, *bundled* into Chrome/Googlebook. No indie out-distributes a free OS/browser feature. **Our answer:** Google structurally can't offer BYO-model, privacy-by-PTT, or *your own agent acting on your desktop*. We win on what their data model forbids.
- **HeyClicky** (the direct rival): a16z-backed, hosted always-on voice, polished, aimed at the mainstream at $20–64/mo. **Our answer:** they're hosted-only and can't act or integrate; we own the power-user/privacy/own-agent flank they're structurally bad at. Window to ship is ~6–9 months.
- **AIPointer** (the look-alike): closest *core loop*, but answer-only — no pointing, no action, no integrations, modest traction (261★). **Our answer:** we're already past it on the two axes that matter (pointing + agent action). Not a threat; a validation that the loop resonates.

---

## 7. Strategic risks & our answer

1. **Google pushes AI Pointer down to the OS.** → Don't fight on "explain my screen." Win on BYO/privacy/own-agent — the quadrant Google can't enter.
2. **HeyClicky's war chest captures the mainstream first.** → Don't chase the mainstream. Lock the power-user/developer/privacy niche they underserve; ship the agent-action + mobile story fast.
3. **macOS-only caps reach & community discovery.** → Accept it short-term; depth over breadth. Native quality is the wedge. Revisit a thin Windows/web companion only after the agent story is proven.

---

## 8. The moat

What's hard to copy, in order of defensibility:

1. **Your-own-agent execution + mobile reach** — architectural, privacy-rooted, and the direction the whole market is heading. Hosted competitors can't follow without abandoning their model.
2. **MCP integrations as a voice+vision front-end** — habit-forming, and absent from every pointing/cursor tool.
3. **The companion/presence brand** — emotional moat the name and UX were built for.
4. **Native macOS craft** — pointing, multi-monitor, on-device, menu-bar citizenship.

---

## 9. From positioning to roadmap

The pillars above map to concrete epics (tracked in Linear):

- **Agent Action Layer** — route "do this" to the user's own agent; live run panel *(pillar 4–5)*
- **MCP Integrations Marketplace** — GitHub/Notion/Linear/Google, two-way *(pillar 6)*
- **Mobile Remote / Agent-touches-desktop** — phone → your agent → acts on your Mac *(pillar 7)*
- **Companion Presence** — the maus as a character: Hub/Dock, personality, voice *(pillar 2)*
- **Privacy posture, said out loud** — "only looks when you ask," on-device, BYO *(pillars 8–10)*

> **The sentence to keep returning to:** *AskMaus is where your own agent gets a face, eyes, and hands on your Mac — and only when you ask.*
