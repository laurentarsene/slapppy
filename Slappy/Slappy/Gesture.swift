//
//  Gesture.swift
//  Slappy
//
//  Created by Arsène Laurent on 28/03/2026.
//

import Foundation

// MARK: - GesturePoint

struct GesturePoint: Codable, Equatable {
    var x: Double
    var y: Double
}

// MARK: - GestureTemplate

struct GestureTemplate: Identifiable, Codable, Equatable {
    var id:     UUID           = UUID()
    var name:   String
    var path:   [GesturePoint] // normalised by DollarOneRecognizer
    var action: PatternAction  = .none
}

// MARK: - GestureStore

@Observable
final class GestureStore {
    private(set) var templates: [GestureTemplate] = []

    private let saveKey = "slappy.gestures"

    init() { load() }

    func add(_ t: GestureTemplate)        { templates.append(t); save() }
    func remove(id: UUID)                  { templates.removeAll { $0.id == id }; save() }

    func rename(id: UUID, to name: String) {
        guard let i = templates.firstIndex(where: { $0.id == id }) else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        templates[i].name = n.isEmpty ? "Geste" : n
        save()
    }

    func setAction(_ action: PatternAction, forID id: UUID) {
        guard let i = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[i].action = action
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    private func load() {
        guard let data  = UserDefaults.standard.data(forKey: saveKey),
              let saved = try? JSONDecoder().decode([GestureTemplate].self, from: data)
        else { return }
        templates = saved
    }
}
