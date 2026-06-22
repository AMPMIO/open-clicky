//
//  SystemAudioCaptureService.swift
//  leanring-buddy
//
//  Captures the Mac's system audio (what's playing out of the speakers — a call,
//  a tutorial, a video) via ScreenCaptureKit's audio capture, converts it to
//  PCM16 mono, and hands buffers to a callback. Used by Live Companion so Clicky
//  can hear AND see, bot-free (no meeting-room join). Native since macOS 13 — no
//  kernel extension. Requires Screen Recording permission (covers audio capture).
//

import AVFoundation
import Foundation
import ScreenCaptureKit

@MainActor
final class SystemAudioCaptureService: NSObject, ObservableObject {
    @Published private(set) var isCapturing = false

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "com.clicky.systemaudio")
    /// Receives PCM16 mono audio data on the main actor as it arrives.
    private var onPCM16: ((Data) -> Void)?

    /// Target format the transcription layer expects (PCM16 mono 16 kHz).
    static let targetSampleRate: Double = 16_000

    /// Starts system-audio capture. Throws if Screen Recording content isn't
    /// available (permission not granted) or the stream can't start.
    func start(onPCM16: @escaping (Data) -> Void) async throws {
        guard !isCapturing else { return }
        self.onPCM16 = onPCM16

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "SystemAudioCapture", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No display available for audio capture."])
        }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true // don't capture Clicky's own TTS
        config.sampleRate = Int(Self.targetSampleRate)
        config.channelCount = 1
        // Minimal video config — we only want audio, but a display filter is required.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
        isCapturing = true
    }

    func stop() async {
        guard let stream else { isCapturing = false; return }
        try? await stream.stopCapture()
        self.stream = nil
        self.onPCM16 = nil
        isCapturing = false
    }

    /// One-shot transcription of buffered PCM16 mono audio via OpenAI's
    /// transcription API (reuses the `OpenAIAPIKey` from Info.plist — the same key
    /// the upload-based STT fallback uses). Returns "" when no key is configured.
    nonisolated static func transcribe(pcm16: Data, sampleRate: Int) async throws -> String {
        guard let apiKey = AppBundleConfiguration.stringValue(forKey: "OpenAIAPIKey"),
              !apiKey.isEmpty, !pcm16.isEmpty,
              let url = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            return ""
        }
        let wav = BuddyWAVFileBuilder.buildWAVData(fromPCM16MonoAudio: pcm16, sampleRate: sampleRate)

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "SystemAudioTranscribe",
                          code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: "transcription failed"])
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["text"] as? String) ?? ""
    }
}

extension SystemAudioCaptureService: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let pcm = Self.pcm16Data(from: sampleBuffer) else { return }
        Task { @MainActor [weak self] in
            self?.onPCM16?(pcm)
        }
    }

    /// Converts a CMSampleBuffer of audio into interleaved PCM16 mono Data.
    private nonisolated static func pcm16Data(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let formatDescription = sampleBuffer.formatDescription,
              let asbd = formatDescription.audioStreamBasicDescription else { return nil }

        // Pull the raw audio bytes out of the sample buffer's block buffer.
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let data = audioBufferList.mBuffers.mData else { return nil }
        let byteCount = Int(audioBufferList.mBuffers.mDataByteSize)

        // SCStream audio is float32; convert to PCM16.
        if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            let floatCount = byteCount / MemoryLayout<Float32>.size
            let floats = data.bindMemory(to: Float32.self, capacity: floatCount)
            var pcm = Data(capacity: floatCount * 2)
            for index in 0..<floatCount {
                let clamped = max(-1.0, min(1.0, floats[index]))
                var sample = Int16(clamped * Float(Int16.max))
                withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
            }
            return pcm
        }
        // Already integer PCM — only 16-bit matches the WAV header we build.
        guard asbd.mBitsPerChannel == 16 else {
            print("SystemAudioCaptureService: unexpected integer PCM bit depth \(asbd.mBitsPerChannel)")
            return nil
        }
        return Data(bytes: data, count: byteCount)
    }
}
