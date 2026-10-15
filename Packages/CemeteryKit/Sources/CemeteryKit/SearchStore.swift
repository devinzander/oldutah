//
//  SearchStore.swift
//  City Cemetery
//
//  One name, every register at once. Each cemetery with records is asked in
//  parallel and its group fills in as it answers; the two mapped cemeteries
//  come first because they can show the grave.
//

import Foundation
import Observation

struct SearchGroup: Identifiable {
    let cemetery: Cemetery
    var records: [GraveRecord] = []
    var error: String?
    var done = false
    var id: String { cemetery.id }
}

@MainActor
@Observable
final class SearchStore {
    var text = ""
    /// A cemetery id, or nil for all of them.
    var scope: String?
    private(set) var submitted: NameQuery?
    private(set) var groups: [SearchGroup] = []
    private(set) var isSearching = false
    private var task: Task<Void, Never>?

    var total: Int { groups.reduce(0) { $0 + $1.records.count } }
    var scopeCemetery: Cemetery? { scope.flatMap { Cemeteries.byID[$0] } }

    func clear() {
        task?.cancel()
        submitted = nil
        groups = []
        isSearching = false
    }

    func search(_ raw: String) {
        let query = NameQuery(raw)
        guard !query.isEmpty else { clear(); return }
        task?.cancel()
        submitted = query
        let targets = Cemeteries.withRecords.filter { scope == nil || $0.id == scope }
        groups = targets.map { SearchGroup(cemetery: $0) }
        isSearching = true
        task = Task { [weak self] in
            await withTaskGroup(of: (String, Result<[GraveRecord], Error>).self) { group in
                for c in targets {
                    group.addTask {
                        do {
                            let r = try await Self.fetch(c, query)
                            return (c.id, .success(r))
                        } catch {
                            return (c.id, .failure(error))
                        }
                    }
                }
                for await (id, result) in group {
                    guard !Task.isCancelled, let self, let i = self.groups.firstIndex(where: { $0.id == id }) else { continue }
                    switch result {
                    case .success(let records): self.groups[i].records = records
                    case .failure(let e): self.groups[i].error = e.localizedDescription
                    }
                    self.groups[i].done = true
                }
            }
            guard !Task.isCancelled else { return }
            self?.isSearching = false
        }
    }

    nonisolated static func fetch(_ c: Cemetery, _ q: NameQuery) async throws -> [GraveRecord] {
        switch c.source {
        case .arcgis(let config): return try await ArcGIS.searchGraves(config, cemeteryID: c.id, query: q)
        case .state(let filter): return try await StateRecords.search(cemetery: c, filter: filter, query: q)
        case .va(let code): return try await VALocator.search(cemetery: c, code: code, query: q)
        case .none: return []
        }
    }
}
