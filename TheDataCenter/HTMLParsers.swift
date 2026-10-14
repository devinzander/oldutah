//
//  HTMLParsers.swift
//  The Data Center
//
//  The library's site is server-rendered HTML with no JSON API, so the app
//  reads the same pages a browser does. The markup is generated and very
//  regular (single-quoted attributes, fixed class names), which keeps the
//  parsers to anchored regular expressions.
//

import Foundation

enum HTML {
    /// Decode the entities the site emits (&amp; &#039; &quot; &nbsp; …).
    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        let named: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#039;", "'"), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", "\u{00A0}"),
            ("&ndash;", "–"), ("&mdash;", "—"), ("&hellip;", "…"), ("&rsquo;", "’"),
            ("&lsquo;", "‘"), ("&rdquo;", "”"), ("&ldquo;", "“"), ("&eacute;", "é"),
        ]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        // Numeric references.
        out = RX.numericEntity.replace(in: out) { groups in
            let body = groups[1]
            let code: UInt32?
            if body.hasPrefix("x") || body.hasPrefix("X") {
                code = UInt32(body.dropFirst(), radix: 16)
            } else {
                code = UInt32(body)
            }
            return code.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? groups[0]
        }
        return out
    }

    /// Tags out, entities decoded, whitespace collapsed.
    static func text(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "<br>", with: " ")
            .replacingOccurrences(of: "<br/>", with: " ")
            .replacingOccurrences(of: "<br />", with: " ")
        out = RX.tag.replace(in: out) { _ in " " }
        out = decode(out)
        out = out.replacingOccurrences(of: "\u{00A0}", with: " ")
        out = RX.spaces.replace(in: out) { _ in " " }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func int(_ s: String) -> Int {
        Int(s.replacingOccurrences(of: ",", with: "")) ?? 0
    }
}

/// Thin NSRegularExpression wrapper: dot matches newlines, groups come back
/// as strings (empty for a group that did not participate).
struct RX {
    let re: NSRegularExpression

    init(_ pattern: String) {
        re = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    }

    func first(in s: String) -> [String]? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return groups(m, ns)
    }

    func all(in s: String) -> [[String]] {
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { groups($0, ns) }
    }

    func replace(in s: String, with f: ([String]) -> String) -> String {
        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return s }
        var out = ""
        var cursor = 0
        for m in matches {
            out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            out += f(groups(m, ns))
            cursor = m.range.location + m.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    private func groups(_ m: NSTextCheckingResult, _ ns: NSString) -> [String] {
        (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    static let tag = RX("<[^>]+>")
    static let spaces = RX("\\s+")
    static let numericEntity = RX("&#([xX]?[0-9a-fA-F]+);")
}

// MARK: - Browse pages (institutions, collections A–Z, topic)

struct BrowseSection {
    /// Anchor id — institution prefix, A–Z letter, or nil on a topic page.
    let anchor: String?
    let heading: String
    let collections: [Collection]
}

enum BrowseParser {
    private static let marker = RX("<div(?: id='([^']*)')? class='az_letter'>(.*?)</div>|<div class='az_item'")
    private static let setname = RX("facet_setname_s=([^'&]+)'")
    private static let img = RX("<img src='([^']+)'")
    private static let content = RX("<div class='az_content'>(.*?)<div style='clear: both'>")
    private static let anchorText = RX("<a [^>]*>(.*?)</a>")

    static func sections(from html: String) -> [BrowseSection] {
        guard let start = html.range(of: "<div id='az_body'>") else { return [] }
        var body = String(html[start.upperBound...])
        if let footer = body.range(of: "<footer") { body = String(body[..<footer.lowerBound]) }

        let ns = body as NSString
        let matches = marker.re.matches(in: body, range: NSRange(location: 0, length: ns.length))
        var sections: [BrowseSection] = []
        var anchor: String? = nil
        var heading = ""
        var current: [Collection] = []

        func flush() {
            if !heading.isEmpty || !current.isEmpty {
                sections.append(BrowseSection(anchor: anchor, heading: heading, collections: current))
            }
            current = []
        }

        for (i, m) in matches.enumerated() {
            let whole = ns.substring(with: m.range)
            if whole.hasPrefix("<div class='az_item'") {
                let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
                let chunk = ns.substring(with: NSRange(location: m.range.location, length: end - m.range.location))
                if let c = collection(fromItem: chunk) { current.append(c) }
            } else {
                flush()
                let idRange = m.range(at: 1)
                anchor = idRange.location == NSNotFound ? nil : ns.substring(with: idRange)
                heading = HTML.text(ns.substring(with: m.range(at: 2)))
            }
        }
        flush()
        return sections
    }

    static func collection(fromItem chunk: String) -> Collection? {
        guard let sn = setname.first(in: chunk)?[1],
              let body = content.first(in: chunk)?[1],
              let a = anchorText.first(in: body) else { return nil }
        let title = HTML.text(a[1])
        let afterTitle = body.range(of: a[0]).map { String(body[$0.upperBound...]) } ?? ""
        let description = HTML.text(afterTitle)
        let thumb = img.first(in: chunk)?[1]
        return Collection(setname: HTML.decode(sn), title: title, description: description, thumbnail: thumb)
    }

    static func institutions(from html: String) -> [Institution] {
        sections(from: html).compactMap { s in
            guard let prefix = s.anchor else { return nil }
            return Institution(prefix: prefix, name: s.heading, collections: s.collections)
        }
    }

    private static let topicLink = RX("<a href='/browse/topic/([^']+)'>([^<]+)</a>")

    static func topics(from html: String) -> [Topic] {
        var seen = Set<String>()
        return topicLink.all(in: html).compactMap { g in
            let slug = HTML.decode(g[1]).removingPercentEncoding ?? g[1]
            guard seen.insert(slug).inserted else { return nil }
            return Topic(slug: slug, name: HTML.text(g[2]))
        }
    }
}

// MARK: - Search results

enum SearchParser {
    private static let entries = RX("<strong>([\\d,]+)</strong> - <strong>([\\d,]+)</strong> of <strong>([\\d,]+)</strong>")
    private static let row = RX("<tr id='id(\\d+)'>(.*?)</tr>")
    private static let cell = RX("<td[^>]*>(.*?)</td>")
    private static let th = RX("<th[^>]*>(.*?)</th>")
    private static let src = RX("src='([^']+)'")
    private static let link = RX("<a [^>]*>(.*?)</a>")
    private static let panel = RX("toggle_facet\\(this, '([^']+)'\\); return false;\">([^<]+)</a>")
    private static let facetRow = RX("<li[^>]*><span class='facet-label'><a href='([^']+)'>(.*?)</a></span><span class='facet-count'>([\\d,]+)</span></li>")
    private static let yearOption = RX("<option value='(\\d{4})'\\s*(?:selected)?\\s*(disabled)?\\s*>")

    static func page(from html: String, query: SearchQuery) -> SearchPage {
        var total = 0, first = 0, last = 0
        if let e = entries.first(in: html) {
            first = HTML.int(e[1]); last = HTML.int(e[2]); total = HTML.int(e[3])
        }

        // Column order varies: the global table is Title/Date/Type/Setname,
        // a collection's table swaps in its own fields (Paper, Creator…).
        // The header row says which is which.
        var headers: [String] = []
        if let t = html.range(of: "<table class='table table-bordered'>") {
            let tail = html[t.upperBound...]
            let headRow = tail.range(of: "</tr>").map { String(tail[..<$0.lowerBound]) } ?? ""
            headers = th.all(in: headRow).map { HTML.text($0[1]) }
        }
        func column(_ name: String) -> Int? { headers.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame } }
        let titleIdx = column("Title") ?? 2
        let dateIdx = column("Date")
        let typeIdx = column("Type")
        let setIdx = column("Setname")
        let extraIdx = headers.indices.first { i in
            i > 1 && !headers[i].isEmpty && ![titleIdx, dateIdx, typeIdx, setIdx].contains(i)
        }
        // A single-collection page omits Setname; the query says which it is.
        let impliedSetname = query.filters.first { $0.isCollection }?.bareValue ?? ""

        var hits: [SearchHit] = []
        for r in row.all(in: html) {
            guard let id = Int(r[1]) else { continue }
            let cells = cell.all(in: r[2]).map { $0[1] }
            guard cells.count > titleIdx else { continue }
            func text(_ i: Int?) -> String {
                guard let i, i < cells.count else { return "" }
                return HTML.text(cells[i])
            }
            let thumb = cells.count > 1 ? src.first(in: cells[1]).flatMap { UDL.absolute($0[1]) } : nil
            let title = link.first(in: cells[titleIdx]).map { HTML.text($0[1]) } ?? HTML.text(cells[titleIdx])
            let subtitle = text(extraIdx)
            hits.append(SearchHit(id: id,
                                  title: title.isEmpty ? "Untitled" : title,
                                  date: text(dateIdx),
                                  type: text(typeIdx),
                                  setname: setIdx == nil ? impliedSetname : text(setIdx),
                                  thumbnail: thumb,
                                  subtitle: subtitle.isEmpty ? nil : subtitle))
        }

        var facets: [FacetGroup] = []
        for p in panel.all(in: html) {
            let panelID = p[1], title = HTML.text(p[2])
            guard panelID != "facet_year" else { continue }
            let field: String
            switch panelID {
            case "facet_institution": field = "facet_setname_s"
            default: field = panelID.hasPrefix("facet_") ? String(panelID.dropFirst(6)) : panelID
            }
            guard let start = html.range(of: "id='\(panelID)'") else { continue }
            let tail = html[start.upperBound...]
            let block = tail.range(of: "</ul>").map { String(tail[..<$0.lowerBound]) } ?? String(tail)
            let values: [FacetValue] = facetRow.all(in: block).compactMap { g in
                let href = HTML.decode(g[1])
                guard let comps = URLComponents(string: href),
                      let value = comps.queryItems?.first(where: { $0.name == field })?.value else { return nil }
                let label = HTML.text(g[2])
                return FacetValue(filter: FacetFilter(field: field, value: value, label: label),
                                  count: HTML.int(g[3]))
            }
            if !values.isEmpty {
                facets.append(FacetGroup(title: title, field: field, values: values))
            }
        }

        var yearRange: ClosedRange<Int>? = nil
        if let sel = html.range(of: "id='start_year'") {
            let tail = html[sel.upperBound...]
            let block = tail.range(of: "</select>").map { String(tail[..<$0.lowerBound]) } ?? ""
            let enabled = yearOption.all(in: block).filter { $0[2].isEmpty }.compactMap { Int($0[1]) }
            if let lo = enabled.min(), let hi = enabled.max() { yearRange = lo...hi }
        }

        return SearchPage(query: query, total: total, first: first, last: last,
                          hits: hits, facets: facets, yearRange: yearRange)
    }
}

// MARK: - Item record

enum ItemParser {
    private static let title = RX("<h4 id='title'>(.*?)</h4>")
    private static let download = RX("<a href='(/file\\?id=\\d+)' id='download' class='download' title='Download - ([^']*)'")
    private static let permalink = RX("id='permalink_url' type='text' value='([^']+)'")
    private static let ogImage = RX("<meta property='og:image' content='([^']+)'")
    private static let viewer = RX("display: table-cell; width: 100%'>(.*?)<div class='record_nav'")
    private static let canvasImg = RX("<canvas[^>]*>\\s*<img [^>]*src='([^']+)'")
    private static let pdfFrame = RX("<iframe [^>]*src='[^']*?file=([^'&]+)'")
    private static let audioSrc = RX("<audio[^>]*>.*?<source src='([^']+)'")
    private static let videoSrc = RX("<video[^>]*>.*?<source src='([^']+)'")
    private static let fieldRow = RX("<tr>\\s*<td>(.*?)</td>\\s*<td([^>]*)>(.*?)</td>\\s*</tr>")
    private static let dataField = RX("data-field='([^']*)'")
    private static let dataEdit = RX("data-edit='([^']*)'")
    private static let href = RX("href='([^']+)'")
    private static let collection = RX("<span class='collection-name dl'><a class='title_link' href='/search\\?facet_setname_s=([^']+)'>(.*?)</a></span>")

    static func record(from html: String, id: Int) -> ItemRecord {
        let name = title.first(in: html).map { HTML.text($0[1]) } ?? "Untitled"
        let dl = download.first(in: html)
        let ref = permalink.first(in: html).flatMap { URL(string: HTML.decode($0[1])) }
        let thumb = ogImage.first(in: html).flatMap { UDL.absolute(HTML.decode($0[1])) }

        var media: ItemMedia = .none
        if let v = viewer.first(in: html)?[1] {
            if let m = canvasImg.first(in: v), let u = UDL.absolute(HTML.decode(m[1])) { media = .image(u) }
            else if let m = pdfFrame.first(in: v), let u = UDL.absolute(HTML.decode(m[1])) { media = .pdf(u) }
            else if let m = audioSrc.first(in: v), let u = UDL.absolute(HTML.decode(m[1])) { media = .audio(u) }
            else if let m = videoSrc.first(in: v), let u = UDL.absolute(HTML.decode(m[1])) { media = .video(u) }
        }

        var fields: [ItemField] = []
        if let tableStart = html.range(of: "<table class='table table-bordered'>") {
            let tail = html[tableStart.upperBound...]
            let table = tail.range(of: "</table>").map { String(tail[..<$0.lowerBound]) } ?? String(tail)
            for r in fieldRow.all(in: table) {
                let label = HTML.text(r[1])
                let attrs = r[2]
                let field = dataField.first(in: attrs)?[1]
                let inner = r[3]
                let value = dataEdit.first(in: attrs).map { HTML.decode($0[1]) } ?? HTML.text(inner)
                let text = HTML.text(value)
                guard !label.isEmpty, !text.isEmpty else { continue }
                var link: URL? = nil
                if let h = href.first(in: inner)?[1] {
                    link = UDL.absolute(HTML.decode(h))
                }
                fields.append(ItemField(label: label, field: field, value: text, link: link))
            }
        }

        let coll = collection.first(in: html)
        return ItemRecord(id: id,
                          title: name,
                          referenceURL: ref,
                          downloadURL: dl.flatMap { UDL.absolute($0[1]) },
                          downloadSize: dl?[2],
                          media: media,
                          thumbnail: thumb,
                          fields: fields,
                          collectionSetname: coll.map { HTML.decode($0[1]) },
                          collectionTitle: coll.map { HTML.text($0[2]) })
    }
}
