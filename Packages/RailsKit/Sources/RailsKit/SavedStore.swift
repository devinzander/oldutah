//
//  SavedStore.swift
//  Utah Rails
//
//  Bookmarked pages, reading history and recent searches — on-device only.
//

import Foundation
import Observation

struct SavedPage: Codable, Identifiable, Hashable {
    let page: PageRef
    let savedAt: Date
    var id: String { page.path }
}

@MainActor
@Observable
final class SavedStore {
    private(set) var items: [SavedPage] = []
    private(set) var history: [SavedPage] = []
    private(set) var recentSearches: [String] = []

    private let itemsKey = "rails.saved.pages"
    private let historyKey = "rails.saved.history"
    private let searchesKey = "rails.saved.searches"

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: itemsKey), let decoded = try? JSONDecoder().decode([SavedPage].self, from: data) { items = decoded }
        if let data = d.data(forKey: historyKey), let decoded = try? JSONDecoder().decode([SavedPage].self, from: data) { history = decoded }
        recentSearches = d.stringArray(forKey: searchesKey) ?? []
    }

    func isSaved(_ path: String) -> Bool { items.contains { $0.id == path } }

    func toggle(_ page: PageRef) {
        if let i = items.firstIndex(where: { $0.id == page.path }) {
            items.remove(at: i)
        } else {
            items.insert(SavedPage(page: page, savedAt: .now), at: 0)
        }
        persist(items, itemsKey)
    }

    func remove(_ path: String) {
        items.removeAll { $0.id == path }
        persist(items, itemsKey)
    }

    func removeAll() {
        items.removeAll()
        persist(items, itemsKey)
    }

    func noteVisit(_ page: PageRef) {
        history.removeAll { $0.id == page.path }
        history.insert(SavedPage(page: page, savedAt: .now), at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
        persist(history, historyKey)
    }

    func clearHistory() {
        history.removeAll()
        persist(history, historyKey)
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

    private func persist(_ list: [SavedPage], _ key: String) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }
}
