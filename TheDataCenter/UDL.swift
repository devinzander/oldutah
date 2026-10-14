//
//  UDL.swift
//  The Data Center
//
//  Client for the J. Willard Marriott Digital Library at the University of
//  Utah (collections.lib.utah.edu). The site fronts its HTML with a small
//  JavaScript cookie challenge (HTTP 418 + an obfuscated script that sets a
//  cookie and reloads). Images and files are served without it. The client
//  carries the last known cookie and, when the site rotates it, runs the
//  challenge script inside a bare JavaScriptCore context — no DOM, no
//  network, no storage — to learn the new cookie, then retries.
//

import Foundation
import JavaScriptCore

enum UDL {
    static let base = URL(string: "https://collections.lib.utah.edu")!
    static let host = "collections.lib.utah.edu"
    /// Site links the app hands off to Safari.
    static let askURL = URL(string: "https://forms.lib.utah.edu/dl-feedback/")!
    static let harmfulLanguageURL = URL(string: "https://lib.utah.edu/services/digital-library/index.php#tab7")!
    static let libraryURL = URL(string: "https://lib.utah.edu")!

    static func absolute(_ path: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    static func collectionThumbnail(_ setname: String) -> URL {
        base.appendingPathComponent("dl_custom/thumbnails/\(setname).jpg")
    }
}

enum UDLError: LocalizedError {
    case status(Int)
    case challenge
    case offline

    var errorDescription: String? {
        switch self {
        case .status(let code): return "The library's site answered with an error (\(code))."
        case .challenge: return "The library's site is checking that you're a person. Try again in a moment."
        case .offline: return "You're offline. The archive needs a connection."
        }
    }
}

actor UDLClient {
    static let shared = UDLClient()

    private let session: URLSession
    private static let cookieName = "t7COUOGwZmurvFA6"   // as observed 2026-09-17
    private static let cookieKey = "udl.challengeCookie"

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "Accept": "text/html,application/xhtml+xml",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        session = URLSession(configuration: config)
        let saved = UserDefaults.standard.string(forKey: Self.cookieKey) ?? "\(Self.cookieName)=1"
        Self.install(cookie: saved)
    }

    private static func install(cookie: String) {
        let parts = cookie.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let c = HTTPCookie(properties: [
            .domain: UDL.host, .path: "/", .name: parts[0], .value: parts[1],
            .secure: "TRUE", .expires: Date().addingTimeInterval(60 * 60 * 24 * 365),
        ])
        if let c { HTTPCookieStorage.shared.setCookie(c) }
    }

    // MARK: Pages

    func html(_ path: String, query: [URLQueryItem] = []) async throws -> String {
        var comps = URLComponents(url: UDL.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw UDLError.status(0) }

        var attempt = 0
        while true {
            attempt += 1
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(from: url)
            } catch let e as URLError where e.code == .notConnectedToInternet || e.code == .networkConnectionLost {
                throw UDLError.offline
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(decoding: data, as: UTF8.self)
            if code == 418 || (code == 200 && text.hasPrefix("<script>var m=d;")) {
                guard attempt < 3, let cookie = Self.solve(challenge: text) else { throw UDLError.challenge }
                Self.install(cookie: cookie)
                UserDefaults.standard.set(cookie, forKey: Self.cookieKey)
                continue
            }
            guard (200..<300).contains(code) else { throw UDLError.status(code) }
            return text
        }
    }

    /// Run the challenge page's script in an empty JavaScriptCore context
    /// with just enough of `document`/`window` stubbed to catch the cookie it
    /// sets. The context has no access to anything outside itself.
    private static func solve(challenge html: String) -> String? {
        guard let open = html.range(of: "<script>"), let close = html.range(of: "</script>") ,
              open.upperBound <= close.lowerBound else { return nil }
        let script = String(html[open.upperBound..<close.lowerBound])
        guard let ctx = JSContext() else { return nil }
        ctx.exceptionHandler = { _, _ in }
        ctx.evaluateScript("""
        var __cookies = [];
        var document = {};
        Object.defineProperty(document, 'cookie', {
            set: function (v) { __cookies.push(String(v)); },
            get: function () { return __cookies.join('; '); }
        });
        var window = { location: { reload: function () {}, href: 'https://collections.lib.utah.edu/' } };
        var location = window.location;
        var navigator = { userAgent: 'Mozilla/5.0' };
        """)
        ctx.evaluateScript(script)
        guard let set = ctx.objectForKeyedSubscript("__cookies").toArray() as? [String],
              let first = set.first else { return nil }
        // "name=value; path=/" → "name=value"
        let pair = first.split(separator: ";").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return pair.contains("=") ? pair : nil
    }

    // MARK: Endpoints

    func institutions() async throws -> [Institution] {
        BrowseParser.institutions(from: try await html("browse/institutions"))
    }

    func collectionsAZ() async throws -> [BrowseSection] {
        BrowseParser.sections(from: try await html("browse"))
    }

    func topics() async throws -> [Topic] {
        BrowseParser.topics(from: try await html("browse/topics"))
    }

    func topic(_ slug: String) async throws -> [Collection] {
        let page = try await html("browse/topic/\(slug)")
        return BrowseParser.sections(from: page).flatMap(\.collections)
    }

    func search(_ query: SearchQuery) async throws -> SearchPage {
        SearchParser.page(from: try await html("search", query: query.queryItems), query: query)
    }

    func item(_ id: Int) async throws -> ItemRecord {
        ItemParser.record(from: try await html("details", query: [URLQueryItem(name: "id", value: String(id))]), id: id)
    }
}
