//
//  ModelCatalogService.swift
//  leanring-buddy
//
//  Fetches available models from OpenRouter's catalog API.
//

import Foundation

struct ModelInfo: Identifiable, Codable {
    let id: String
    let name: String
    let contextLength: Int?
    let supportsVision: Bool

    /// Short display name (strips provider prefix like "anthropic/")
    var shortName: String {
        if let slashIndex = id.firstIndex(of: "/") {
            return String(id[id.index(after: slashIndex)...])
        }
        return id
    }

    /// Provider prefix (e.g., "anthropic", "google", "openai")
    var providerPrefix: String {
        if let slashIndex = id.firstIndex(of: "/") {
            return String(id[id.startIndex..<slashIndex])
        }
        return "other"
    }
}

@MainActor
class ModelCatalogService: ObservableObject {
    @Published private(set) var models: [ModelInfo] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?

    private var lastFetchDate: Date?
    private static let cacheInterval: TimeInterval = 3600 // 1 hour

    func fetchModelsIfNeeded() {
        if let lastFetch = lastFetchDate,
           Date().timeIntervalSince(lastFetch) < Self.cacheInterval,
           !models.isEmpty {
            return
        }
        fetchModels()
    }

    func fetchModels() {
        guard !isLoading else { return }
        isLoading = true
        lastError = nil

        Task {
            do {
                let url = URL(string: "https://openrouter.ai/api/v1/models")!
                let (data, response) = try await URLSession.shared.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw ProviderError.apiError(statusCode: statusCode, message: "Failed to fetch models")
                }

                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let dataArray = json?["data"] as? [[String: Any]] else {
                    throw ProviderError.invalidResponseFormat
                }

                let parsed: [ModelInfo] = dataArray.compactMap { entry in
                    guard let id = entry["id"] as? String,
                          let name = entry["name"] as? String else { return nil }

                    let contextLength = entry["context_length"] as? Int
                    // Check if model supports vision via architecture modalities
                    let architecture = entry["architecture"] as? [String: Any]
                    let inputModalities = architecture?["modality"] as? String ?? ""
                    let supportsVision = inputModalities.contains("image")

                    return ModelInfo(
                        id: id,
                        name: name,
                        contextLength: contextLength,
                        supportsVision: supportsVision
                    )
                }

                self.models = parsed.sorted { $0.name.lowercased() < $1.name.lowercased() }
                self.lastFetchDate = Date()
                self.isLoading = false
            } catch {
                self.lastError = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    /// Filter models, optionally vision-only
    func filteredModels(query: String, visionOnly: Bool = false) -> [ModelInfo] {
        var result = models
        if visionOnly {
            result = result.filter { $0.supportsVision }
        }
        if !query.isEmpty {
            let lowered = query.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(lowered) || $0.id.lowercased().contains(lowered)
            }
        }
        return result
    }

    /// Group models by provider prefix
    func groupedModels(query: String = "", visionOnly: Bool = false) -> [(provider: String, models: [ModelInfo])] {
        let filtered = filteredModels(query: query, visionOnly: visionOnly)
        let grouped = Dictionary(grouping: filtered) { $0.providerPrefix }
        return grouped
            .map { (provider: $0.key, models: $0.value) }
            .sorted { $0.provider < $1.provider }
    }
}
