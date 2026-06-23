//
//  SpokenMacroStore.swift
//  leanring-buddy
//
//  Named, voice-recorded macros. A macro is an ordered list of natural-language
//  steps; replay runs each step through the normal companion pipeline so every step
//  re-resolves against the LIVE screen (point/act).
//
//  ponytail: steps are plain instructions replayed through the existing pipeline,
//  not recorded coordinate/AX-event sequences. Robust to layout changes and reuses
//  all of F1's actuation + confirmation; upgrade to recorded AX events only if
//  deterministic replay is ever needed.
//

import Combine
import os
import Foundation

struct SpokenMacro: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var steps: [String]
}

@MainActor
final class SpokenMacroStore: ObservableObject {
    static let shared = SpokenMacroStore()
    @Published private(set) var macros: [SpokenMacro] = []
    private let defaultsKey = "spokenMacros"

    private init() { load() }

    func macro(named name: String) -> SpokenMacro? {
        let target = name.lowercased().trimmingCharacters(in: .whitespaces)
        return macros.first { $0.name.lowercased() == target }
    }

    func save(name: String, steps: [String]) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !steps.isEmpty else { return }
        macros.removeAll { $0.name.lowercased() == trimmedName.lowercased() }
        macros.append(SpokenMacro(name: trimmedName, steps: steps))
        ClickyTelemetry.spokenMacros.info("save macro name=\(trimmedName, privacy: .public) stepCount=\(steps.count, privacy: .public)")
        persist()
    }

    func delete(named name: String) {
        macros.removeAll { $0.name.lowercased() == name.lowercased() }
        ClickyTelemetry.spokenMacros.info("delete macro name=\(name, privacy: .public)")
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        do {
            macros = try JSONDecoder().decode([SpokenMacro].self, from: data)
            ClickyTelemetry.spokenMacros.info("load macros macroCount=\(self.macros.count, privacy: .public)")
        } catch {
            ClickyTelemetry.spokenMacros.error("load decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(macros)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            ClickyTelemetry.spokenMacros.error("persist encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
