//
//  HTMLParsers.swift
//  Utah Rails
//
//  utahrails.net is hand-written, semantic HTML: h1 title, h2–h4 sections,
//  paragraphs, `div.quote` block quotes, `table.roster` rosters, a few
//  lists. A small tolerant tokenizer builds a tree, and the article parser
//  walks `#content` into native blocks. The index idiom
//  `<p><a>Title</a> -- description</p>` becomes a navigable row.
//

import Foundation
import SwiftUI

// MARK: - Entities & regex helpers

enum HTML {
    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        let named: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#039;", "'"), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", "\u{00A0}"),
            ("&ndash;", "–"), ("&mdash;", "—"), ("&hellip;", "…"), ("&rsquo;", "’"),
            ("&lsquo;", "‘"), ("&rdquo;", "”"), ("&ldquo;", "“"), ("&eacute;", "é"),
            ("&uarr;", "↑"), ("&deg;", "°"), ("&frac12;", "½"), ("&frac14;", "¼"),
            ("&copy;", "©"), ("&reg;", "®"), ("&trade;", "™"), ("&times;", "×"),
            ("&ouml;", "ö"), ("&uuml;", "ü"), ("&auml;", "ä"), ("&egrave;", "è"),
            ("&ccedil;", "ç"), ("&ntilde;", "ñ"), ("&aacute;", "á"), ("&iacute;", "í"),
            ("&oacute;", "ó"), ("&uacute;", "ú"), ("&sect;", "§"), ("&para;", "¶"),
        ]
        for (k, v) in named where out.contains(k) { out = out.replacingOccurrences(of: k, with: v) }
        out = RX.numericEntity.replace(in: out) { groups in
            let body = groups[1]
            let code: UInt32? = body.hasPrefix("x") || body.hasPrefix("X") ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
            return code.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? groups[0]
        }
        return out
    }

    /// Tags out, entities decoded, whitespace collapsed.
    static func text(_ s: String) -> String {
        var out = RX.br.replace(in: s) { _ in " " }
        out = RX.tag.replace(in: out) { _ in " " }
        out = decode(out)
        out = out.replacingOccurrences(of: "\u{00A0}", with: " ")
        out = RX.spaces.replace(in: out) { _ in " " }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Path of `<link rel="canonical">`, site-relative.
    static func canonicalPath(_ html: String) -> String? {
        guard let m = RX.canonical.first(in: html), let url = URL(string: m[1]) else { return nil }
        return Site.path(of: url)
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
    static let br = RX("<br\\s*/?>")
    static let spaces = RX("\\s+")
    static let numericEntity = RX("&#([xX]?[0-9a-fA-F]+);")
    static let canonical = RX("<link rel=\"canonical\" href=\"([^\"]+)\"")
    static let smugKey = RX("\"apiKey\":\"([A-Za-z0-9]+)\"")
    static let dashLead = RX("^\\s*(?:--|—|–|-)\\s*")
    static let wordHyphen = RX("(?<![0-9])-|-(?![0-9])")
    /// A date line as the site writes them: "1985", "July 1, 1862",
    /// "October 2010", "1960s", "ca. 1900", "1985-1986", "May 10-12, 1869".
    static let dateLine = RX("^(?:(?:ca\\.|circa|about|early|late|mid|by|before|after|spring|summer|fall|winter)\\s+)?(?:(?:january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\\.?\\s+(?:\\d{1,2}(?:\\s*[-–]\\s*\\d{1,2})?,?\\s+)?)?\\d{4}s?(?:\\s*(?:[-–]|to|and)\\s*(?:(?:january|february|march|april|may|june|july|august|september|october|november|december)\\s+)?\\d{2,4}s?)?\\.?$")
    static let sitemapPage = RX("<a href=\"([^\"]+)\" title=\"[^\"]*\">(.*?)</a>")
    static let recentItem = RX("<span class=\"date-tag\">\\[([^\\]]+)\\]</span>\\s*<a class=\"page-link\" href=\"([^\"]+)\"[^>]*>(.*?)</a>")
}

// MARK: - Tolerant HTML tree

final class HNode {
    let tag: String          // "" for text
    var attrs: [String: String]
    var children: [HNode] = []
    var text: String

    init(tag: String, attrs: [String: String] = [:], text: String = "") {
        self.tag = tag; self.attrs = attrs; self.text = text
    }

    var isText: Bool { tag.isEmpty }
    var classes: Set<String> { Set((attrs["class"] ?? "").split(separator: " ").map(String.init)) }
    func has(class c: String) -> Bool { classes.contains(c) }
    var id: String? { attrs["id"] }

    /// Depth-first search.
    func first(where test: (HNode) -> Bool) -> HNode? {
        if test(self) { return self }
        for c in children { if let f = c.first(where: test) { return f } }
        return nil
    }

    func all(_ tag: String) -> [HNode] {
        var out: [HNode] = []
        func walk(_ n: HNode) {
            if n.tag == tag { out.append(n) }
            for c in n.children { walk(c) }
        }
        walk(self)
        return out
    }

    /// Text content, entities decoded, whitespace collapsed.
    var plainText: String {
        var s = ""
        func walk(_ n: HNode) {
            if n.isText { s += n.text } else if n.tag == "br" { s += " " } else { n.children.forEach(walk) }
        }
        walk(self)
        return HTML.text(s)
    }
}

enum HTMLTree {
    private static let void: Set<String> = ["br", "img", "hr", "input", "meta", "link", "area", "base", "col", "embed", "source", "track", "wbr", "param"]
    private static let raw: Set<String> = ["script", "style"]

    static func parse(_ html: String) -> HNode {
        let b = Array(html.utf8)
        let n = b.count
        let root = HNode(tag: "#root")
        var stack: [HNode] = [root]
        var i = 0

        func str(_ lo: Int, _ hi: Int) -> String { String(decoding: b[lo..<hi], as: UTF8.self) }
        func isNameByte(_ c: UInt8) -> Bool {
            (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 45 || c == 58
        }
        func popTo(_ tag: String, stopAt: Set<String> = []) -> Bool {
            var k = stack.count - 1
            while k > 0 {
                if stack[k].tag == tag { stack.removeSubrange(k...); return true }
                if stopAt.contains(stack[k].tag) { return false }
                k -= 1
            }
            return false
        }
        func appendText(_ s: String) {
            guard !s.isEmpty else { return }
            let top = stack[stack.count - 1]
            if let last = top.children.last, last.isText { last.text += s } else { top.children.append(HNode(tag: "", text: s)) }
        }

        while i < n {
            if b[i] != 60 /* < */ {
                var j = i
                while j < n && b[j] != 60 { j += 1 }
                appendText(str(i, j))
                i = j
                continue
            }
            // Comment
            if i + 3 < n && b[i + 1] == 33 && b[i + 2] == 45 && b[i + 3] == 45 {
                var j = i + 4
                while j + 2 < n && !(b[j] == 45 && b[j + 1] == 45 && b[j + 2] == 62) { j += 1 }
                i = min(n, j + 3)
                continue
            }
            // Doctype / processing instruction
            if i + 1 < n && (b[i + 1] == 33 || b[i + 1] == 63) {
                var j = i
                while j < n && b[j] != 62 { j += 1 }
                i = min(n, j + 1)
                continue
            }
            // Closing tag
            if i + 1 < n && b[i + 1] == 47 {
                var j = i + 2
                while j < n && isNameByte(b[j]) { j += 1 }
                let name = str(i + 2, j).lowercased()
                while j < n && b[j] != 62 { j += 1 }
                i = min(n, j + 1)
                _ = popTo(name)
                continue
            }
            // Opening tag
            var j = i + 1
            while j < n && isNameByte(b[j]) { j += 1 }
            if j == i + 1 { appendText("<"); i += 1; continue }   // a stray '<'
            let name = str(i + 1, j).lowercased()
            var attrs: [String: String] = [:]
            var selfClosing = false
            // Attributes
            while j < n && b[j] != 62 {
                let c = b[j]
                if c == 47 { selfClosing = true; j += 1; continue }
                if c == 32 || c == 9 || c == 10 || c == 13 { j += 1; continue }
                var k = j
                while k < n && b[k] != 61 && b[k] != 62 && b[k] != 32 && b[k] != 9 && b[k] != 10 && b[k] != 13 && b[k] != 47 { k += 1 }
                let key = str(j, k).lowercased()
                j = k
                while j < n && (b[j] == 32 || b[j] == 9 || b[j] == 10 || b[j] == 13) { j += 1 }
                if j < n && b[j] == 61 {
                    j += 1
                    while j < n && (b[j] == 32 || b[j] == 9 || b[j] == 10 || b[j] == 13) { j += 1 }
                    if j < n && (b[j] == 34 || b[j] == 39) {
                        let q = b[j]; j += 1
                        var e = j
                        while e < n && b[e] != q { e += 1 }
                        attrs[key] = HTML.decode(str(j, e))
                        j = min(n, e + 1)
                    } else {
                        var e = j
                        while e < n && b[e] != 62 && b[e] != 32 && b[e] != 9 && b[e] != 10 && b[e] != 13 { e += 1 }
                        attrs[key] = HTML.decode(str(j, e))
                        j = e
                    }
                } else if !key.isEmpty {
                    attrs[key] = ""
                }
            }
            i = min(n, j + 1)

            if raw.contains(name) {
                // Skip to the matching close tag.
                let close = Array("</\(name)".utf8)
                var k = i
                outer: while k + close.count <= n {
                    var ok = true
                    for (o, cb) in close.enumerated() where (b[k + o] | 0x20) != cb { ok = false; break }
                    if ok { break outer }
                    k += 1
                }
                var e = k
                while e < n && b[e] != 62 { e += 1 }
                i = min(n, e + 1)
                continue
            }

            // Implicit closes for the few nestings the site uses.
            switch name {
            case "p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "table", "div", "blockquote", "pre", "hr":
                _ = popTo("p", stopAt: ["div", "td", "th", "li", "blockquote", "#root", "body"])
            case "li": _ = popTo("li", stopAt: ["ul", "ol"])
            case "td", "th": _ = popTo("td", stopAt: ["tr"]) || popTo("th", stopAt: ["tr"])
            case "tr": _ = popTo("tr", stopAt: ["table", "tbody", "thead"])
            default: break
            }

            let node = HNode(tag: name, attrs: attrs)
            stack[stack.count - 1].children.append(node)
            if !void.contains(name) && !selfClosing { stack.append(node) }
        }
        return root
    }
}

// MARK: - Inline text

enum Inline {
    /// Build attributed text from inline nodes. Links resolve against `base`.
    static func rich(_ nodes: [HNode], base: URL) -> AttributedString {
        var out = AttributedString()
        for n in nodes { append(n, to: &out, base: base, italic: false, bold: false, link: nil) }
        trim(&out)
        return out
    }

    private static func append(_ n: HNode, to out: inout AttributedString, base: URL, italic: Bool, bold: Bool, link: URL?) {
        if n.isText {
            var s = HTML.decode(n.text).replacingOccurrences(of: "\u{00A0}", with: " ")
            s = RX.spaces.replace(in: s) { _ in " " }
            guard !s.isEmpty else { return }
            // Collapse a space that follows whitespace already emitted.
            if s.hasPrefix(" "), let last = out.characters.last, last == " " || last == "\n" { s.removeFirst() }
            guard !s.isEmpty else { return }
            var a = AttributedString(s)
            if italic && bold { a.inlinePresentationIntent = [.emphasized, .stronglyEmphasized] }
            else if italic { a.inlinePresentationIntent = .emphasized }
            else if bold { a.inlinePresentationIntent = .stronglyEmphasized }
            if let link {
                a.link = link
                a.foregroundColor = Brand.accent
            }
            out.append(a)
            return
        }
        switch n.tag {
        case "br":
            out.append(AttributedString("\n"))
        case "img":
            if let alt = n.attrs["alt"], !alt.isEmpty { out.append(AttributedString("[\(alt)]")) }
        case "script", "style":
            break
        case "a":
            let href = n.attrs["href"] ?? ""
            let url = href.isEmpty ? nil : URL(string: href.trimmingCharacters(in: .whitespaces), relativeTo: base)?.absoluteURL
            for c in n.children { append(c, to: &out, base: base, italic: italic, bold: bold, link: url ?? link) }
        case "i", "em", "cite", "var":
            for c in n.children { append(c, to: &out, base: base, italic: true, bold: bold, link: link) }
        case "b", "strong":
            for c in n.children { append(c, to: &out, base: base, italic: italic, bold: true, link: link) }
        case "p", "div", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote":
            if !out.characters.isEmpty, out.characters.last != "\n" { out.append(AttributedString("\n")) }
            for c in n.children { append(c, to: &out, base: base, italic: italic, bold: bold, link: link) }
        case "ul", "ol":
            for c in n.children where c.tag == "li" {
                if !out.characters.isEmpty, out.characters.last != "\n" { out.append(AttributedString("\n")) }
                out.append(AttributedString("• "))
                for cc in c.children { append(cc, to: &out, base: base, italic: italic, bold: bold, link: link) }
            }
        default:
            for c in n.children { append(c, to: &out, base: base, italic: italic, bold: bold, link: link) }
        }
    }

    static func trim(_ a: inout AttributedString) {
        while let f = a.characters.first, f.isWhitespace || f.isNewline { a.characters.removeFirst() }
        while let l = a.characters.last, l.isWhitespace || l.isNewline { a.characters.removeLast() }
    }

    /// Remove a leading "-- " (the site's title/description separator).
    static func stripDashLead(_ a: inout AttributedString) {
        let plain = String(a.characters)
        guard let m = RX.dashLead.first(in: plain), !m[0].isEmpty else { return }
        let count = m[0].count
        let end = a.characters.index(a.characters.startIndex, offsetBy: count)
        a.characters.removeSubrange(a.characters.startIndex..<end)
        trim(&a)
    }
}

// MARK: - Article

enum ArticleParser {
    private static let inlineTags: Set<String> = ["a", "i", "em", "b", "strong", "span", "br", "small", "sup", "sub", "u", "cite", "code", "abbr", "font", "img", "var", "s", "strike"]
    private static let wrapperClasses: Set<String> = ["sidebar", "bordered", "indent", "indentgray", "description", "roster-note", "centered"]

    static func article(from html: String, page: PageRef) -> Article {
        let tree = HTMLTree.parse(html)
        let base = page.url
        let content = tree.first { $0.tag == "div" && $0.id == "content" }
            ?? tree.first { $0.tag == "body" } ?? tree

        var title = ""
        var subtitle: String? = nil
        var updated: String? = nil
        var returnTo: [PageRef] = []
        var blocks: [Block] = []
        var headings: [Heading] = []
        var headingCount = 0
        var seenBody = false

        func heading(_ n: HNode, level: Int) -> Heading {
            headingCount += 1
            let anchor = n.id ?? "h\(headingCount)"
            let h = Heading(anchor: anchor, level: level, text: n.plainText, inContents: !n.has(class: "no-TOC") && !n.has(class: "no-toc"))
            return h
        }

        func linkRow(_ p: HNode) -> Block? {
            let kids = p.children.filter { !($0.isText && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            guard let first = kids.first, first.tag == "a", let href = first.attrs["href"],
                  let url = URL(string: href.trimmingCharacters(in: .whitespaces), relativeTo: base)?.absoluteURL else { return nil }
            let titleText = first.plainText
            guard !titleText.isEmpty else { return nil }
            let rest = Array(kids.dropFirst())
            let restPlain = HTML.text(rest.map { $0.isText ? $0.text : $0.plainText }.joined(separator: " "))
            if restPlain.isEmpty { return .linkRow(url: url, title: titleText, blurb: nil) }
            guard RX.dashLead.first(in: restPlain).map({ !$0[0].isEmpty }) == true else { return nil }
            var blurb = Inline.rich(rest, base: base)
            Inline.stripDashLead(&blurb)
            return .linkRow(url: url, title: titleText, blurb: blurb.characters.isEmpty ? nil : RichText(attributed: blurb))
        }

        /// `<p>1985<br>…</p>` → a dated entry. The date may also be wrapped
        /// in `<b>` or `<i>`.
        func dated(_ p: HNode) -> Block? {
            let kids = p.children.filter { !($0.isText && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            guard kids.count >= 2, kids[1].tag == "br" else { return nil }
            let first = kids[0]
            guard first.isText || ((first.tag == "b" || first.tag == "strong" || first.tag == "i") && first.children.count == 1) else { return nil }
            let date = first.plainText
            guard date.count <= 40, RX.dateLine.first(in: date.lowercased()) != nil else { return nil }
            var body = Inline.rich(Array(kids.dropFirst(2)), base: base)
            Inline.trim(&body)
            return .entry(date: date, body: RichText(attributed: body))
        }

        func table(_ t: HNode) -> Block? {
            let caption = t.children.first { $0.tag == "caption" }?.plainText
            let rows = t.all("tr")
            guard !rows.isEmpty else { return nil }
            var header: [String]? = nil
            var body: [[RichText]] = []
            for (i, r) in rows.enumerated() {
                let cells = r.children.filter { $0.tag == "td" || $0.tag == "th" }
                let isHead = i == 0 && (r.has(class: "data-heading") || r.has(class: "heading") || cells.contains { $0.tag == "th" } || rows.count > 1 && cells.allSatisfy { $0.all("b").count > 0 || $0.tag == "th" } && !cells.isEmpty)
                if isHead {
                    header = cells.map { $0.plainText }
                } else {
                    body.append(cells.map { RichText(attributed: Inline.rich($0.children, base: base)) })
                }
            }
            return .table(TableBlock(caption: caption, header: header, rows: body))
        }

        func convert(_ nodes: [HNode], into out: inout [Block], depth: Int) {
            var inlineRun: [HNode] = []
            func flushInline() {
                guard !inlineRun.isEmpty else { return }
                let r = Inline.rich(inlineRun, base: base)
                if !r.characters.isEmpty { out.append(.paragraph(RichText(attributed: r))) }
                inlineRun = []
            }
            for n in nodes {
                if n.isText || inlineTags.contains(n.tag) {
                    if n.isText && n.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && inlineRun.isEmpty { continue }
                    inlineRun.append(n)
                    continue
                }
                flushInline()
                switch n.tag {
                case "h1":
                    if title.isEmpty { title = n.plainText } else { headings.append(heading(n, level: 1)); out.append(.heading(headings.last!)) }
                case "h2", "h3", "h4", "h5", "h6":
                    let level = Int(String(n.tag.last!)) ?? 2
                    if !seenBody, depth == 0, subtitle == nil, level == 2, n.has(class: "no-TOC") {
                        subtitle = n.plainText
                    } else {
                        let h = heading(n, level: level)
                        headings.append(h)
                        out.append(.heading(h))
                        seenBody = true
                    }
                case "p":
                    if n.has(class: "updated") {
                        updated = n.plainText.replacingOccurrences(of: "This page was last updated on ", with: "").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                    } else if n.has(class: "returnto") {
                        for a in n.all("a") {
                            if let href = a.attrs["href"], let u = URL(string: href, relativeTo: base)?.absoluteURL, let p = Site.path(of: u) {
                                returnTo.append(PageRef(path: p, title: a.plainText.replacingOccurrences(of: "Return to ", with: "").replacingOccurrences(of: "Return To ", with: "")))
                            }
                        }
                    } else if n.has(class: "copyright") || n.has(class: "logo") {
                        break
                    } else if n.has(class: "group-heading") || n.has(class: "psc-heading") {
                        // Roster class headings ("Class CA-10") — the site styles
                        // these paragraphs as group heads.
                        let h = heading(n, level: 3)
                        headings.append(h)
                        out.append(.heading(h))
                        seenBody = true
                    } else if !n.classes.isDisjoint(with: ["passcarhistoryheading", "roster-note-heading", "heading", "sidebarheading"]) {
                        headingCount += 1
                        out.append(.heading(Heading(anchor: n.id ?? "h\(headingCount)", level: 4, text: n.plainText, inContents: false)))
                        seenBody = true
                    } else if let entry = dated(n) {
                        out.append(entry); seenBody = true
                    } else if let row = linkRow(n) {
                        out.append(row); seenBody = true
                    } else if n.all("img").count == 1 && n.plainText.isEmpty, let img = n.all("img").first, let src = img.attrs["src"], let u = URL(string: src, relativeTo: base)?.absoluteURL {
                        out.append(.image(url: u, alt: img.attrs["alt"] ?? ""))
                    } else {
                        let r = Inline.rich(n.children, base: base)
                        if !r.characters.isEmpty { out.append(.paragraph(RichText(attributed: r))); seenBody = true }
                    }
                case "div":
                    if n.id == "generated-toc" || n.id == "myBtn" || n.has(class: "mainmenubutton") { break }
                    if n.has(class: "quote") {
                        var inner: [Block] = []
                        convert(n.children, into: &inner, depth: depth + 1)
                        if !inner.isEmpty { out.append(.quote(inner)) }
                    } else if !n.classes.isDisjoint(with: wrapperClasses) {
                        var inner: [Block] = []
                        convert(n.children, into: &inner, depth: depth + 1)
                        if !inner.isEmpty { out.append(n.has(class: "indent") || n.has(class: "centered") ? .quote(inner) : .sidebar(inner)) }
                    } else {
                        convert(n.children, into: &out, depth: depth + 1)
                    }
                case "blockquote":
                    var inner: [Block] = []
                    convert(n.children, into: &inner, depth: depth + 1)
                    if !inner.isEmpty { out.append(.quote(inner)) }
                case "ul", "ol":
                    let items = n.children.filter { $0.tag == "li" }.map { RichText(attributed: Inline.rich($0.children, base: base)) }.filter { !$0.isEmpty }
                    if !items.isEmpty { out.append(.list(ordered: n.tag == "ol", items: items)) }
                case "table":
                    if let t = table(n) { out.append(t) }
                case "hr":
                    out.append(.rule)
                case "pre":
                    let t = HTML.decode(n.plainTextPreservingWhitespace)
                    if !t.isEmpty { out.append(.pre(t)) }
                case "img":
                    if let src = n.attrs["src"], let u = URL(string: src, relativeTo: base)?.absoluteURL { out.append(.image(url: u, alt: n.attrs["alt"] ?? "")) }
                case "form", "button", "script", "style", "nav", "iframe", "input":
                    break
                default:
                    convert(n.children, into: &out, depth: depth + 1)
                }
            }
            flushInline()
        }

        convert(content.children, into: &blocks, depth: 0)
        if title.isEmpty { title = page.title }
        return Article(page: page, title: title, subtitle: subtitle, updated: updated, returnTo: returnTo, blocks: blocks, headings: headings)
    }
}

extension HNode {
    var plainTextPreservingWhitespace: String {
        var s = ""
        func walk(_ n: HNode) {
            if n.isText { s += n.text } else if n.tag == "br" { s += "\n" } else { n.children.forEach(walk) }
        }
        walk(self)
        return s.trimmingCharacters(in: .newlines)
    }
}

// MARK: - Home page index, site map, What's New

enum IndexParser {
    static func sections(from html: String) -> [IndexSection] {
        let article = ArticleParser.article(from: html, page: PageRef(path: Site.homePath, title: "UtahRails.net"))
        var sections: [IndexSection] = []
        var title = ""
        var entries: [IndexEntry] = []
        func flush() {
            if !entries.isEmpty { sections.append(IndexSection(title: title, entries: entries)) }
            entries = []
        }
        for b in article.blocks {
            switch b {
            case .heading(let h) where h.level == 2:
                flush(); title = h.text
            case .linkRow(let url, let t, let blurb):
                if let p = Site.path(of: url) {
                    entries.append(IndexEntry(path: p, title: t, blurb: blurb?.plain ?? ""))
                } else {
                    entries.append(IndexEntry(path: url.absoluteString, title: t, blurb: blurb?.plain ?? "", external: true))
                }
            default: break
            }
        }
        flush()
        return sections
    }
}

enum SitemapParser {
    static func pages(from html: String) -> [(String, String)] {
        RX.sitemapPage.all(in: html).compactMap { m in
            guard let u = URL(string: m[1]), let p = Site.path(of: u), !p.contains("?") else { return nil }
            return (p, HTML.text(m[2]))
        }
    }

    static func folders(from pages: [(String, String)], names: [String: String]) -> [SiteFolder] {
        var order: [String] = []
        var byFolder: [String: [PageRef]] = [:]
        var seen: Set<String> = []
        for (path, title) in pages {
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            let parts = path.split(separator: "/", omittingEmptySubsequences: true)
            var slug = parts.count > 1 ? String(parts[0]) : "/"
            if slug == "test" { continue }
            if slug == "utahrails" && parts.count > 2 { slug = "pdf" }
            if byFolder[slug] == nil { order.append(slug) }
            byFolder[slug, default: []].append(PageRef(path: path, title: title))
        }
        var folders = order.map { slug in
            SiteFolder(slug: slug, name: names[slug] ?? slug,
                       pages: byFolder[slug]!.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        }
        folders.sort { a, b in
            if (a.slug == "/") != (b.slug == "/") { return b.slug == "/" }
            return a.pages.count > b.pages.count
        }
        return folders
    }
}

enum NewsParser {
    /// What's New: dated h3 headings, each followed by the day's entries.
    static func entries(from html: String) -> [NewsEntry] {
        let article = ArticleParser.article(from: html, page: PageRef(path: Site.whatsNewPath, title: "What's New"))
        var out: [NewsEntry] = []
        var date: String? = nil
        var blocks: [Block] = []
        var inList = false
        func flush() {
            if let date, !blocks.isEmpty { out.append(NewsEntry(date: date, blocks: blocks)) }
            blocks = []
        }
        for b in article.blocks {
            switch b {
            case .heading(let h) where h.level == 2:
                flush(); date = nil
                inList = h.text.lowercased().contains("what's new")
            case .heading(let h) where h.level == 3 && inList:
                flush(); date = h.text
            default:
                if inList, date != nil { blocks.append(b) }
            }
        }
        flush()
        return out
    }

    /// Recent updates: an auto-generated list of every page touched this
    /// month and last.
    static func recent(from html: String) -> [RecentUpdate] {
        var seen: Set<String> = []
        return RX.recentItem.all(in: html).compactMap { m in
            guard let u = URL(string: m[2], relativeTo: Site.base)?.absoluteURL, let p = Site.path(of: u), !seen.contains(p) else { return nil }
            seen.insert(p)
            return RecentUpdate(date: m[1], page: PageRef(path: p, title: HTML.text(m[3])))
        }
    }
}
