//
//  CircleToPointGestureCaptureView.swift
//  leanring-buddy
//
//  G8 (OC-107): "circle-to-point" reference gesture. While the user holds push-to-talk
//  they can draw a freehand loop around a region of their screen with the left mouse to
//  say "what's *this*?". This file owns the two pieces that make that work:
//
//    • CircleToPointGestureCaptureView — a transparent, full-screen AppKit view layered
//      above the SwiftUI cursor overlay. It records the freehand drag (in global AppKit
//      screen coordinates) and draws the stroke live so the user sees what they circled.
//
//    • CircleToPointGesture — pure helpers that decide whether a drag counts as a real
//      gesture and that annotate the captured screenshot with the circle so Claude can
//      see exactly which region the user meant.
//
//  Why an AppKit NSView and not a SwiftUI gesture: the overlay window is borderless,
//  non-key, and normally click-through (ignoresMouseEvents = true). SwiftUI gestures are
//  unreliable on a window that never becomes key, so we toggle the window off click-through
//  only while push-to-talk is held and let this view receive the raw mouse events directly.
//

import AppKit

/// Transparent full-screen view that records a freehand "circle this region" drag with
/// the left mouse button while push-to-talk is held, and draws the stroke live.
///
/// It only intercepts the mouse while `armed`; the rest of the time `hitTest` returns nil
/// so the overlay stays fully click-through and nothing beneath it is affected.
final class CircleToPointGestureCaptureView: NSView {

    /// The drawn path in GLOBAL AppKit screen coordinates (bottom-left origin) — the same
    /// space as `NSScreen.frame` and `CompanionScreenCapture.displayFrame`, so the path
    /// maps cleanly onto a captured screenshot without any coordinate-system guesswork.
    private(set) var capturedGlobalPath: [CGPoint] = []

    /// The same path in this view's local coordinates, used only for the live stroke.
    private var capturedLocalPath: [CGPoint] = []

    /// When false the view ignores all mouse input. This is belt-and-suspenders alongside
    /// the overlay window's `ignoresMouseEvents` toggle, so a stray event can never start
    /// a gesture while the feature is disarmed.
    private var isArmed = false

    /// Brand blue for the live stroke (matches the cursor companion's accent).
    private let strokeColor = NSColor(srgbRed: 0.20, green: 0.55, blue: 1.0, alpha: 0.95)
    private let strokeWidthInPoints: CGFloat = 4.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Layer-backed so this view reliably composites ABOVE the layer-backed
        // NSHostingView sibling that renders the SwiftUI cursor content.
        wantsLayer = true
        // Redraw the stroke whenever we mark the view dirty (each mouse sample), instead
        // of only on resize — otherwise the live path may not update during the drag.
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — this view is created in code only.")
    }

    /// A bottom-left origin keeps the live stroke in the same coordinate convention as the
    /// global AppKit points we record, so the two never drift apart.
    override var isFlipped: Bool { false }

    /// Deliver the very first click even though the overlay window never becomes key —
    /// without this, the initial mouse-down on a non-key window is swallowed to "activate"
    /// rather than reported as a drag.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isArmed }

    /// Only participate in hit-testing while armed. When disarmed, returning nil lets
    /// events fall through to the SwiftUI cursor content (and the window is click-through
    /// anyway), so normal use is never disturbed.
    override func hitTest(_ point: NSPoint) -> NSView? {
        isArmed ? super.hitTest(point) : nil
    }

    /// Begin capturing. Clears any previous path so each push-to-talk hold starts fresh.
    func arm() {
        isArmed = true
        capturedGlobalPath = []
        capturedLocalPath = []
        needsDisplay = true
    }

    /// Stop capturing and clear the live stroke. The recorded path should be read via
    /// `capturedGlobalPath` BEFORE calling this if it's still needed.
    func disarm() {
        isArmed = false
        capturedGlobalPath = []
        capturedLocalPath = []
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isArmed else { return super.mouseDown(with: event) }
        capturedGlobalPath = [NSEvent.mouseLocation]
        capturedLocalPath = [convert(event.locationInWindow, from: nil)]
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isArmed else { return super.mouseDragged(with: event) }
        capturedGlobalPath.append(NSEvent.mouseLocation)
        capturedLocalPath.append(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isArmed else { return super.mouseUp(with: event) }
        capturedGlobalPath.append(NSEvent.mouseLocation)
        capturedLocalPath.append(convert(event.locationInWindow, from: nil))
        needsDisplay = true
        // The path is intentionally kept (not cleared here): the user may lift the left
        // mouse before releasing the push-to-talk key, and the gesture is only collected
        // on key-up. disarm() clears it once it has been read.
    }

    override func draw(_ dirtyRect: NSRect) {
        guard capturedLocalPath.count > 1 else { return }
        let strokePath = NSBezierPath()
        strokePath.lineWidth = strokeWidthInPoints
        strokePath.lineJoinStyle = .round
        strokePath.lineCapStyle = .round
        strokePath.move(to: capturedLocalPath[0])
        for point in capturedLocalPath.dropFirst() {
            strokePath.line(to: point)
        }
        strokeColor.setStroke()
        strokePath.stroke()
    }
}

/// Pure helpers for turning a recorded freehand path into a decision ("is this a real
/// circle gesture?") and an annotated screenshot ("draw that circle onto the image").
/// Kept separate from the view so the logic is testable and free of UI state.
enum CircleToPointGesture {

    /// Ignore incidental clicks and tiny twitches: only treat a drag as a deliberate
    /// "circle this" gesture when its bounding box spans at least this many points on its
    /// larger side. Sized to comfortably clear a single icon while rejecting a stray click.
    static let minimumBoundingSizeInPoints: CGFloat = 28

    /// Axis-aligned bounding box of the path, in whatever coordinate space the points use.
    static func boundingBox(ofPoints points: [CGPoint]) -> CGRect {
        guard let firstPoint = points.first else { return .zero }
        var minX = firstPoint.x
        var maxX = firstPoint.x
        var minY = firstPoint.y
        var maxY = firstPoint.y
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// True when the drag is large enough to count as an intentional reference gesture.
    static func isQualifyingGesture(_ globalPoints: [CGPoint]) -> Bool {
        guard globalPoints.count >= 3 else { return false }
        let box = boundingBox(ofPoints: globalPoints)
        return max(box.width, box.height) >= minimumBoundingSizeInPoints
    }

    /// Center of the gesture, used to pick which screen's screenshot to annotate when the
    /// user has multiple monitors.
    static func centerGlobalPoint(ofGlobalPoints globalPoints: [CGPoint]) -> CGPoint {
        let box = boundingBox(ofPoints: globalPoints)
        return CGPoint(x: box.midX, y: box.midY)
    }

    /// Draws the freehand loop onto a copy of `capture`'s screenshot and returns new JPEG
    /// data at the SAME pixel dimensions as the original — so the "image is N×M pixels"
    /// label and Claude's [POINT] coordinate space both stay valid. Returns nil on failure
    /// (caller then sends the unannotated screenshot).
    ///
    /// Coordinate handling: the gesture points and `displayFrame` are both in global AppKit
    /// space (bottom-left origin), and we draw into a bottom-left bitmap context, so the
    /// stroke and the naturally-oriented screenshot line up with no vertical flip.
    static func annotatedScreenshot(of capture: CompanionScreenCapture,
                                    withGlobalPath globalPoints: [CGPoint]) -> Data? {
        let pixelWidth = capture.screenshotWidthInPixels
        let pixelHeight = capture.screenshotHeightInPixels
        let displayFrame = capture.displayFrame

        guard pixelWidth > 0, pixelHeight > 0,
              displayFrame.width > 0, displayFrame.height > 0,
              globalPoints.count > 1,
              let sourceImage = NSImage(data: capture.imageData),
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0)
        else { return nil }

        // Treat the bitmap as 1 point == 1 pixel so drawing coordinates are pixel coordinates.
        bitmap.size = NSSize(width: pixelWidth, height: pixelHeight)

        let pixelsPerPointX = CGFloat(pixelWidth) / displayFrame.width
        let pixelsPerPointY = CGFloat(pixelHeight) / displayFrame.height
        let pixelPoints = globalPoints.map { globalPoint in
            CGPoint(
                x: (globalPoint.x - displayFrame.origin.x) * pixelsPerPointX,
                y: (globalPoint.y - displayFrame.origin.y) * pixelsPerPointY
            )
        }

        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphicsContext

        sourceImage.draw(in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        // Scale the stroke with the image so it reads clearly at any capture size.
        let strokeWidthInPixels = max(5.0, CGFloat(pixelWidth) / 180.0)
        let ringPath = NSBezierPath()
        ringPath.lineWidth = strokeWidthInPixels
        ringPath.lineJoinStyle = .round
        ringPath.lineCapStyle = .round
        ringPath.move(to: pixelPoints[0])
        for point in pixelPoints.dropFirst() {
            ringPath.line(to: point)
        }
        // Close the freehand loop so it reads as a ring around the region.
        ringPath.close()

        NSColor(srgbRed: 0.20, green: 0.55, blue: 1.0, alpha: 0.95).setStroke()
        ringPath.stroke()

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
