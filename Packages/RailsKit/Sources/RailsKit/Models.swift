//
//  Models.swift
//  Utah Rails
//

import Foundation
import SwiftUI

// MARK: - Catalog (bundled snapshot of the site's index and site map)

/// One entry on an index page: a link, its title, and the site's own
/// one-line description.
struct IndexEntry: Codable, Hashable, Identifiable {
    let path: String
    let title: String
    let blurb: String
    var external: Bool? = nil
    var id: String { path }

    var url: URL { Site.absolute(path) }
    var isExternal: Bool { external == true }
    var page: PageRef { PageRef(path: path, title: title) }
}

struct IndexSection: Codable, Hashable, Identifiable {
    let title: String
    let entries: [IndexEntry]
    var id: String { title }
}

/// A folder of the site map — `/up/`, `/mining/` — with every page in it.
struct SiteFolder: Codable, Hashable, Identifiable {
    let slug: String
    let name: String
    let pages: [PageRef]
    var id: String { slug }
}

/// A page on utahrails.net. The path is site-relative ("/up/uprr-index.html").
struct PageRef: Codable, Hashable, Identifiable {
    let path: String
    let title: String
    var id: String { path }

    var url: URL { Site.absolute(path) }
    var isPDF: Bool { path.lowercased().hasSuffix(".pdf") }
    /// The site-map folder this page lives in.
    var folderSlug: String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        return parts.count > 1 ? String(parts[0]) : "/"
    }
}

struct Catalog: Codable {
    let fetched: String
    let sections: [IndexSection]
    let folders: [SiteFolder]
}

// MARK: - Article (a page rendered natively)

struct Heading: Hashable, Identifiable {
    let anchor: String
    let level: Int
    let text: String
    /// The site marks some headings `no-TOC`; they still render, but stay
    /// out of the page's contents menu.
    let inContents: Bool
    var id: String { anchor }
}

/// Inline-formatted text: links, emphasis, line breaks — ready for Text.
struct RichText: Hashable {
    let attributed: AttributedString
    var plain: String { String(attributed.characters) }
    var isEmpty: Bool { plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct TableBlock: Hashable {
    let caption: String?
    /// Column heads, when the first row is marked as one.
    let header: [String]?
    let rows: [[RichText]]
    var columnCount: Int { max(header?.count ?? 0, rows.map(\.count).max() ?? 0) }
}

indirect enum Block: Hashable, Identifiable {
    case heading(Heading)
    case paragraph(RichText)
    /// `<p>1985<br>Caterpillar boosted…</p>` — the site's chronology idiom:
    /// a date on its own line, then the entry.
    case entry(date: String, body: RichText)
    /// `<p><a>Title</a> -- description</p>` — the site's index idiom.
    case linkRow(url: URL, title: String, blurb: RichText?)
    case quote([Block])
    case sidebar([Block])
    case list(ordered: Bool, items: [RichText])
    case table(TableBlock)
    case image(url: URL, alt: String)
    case rule
    case pre(String)

    var id: Int { hashValue }
}

struct Article: Hashable {
    let page: PageRef
    let title: String
    let subtitle: String?
    let updated: String?
    let returnTo: [PageRef]
    let blocks: [Block]
    let headings: [Heading]

    var url: URL { page.url }
}

// MARK: - What's New

struct NewsEntry: Hashable, Identifiable {
    let date: String
    let blocks: [Block]
    var id: String { date + "|" + blocks.count.description }
}

struct RecentUpdate: Hashable, Identifiable {
    let date: String
    let page: PageRef
    var id: String { page.path + date }
}

// MARK: - Photos (SmugMug)

enum SmugNodeType: String, Codable { case folder = "Folder", album = "Album", page = "Page" }

struct SmugNode: Hashable, Identifiable, Codable {
    let nodeID: String
    let name: String
    let type: SmugNodeType
    let urlPath: String
    let description: String
    let dateModified: String
    let hasChildren: Bool
    /// Album key for album nodes ("/api/v2/album/KEY").
    let albumKey: String?
    var highlight: URL?
    var id: String { nodeID }

    var webURL: URL { URL(string: "https://donstrack.smugmug.com" + urlPath)! }
}

struct SmugAlbum: Hashable, Identifiable, Codable {
    let albumKey: String
    let nodeID: String
    let name: String
    let description: String
    let imageCount: Int
    let urlPath: String
    let lastUpdated: String
    var id: String { albumKey }

    var webURL: URL { URL(string: "https://donstrack.smugmug.com" + urlPath)! }
}

struct SmugImage: Hashable, Identifiable, Codable {
    let imageKey: String
    let title: String
    let caption: String
    let keywords: [String]
    let fileName: String
    let thumbnail: URL
    let width: Int
    let height: Int
    let isVideo: Bool
    let date: String
    var id: String { imageKey }

    /// SmugMug serves every size under the same path — only the size code
    /// changes. Th 100 · S 400 · M 600 · L 800 · XL 1024 · X2 1600 ·
    /// X3 2048 · X4 3072 · X5 4096 · O original.
    func url(size: String) -> URL {
        let s = thumbnail.absoluteString
            .replacingOccurrences(of: "/Th/", with: "/\(size)/")
            .replacingOccurrences(of: "-Th.", with: "-\(size).")
        return URL(string: s) ?? thumbnail
    }

    var headline: String {
        if !title.isEmpty { return title }
        if !caption.isEmpty { return caption }
        // "B&G_0-8-8-0_102_with-engineer.jpg" → "B&G 0-8-8-0 102 with engineer":
        // underscores become spaces, hyphens too unless they join digits
        // (wheel arrangements, dates, road-number ranges).
        var name = (fileName as NSString).deletingPathExtension.replacingOccurrences(of: "_", with: " ")
        name = RX.wordHyphen.replace(in: name) { _ in " " }
        return RX.spaces.replace(in: name) { _ in " " }.trimmingCharacters(in: .whitespaces)
    }

    /// SmugMug fills keywords from the file name when none were entered;
    /// those add nothing, so only real keywords are shown.
    var realKeywords: [String] {
        let f = fileName.lowercased()
        let fromName = keywords.allSatisfy { f.contains($0.lowercased()) }
        return fromName ? [] : keywords
    }
    var aspect: CGFloat { width > 0 && height > 0 ? CGFloat(width) / CGFloat(height) : 1 }
}

struct SmugPage<T: Hashable>: Hashable {
    let items: [T]
    let total: Int
    let next: Int?
}

/// Navigation value for a SmugMug link met inside an article — resolved
/// against the API once the screen appears.
struct SmugLink: Hashable {
    let url: URL
    var path: String { url.path }
    /// "…/i-PxF9Qgj/A" → "PxF9Qgj"
    var imageKey: String? {
        guard let r = path.range(of: "/i-") else { return nil }
        let rest = path[r.upperBound...]
        return rest.split(separator: "/").first.map(String.init)
    }
    /// The album or folder part of the path, without any image segment.
    var nodePath: String {
        guard let r = path.range(of: "/i-") else { return path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path }
        return String(path[..<r.lowerBound])
    }
}

struct PDFRef: Hashable {
    let url: URL
    let title: String
}
