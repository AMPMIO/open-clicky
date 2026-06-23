//
//  ScreenMemoryStore.swift
//  leanring-buddy
//
//  On-device, opt-in recall of what Clicky has seen. Each push-to-talk turn can
//  be persisted (cursor-screen screenshot + transcript + reply), OCR'd with
//  Vision, and embedded with NLEmbedding so the user can later ask recall
//  questions by voice. Everything stays local and is encrypted at rest with
//  AES-GCM (key in the Keychain). Off by default; pause / exclude-app / purge.
//

import AppKit
import Combine
import CryptoKit
import Foundation
import NaturalLanguage
import Security
import Vision

struct ScreenMemoryEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let appName: String?
    let transcript: String
    let reply: String
    let ocrText: String
    let imageFileName: String
    let embedding: [Double]
}

/// A recalled moment plus its decrypted screenshot, ready to inject into a vision
/// request and point back at.
struct ScreenMemoryRecall {
    let entry: ScreenMemoryEntry
    let imageData: Data
}

@MainActor
final class ScreenMemoryStore: ObservableObject {
    static let shared = ScreenMemoryStore()

    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "screenMemoryEnabled")
    @Published var isPaused: Bool = false
    /// Lowercased app names to never record (user-managed exclude list).
    @Published var excludedApps: Set<String> = Set(
        (UserDefaults.standard.array(forKey: "screenMemoryExcludedApps") as? [String]) ?? []
    )

    private let directory: URL
    private let indexURL: URL
    private var entries: [ScreenMemoryEntry] = []
    private let embedder = NLEmbedding.sentenceEmbedding(for: .english)
    private let maxEntries = 500
    private static let encryptionKeyService = "com.clicky.screen-memory-key"
    /// Bumped on disable / pause / purge so an in-flight recording task can detect
    /// the user changed their mind and skip persisting.
    private var generation = 0
    /// Whether the index decrypted+loaded successfully — gates orphan sweeping so we
    /// never delete images that an unreadable index still references.
    private var indexLoaded = false

    private init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("ClickyScreenMemory", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.enc")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadIndex()
        ClickyTelemetry.screenMemory.info("init isEnabled=\(self.isEnabled, privacy: .public) entryCount=\(self.entries.count, privacy: .public)")
        sweepOrphans()
    }

    /// Removes encrypted image files not referenced by any entry (e.g. left behind
    /// by a crash between the image write and the index write).
    private func sweepOrphans() {
        // Don't sweep if we couldn't read the index — otherwise we'd delete images
        // the (currently unreadable) index still references.
        guard indexLoaded else { return }
        let referenced = Set(entries.map { $0.imageFileName })
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        var sweptOrphanCount = 0
        for file in files where file.hasSuffix(".enc") && file != "index.enc" && !referenced.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
            sweptOrphanCount += 1
        }
        ClickyTelemetry.screenMemory.info("sweepOrphans swept=\(sweptOrphanCount, privacy: .public)")
    }

    // MARK: - Controls

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "screenMemoryEnabled")
        if !enabled { generation += 1 } // invalidate any in-flight recording
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused { generation += 1 }
    }

    func setExcludedApps(_ apps: Set<String>) {
        let lowercased = Set(apps.map { $0.lowercased() })
        excludedApps = lowercased
        UserDefaults.standard.set(Array(lowercased), forKey: "screenMemoryExcludedApps")
    }

    /// Excludes the given app (lowercased) from recording, going forward.
    func excludeApp(_ appName: String) {
        var updated = excludedApps
        updated.insert(appName.lowercased())
        setExcludedApps(updated)
    }

    /// Deletes all stored moments (index + screenshots).
    func purge() {
        generation += 1 // invalidate in-flight recordings so they don't repopulate
        entries = []
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var entryCount: Int { entries.count }

    // MARK: - Recording

    /// Records one turn if enabled and not paused/excluded. Runs OCR + embedding
    /// off the main actor and persists encrypted. `imageData` is the cursor
    /// screen's JPEG; `appName` is the frontmost app at capture time.
    func recordTurn(imageData: Data, transcript: String, reply: String, appName: String?) {
        guard isEnabled, !isPaused else { return }
        if let appName, excludedApps.contains(appName.lowercased()) { return }
        let capturedGeneration = generation

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let ocrText = Self.recognizeText(in: imageData)
            let combined = "\(transcript)\n\(ocrText)"
            let embedding = await self.embed(combined)
            let entry = ScreenMemoryEntry(
                id: UUID(), date: Date(), appName: appName,
                transcript: transcript, reply: reply, ocrText: ocrText,
                imageFileName: UUID().uuidString + ".enc", embedding: embedding
            )
            await self.persist(entry: entry, imageData: imageData, capturedGeneration: capturedGeneration)
        }
    }

    // MARK: - Recall

    /// Returns the top-k most relevant past moments for a query, with decrypted
    /// screenshots, ranked by embedding cosine similarity (falling back to a simple
    /// keyword overlap score when embeddings are unavailable).
    func recall(query: String, topK: Int = 2, minScore: Double = 0.2) async -> [ScreenMemoryRecall] {
        guard isEnabled, !entries.isEmpty else { return [] }
        let queryEmbedding = await embed(query)
        let scored = entries.map { entry -> (ScreenMemoryEntry, Double) in
            let score: Double
            if !queryEmbedding.isEmpty, !entry.embedding.isEmpty {
                score = Self.cosineSimilarity(queryEmbedding, entry.embedding)
            } else {
                score = Self.keywordOverlap(query, "\(entry.transcript) \(entry.ocrText)")
            }
            return (entry, score)
        }
        // Only return genuinely-relevant moments, so an ordinary current-screen
        // question never attaches unrelated old screenshots.
        let top = scored.sorted { $0.1 > $1.1 }.prefix(topK).filter { $0.1 >= minScore }
        let recalls = top.compactMap { (entry, _) -> ScreenMemoryRecall? in
            guard let data = decryptImage(named: entry.imageFileName) else { return nil }
            return ScreenMemoryRecall(entry: entry, imageData: data)
        }
        // Counts/score only — never the query or any stored transcript/reply/OCR text.
        let topScore = top.first?.1 ?? 0
        ClickyTelemetry.screenMemory.info("recall injected \(recalls.count, privacy: .public) moments topScore=\(topScore, privacy: .public)")
        return recalls
    }

    // MARK: - Persistence

    private func persist(entry: ScreenMemoryEntry, imageData: Data, capturedGeneration: Int) {
        // Re-validate on the MainActor: the user may have disabled / paused / purged
        // (or excluded this app) while we were OCR'ing + embedding. If so, drop it.
        guard capturedGeneration == generation, isEnabled, !isPaused else {
            let generationChanged = capturedGeneration != generation
            ClickyTelemetry.screenMemory.notice("persist dropped on re-validation generationChanged=\(generationChanged, privacy: .public) isEnabled=\(self.isEnabled, privacy: .public) isPaused=\(self.isPaused, privacy: .public)")
            return
        }
        if let appName = entry.appName, excludedApps.contains(appName.lowercased()) {
            ClickyTelemetry.screenMemory.notice("persist dropped on re-validation excludedApp=\(true, privacy: .public)")
            return
        }
        guard let sealed = try? encrypt(imageData) else {
            ClickyTelemetry.screenMemory.error("persist encrypt failed — moment not stored")
            return
        }
        try? sealed.write(to: directory.appendingPathComponent(entry.imageFileName), options: .atomic)
        entries.append(entry)
        var evictedOverMaxCount = 0
        if entries.count > maxEntries {
            let overflow = entries.prefix(entries.count - maxEntries)
            for old in overflow {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(old.imageFileName))
            }
            evictedOverMaxCount = entries.count - maxEntries
            entries.removeFirst(entries.count - maxEntries)
        }
        ClickyTelemetry.screenMemory.info("persist stored entryCount=\(self.entries.count, privacy: .public) evictedOverMax=\(evictedOverMaxCount, privacy: .public)")
        saveIndex()
    }

    private func loadIndex() {
        // A missing index on first launch is normal, not a failure — only flag a
        // present-but-unreadable index (decrypt/decode failure) as an error.
        guard let encrypted = try? Data(contentsOf: indexURL) else { return }
        guard let decrypted = try? decrypt(encrypted),
              let decoded = try? JSONDecoder().decode([ScreenMemoryEntry].self, from: decrypted) else {
            ClickyTelemetry.screenMemory.error("loadIndex failed to decrypt/decode index bytes=\(encrypted.count, privacy: .public)")
            return
        }
        entries = decoded
        indexLoaded = true
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(entries),
              let encrypted = try? encrypt(data) else {
            ClickyTelemetry.screenMemory.error("saveIndex failed to encode/encrypt entryCount=\(self.entries.count, privacy: .public)")
            return
        }
        do {
            try encrypted.write(to: indexURL, options: .atomic)
        } catch {
            ClickyTelemetry.screenMemory.error("saveIndex failed to write index bytes=\(encrypted.count, privacy: .public)")
        }
    }

    private func decryptImage(named name: String) -> Data? {
        guard let encrypted = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? decrypt(encrypted)
    }

    // MARK: - Encryption (AES-GCM, key in Keychain)

    private func encrypt(_ data: Data) throws -> Data {
        guard let key = Self.encryptionKey() else {
            ClickyTelemetry.screenMemory.error("encrypt failed — no encryption key available bytes=\(data.count, privacy: .public)")
            throw CocoaError(.coderInvalidValue)
        }
        return try AES.GCM.seal(data, using: key).combined ?? Data()
    }

    private func decrypt(_ data: Data) throws -> Data {
        guard let key = Self.encryptionKey() else {
            ClickyTelemetry.screenMemory.error("decrypt failed — no encryption key available bytes=\(data.count, privacy: .public)")
            throw CocoaError(.coderInvalidValue)
        }
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    /// Loads the symmetric key from the Keychain, creating + persisting one if
    /// absent. Returns nil — failing CLOSED — if a new key can't be persisted, so
    /// we never write data that can't be decrypted after a restart.
    private static func encryptionKey() -> SymmetricKey? {
        if let raw = KeychainManager.retrieve(service: encryptionKeyService),
           let data = Data(base64Encoded: raw) {
            return SymmetricKey(data: data)
        }
        // retrieve() returned nil — either no key exists, or the Keychain was
        // transiently unavailable. Use a NON-destructive add (not delete+add) so a
        // transient read failure can't overwrite an existing key and orphan all
        // previously-encrypted data: errSecDuplicateItem means a key already exists
        // that we just couldn't read, so we fail closed instead of replacing it.
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }.base64EncodedString()
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: encryptionKeyService,
            kSecValueData as String: Data(raw.utf8),
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            ClickyTelemetry.screenMemory.notice("encryptionKey created new key")
            return key
        case errSecDuplicateItem:
            ClickyTelemetry.screenMemory.error("encryptionKey: key exists but is currently unreadable — failing closed, skipping storage this session status=\(status, privacy: .public)")
            return nil
        default:
            ClickyTelemetry.screenMemory.error("encryptionKey: can't persist encryption key — skipping storage status=\(status, privacy: .public)")
            return nil
        }
    }

    // MARK: - OCR + Embeddings

    private nonisolated static func recognizeText(in imageData: Data) -> String {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        let observations = request.results ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private func embed(_ text: String) async -> [Double] {
        guard let embedder, !text.isEmpty else { return [] }
        // NLEmbedding.vector(for:) wants a short string; truncate very long OCR.
        let snippet = String(text.prefix(900))
        return embedder.vector(for: snippet) ?? []
    }

    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]; normA += a[i] * a[i]; normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }

    private static func keywordOverlap(_ query: String, _ text: String) -> Double {
        let q = Set(query.lowercased().split(separator: " ").map(String.init))
        let t = Set(text.lowercased().split(separator: " ").map(String.init))
        guard !q.isEmpty else { return 0 }
        return Double(q.intersection(t).count) / Double(q.count)
    }
}
