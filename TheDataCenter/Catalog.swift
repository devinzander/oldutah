//
//  Catalog.swift
//  The Data Center
//
//  The institution → collection catalog and the topic list. A snapshot is
//  bundled so the Browse tab renders instantly (and offline); a live copy is
//  fetched on launch and cached in Application Support.
//

import Foundation
import Observation

@MainActor
@Observable
final class CatalogStore {
    private(set) var institutions: [Institution] = []
    private(set) var topics: [Topic] = []
    private(set) var fetched = ""
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    private var bySetname: [String: Collection] = [:]
    private var byPrefix: [String: Institution] = [:]

    /// Every collection, title-sorted, for the A–Z browse and search suggestions.
    private(set) var allCollections: [Collection] = []

    init() {
        if let cached = Self.load(from: Self.cacheURL) {
            apply(cached)
        } else if let url = Bundle.main.url(forResource: "Catalog", withExtension: "json"),
                  let bundled = Self.load(from: url) {
            apply(bundled)
        }
    }

    private func apply(_ c: Catalog) {
        institutions = c.institutions
        topics = c.topics
        fetched = c.fetched
        byPrefix = Dictionary(uniqueKeysWithValues: c.institutions.map { ($0.prefix, $0) })
        var map: [String: Collection] = [:]
        for i in c.institutions { for col in i.collections { map[col.setname] = col } }
        bySetname = map
        allCollections = map.values.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            async let insts = UDLClient.shared.institutions()
            async let tops = UDLClient.shared.topics()
            let (i, t) = try await (insts, tops)
            guard !i.isEmpty else { return }
            let c = Catalog(fetched: ISO8601DateFormatter().string(from: .now), institutions: i, topics: t.isEmpty ? topics : t)
            apply(c)
            lastError = nil
            if let data = try? JSONEncoder().encode(c) {
                try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: Self.cacheURL, options: .atomic)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func collection(_ setname: String) -> Collection? { bySetname[setname] }

    func institution(prefix: String) -> Institution? { byPrefix[prefix] }

    func institution(forSetname setname: String) -> Institution? {
        byPrefix[setname.split(separator: "_").first.map(String.init) ?? ""]
    }

    /// Display title for a setname, falling back to the code itself.
    func title(forSetname setname: String) -> String {
        bySetname[setname]?.title ?? setname
    }

    /// Human label for a facet value — collection and institution codes
    /// become their names.
    func label(for filter: FacetFilter) -> String {
        if filter.isInstitution, let i = byPrefix[filter.bareValue] { return i.name }
        if filter.isCollection, let c = bySetname[filter.bareValue] { return c.title }
        if filter.field == "facet_type_t" { return Brand.typeLabel(filter.bareValue) }
        if filter.field == "facet_format_t" { return Brand.formatLabel(filter.bareValue) }
        return filter.label
    }

    var collectionCount: Int { bySetname.count }

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("catalog.json")
    }

    private static func load(from url: URL) -> Catalog? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Catalog.self, from: data)
    }
}
