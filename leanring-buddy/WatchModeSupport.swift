//
//  WatchModeSupport.swift
//  leanring-buddy
//
//  Cheap, local first-pass gates for Watch Mode so the full vision model is only
//  invoked when the screen genuinely changed AND something actionable is likely on
//  it. Keeps proactive watching cheap + private.
//
//  ponytail: a debounced poll + perceptual-hash gate (below), not a continuous
//  low-fps SCStream + per-frame diff. Same "ignore static screens" outcome with far
//  less machinery; upgrade to a real SCStream watcher only if poll latency matters.
//

import AppKit
import CoreGraphics
import Foundation
import Vision

/// Perceptual "average hash" (aHash) used to ignore static screens: downsamples to
/// 8x8 grayscale and thresholds each pixel against the mean, giving a 64-bit hash
/// whose Hamming distance tracks how much the screen actually changed.
enum WatchModeChangeDetector {
    static func averageHash(of imageData: Data) -> UInt64? {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            ClickyTelemetry.watchMode.notice("averageHash image decode failed bytes=\(imageData.count, privacy: .public)")
            return nil
        }
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side)
        let grayColorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side, space: grayColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            ClickyTelemetry.watchMode.notice("averageHash CGContext create failed")
            return nil
        }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        let total = pixels.reduce(0) { $0 + Int($1) }
        let mean = total / pixels.count
        var hash: UInt64 = 0
        for (index, value) in pixels.enumerated() where Int(value) >= mean {
            hash |= (UInt64(1) << UInt64(index))
        }
        return hash
    }

    /// Number of differing bits between two hashes (0 = identical screens).
    static func hammingDistance(_ first: UInt64, _ second: UInt64) -> Int {
        (first ^ second).nonzeroBitCount
    }
}

/// Cheap OCR pre-gate (OC-52): true when the frame contains text that looks worth a
/// proactive nudge (errors / failures / blocked states), so the full vision model is
/// only escalated to when something actionable is likely on screen.
enum WatchModeTextGate {
    private static let actionableKeywords = [
        "error", "failed", "failure", "exception", "warning", "denied",
        "not found", "cannot", "unable", "invalid", "timeout", "timed out",
        "crash", "traceback", "undefined", "permission", "blocked",
    ]

    static func looksActionable(in imageData: Data) -> Bool {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            ClickyTelemetry.watchMode.notice("looksActionable image decode failed bytes=\(imageData.count, privacy: .public)")
            return false
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .lowercased()
        return actionableKeywords.contains { text.contains($0) }
    }
}
