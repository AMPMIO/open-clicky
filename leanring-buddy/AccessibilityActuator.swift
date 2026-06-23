//
//  AccessibilityActuator.swift
//  leanring-buddy
//
//  Performs voice-confirmed UI actions (press / type) on on-screen elements via
//  the macOS Accessibility API. Used by Hands-On Mode (and later by Hermes
//  computer-use and Spoken Macros). This type only EXECUTES a resolved action —
//  the confirm-before-act gate lives in CompanionManager, so nothing here runs
//  without an explicit user confirmation upstream.
//
//  Coordinate note: the Accessibility API and `AXUIElementCopyElementAtPosition`
//  use global screen coordinates with a TOP-LEFT origin (Quartz/CGEvent space),
//  whereas the cursor overlay computes AppKit GLOBAL coordinates (bottom-left
//  origin). `quartzPoint(fromAppKitGlobal:)` converts between them.
//

import AppKit
import os
import ApplicationServices

enum AccessibilityActuatorError: LocalizedError {
    case permissionDenied
    case noElementAtPoint
    case actionUnsupported
    case actionFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Accessibility permission is required to act on screen."
        case .noElementAtPoint:
            return "Couldn't find a control at that location."
        case .actionUnsupported:
            return "That element can't be acted on."
        case .actionFailed(let detail):
            return "The action failed (\(detail))."
        }
    }
}

enum AccessibilityActuator {

    /// Converts an AppKit global point (bottom-left origin, as the overlay uses)
    /// to a Quartz global point (top-left origin) for the Accessibility API.
    /// The flip is anchored to the primary display height (the display whose
    /// AppKit origin is (0,0)); this is correct across multiple monitors because
    /// both coordinate systems share the same x-axis and primary-anchored y.
    static func quartzPoint(fromAppKitGlobal appKitPoint: CGPoint) -> CGPoint {
        // If we somehow can't determine the primary display height, return the
        // point unconverted rather than collapsing y to 0 (which would map every
        // action to the top edge of the screen).
        guard let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
                ?? NSScreen.main?.frame.height else {
            ClickyTelemetry.handsOn.notice("quartzPoint: no primary display height; returning point unconverted x=\(appKitPoint.x, privacy: .public) y=\(appKitPoint.y, privacy: .public)")
            return appKitPoint
        }
        return CGPoint(x: appKitPoint.x, y: primaryHeight - appKitPoint.y)
    }

    /// Presses (activates) the UI element at a Quartz global point.
    static func press(atQuartzPoint point: CGPoint) throws {
        ClickyTelemetry.handsOn.notice("press start x=\(point.x, privacy: .public) y=\(point.y, privacy: .public)")
        let element = try elementAtPoint(point)
        guard supportsAction(element, kAXPressAction) else {
            ClickyTelemetry.handsOn.error("press unsupported action at x=\(point.x, privacy: .public) y=\(point.y, privacy: .public)")
            throw AccessibilityActuatorError.actionUnsupported
        }
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success else {
            ClickyTelemetry.handsOn.error("press failed result=\(result.rawValue, privacy: .public) x=\(point.x, privacy: .public) y=\(point.y, privacy: .public)")
            throw AccessibilityActuatorError.actionFailed("press \(result.rawValue)")
        }
        ClickyTelemetry.handsOn.info("press success x=\(point.x, privacy: .public) y=\(point.y, privacy: .public)")
    }

    /// Types `text` into the element at a Quartz global point by setting its
    /// AXValue. Best-effort: works for standard text fields/areas.
    static func setValue(_ text: String, atQuartzPoint point: CGPoint) throws {
        ClickyTelemetry.handsOn.notice("setValue start x=\(point.x, privacy: .public) y=\(point.y, privacy: .public) textLength=\(text.count, privacy: .public)")
        let element = try elementAtPoint(point)
        // Only set the value if the element actually exposes a writable AXValue,
        // so we fail with a clear error on non-text elements instead of silently.
        var isSettable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &isSettable) == .success,
              isSettable.boolValue else {
            ClickyTelemetry.handsOn.error("setValue unsupported: AXValue not settable at x=\(point.x, privacy: .public) y=\(point.y, privacy: .public)")
            throw AccessibilityActuatorError.actionUnsupported
        }
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        guard result == .success else {
            ClickyTelemetry.handsOn.error("setValue failed result=\(result.rawValue, privacy: .public) x=\(point.x, privacy: .public) y=\(point.y, privacy: .public)")
            throw AccessibilityActuatorError.actionFailed("setValue \(result.rawValue)")
        }
        ClickyTelemetry.handsOn.info("setValue success x=\(point.x, privacy: .public) y=\(point.y, privacy: .public) textLength=\(text.count, privacy: .public)")
    }

    // MARK: - Private

    private static func elementAtPoint(_ point: CGPoint) throws -> AXUIElement {
        guard AXIsProcessTrusted() else {
            ClickyTelemetry.handsOn.error("elementAtPoint: AXIsProcessTrusted false — accessibility permission gate")
            throw AccessibilityActuatorError.permissionDenied
        }
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard result == .success, let element else {
            ClickyTelemetry.handsOn.error("elementAtPoint: no element result=\(result.rawValue, privacy: .public) x=\(point.x, privacy: .public) y=\(point.y, privacy: .public)")
            throw AccessibilityActuatorError.noElementAtPoint
        }
        return element
    }

    /// Whether the element advertises the given action (so we don't blindly
    /// press something that won't respond).
    private static func supportsAction(_ element: AXUIElement, _ action: String) -> Bool {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success,
              let names = actions as? [String] else {
            return false
        }
        return names.contains(action)
    }
}
