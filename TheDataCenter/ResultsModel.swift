//
//  ResultsModel.swift
//  The Data Center
//
//  One paged search — the same object drives the Search tab, a collection,
//  an institution, a topic and the Recent feed.
//

import Foundation
import Observation

@MainActor
@Observable
final class ResultsModel {
    var query: SearchQuery {
        didSet { if query != oldValue { reload() } }
    }
    private(set) var hits: [SearchHit] = []
    private(set) var total: Int?
    private(set) var facets: [FacetGroup] = []
    /// Format chips stay put while one is applied: the site only reports the
    /// chosen format back, so the list is remembered from the last unfiltered
    /// load of this query.
    private(set) var formatOptions: [FacetValue] = []
    private(set) var yearRange: ClosedRange<Int>?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var error: String?
    private(set) var hasMore = false

    private var task: Task<Void, Never>?
    private var generation = 0

    init(query: SearchQuery) {
        self.query = query
    }

    var loaded: Bool { total != nil }

    func loadIfNeeded() {
        if total == nil && !isLoading { reload() }
    }

    func reload() {
        task?.cancel()
        generation += 1
        let gen = generation
        var q = query
        q.page = 1
        isLoading = true
        error = nil
        task = Task {
            do {
                let page = try await UDLClient.shared.search(q)
                guard gen == generation, !Task.isCancelled else { return }
                hits = Self.naturallyOrdered(page.hits)
                total = page.total
                facets = page.facets
                if !q.filters.contains(where: { $0.field == "facet_format_t" }) || formatOptions.isEmpty {
                    formatOptions = page.facets.first { $0.field == "facet_format_t" }?.values ?? []
                }
                yearRange = page.yearRange
                hasMore = page.hasMore
                isLoading = false
            } catch is CancellationError {
            } catch {
                guard gen == generation else { return }
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func loadMore(after hit: SearchHit) {
        guard hasMore, !isLoading, !isLoadingMore,
              hits.suffix(5).contains(where: { $0.id == hit.id }) else { return }
        let gen = generation
        var q = query
        q.page = hits.count / max(query.rows, 1) + 1
        isLoadingMore = true
        Task {
            defer { if gen == generation { isLoadingMore = false } }
            do {
                let page = try await UDLClient.shared.search(q)
                guard gen == generation else { return }
                let known = Set(hits.map(\.id))
                hits.append(contentsOf: Self.naturallyOrdered(page.hits.filter { !known.contains($0.id) }))
                hasMore = page.hasMore && !page.hits.isEmpty
            } catch {
                guard gen == generation else { return }
                hasMore = false
            }
        }
    }

    /// The site ranks by relevance, which scatters serial titles — "part 1,
    /// part 4, part 2, part 3". Runs of consecutive hits whose titles differ
    /// only in their numbers are put in numeric order; everything else keeps
    /// the site's ranking.
    static func naturallyOrdered(_ hits: [SearchHit]) -> [SearchHit] {
        guard hits.count > 1 else { return hits }
        func skeleton(_ t: String) -> String {
            t.lowercased().filter { !$0.isNumber }.trimmingCharacters(in: .whitespaces)
        }
        var out: [SearchHit] = []
        var run: [SearchHit] = []
        var key = ""
        func flush() {
            if run.count > 1 {
                out.append(contentsOf: run.sorted {
                    $0.title.compare($1.title, options: [.numeric, .caseInsensitive]) == .orderedAscending
                })
            } else {
                out.append(contentsOf: run)
            }
            run = []
        }
        for h in hits {
            let k = skeleton(h.title)
            if k != key { flush(); key = k }
            run.append(h)
        }
        flush()
        return out
    }

    // Each mutation is applied to a copy and assigned once, so `didSet`
    // reloads a single time.
    func apply(_ filter: FacetFilter) { var q = query; q.set(filter); query = q }
    func remove(_ filter: FacetFilter) { var q = query; q.remove(filter); query = q }
    func setSort(_ sort: SortOrder) { var q = query; q.sort = sort; q.page = 1; query = q }
    func setYears(_ range: ClosedRange<Int>?) {
        var q = query
        q.yearStart = range?.lowerBound
        q.yearEnd = range?.upperBound
        q.page = 1
        query = q
    }
    func setText(_ text: String) { var q = query; q.text = text; q.page = 1; query = q }
    /// Replace the type constraint (search scopes) — nil clears it.
    func setType(_ filter: FacetFilter?) {
        var q = query
        q.filters.removeAll { $0.field == "facet_type_t" }
        if let filter { q.filters.append(filter) }
        q.page = 1
        query = q
    }
}
