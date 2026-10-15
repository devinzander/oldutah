//
//  VALocator.swift
//  City Cemetery
//
//  Fort Douglas Post Cemetery is a national cemetery, so its register is
//  in the VA's Nationwide Gravesite Locator: a form POST that answers with
//  an HTML table of "Label:" / value rows, ten per page.
//

import Foundation

enum VALocator {
    static let home = URL(string: "https://gravelocator.cem.va.gov/ngl/")!
    static let result = URL(string: "https://gravelocator.cem.va.gov/ngl/result")!

    static func search(cemetery: Cemetery, code: String, query: NameQuery) async throws -> [GraveRecord] {
        guard !query.last.isEmpty else { return [] }
        // The result page wants the session cookie the search page sets.
        _ = try? await URLSession.shared.data(from: home)
        var req = URLRequest(url: result)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(StateRecords.userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 40
        let form: [(String, String)] = [
            ("nglUP", "1"), ("cemetery", code),
            ("lastNameOpt", "2"), ("lastName", query.last),
            ("firstNameOpt", "2"), ("firstName", query.first),
            ("middleNameOpt", "1"), ("middleName", ""),
            ("p_birthMM", ""), ("p_birthYY", ""), ("p_deathMM", ""), ("p_deathYY", ""),
        ]
        req.httpBody = form.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, let html = String(data: data, encoding: .utf8) else {
            throw ArcGISError.badResponse
        }
        return parse(html, cemetery: cemetery)
    }

    /// Each decedent starts with a numbered "Name:" row; the rows after it are that person's fields.
    static func parse(_ html: String, cemetery: Cemetery) -> [GraveRecord] {
        let rows = HTML.matches(in: html, pattern: "<tr[^>]*>(.*?)</tr>").map(HTML.cells)
        var people: [[String: String]] = []
        for cells in rows {
            let trimmed = cells.map { $0.trimmingCharacters(in: .whitespaces) }
            guard trimmed.count >= 2 else { continue }
            // "1 | Name: | SMITH, ANTONIA" or "Date of Birth: | 04/24/1933"
            let pair: (String, String)
            if trimmed.count >= 3, Int(trimmed[0]) != nil { pair = (trimmed[1], trimmed[2]) }
            else { pair = (trimmed[0], trimmed[1]) }
            guard pair.0.hasSuffix(":") else { continue }
            let label = String(pair.0.dropLast())
            if label == "Name" { people.append([:]) }
            guard !people.isEmpty else { continue }
            people[people.count - 1][label] = pair.1
        }
        return people.compactMap { p in
            guard let name = p["Name"], !name.isEmpty else { return nil }
            let birth = p["Date of Birth"].flatMap { PartialDate(text: $0) }
            let death = p["Date of Death"].flatMap { PartialDate(text: $0) }
            let plot = p["Buried At"]
            var life: [RecordField] = []
            if let b = birth { life.append(RecordField(label: "Born", value: b.longText)) }
            if let d = death { life.append(RecordField(label: "Died", value: d.longText)) }
            if let r = p["Relationships"], !r.isEmpty { life.append(RecordField(label: "Relationship", value: r)) }
            var service: [RecordField] = []
            if let rb = p["Rank & Branch"], !rb.isEmpty { service.append(RecordField(label: "Rank & branch", value: rb)) }
            var burial: [RecordField] = []
            if let plot, !plot.isEmpty { burial.append(RecordField(label: "Buried at", value: plot)) }
            if let c = p["Cemetery"] { burial.append(RecordField(label: "Cemetery", value: Names.titleCase(c))) }
            var sections: [RecordSection] = []
            if !life.isEmpty { sections.append(RecordSection(title: "Life", fields: life)) }
            if !service.isEmpty { sections.append(RecordSection(title: "Service", fields: service)) }
            if !burial.isEmpty { sections.append(RecordSection(title: "Burial", fields: burial)) }
            let key = [name, birth?.text ?? "", death?.text ?? "", plot ?? ""].joined(separator: "|")
            return GraveRecord(
                id: "\(cemetery.id):\(key.hashValue)",
                cemeteryID: cemetery.id,
                name: name,
                objectID: nil,
                plot: plot,
                status: nil,
                birth: birth,
                death: death,
                burial: nil,
                birthPlace: nil,
                deathPlace: nil,
                age: nil,
                veteran: !(p["Rank & Branch"] ?? "").isEmpty,
                sections: sections,
                ring: nil,
                centroid: nil,
                source: "VA Nationwide Gravesite Locator, National Cemetery Administration")
        }
    }
}
