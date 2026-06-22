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
import CryptoKit
import Foundation
import NaturalLanguage
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

    private init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("ClickyScreenMemory", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.enc")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadIndex()
    }

    // MARK: - Controls

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "screenMemoryEnabled")
    }

    func setPaused(_ paused: Bool) { isPaused = paused }

    func setExcludedApps(_ apps: Set<String>) {
        let lowercased = Set(apps.map { $0.lowercased() })
        excludedApps = lowercased
        UserDefaults.standard.set(Array(lowercased), forKey: "screenMemoryExcludedApps")
    }

    /// Deletes all stored moments (index + screenshots).
    func purge() {
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
            await self.persist(entry: entry, imageData: imageData)
        }
    }

    // MARK: - Recall

    /// Returns the top-k most relevant past moments for a query, with decrypted
    /// screenshots, ranked by embedding cosine similarity (falling back to a simple
    /// keyword overlap score when embeddings are unavailable).
    func recall(query: String, topK: Int = 2) async -> [ScreenMemoryRecall] {
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
        let top = scored.sorted { $0.1 > $1.1 }.prefix(topK).filter { $0.1 > 0 }
        return top.compactMap { (entry, _) in
            guard let data = decryptImage(named: entry.imageFileName) else { return nil }
            return ScreenMemoryRecall(entry: entry, imageData: data)
        }
    }

    // MARK: - Persistence

    private func persist(entry: ScreenMemoryEntry, imageData: Data) {
        guard let sealed = try? encrypt(imageData) else { return }
        try? sealed.write(to: directory.appendingPathComponent(entry.imageFileName), options: .atomic)
        entries.append(entry)
        if entries.count > maxEntries {
            let overflow = entries.prefix(entries.count - maxEntries)
            for old in overflow {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(old.imageFileName))
            }
            entries.removeFirst(entries.count - maxEntries)
        }
        saveIndex()
    }

    private func loadIndex() {
        guard let encrypted = try? Data(contentsOf: indexURL),
              let decrypted = try? decrypt(encrypted),
              let decoded = try? JSONDecoder().decode([ScreenMemoryEntry].self, from: decrypted) else {
            return
        }
        entries = decoded
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(entries),
              let encrypted = try? encrypt(data) else { return }
        try? encrypted.write(to: indexURL, options: .atomic)
    }

    private func decryptImage(named name: String) -> Data? {
        guard let encrypted = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? decrypt(encrypted)
    }

    // MARK: - Encryption (AES-GCM, key in Keychain)

    private func encrypt(_ data: Data) throws -> Data {
        let key = Self.encryptionKey()
        return try AES.GCM.seal(data, using: key).combined ?? Data()
    }

    private func decrypt(_ data: Data) throws -> Data {
        let key = Self.encryptionKey()
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    /// Loads (or creates + stores) the symmetric key from the Keychain.
    private static func encryptionKey() -> SymmetricKey {
        if let raw = KeychainManager.retrieve(service: encryptionKeyService),
           let data = Data(base64Encoded: raw) {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }.base64EncodedString()
        if !KeychainManager.save(key: raw, service: encryptionKeyService) {
            // If the key can't be persisted, this session's data won't be
            // readable next launch — surface it rather than silently losing data.
            print("⚠️ ScreenMemoryStore: failed to persist encryption key to Keychain")
        }
        return key
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
