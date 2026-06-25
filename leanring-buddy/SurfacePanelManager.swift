//
//  SurfacePanelManager.swift
//  leanring-buddy
//
//  G4: an always-visible "surface" for at-a-glance status — either the corner
//  "Hub" (a liquid-glass dashboard, mostly transparent at rest, revealing on
//  hover) or the notch "Dock" (a compact top-center bar). Switchable in Settings
//  (Off / Hub / Dock) so the two designs can be A/B tested. Reuses the borderless
//  non-activating NSPanel pattern from MenuBarPanelManager.
//
//  ponytail: glass is SwiftUI's native .ultraThinMaterial (not a custom
//  NSVisualEffectView). If behind-window blur ever needs to be stronger, swap in
//  an NSVisualEffectView with blendingMode .behindWindow.
//

import AppKit
import SwiftUI

enum SurfaceMode: String, CaseIterable {
    case off, hub, dock

    var label: String {
        switch self {
        case .off: return "Off"
        case .hub: return "Hub (corner)"
        case .dock: return "Dock (notch)"
        }
    }
}

enum HubCorner: String, CaseIterable {
    case topRight, topLeft, bottomRight, bottomLeft

    var label: String {
        switch self {
        case .topRight: return "Top Right"
        case .topLeft: return "Top Left"
        case .bottomRight: return "Bottom Right"
        case .bottomLeft: return "Bottom Left"
        }
    }
}

@MainActor
final class SurfacePanelManager: NSObject {
    private var panel: NSPanel?
    private var mode: SurfaceMode = .off
    private var corner: HubCorner = .topRight
    private var hubExpanded = false

    private let pillSize = CGSize(width: 68, height: 40)
    private let cardSize = CGSize(width: 280, height: 210)
    private let dockSize = CGSize(width: 360, height: 46)

    /// Builds/updates the surface for the given mode + corner. Off hides it.
    func apply(mode: SurfaceMode, corner: HubCorner, companionManager: CompanionManager) {
        self.mode = mode
        self.corner = corner
        self.hubExpanded = false

        guard mode != .off else {
            panel?.orderOut(nil)
            return
        }

        let surfaceView = SurfaceView(
            companionManager: companionManager,
            agentRunManager: companionManager.agentRunManager,
            mode: mode,
            onHoverChange: { [weak self] hovering in
                self?.setHubExpanded(hovering)
            }
        )

        let hostingView = NSHostingView(rootView: surfaceView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.autoresizingMask = [.width, .height]

        let surfacePanel = panel ?? makePanel()
        surfacePanel.contentView = hostingView
        hostingView.frame = surfacePanel.contentView?.bounds ?? .zero
        panel = surfacePanel

        reposition()
        surfacePanel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let surfacePanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: cardSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        surfacePanel.isFloatingPanel = true
        surfacePanel.level = .floating
        surfacePanel.isOpaque = false
        surfacePanel.backgroundColor = .clear
        surfacePanel.hasShadow = false
        surfacePanel.hidesOnDeactivate = false
        surfacePanel.isExcludedFromWindowsMenu = true
        surfacePanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        surfacePanel.isMovableByWindowBackground = false
        // Keep the surface out of OpenClicky's own captures / third-party recordings.
        surfacePanel.sharingType = .none
        return surfacePanel
    }

    /// Hub only: grow to the full card on hover, shrink back to the pill on exit.
    private func setHubExpanded(_ expanded: Bool) {
        guard mode == .hub, hubExpanded != expanded else { return }
        hubExpanded = expanded
        reposition()
    }

    private func reposition() {
        guard let panel else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame

        switch mode {
        case .off:
            return
        case .dock:
            // ponytail: centered under the menu bar; notch-precise centering can come later.
            let originX = area.midX - dockSize.width / 2
            let originY = area.maxY - dockSize.height - 6
            panel.setFrame(NSRect(x: originX, y: originY, width: dockSize.width, height: dockSize.height), display: true)
        case .hub:
            let size = hubExpanded ? cardSize : pillSize
            panel.setFrame(cornerRect(size: size, in: area, corner: corner, inset: 12), display: true)
        }
    }

    private func cornerRect(size: CGSize, in area: NSRect, corner: HubCorner, inset: CGFloat) -> NSRect {
        // AppKit screen coords: origin is bottom-left, so maxY is the top edge.
        let originX: CGFloat
        let originY: CGFloat
        switch corner {
        case .topRight:    originX = area.maxX - size.width - inset; originY = area.maxY - size.height - inset
        case .topLeft:     originX = area.minX + inset;              originY = area.maxY - size.height - inset
        case .bottomRight: originX = area.maxX - size.width - inset; originY = area.minY + inset
        case .bottomLeft:  originX = area.minX + inset;              originY = area.minY + inset
        }
        return NSRect(x: originX, y: originY, width: size.width, height: size.height)
    }
}

/// SwiftUI content for the surface. Renders the Hub (pill at rest, card on hover)
/// or the Dock bar. Read-only status for v1 (visibility); interactive quick
/// toggles + live agent runs land with G5.
struct SurfaceView: View {
    @ObservedObject var companionManager: CompanionManager
    @ObservedObject var agentRunManager: AgentRunManager
    let mode: SurfaceMode
    let onHoverChange: (Bool) -> Void

    @State private var hovering = false

    private let eyeGlyph = "\u{1F441}\u{FE0F}\u{200D}\u{1F5E8}\u{FE0F}"

    var body: some View {
        content
            .onHover { isHovering in
                hovering = isHovering
                onHoverChange(isHovering)
            }
            .animation(.easeInOut(duration: 0.18), value: hovering)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .dock:
            dockBar
        case .hub:
            if hovering { hubCard } else { hubPill }
        case .off:
            EmptyView()
        }
    }

    // MARK: - Hub

    private var hubPill: some View {
        HStack(spacing: 6) {
            Text(eyeGlyph).font(.system(size: 16))
            // Active-run count takes priority over the idle status dot so the user
            // sees at-a-glance that an agent run is in flight (G5).
            if agentRunManager.activeRunCount > 0 {
                Text("\(agentRunManager.activeRunCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Colors.accentText)
            } else {
                Circle().fill(statusColor).frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: Capsule())
        .opacity(0.6)
    }

    private var hubCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(eyeGlyph).font(.system(size: 18))
                Text("OpenClicky").font(.system(size: 13, weight: .semibold))
                Spacer()
                Circle().fill(statusColor).frame(width: 8, height: 8)
            }
            Divider().opacity(0.4)
            statusRow("Status", statusText)
            statusRow("Model", providerLabel)
            statusRow("Hands-On", companionManager.isHandsOnModeEnabled ? "On" : "Off")
            statusRow("Watch", companionManager.isWatchModeEnabled ? "On" : "Off")
            Divider().opacity(0.4)
            recentRuns
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
    }

    /// A compact live list of the most recent agent runs (G5). Shows the 3 newest,
    /// each as a stage-colored dot + title + stage label, or a quiet empty state.
    @ViewBuilder
    private var recentRuns: some View {
        let runs = agentRunManager.runs.prefix(3)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Agent runs")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if agentRunManager.activeRunCount > 0 {
                    Text("\(agentRunManager.activeRunCount) active")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.Colors.accentText)
                }
            }
            if runs.isEmpty {
                Text("no agent runs yet")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(runs) { run in
                    HStack(spacing: 6) {
                        Circle().fill(run.stage.indicatorColor).frame(width: 6, height: 6)
                        Text(run.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(run.stage.displayLabel)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Dock

    private var dockBar: some View {
        HStack(spacing: 10) {
            Text(eyeGlyph).font(.system(size: 16))
            Circle().fill(statusColor).frame(width: 7, height: 7)
            Text(statusText).font(.system(size: 12, weight: .medium))
            Spacer()
            Text(providerLabel)
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Status

    private var providerLabel: String {
        companionManager.providerManager.configuration.activeProvider.displayName
    }

    private var statusText: String {
        switch companionManager.voiceState {
        case .idle: return "Idle"
        case .listening: return "Listening…"
        case .processing: return "Thinking…"
        case .responding: return "Responding…"
        }
    }

    private var statusColor: Color {
        switch companionManager.voiceState {
        case .idle: return .gray
        case .listening: return .green
        case .processing: return .yellow
        case .responding: return .blue
        }
    }
}
