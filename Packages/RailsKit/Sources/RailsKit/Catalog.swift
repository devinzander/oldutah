//
//  Catalog.swift
//  Utah Rails
//
//  The site's index (home-page sections) and site map (folders → pages). A
//  snapshot is bundled so Browse and Search work instantly and offline; a
//  live copy is fetched on launch and cached in Application Support.
//  Articles the user opens are cached here too, so re-visits are instant.
//

import Foundation
import Observation

@MainActor
@Observable
final class CatalogStore {
    private(set) var sections: [IndexSection] = []
    private(set) var folders: [SiteFolder] = []
    private(set) var fetched = ""
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    /// Every page in the site map, title-sorted, for search.
    private(set) var allPages: [PageRef] = []
    private var byPath: [String: PageRef] = [:]
    private var folderBySlug: [String: SiteFolder] = [:]

    init() {
        if let cached = Self.load(from: Self.cacheURL) {
            apply(cached)
        } else if let url = Bundle.module.url(forResource: "Catalog", withExtension: "json"),
                  let bundled = Self.load(from: url) {
            apply(bundled)
        }
    }

    private func apply(_ c: Catalog) {
        sections = c.sections
        folders = c.folders
        fetched = c.fetched
        folderBySlug = Dictionary(c.folders.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        var map: [String: PageRef] = [:]
        for f in c.folders { for p in f.pages { map[p.path] = p } }
        byPath = map
        allPages = map.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let names = Dictionary(folders.map { ($0.slug, $0.name) }, uniquingKeysWith: { a, _ in a })
            async let secs = SiteClient.shared.indexSections()
            async let fols = SiteClient.shared.siteMap(names: names)
            let (s, f) = try await (secs, fols)
            guard !f.isEmpty, !s.isEmpty else { return }
            let c = Catalog(fetched: ISO8601DateFormatter().string(from: .now), sections: s, folders: f)
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

    func page(at path: String) -> PageRef? { byPath[path] }
    func folder(_ slug: String) -> SiteFolder? { folderBySlug[slug] }

    /// Title for a path — the site map's, or a readable form of the file name.
    func title(for path: String) -> String {
        if let p = byPath[path] { return p.title }
        let name = (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".html", with: "").replacingOccurrences(of: ".pdf", with: "")
        return name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
    }

    var pageCount: Int { byPath.count }
    var htmlPageCount: Int { byPath.values.filter { !$0.isPDF }.count }
    var pdfCount: Int { byPath.values.filter(\.isPDF).count }

    /// Title search: every word must match somewhere in the title (or the
    /// path); titles that start with the query rank first.
    func search(_ query: String, pdfs: Bool? = nil, folder: String? = nil) -> [PageRef] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let words = q.split(separator: " ").map(String.init)
        var starts: [PageRef] = []
        var titled: [PageRef] = []
        var pathOnly: [PageRef] = []
        for p in allPages {
            if let pdfs, p.isPDF != pdfs { continue }
            if let folder, p.folderSlug != folder { continue }
            let t = p.title.lowercased()
            if words.allSatisfy({ t.contains($0) }) {
                if t.hasPrefix(q) { starts.append(p) } else { titled.append(p) }
            } else {
                let path = p.path.lowercased()
                if words.allSatisfy({ t.contains($0) || path.contains($0) }) { pathOnly.append(p) }
            }
        }
        return starts + titled + pathOnly
    }

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("catalog.json")
    }

    private static func load(from url: URL) -> Catalog? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Catalog.self, from: data)
    }
}

/// Parsed articles, kept for the session so going back is instant.
@MainActor
@Observable
final class ArticleStore {
    private var cache: [String: Article] = [:]
    private var inflight: [String: Task<Article, Error>] = [:]

    func article(_ page: PageRef, reload: Bool = false) async throws -> Article {
        if !reload, let a = cache[page.path] { return a }
        if let t = inflight[page.path] { return try await t.value }
        let task = Task { try await SiteClient.shared.article(page) }
        inflight[page.path] = task
        defer { inflight[page.path] = nil }
        let a = try await task.value
        cache[page.path] = a
        return a
    }

    func cached(_ path: String) -> Article? { cache[path] }
}
