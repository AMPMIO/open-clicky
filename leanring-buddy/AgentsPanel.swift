//
//  AgentsPanel.swift
//  leanring-buddy
//
//  G5: SwiftUI views for displaying agent runs. `AgentsPanel` is the full list of
//  recent runs (used inside the Hub card), and `AgentRunCard` renders a single run
//  — title, which agent it went to, a stage indicator dot, and (when expanded) the
//  last few log lines. Styled to match the Hub's liquid-glass look: ultraThinMaterial
//  surfaces and DesignSystem (`DS`) color tokens.
//

import SwiftUI

/// A scrollable list of recent agent runs. When there are no runs yet, shows a
/// quiet empty state instead of a blank area. Intended to live inside the Hub
/// card, so it sizes to fill the space it's given.
struct AgentsPanel: View {
    @ObservedObject var agentRunManager: AgentRunManager

    var body: some View {
        if agentRunManager.runs.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(agentRunManager.runs) { run in
                        AgentRunCard(run: run)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        Text("no agent runs yet")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A single run row. Collapsed it shows the title, agent label, and a colored
/// stage dot; tapping expands it to reveal the most recent log lines so the user
/// can see what the agent actually did.
struct AgentRunCard: View {
    let run: AgentRun

    @State private var isExpanded = false

    /// How many of the most recent log lines to reveal when expanded. Capped so a
    /// long-running agent's log doesn't blow out the compact Hub card.
    private let maximumVisibleLogLines = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if isExpanded, !run.logLines.isEmpty {
                logLinesView
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            stageIndicatorDot
            VStack(alignment: .leading, spacing: 2) {
                Text(run.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(run.agentLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(run.stage.displayLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(run.stage.indicatorColor)
                }
            }
            Spacer(minLength: 0)
            if !run.logLines.isEmpty {
                // Affordance hinting the row expands to show the run's log lines.
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Pulse the dot while the run is still active so an in-flight run reads as
    /// "live" at a glance; settle to a steady dot once it's done or failed.
    private var stageIndicatorDot: some View {
        Circle()
            .fill(run.stage.indicatorColor)
            .frame(width: 7, height: 7)
            .opacity(run.stage.isActive ? 0.9 : 1.0)
    }

    private var logLinesView: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Show the most recent lines (the tail is what matters for status).
            ForEach(Array(run.logLines.suffix(maximumVisibleLogLines).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
