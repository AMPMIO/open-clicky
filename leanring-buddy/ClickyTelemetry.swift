//
//  ClickyTelemetry.swift
//  leanring-buddy
//
//  Thin os.Logger wrapper — one logger per testable feature, plus shared
//  pipeline/provider/build. Unlike print(), os.Logger entries flow into the
//  unified logging system, so they are readable via `scripts/monitor.sh`
//  (log stream) and Console.app EVEN WHEN the app runs in the background — exactly
//  the case Watch Mode / Live Companion exercise.
//
//  Privacy: interpolate `.public` for status/category/counts/coordinates/booleans
//  and `.private` for transcripts, replies, tokens, and any injected text. Prefer
//  logging a LENGTH or a boolean over the sensitive value itself.
//
//  This is per-test diagnostics, NOT product analytics — keep curated funnel
//  events in ClickyAnalytics (PostHog); keep verbose failure-catching here.
//
//  The subsystem MUST equal the value `scripts/monitor.sh` predicates on
//  (the app bundle id). If the bundle id changes, update both together.
//

import os

enum ClickyTelemetry {
    private static let subsystem = "com.ampmio.leanring-buddy"

    static let handsOn        = Logger(subsystem: subsystem, category: "handsOn")        // F1
    static let screenMemory   = Logger(subsystem: subsystem, category: "screenMemory")   // F2
    static let watchMode      = Logger(subsystem: subsystem, category: "watchMode")       // F3
    static let liveAudio      = Logger(subsystem: subsystem, category: "liveAudio")       // F4
    static let spokenMacros   = Logger(subsystem: subsystem, category: "spokenMacros")    // F5
    static let oauth          = Logger(subsystem: subsystem, category: "oauth")           // F6
    static let terminalBridge = Logger(subsystem: subsystem, category: "terminalBridge")  // F7
    static let pipeline       = Logger(subsystem: subsystem, category: "pipeline")        // voice→screenshot→LLM→TTS
    static let provider       = Logger(subsystem: subsystem, category: "provider")        // provider selection / build
    static let build          = Logger(subsystem: subsystem, category: "build")           // reserved for build-time diagnostics
}
