//
//  SavedStore.swift
//  The Data Center
//
//  Bookmarked items and recent searches — on-device only.
//

import Foundation
import Observation

struct SavedItem: Codable, Identifiable, Hashable {
    let hit: SearchHit
    let savedAt: Date
    var id: Int { hit.id }
}

@MainActor
@Observable
final class SavedStore {
    private(set) var items: [SavedItem] = []
    private(set) var recentSearches: [String] = []

    private let itemsKey = "saved.items"
    private let searchesKey = "saved.searches"

    init() {
        if let data = UserDefaults.standard.data(forKey: itemsKey),
           let decoded = try? JSONDecoder().decode([SavedItem].self, from: data) {
            items = decoded
        }
        recentSearches = UserDefaults.standard.stringArray(forKey: searchesKey) ?? []
    }

    func isSaved(_ id: Int) -> Bool { items.contains { $0.id == id } }

    func toggle(_ hit: SearchHit) {
        if let i = items.firstIndex(where: { $0.id == hit.id }) {
            items.remove(at: i)
        } else {
            items.insert(SavedItem(hit: hit, savedAt: .now), at: 0)
        }
        persist()
    }

    func remove(_ id: Int) {
        items.removeAll { $0.id == id }
        persist()
    }

    func removeAll() {
        items.removeAll()
        persist()
    }

    func noteSearch(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(t) == .orderedSame }
        recentSearches.insert(t, at: 0)
        if recentSearches.count > 8 { recentSearches.removeLast(recentSearches.count - 8) }
        UserDefaults.standard.set(recentSearches, forKey: searchesKey)
    }

    func clearSearches() {
        recentSearches.removeAll()
        UserDefaults.standard.set(recentSearches, forKey: searchesKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: itemsKey)
        }
    }
}
