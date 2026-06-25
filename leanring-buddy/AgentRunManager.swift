//
//  AgentRunManager.swift
//  leanring-buddy
//
//  G5: the model + store for "agent runs" — OpenClicky's differentiator. A run
//  is one piece of work Clicky dispatched to an agent backend (a prompt sent to a
//  terminal coding agent, a confirmed Hands-On click, or — once wired — a Hermes
//  task), tracked through its lifecycle so the always-visible Hub can show what
//  Clicky is currently doing at a glance.
//
//  This is purely a UI-facing progress store. It does NOT perform any dispatch
//  itself; CompanionManager owns the dispatch paths and calls in here to report
//  progress (startRun → update → complete/fail).
//

import Combine
import Foundation
import SwiftUI

/// The lifecycle stage of an agent run. Each stage carries a human-readable
/// label plus a color + SF Symbol so the Hub and the Agents panel can render a
/// consistent status indicator without duplicating that mapping.
enum RunStage {
    /// The run has been created but the agent hasn't started working yet.
    case starting
    /// The agent is actively thinking/working on the request.
    case processing
    /// The run is paused waiting for the user's spoken confirmation
    /// (Clicky never dispatches a click or terminal prompt unconfirmed).
    case awaitingConfirmation
    /// The confirmed work is being carried out (prompt pasted, click performed).
    case executing
    /// The run finished successfully.
    case complete
    /// The run failed; see the run's log lines for the reason.
    case failed

    /// Short, user-facing label for the stage (shown next to the run title).
    var displayLabel: String {
        switch self {
        case .starting: return "Starting"
        case .processing: return "Working"
        case .awaitingConfirmation: return "Needs confirmation"
        case .executing: return "Executing"
        case .complete: return "Done"
        case .failed: return "Failed"
        }
    }

    /// The dot/indicator color for the stage. Pulls from the design system so
    /// run status reads the same as the rest of OpenClicky's UI.
    var indicatorColor: Color {
        switch self {
        case .starting: return DS.Colors.textTertiary
        case .processing: return DS.Colors.warning
        case .awaitingConfirmation: return DS.Colors.info
        case .executing: return DS.Colors.accentText
        case .complete: return DS.Colors.success
        case .failed: return DS.Colors.destructiveText
        }
    }

    /// SF Symbol name describing the stage, for places that prefer an icon to a dot.
    var symbolName: String {
        switch self {
        case .starting: return "circle.dashed"
        case .processing: return "gearshape"
        case .awaitingConfirmation: return "questionmark.circle"
        case .executing: return "bolt.fill"
        case .complete: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    /// Whether the run is still active (not yet finished). Used to count
    /// in-flight runs for the Hub's active-run indicator.
    var isActive: Bool {
        switch self {
        case .starting, .processing, .awaitingConfirmation, .executing:
            return true
        case .complete, .failed:
            return false
        }
    }
}

/// One unit of dispatched work that Clicky is tracking. Identifiable so SwiftUI
/// lists can diff runs efficiently. `logLines` accumulates short status messages
/// (the dispatched prompt, the confirmation, the outcome) for the expandable view.
struct AgentRun: Identifiable {
    let id: UUID
    /// A short human-readable description of the work (e.g. the dispatched prompt).
    let title: String
    /// Which agent the run was dispatched to (e.g. "Terminal", "Hands-On", "Hermes").
    let agentLabel: String
    /// The current lifecycle stage.
    var stage: RunStage
    /// When the run was first created.
    let createdAt: Date
    /// When the run last changed stage or appended a log line.
    var lastUpdate: Date
    /// Ordered status/log lines for the expandable detail view.
    var logLines: [String]
}

/// Owns the list of recent agent runs and exposes mutation methods that keep
/// `lastUpdate` and the cap consistent. `@MainActor` because every mutation
/// drives observable UI; `ObservableObject` so SwiftUI views (the Hub, the
/// Agents panel) re-render when runs change.
@MainActor
final class AgentRunManager: ObservableObject {
    /// Most-recent-first list of runs. Read-only to callers — they mutate via the
    /// methods below so invariants (cap, lastUpdate) are always maintained.
    @Published private(set) var runs: [AgentRun] = []

    /// Keep only the most recent runs so the store never grows unbounded over a
    /// long session. The Hub/panel only ever show a handful at once.
    private let maximumRetainedRuns = 20

    /// Number of runs that are still in flight (anything not complete/failed).
    /// Surfaced on the Hub pill so the user sees activity without expanding.
    var activeRunCount: Int {
        runs.filter { $0.stage.isActive }.count
    }

    /// Creates a new run at the given starting stage and returns its id so the
    /// caller can advance it later. New runs go to the front (most recent first)
    /// and the oldest are trimmed past the retention cap.
    @discardableResult
    func startRun(
        title: String,
        agentLabel: String,
        stage: RunStage = .starting,
        initialLogLine: String? = nil
    ) -> UUID {
        let now = Date()
        let run = AgentRun(
            id: UUID(),
            title: title,
            agentLabel: agentLabel,
            stage: stage,
            createdAt: now,
            lastUpdate: now,
            logLines: initialLogLine.map { [$0] } ?? []
        )
        runs.insert(run, at: 0)
        if runs.count > maximumRetainedRuns {
            runs.removeLast(runs.count - maximumRetainedRuns)
        }
        return run.id
    }

    /// Advances an existing run: optionally moves it to a new stage and/or appends
    /// a log line. No-op if the id isn't found (the run may have been trimmed).
    func update(id: UUID, stage: RunStage? = nil, appendLog: String? = nil) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        if let stage {
            runs[index].stage = stage
        }
        if let appendLog {
            runs[index].logLines.append(appendLog)
        }
        runs[index].lastUpdate = Date()
    }

    /// Marks a run complete, optionally appending a final log line.
    func complete(id: UUID, appendLog: String? = nil) {
        update(id: id, stage: .complete, appendLog: appendLog)
    }

    /// Marks a run failed and records the reason as a log line.
    func fail(id: UUID, reason: String) {
        update(id: id, stage: .failed, appendLog: reason)
    }
}
