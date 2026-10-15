//
//  Site.swift
//  Utah Rails
//
//  Client for utahrails.net — Don Strack's static, hand-written site. No
//  API: the app reads the same HTML a browser does. Pages that don't exist
//  come back as the home page with a 200, so the client checks the canonical
//  link. Everything goes through URLCache so pages you've read are there
//  offline.
//

import Foundation

enum Site {
    static let base = URL(string: "https://utahrails.net")!
    static let host = "utahrails.net"
    static let homePath = "/index.html"
    static let whatsNewPath = "/whatsnew.html"
    static let recentPath = "/utahrails-recent-updates.html"
    static let aboutPath = "/about.html"
    static let contactPath = "/contactme.html"
    static let copyrightPath = "/copyright-info.html"
    static let sitemapPaths = ["/sitemap_4372390.html", "/sitemap_4372390_2.html", "/sitemap_4372390_3.html"]

    static func absolute(_ path: String) -> URL {
        if path.hasPrefix("http://") || path.hasPrefix("https://"), let u = URL(string: path) { return u }
        return URL(string: path, relativeTo: base)?.absoluteURL ?? base
    }

    /// Site-relative path for a utahrails.net URL, nil for anything else.
    static func path(of url: URL) -> String? {
        guard let host = url.host?.lowercased(), host == Site.host || host == "www." + Site.host else { return nil }
        var p = url.path
        if p.isEmpty || p == "/" { p = homePath }
        return p
    }

    static func isSmugMug(_ url: URL) -> Bool {
        (url.host ?? "").lowercased().hasSuffix("donstrack.smugmug.com")
    }

    /// The site's own search is a Google site: search.
    static func googleSearch(_ q: String) -> URL {
        var c = URLComponents(string: "https://www.google.com/search")!
        c.queryItems = [URLQueryItem(name: "q", value: "site:utahrails.net \(q)")]
        return c.url!
    }
}

enum SiteError: LocalizedError {
    case status(Int)
    case notFound
    case offline

    var errorDescription: String? {
        switch self {
        case .status(let code): return "utahrails.net answered with an error (\(code))."
        case .notFound: return "That page isn't on utahrails.net any more."
        case .offline: return "You're offline, and this page hasn't been read on this device yet."
        }
    }
}

actor SiteClient {
    static let shared = SiteClient()

    private let session: URLSession
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1 UtahRailsApp/1.0"

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache.shared
        config.httpAdditionalHeaders = [
            "Accept": "text/html,application/xhtml+xml,application/pdf;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
            "User-Agent": Self.userAgent,
        ]
        session = URLSession(configuration: config)
    }

    /// Raw HTML for a site path. Falls back to the cache when offline.
    func html(_ path: String) async throws -> String {
        let url = Site.absolute(path)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let e as URLError where e.code == .notConnectedToInternet || e.code == .networkConnectionLost || e.code == .timedOut || e.code == .cannotFindHost {
            var req = URLRequest(url: url)
            req.cachePolicy = .returnCacheDataDontLoad
            guard let cached = try? await session.data(for: req) else { throw SiteError.offline }
            (data, response) = cached
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw code == 404 ? SiteError.notFound : SiteError.status(code)
        }
        let text = String(decoding: data, as: UTF8.self)
        // Missing pages are served as the home page with a 200.
        if path != Site.homePath, let canonical = HTML.canonicalPath(text), canonical == Site.homePath {
            throw SiteError.notFound
        }
        return text
    }

    func article(_ page: PageRef) async throws -> Article {
        let text = try await html(page.path)
        return ArticleParser.article(from: text, page: page)
    }

    func whatsNew() async throws -> [NewsEntry] {
        NewsParser.entries(from: try await html(Site.whatsNewPath))
    }

    func recentUpdates() async throws -> [RecentUpdate] {
        NewsParser.recent(from: try await html(Site.recentPath))
    }

    /// The site map's folders, live.
    func siteMap(names: [String: String]) async throws -> [SiteFolder] {
        var pages: [(String, String)] = []
        for p in Site.sitemapPaths {
            pages += SitemapParser.pages(from: try await html(p))
        }
        return SitemapParser.folders(from: pages, names: names)
    }

    func indexSections() async throws -> [IndexSection] {
        IndexParser.sections(from: try await html(Site.homePath))
    }

    /// Bytes of a site file (PDF), cache-backed.
    func data(_ url: URL) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { throw SiteError.status(code) }
            return data
        } catch let e as URLError where e.code == .notConnectedToInternet || e.code == .networkConnectionLost {
            var req = URLRequest(url: url)
            req.cachePolicy = .returnCacheDataDontLoad
            guard let (data, _) = try? await session.data(for: req) else { throw SiteError.offline }
            return data
        }
    }
}

// MARK: - SmugMug

/// Don Strack's photo albums live on SmugMug (donstrack.smugmug.com). The
/// site's own pages carry the API key their JavaScript uses; the client
/// reads it from the page, remembers it, and re-reads it if the API ever
/// answers 401. Only public, read-only endpoints are used.
enum Smug {
    static let host = "donstrack.smugmug.com"
    static let web = URL(string: "https://donstrack.smugmug.com")!
    static let api = URL(string: "https://api.smugmug.com")!
    static let nickname = "donstrack"
    /// The "UtahRails" top folder — the only child of the site root.
    static let rootPath = "/UtahRails"
}

enum SmugError: LocalizedError {
    case status(Int)
    case noKey
    case notFound
    case offline

    var errorDescription: String? {
        switch self {
        case .status(let code): return "SmugMug answered with an error (\(code))."
        case .noKey: return "Couldn't reach Don Strack's photo albums. Try again in a moment."
        case .notFound: return "That album isn't on SmugMug any more."
        case .offline: return "You're offline. The albums need a connection."
        }
    }
}

actor SmugClient {
    static let shared = SmugClient()

    private let session: URLSession
    private static let keyDefault = "smug.apiKey"
    private static let observedKey = "W0g9oqdOrzuhEpIQ2qaTXimrzsfryKSZ"   // as seen on the site 2026-09-17
    private var apiKey: String

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.urlCache = URLCache.shared
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Accept-Language": "en-US,en;q=0.9",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
        ]
        session = URLSession(configuration: config)
        apiKey = UserDefaults.standard.string(forKey: Self.keyDefault) ?? Self.observedKey
    }

    /// Read the key the site's own JavaScript uses from the home page.
    private func discoverKey() async -> String? {
        var req = URLRequest(url: Smug.web)
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await session.data(for: req) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard let m = RX.smugKey.first(in: text) else { return nil }
        return m[1]
    }

    private func get(_ path: String, _ query: [String: String]) async throws -> [String: Any] {
        var attempt = 0
        while true {
            attempt += 1
            var comps = URLComponents(url: Smug.api.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
            var items = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            items.append(URLQueryItem(name: "APIKey", value: apiKey))
            comps.queryItems = items
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(from: comps.url!)
            } catch let e as URLError where e.code == .notConnectedToInternet || e.code == .networkConnectionLost {
                throw SmugError.offline
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403, attempt == 1, let fresh = await discoverKey(), fresh != apiKey {
                apiKey = fresh
                UserDefaults.standard.set(fresh, forKey: Self.keyDefault)
                continue
            }
            if code == 404 { throw SmugError.notFound }
            guard (200..<300).contains(code) else { throw code == 401 ? SmugError.noKey : SmugError.status(code) }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let resp = json["Response"] as? [String: Any] else { throw SmugError.status(code) }
            var out = resp
            out["_expansions"] = json["Expansions"] as? [String: Any] ?? [:]
            return out
        }
    }

    // MARK: Nodes

    private static let nodeFilter = "Name,Type,NodeID,UrlPath,DateModified,HasChildren,Description"

    /// Children of a folder node: sub-folders and albums, with their
    /// highlight thumbnails.
    func children(of nodeID: String, start: Int = 1, count: Int = 100) async throws -> SmugPage<SmugNode> {
        let r = try await get("/api/v2/node/\(nodeID)!children", [
            "count": String(count), "start": String(start), "_verbosity": "1",
            "_expand": "HighlightImage", "_filter": Self.nodeFilter, "_filteruri": "Album,HighlightImage",
        ])
        let expansions = r["_expansions"] as? [String: Any] ?? [:]
        let nodes = (r["Node"] as? [[String: Any]] ?? []).compactMap { Self.node($0, expansions: expansions) }
        return Self.page(nodes, r)
    }

    /// Resolve a SmugMug web path to what lives there.
    enum Lookup { case folder(SmugNode), album(SmugAlbum) }

    func lookup(path: String) async throws -> Lookup {
        let r = try await get("/api/v2/user/\(Smug.nickname)!urlpathlookup", [
            "urlpath": path, "_verbosity": "1", "_filteruri": "Album,HighlightImage,Node",
        ])
        if let a = r["Album"] as? [String: Any], let album = Self.album(a) { return .album(album) }
        if let f = r["Folder"] as? [String: Any] {
            let node = SmugNode(nodeID: f["NodeID"] as? String ?? "", name: f["Name"] as? String ?? "",
                                type: .folder, urlPath: f["UrlPath"] as? String ?? path,
                                description: f["Description"] as? String ?? "",
                                dateModified: f["DateModified"] as? String ?? "", hasChildren: true,
                                albumKey: nil, highlight: nil)
            return .folder(node)
        }
        throw SmugError.notFound
    }

    func album(key: String) async throws -> SmugAlbum {
        let r = try await get("/api/v2/album/\(key)", [
            "_filter": "AlbumKey,Name,Title,Description,ImageCount,LastUpdated,UrlPath,NodeID", "_filteruri": "",
        ])
        guard let a = r["Album"] as? [String: Any], let album = Self.album(a) else { throw SmugError.notFound }
        return album
    }

    private static let imageFilter = "ImageKey,Title,Caption,Keywords,FileName,ThumbnailUrl,OriginalWidth,OriginalHeight,IsVideo,Format,Date"

    func images(album key: String, start: Int = 1, count: Int = 60) async throws -> SmugPage<SmugImage> {
        let r = try await get("/api/v2/album/\(key)!images", [
            "count": String(count), "start": String(start), "_verbosity": "1",
            "_filter": Self.imageFilter, "_filteruri": "",
        ])
        let images = (r["AlbumImage"] as? [[String: Any]] ?? []).compactMap(Self.image)
        return Self.page(images, r)
    }

    func image(key: String) async throws -> SmugImage {
        let r = try await get("/api/v2/image/\(key)", ["_filter": Self.imageFilter, "_filteruri": ""])
        guard let i = r["Image"] as? [String: Any], let image = Self.image(i) else { throw SmugError.notFound }
        return image
    }

    // MARK: Decoding

    private static func page<T: Hashable>(_ items: [T], _ r: [String: Any]) -> SmugPage<T> {
        let pages = r["Pages"] as? [String: Any] ?? [:]
        let total = pages["Total"] as? Int ?? items.count
        let start = pages["Start"] as? Int ?? 1
        let count = pages["Count"] as? Int ?? items.count
        let next = start + count <= total ? start + count : nil
        return SmugPage(items: items, total: total, next: items.isEmpty ? nil : next)
    }

    /// SmugMug descriptions may carry HTML and Don's "||" separators.
    private static func plain(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        return HTML.text(s).replacingOccurrences(of: " || ", with: " ").replacingOccurrences(of: "||", with: " ")
            .replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    private static func node(_ n: [String: Any], expansions: [String: Any]) -> SmugNode? {
        guard let id = n["NodeID"] as? String, let name = n["Name"] as? String,
              let type = SmugNodeType(rawValue: n["Type"] as? String ?? ""), type != .page else { return nil }
        let uris = n["Uris"] as? [String: Any] ?? [:]
        var albumKey: String? = nil
        if let a = uris["Album"] as? String { albumKey = a.split(separator: "/").last.map(String.init) }
        var highlight: URL? = nil
        if let h = uris["HighlightImage"] as? String, let exp = expansions[h] as? [String: Any],
           let img = exp["Image"] as? [String: Any], let t = img["ThumbnailUrl"] as? String {
            highlight = URL(string: t)
        }
        return SmugNode(nodeID: id, name: name, type: type, urlPath: n["UrlPath"] as? String ?? "",
                        description: Self.plain(n["Description"] as? String),
                        dateModified: n["DateModified"] as? String ?? "",
                        hasChildren: n["HasChildren"] as? Bool ?? (type == .folder),
                        albumKey: albumKey, highlight: highlight)
    }

    private static func album(_ a: [String: Any]) -> SmugAlbum? {
        guard let key = a["AlbumKey"] as? String else { return nil }
        return SmugAlbum(albumKey: key, nodeID: a["NodeID"] as? String ?? "",
                         name: (a["Title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? a["Name"] as? String ?? "",
                         description: Self.plain(a["Description"] as? String),
                         imageCount: a["ImageCount"] as? Int ?? 0,
                         urlPath: a["UrlPath"] as? String ?? "",
                         lastUpdated: a["LastUpdated"] as? String ?? "")
    }

    private static func image(_ i: [String: Any]) -> SmugImage? {
        guard let key = i["ImageKey"] as? String, let t = i["ThumbnailUrl"] as? String, let thumb = URL(string: t) else { return nil }
        let keywords = (i["Keywords"] as? String ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return SmugImage(imageKey: key, title: Self.plain(i["Title"] as? String), caption: Self.plain(i["Caption"] as? String),
                         keywords: keywords, fileName: i["FileName"] as? String ?? "", thumbnail: thumb,
                         width: i["OriginalWidth"] as? Int ?? 0, height: i["OriginalHeight"] as? Int ?? 0,
                         isVideo: i["IsVideo"] as? Bool ?? false, date: i["Date"] as? String ?? "")
    }
}

extension String {
    /// "2026-08-24T11:17:57+00:00" → "Aug 24, 2026"
    var isoDateLabel: String {
        guard count >= 10, let d = ISO8601DateFormatter().date(from: self) ?? ISO8601DateFormatter().date(from: String(prefix(19)) + "Z") else { return self }
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}
