//
//  TerminalAgentBridge.swift
//  leanring-buddy
//
//  Dispatches a spoken prompt to a running terminal agent session (e.g. a
//  Claude Code session) by activating the terminal app and pasting the prompt +
//  Return into its focused session. This drives whatever interactive program is
//  in the focused terminal — it does NOT run a fresh `do script` command.
//
//  Requires Accessibility + Automation (Apple Events) permission. Every dispatch
//  is gated by an explicit voice confirmation in CompanionManager (like Hands-On
//  Mode), so nothing here runs without the user confirming first.
//

import AppKit
import Foundation

enum TerminalApp: String, CaseIterable {
    case terminal = "Terminal"
    case iterm = "iTerm"
    case ghostty = "Ghostty"

    var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm: return "com.googlecode.iterm2"
        case .ghostty: return "com.mitchellh.ghostty"
        }
    }

    var displayName: String { rawValue }
}

enum TerminalAgentBridgeError: LocalizedError {
    case noRunningTerminal
    case permissionDenied
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRunningTerminal:
            return "No supported terminal (Terminal, iTerm, or Ghostty) is running."
        case .permissionDenied:
            return "Accessibility permission is required to type into the terminal."
        case .scriptFailed(let detail):
            return "Couldn't send the prompt to the terminal (\(detail))."
        }
    }
}

enum TerminalAgentBridge {

    /// Returns a running, supported terminal app — preferring the frontmost one
    /// so "send this to Claude Code" targets the terminal the user is looking at.
    static func targetTerminal() -> TerminalApp? {
        let running = NSWorkspace.shared.runningApplications
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           let match = TerminalApp.allCases.first(where: { $0.bundleIdentifier == front }) {
            return match
        }
        return TerminalApp.allCases.first { app in
            running.contains { $0.bundleIdentifier == app.bundleIdentifier }
        }
    }

    /// Activates `terminal` and pastes `prompt` + Return into its focused session.
    /// Uses the pasteboard (reliable for arbitrary/long text) and restores the
    /// previous clipboard contents afterward.
    static func sendPrompt(_ prompt: String, to terminal: TerminalApp) throws {
        guard AXIsProcessTrusted() else { throw TerminalAgentBridgeError.permissionDenied }

        let pasteboard = NSPasteboard.general
        let savedItems = snapshotPasteboard(pasteboard) // preserve ALL clipboard items (text/image/files)
        pasteboard.clearContents()
        pasteboard.setString(prompt, forType: .string)

        let script = """
        tell application "\(terminal.rawValue)" to activate
        delay 0.25
        tell application "System Events"
            keystroke "v" using command down
            delay 0.1
            key code 36
        end tell
        """
        do {
            try runAppleScript(script)
        } catch {
            restorePasteboard(savedItems)
            throw error
        }

        // Restore the user's full clipboard after the paste has been consumed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            restorePasteboard(savedItems)
        }
    }

    /// Best-effort read of the focused terminal window's visible text via the
    /// Accessibility tree, for optional status read-back. Returns nil if it
    /// can't be read (many terminals don't expose a readable AXValue).
    static func readVisibleText(from terminal: TerminalApp) -> String? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == terminal.bundleIdentifier }) else {
            return nil
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedElement = focused,
              CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = focusedElement as! AXUIElement // safe: type checked above
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty else {
            return nil
        }
        return text
    }

    // MARK: - Private

    /// Captures every item on the pasteboard (all representations) so the user's
    /// clipboard — text, images, files — can be restored after our paste.
    private static func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            var representation: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { representation[type] = data }
            }
            return representation
        }
    }

    private static func restorePasteboard(_ snapshot: [[NSPasteboard.PasteboardType: Data]]) {
        let nonEmpty = snapshot.filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items: [NSPasteboardItem] = nonEmpty.map { representation in
            let item = NSPasteboardItem()
            for (type, data) in representation { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private static func runAppleScript(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw TerminalAgentBridgeError.scriptFailed("could not compile AppleScript")
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            throw TerminalAgentBridgeError.scriptFailed(error[NSAppleScript.errorMessage] as? String ?? "AppleScript error")
        }
    }
}
