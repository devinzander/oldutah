//
//  SavedStore.swift
//  City Cemetery
//
//  Graves the user keeps, and recent searches — on the device only.
//

import Foundation
import Observation

struct SavedGrave: Codable, Identifiable, Hashable {
    var record: GraveRecord
    let savedAt: Date
    var id: String { record.id }
}

@MainActor
@Observable
final class SavedStore {
    private(set) var items: [SavedGrave] = []
    private(set) var recentSearches: [String] = []

    private let itemsKey = "cemetery.saved.graves"
    private let searchesKey = "cemetery.saved.searches"

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: itemsKey), let decoded = try? JSONDecoder().decode([SavedGrave].self, from: data) { items = decoded }
        recentSearches = d.stringArray(forKey: searchesKey) ?? []
    }

    func isSaved(_ id: String) -> Bool { items.contains { $0.id == id } }

    func toggle(_ record: GraveRecord) {
        if let i = items.firstIndex(where: { $0.id == record.id }) {
            items.remove(at: i)
        } else {
            items.insert(SavedGrave(record: record, savedAt: .now), at: 0)
        }
        persist()
    }

    /// Keeps the saved copy current once the full record has loaded.
    func refresh(_ record: GraveRecord) {
        guard let i = items.firstIndex(where: { $0.id == record.id }) else { return }
        items[i].record = record
        persist()
    }

    func remove(_ id: String) {
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
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: itemsKey) }
    }
}
