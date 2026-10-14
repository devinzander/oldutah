//
//  Models.swift
//  The Data Center
//

import Foundation

// MARK: - Catalog

struct Institution: Identifiable, Codable, Hashable {
    let prefix: String
    let name: String
    var collections: [Collection]
    var id: String { prefix }

    /// The site's institution-wide filter: every setname under the prefix.
    var filter: FacetFilter {
        FacetFilter(field: "facet_setname_s", value: "\(prefix)_*", label: name)
    }
}

struct Collection: Identifiable, Codable, Hashable {
    let setname: String
    let title: String
    let description: String
    let thumbnail: String?
    var id: String { setname }
    var thumbnailURL: URL? { thumbnail.flatMap(UDL.absolute) }
    var institutionPrefix: String {
        setname.split(separator: "_").first.map(String.init) ?? setname
    }
    var filter: FacetFilter {
        FacetFilter(field: "facet_setname_s", value: setname, label: title)
    }
}

struct Topic: Identifiable, Codable, Hashable {
    let slug: String
    let name: String
    var id: String { slug }
}

struct Catalog: Codable {
    let fetched: String
    let institutions: [Institution]
    let topics: [Topic]
}

// MARK: - Search

enum SortOrder: String, CaseIterable, Identifiable, Codable {
    case relevance = "rel"
    case titleAZ = "az_title asc"
    case titleZA = "az_title desc"
    case dateAsc = "sort_date_t asc"
    case dateDesc = "sort_date_t desc"
    case addedDesc = "created_tdt desc"
    case modifiedDesc = "modified_tdt desc"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .relevance: return "Relevance"
        case .titleAZ: return "Title A–Z"
        case .titleZA: return "Title Z–A"
        case .dateAsc: return "Oldest first"
        case .dateDesc: return "Newest first"
        case .addedDesc: return "Recently added"
        case .modifiedDesc: return "Recently updated"
        }
    }
}

/// One facet constraint exactly as the site's query string carries it —
/// `facet_type_t="Image"`, `facet_setname_s=uum_*`.
struct FacetFilter: Hashable, Codable, Identifiable {
    let field: String
    let value: String
    let label: String
    var id: String { field + "=" + value }

    var isInstitution: Bool { field == "facet_setname_s" && value.hasSuffix("_*") }
    var isCollection: Bool { field == "facet_setname_s" && !value.hasSuffix("_*") }
    /// The setname or prefix without quotes/wildcard, for catalog lookups.
    var bareValue: String {
        var v = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        if v.hasSuffix("_*") { v.removeLast(2) }
        return v
    }
    var fieldLabel: String {
        switch field {
        case "facet_type_t": return "Type"
        case "facet_format_t": return "Format"
        case "facet_setname_s": return isInstitution ? "Institution" : "Collection"
        default: return field
        }
    }
}

struct SearchQuery: Hashable, Codable {
    var text = ""
    var filters: [FacetFilter] = []
    var sort: SortOrder = .relevance
    var rows = 25
    var page = 1
    var yearStart: Int?
    var yearEnd: Int?
    /// Raw site parameters with no facet semantics (`format_t=image`).
    var rawParams: [String: String] = [:]

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if !text.isEmpty { items.append(URLQueryItem(name: "q", value: text)) }
        for f in filters { items.append(URLQueryItem(name: f.field, value: f.value)) }
        if sort != .relevance { items.append(URLQueryItem(name: "sort", value: sort.rawValue)) }
        items.append(URLQueryItem(name: "rows", value: String(rows)))
        if page > 1 { items.append(URLQueryItem(name: "page", value: String(page))) }
        if let yearStart { items.append(URLQueryItem(name: "year_start", value: String(yearStart))) }
        if let yearEnd { items.append(URLQueryItem(name: "year_end", value: String(yearEnd))) }
        for (k, v) in rawParams.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: k, value: v))
        }
        return items
    }

    /// The same search on the website.
    var webURL: URL {
        var c = URLComponents(url: UDL.base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        c.queryItems = queryItems
        return c.url ?? UDL.base
    }

    var hasConstraints: Bool {
        !text.isEmpty || !filters.isEmpty || yearStart != nil || yearEnd != nil
    }

    mutating func set(_ filter: FacetFilter) {
        // One value per field, except setname where institution and
        // collection filters may coexist (the site shows both).
        filters.removeAll { $0.field == filter.field
            && ($0.field != "facet_setname_s" || $0.isInstitution == filter.isInstitution) }
        filters.append(filter)
        page = 1
    }

    mutating func remove(_ filter: FacetFilter) {
        filters.removeAll { $0 == filter }
        page = 1
    }
}

struct SearchHit: Identifiable, Hashable, Codable {
    let id: Int
    let title: String
    let date: String
    let type: String
    let setname: String
    let thumbnail: URL?
    /// A collection-specific column the site shows instead of Type
    /// (a newspaper's name, a creator) — "Salt Lake Telegram".
    var subtitle: String? = nil
}

struct FacetValue: Identifiable, Hashable {
    let filter: FacetFilter
    let count: Int
    var id: String { filter.id }
}

struct FacetGroup: Identifiable, Hashable {
    let title: String
    let field: String
    let values: [FacetValue]
    var id: String { title }
}

struct SearchPage {
    let query: SearchQuery
    let total: Int
    let first: Int
    let last: Int
    let hits: [SearchHit]
    let facets: [FacetGroup]
    /// Years with results, from the site's year slider.
    let yearRange: ClosedRange<Int>?
    var hasMore: Bool { last < total }
}

// MARK: - Item

enum ItemMedia: Hashable {
    case image(URL)
    case pdf(URL)
    case audio(URL)
    case video(URL)
    case none
}

struct ItemField: Identifiable, Hashable {
    let label: String
    let field: String?
    let value: String
    let link: URL?
    var id: String { label + "|" + (field ?? "") }
}

struct ItemRecord: Hashable {
    let id: Int
    let title: String
    let referenceURL: URL?
    let downloadURL: URL?
    let downloadSize: String?
    let media: ItemMedia
    let thumbnail: URL?
    let fields: [ItemField]
    let collectionSetname: String?
    let collectionTitle: String?

    func value(_ field: String) -> String? {
        fields.first { $0.field == field }?.value
    }
    var type: String? { value("type_t") }
    var date: String? { value("date_t") }
    var description: String? { value("description_t") }
    var webURL: URL { UDL.base.appendingPathComponent("details").appending(queryItems: [URLQueryItem(name: "id", value: String(id))]) }

    var asHit: SearchHit {
        SearchHit(id: id, title: title, date: date ?? "", type: type ?? "",
                  setname: collectionSetname ?? "", thumbnail: thumbnail)
    }
}
