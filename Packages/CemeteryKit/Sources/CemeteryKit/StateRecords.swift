//
//  StateRecords.swift
//  City Cemetery
//
//  Utah is the one state that gathers every cemetery's burial register into
//  a public database (Utah SHPO, since 1997). The search page is a
//  Salesforce site, but its results are a plain GET with the name and a
//  cemetery-name substring, returned as an HTML table: a summary row per
//  burial and a hidden detail row with the plot and the family names.
//

import Foundation

enum StateRecords {
    static let base = "https://cce.my.salesforce-sites.com/burials/searchburials"
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    static func search(cemetery: Cemetery, filter: String, query: NameQuery) async throws -> [GraveRecord] {
        var comps = URLComponents(string: base)!
        comps.queryItems = [
            URLQueryItem(name: "CemeteryName", value: filter),
            URLQueryItem(name: "DeathDateFrom", value: ""),
            URLQueryItem(name: "DeathDateTo", value: ""),
            URLQueryItem(name: "FirstName", value: query.first),
            URLQueryItem(name: "LastName", value: query.last),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 40
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, let html = String(data: data, encoding: .utf8) else {
            throw ArcGISError.badResponse
        }
        return parse(html, cemetery: cemetery)
    }

    /// Rows come in pairs: the visible summary, then the detail the "View" button expands.
    static func parse(_ html: String, cemetery: Cemetery) -> [GraveRecord] {
        let rows = HTML.matches(in: html, pattern: "<tr[^>]*>(.*?)</tr>")
        var out: [GraveRecord] = []
        var i = 0
        while i < rows.count {
            let cells = HTML.cells(rows[i])
            guard cells.count >= 7, cells[6].contains("View") else { i += 1; continue }
            let last = cells[0], first = cells[1]
            let dob = cells[2], birthPlace = cells[3], dod = cells[4], cemeteryName = cells[5]
            let detail = i + 1 < rows.count ? HTML.text(rows[i + 1]) : ""
            i += 2

            let plot = HTML.value("Plot Number:", in: detail)
            let deathPlace = HTML.value("Place Of Death:", in: detail)
            let buried = HTML.value("Date Of Burial:", in: detail)
            let mother = HTML.value("Mother:", in: detail)
            let father = HTML.value("Father:", in: detail)
            let spouse = HTML.value("Spouse:", in: detail)

            let name = first.isEmpty ? last : "\(last), \(first)"
            var life: [RecordField] = []
            if let d = PartialDate(text: dob) { life.append(RecordField(label: "Born", value: d.longText)) }
            if !birthPlace.isEmpty { life.append(RecordField(label: "Birthplace", value: birthPlace)) }
            if let d = PartialDate(text: dod) { life.append(RecordField(label: "Died", value: d.longText)) }
            if let p = deathPlace, !p.isEmpty { life.append(RecordField(label: "Place of death", value: p)) }
            var family: [RecordField] = []
            if let m = mother, !m.isEmpty { family.append(RecordField(label: "Mother", value: m)) }
            if let f = father, !f.isEmpty { family.append(RecordField(label: "Father", value: f)) }
            if let s = spouse, !s.isEmpty { family.append(RecordField(label: "Spouse", value: s)) }
            var burial: [RecordField] = []
            if let b = buried, let d = PartialDate(text: b) { burial.append(RecordField(label: "Buried", value: d.longText)) }
            if let p = plot, !p.isEmpty { burial.append(RecordField(label: "Plot", value: p)) }
            burial.append(RecordField(label: "Cemetery", value: cemeteryName))

            var sections: [RecordSection] = []
            if !life.isEmpty { sections.append(RecordSection(title: "Life", fields: life)) }
            if !family.isEmpty { sections.append(RecordSection(title: "Family", fields: family)) }
            if !burial.isEmpty { sections.append(RecordSection(title: "Burial", fields: burial)) }

            let key = [last, first, dob, dod, plot ?? ""].joined(separator: "|")
            out.append(GraveRecord(
                id: "\(cemetery.id):\(key.hashValue)",
                cemeteryID: cemetery.id,
                name: name,
                objectID: nil,
                plot: plot?.isEmpty == false ? plot : nil,
                status: nil,
                birth: PartialDate(text: dob),
                death: PartialDate(text: dod),
                burial: buried.flatMap { PartialDate(text: $0) },
                birthPlace: birthPlace.isEmpty ? nil : birthPlace,
                deathPlace: deathPlace?.isEmpty == false ? deathPlace : nil,
                age: nil,
                veteran: false,
                sections: sections,
                ring: nil,
                centroid: nil,
                source: "Utah Cemeteries & Burials Database, Utah State Historic Preservation Office"))
        }
        return out
    }
}

/// Just enough HTML handling for two government tables.
enum HTML {
    static func matches(in text: String, pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : nil
        }
    }

    static func cells(_ row: String) -> [String] {
        matches(in: row, pattern: "<t[dh][^>]*>(.*?)</t[dh]>").map(text)
    }

    static func text(_ fragment: String) -> String {
        var s = fragment.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = decode(s)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The value after "Label:" up to the next "Word:" label.
    static func value(_ label: String, in text: String) -> String? {
        guard let r = text.range(of: label) else { return nil }
        let rest = text[r.upperBound...]
        let stop = rest.range(of: "[A-Z][A-Za-z ]{1,24}:", options: .regularExpression)
        let raw = stop.map { rest[..<$0.lowerBound] } ?? rest
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    static func decode(_ s: String) -> String {
        var t = s
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&#160;": " "]
        for (k, v) in map { t = t.replacingOccurrences(of: k, with: v) }
        if let re = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let ns = t as NSString
            for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)).reversed() {
                if let code = Int(ns.substring(with: m.range(at: 1))), let scalar = UnicodeScalar(code) {
                    t = (t as NSString).replacingCharacters(in: m.range, with: String(Character(scalar)))
                }
            }
        }
        return t
    }
}
