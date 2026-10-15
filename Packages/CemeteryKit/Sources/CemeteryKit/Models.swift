//
//  Models.swift
//  City Cemetery
//
//  One record shape for every source: the city's ArcGIS server, Mount
//  Olivet's hosted layer, the state burials database and the VA locator all
//  fold into a GraveRecord. Anything the source knows beyond the headline
//  fields lands in `sections`, the ledger the record screen prints.
//

import Foundation
import CoreLocation

struct Coordinate: Codable, Hashable {
    var lat: Double
    var lon: Double
    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    init(_ lat: Double, _ lon: Double) { self.lat = lat; self.lon = lon }
    init(_ c: CLLocationCoordinate2D) { lat = c.latitude; lon = c.longitude }
}

/// A date the sexton may only have part of.
struct PartialDate: Codable, Hashable {
    var year: Int?
    var month: Int?
    var day: Int?

    init(year: Int?, month: Int?, day: Int?) {
        self.year = (year ?? 0) >= 1000 && (year ?? 0) <= 2100 ? year : nil
        self.month = (1...12).contains(month ?? 0) ? month : nil
        self.day = (1...31).contains(day ?? 0) ? day : nil
    }

    /// "10/29/1967", "0/0/1927", "1967".
    init?(text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let parts = t.split(separator: "/").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 3 {
            self.init(year: parts[2], month: parts[0], day: parts[1])
        } else if parts.count == 1, let y = parts[0] {
            self.init(year: y, month: nil, day: nil)
        } else {
            return nil
        }
        if isEmpty { return nil }
    }

    var isEmpty: Bool { year == nil && month == nil && day == nil }

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let longMonths = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    /// "Oct 13, 1969", "Oct 1969", "1969".
    var text: String {
        var s = ""
        if let month { s = Self.months[month - 1]; if let day { s += " \(day)" } }
        if let year { s += s.isEmpty ? "\(year)" : ", \(year)" }
        return s
    }

    /// "October 13, 1969".
    var longText: String {
        var s = ""
        if let month { s = Self.longMonths[month - 1]; if let day { s += " \(day)" } }
        if let year { s += s.isEmpty ? "\(year)" : ", \(year)" }
        return s
    }

    var yearText: String { year.map(String.init) ?? "—" }

    var date: Date? {
        guard let year else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month ?? 7, day: day ?? 1))
    }
}

struct RecordField: Codable, Hashable, Identifiable {
    let label: String
    let value: String
    var id: String { label + "=" + value }
}

struct RecordSection: Codable, Hashable, Identifiable {
    let title: String
    let fields: [RecordField]
    var id: String { title }
}

/// A grave, wherever the record came from.
struct GraveRecord: Codable, Hashable, Identifiable {
    /// Stable across launches: "<cemetery>:<source key>".
    let id: String
    let cemeteryID: String
    /// As the sexton wrote it — "ZANDER, RHEA MICHELLE" or "Smith, Peter Nelson".
    let name: String
    /// ArcGIS object id, when the record is a mapped polygon.
    let objectID: Int?
    /// The plot string as recorded — "WEST_13_16_5WT", "SECTION L SITE 77".
    let plot: String?
    let status: String?
    let birth: PartialDate?
    let death: PartialDate?
    let burial: PartialDate?
    let birthPlace: String?
    let deathPlace: String?
    let age: String?
    let veteran: Bool
    let sections: [RecordSection]
    /// Outer ring of the grave polygon, when mapped.
    let ring: [Coordinate]?
    let centroid: Coordinate?
    /// Where the record came from, for the footer.
    let source: String

    var cemetery: Cemetery { Cemeteries.byID[cemeteryID] ?? Cemeteries.all[0] }
    var isMapped: Bool { ring != nil }

    /// "Rhea Michelle Zander".
    var displayName: String { Names.display(name) }
    /// "Zander" — the family name, for grouping.
    var surname: String { Names.surname(name) }

    /// "1969 – 2024", "d. 1927", "b. 1907".
    var lifespan: String {
        switch (birth?.year, death?.year) {
        case let (b?, d?): return "\(b) – \(d)"
        case let (b?, nil): return "b. \(b)"
        case let (nil, d?): return "d. \(d)"
        default: return ""
        }
    }

    /// Years lived, when both dates are known and the sexton left age blank.
    var computedAge: Int? {
        guard let b = birth?.date, let d = death?.date else { return nil }
        let y = Calendar.current.dateComponents([.year], from: b, to: d).year ?? 0
        return y >= 0 && y < 125 ? y : nil
    }

    /// The plot split into the cemetery's levels: Plat WEST · Block 13 · Lot 16 · Grave 5WT.
    var plotFields: [RecordField] {
        guard let plot, !plot.isEmpty else { return [] }
        let levels = cemetery.plotLevels
        let parts = plot.split(separator: "_", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        guard levels.count == parts.count else { return [RecordField(label: "Plot", value: plot)] }
        return zip(levels, parts).map { RecordField(label: $0, value: $1) }
    }

    /// Everyone in the same lot shares this prefix (levels above the grave).
    var lotPrefix: String? {
        guard let plot, cemetery.plotLevels.count > 1 else { return nil }
        let parts = plot.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count == cemetery.plotLevels.count else { return nil }
        return parts.dropLast().joined(separator: "_")
    }

    var shareText: String {
        var lines = [displayName]
        if !lifespan.isEmpty { lines.append(lifespan) }
        lines.append(cemetery.name)
        let plotLine = plotFields.map { "\($0.label) \($0.value)" }.joined(separator: " · ")
        if !plotLine.isEmpty { lines.append(plotLine) }
        if let c = centroid {
            lines.append("https://maps.apple.com/?ll=\(c.lat),\(c.lon)&q=\(displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Grave")")
        }
        return lines.joined(separator: "\n")
    }
}

enum Names {
    /// "ZANDER, RHEA MICHELLE" → "Rhea Michelle Zander"; "Smith, Peter Nelson" → "Peter Nelson Smith".
    static func display(_ recorded: String) -> String {
        let cleaned = recorded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "Unnamed" }
        let last: String, first: String
        if let comma = cleaned.firstIndex(of: ",") {
            last = String(cleaned[..<comma]).trimmingCharacters(in: .whitespaces)
            first = String(cleaned[cleaned.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
        } else {
            last = cleaned; first = ""
        }
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return isShouting(full) ? titleCase(full) : full
    }

    static func surname(_ recorded: String) -> String {
        let cleaned = recorded.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = cleaned.split(separator: ",").first.map(String.init) ?? cleaned
        let t = last.trimmingCharacters(in: .whitespaces)
        return isShouting(t) ? titleCase(t) : t
    }

    /// "ZANDER, RHEA" and "Zander, Rhea" both read the same.
    static func isShouting(_ s: String) -> Bool {
        let letters = s.filter(\.isLetter)
        return !letters.isEmpty && letters.allSatisfy(\.isUppercase)
    }

    static func titleCase(_ s: String) -> String {
        s.split(separator: " ").map { word -> String in
            let w = word.lowercased()
            var out = ""
            var capitalizeNext = true
            for ch in w {
                if capitalizeNext, ch.isLetter { out += String(ch).uppercased(); capitalizeNext = false }
                else { out += String(ch) }
                if ch == "'" || ch == "-" || ch == "." || ch == "(" { capitalizeNext = true }
            }
            if out.hasPrefix("Mc"), out.count > 2 {
                let i = out.index(out.startIndex, offsetBy: 2)
                out = "Mc" + String(out[i]).uppercased() + out[out.index(after: i)...]
            }
            return out
        }.joined(separator: " ")
    }
}

/// What the user typed, split the way the sextons file it.
struct NameQuery: Hashable {
    let last: String
    let first: String

    init(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comma = t.firstIndex(of: ",") {
            last = String(t[..<comma]).trimmingCharacters(in: .whitespaces)
            first = String(t[t.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
        } else {
            let words = t.split(separator: " ").map(String.init)
            if words.count >= 2 {
                // "Rhea Zander" — family name last.
                last = words.last!
                first = words.dropLast().joined(separator: " ")
            } else {
                last = t; first = ""
            }
        }
    }

    var isEmpty: Bool { last.isEmpty && first.isEmpty }

    /// A single quote is the only character the ArcGIS SQL needs escaped.
    static func sql(_ s: String) -> String { s.uppercased().replacingOccurrences(of: "'", with: "''") }
}
