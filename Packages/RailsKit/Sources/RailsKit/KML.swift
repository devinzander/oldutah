//
//  KML.swift
//  Utah Rails
//
//  The site's railroad maps are Google My Maps. Each exports as KML, which
//  is bundled with the app and also refreshed live. This is the KML model
//  and a small XMLParser-based reader for the subset My Maps writes:
//  Document → Folder → Placemark with Point / LineString / Polygon (or a
//  MultiGeometry of them), styled through Style / StyleMap.
//

import Foundation
import CoreLocation
import SwiftUI

struct RailMap: Codable, Hashable, Identifiable {
    let title: String
    let mid: String
    let blurb: String
    let related: String?
    let section: String
    var documentName: String?
    var placemarks: Int?
    var id: String { title + "|" + mid }

    var googleURL: URL { URL(string: "https://www.google.com/maps/d/viewer?mid=\(mid)")! }
    var kmlURL: URL { URL(string: "https://www.google.com/maps/d/kml?mid=\(mid)&forcekml=1")! }
    var relatedPage: PageRef? { related.map { PageRef(path: $0, title: "") } }

    /// "A Google Map of …" → "…" — the app isn't Google Maps.
    var cleanBlurb: String {
        var b = blurb
        for prefix in ["A Google Map of ", "A Google map of ", "A Google Map showing ", "A Google map showing ", "A Google Map that shows ", "A Google Map for ", "A Google map with ", "A Google Map with ", "A Google Map ", "A Google map ", "Google map of "] {
            if b.hasPrefix(prefix) { b = String(b.dropFirst(prefix.count)); break }
        }
        guard let f = b.first else { return b }
        return f.uppercased() + b.dropFirst()
    }
}

struct MapsCatalog: Codable {
    let fetched: String
    let maps: [RailMap]
}

enum MapGeometry: Hashable {
    case point(CLLocationCoordinate2D)
    case line([CLLocationCoordinate2D])
    case polygon([CLLocationCoordinate2D])
}

extension CLLocationCoordinate2D: @retroactive Hashable {
    public static func == (a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> Bool { a.latitude == b.latitude && a.longitude == b.longitude }
    public func hash(into h: inout Hasher) { h.combine(latitude); h.combine(longitude) }
}

struct MapFeature: Hashable, Identifiable {
    let id: Int
    let name: String
    let description: String
    let geometry: MapGeometry
    let color: Color
    let lineWidth: CGFloat
    let layer: String

    var coordinate: CLLocationCoordinate2D {
        switch geometry {
        case .point(let c): return c
        case .line(let cs): return cs[cs.count / 2]
        case .polygon(let cs): return cs[cs.count / 2]
        }
    }
    var kindSymbol: String {
        switch geometry {
        case .point: return "mappin"
        case .line: return "point.topleft.down.to.point.bottomright.curvepath"
        case .polygon: return "square.dashed"
        }
    }
}

struct MapLayer: Hashable, Identifiable {
    let name: String
    let features: [MapFeature]
    var id: String { name }
}

struct MapDocument: Hashable {
    let name: String
    let description: String
    let layers: [MapLayer]

    var features: [MapFeature] { layers.flatMap(\.features) }

    /// Bounding box of everything drawn.
    var bounds: (min: CLLocationCoordinate2D, max: CLLocationCoordinate2D)? {
        var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
        var any = false
        for f in features {
            let cs: [CLLocationCoordinate2D]
            switch f.geometry {
            case .point(let c): cs = [c]
            case .line(let l): cs = l
            case .polygon(let p): cs = p
            }
            for c in cs {
                any = true
                minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
                minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
            }
        }
        return any ? (CLLocationCoordinate2D(latitude: minLat, longitude: minLon), CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)) : nil
    }
}

// MARK: - Parser

final class KMLParser: NSObject, XMLParserDelegate {
    private struct Style {
        var lineColor: Color?
        var lineWidth: CGFloat?
        var polyColor: Color?
        var iconColor: Color?
    }

    private var styles: [String: Style] = [:]
    private var styleMaps: [String: String] = [:]     // map id → normal style id
    private var docName = ""
    private var docDescription = ""
    private var layers: [MapLayer] = []
    private var rootFeatures: [MapFeature] = []

    // Parsing state
    private var path: [String] = []
    private var text = ""
    private var currentStyleID: String?
    private var currentStyle = Style()
    private var inStyleMap: String?
    private var pairKey = ""
    private var pairURL = ""
    private var folderName = ""
    private var folderFeatures: [MapFeature] = []
    private var inFolder = false
    private var pm: (name: String, description: String, styleURL: String, geoms: [MapGeometry])?
    private var geomKind = ""
    private var nextID = 0

    static func parse(_ data: Data) -> MapDocument? {
        let p = KMLParser()
        let x = XMLParser(data: data)
        x.delegate = p
        x.shouldProcessNamespaces = false
        guard x.parse() else { return nil }
        var layers = p.layers
        if !p.rootFeatures.isEmpty { layers.insert(MapLayer(name: layers.isEmpty ? "Map" : "Other", features: p.rootFeatures), at: 0) }
        guard !layers.isEmpty else { return nil }
        return MapDocument(name: p.docName, description: p.docDescription, layers: layers)
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        path.append(name)
        text = ""
        switch name {
        case "Style":
            currentStyleID = attributes["id"]
            currentStyle = Style()
        case "StyleMap":
            inStyleMap = attributes["id"]
        case "Pair":
            pairKey = ""; pairURL = ""
        case "Folder":
            inFolder = true; folderName = ""; folderFeatures = []
        case "Placemark":
            pm = ("", "", "", [])
        case "Point", "LineString", "Polygon":
            geomKind = name
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = path.count >= 2 ? path[path.count - 2] : ""
        switch name {
        case "name":
            if let _ = pm, parent == "Placemark" { pm!.name = t }
            else if parent == "Folder" { folderName = t }
            else if parent == "Document" { docName = t }
        case "description":
            if let _ = pm, parent == "Placemark" { pm!.description = HTML.text(t) }
            else if parent == "Document" { docDescription = HTML.text(t) }
        case "styleUrl":
            if let _ = pm, parent == "Placemark" { pm!.styleURL = t }
            else if parent == "Pair" { pairURL = t }
        case "key":
            if parent == "Pair" { pairKey = t }
        case "Pair":
            if pairKey == "normal", let id = inStyleMap { styleMaps[id] = pairURL.replacingOccurrences(of: "#", with: "") }
        case "StyleMap":
            inStyleMap = nil
        case "color":
            let c = Self.color(kml: t)
            if path.contains("LineStyle") { currentStyle.lineColor = c }
            else if path.contains("PolyStyle") { currentStyle.polyColor = c }
            else if path.contains("IconStyle") { currentStyle.iconColor = c }
        case "width":
            if path.contains("LineStyle") { currentStyle.lineWidth = CGFloat(Double(t) ?? 3) }
        case "href":
            // Stock My Maps pins: "22-blue-dot.png", "123-red-dot.png", "157-yellow-dot.png"…
            if path.contains("IconStyle"), currentStyle.iconColor == nil {
                let n = t.lowercased()
                if n.contains("blue") { currentStyle.iconColor = Color(hex: 0x1E5AA8) }
                else if n.contains("red") { currentStyle.iconColor = Color(hex: 0xC8362A) }
                else if n.contains("yellow") { currentStyle.iconColor = Color(hex: 0xC9A227) }
                else if n.contains("purple") { currentStyle.iconColor = Color(hex: 0x6B3FA0) }
                else if n.contains("green") { currentStyle.iconColor = Color(hex: 0x3E6B4F) }
                else if n.contains("orange") { currentStyle.iconColor = Color(hex: 0xD2691E) }
            }
        case "Style":
            if let id = currentStyleID {
                // My Maps encodes the color in the id too: line-000099-6000, icon-1899-0288D1
                if currentStyle.iconColor == nil, let hex = Self.hexFromID(id) { currentStyle.iconColor = Color(hex: hex) }
                if currentStyle.lineColor == nil, id.hasPrefix("line-") || id.hasPrefix("poly-"), let hex = Self.hexFromID(id) { currentStyle.lineColor = Color(hex: hex) }
                styles[id] = currentStyle
            }
            currentStyleID = nil
        case "coordinates":
            guard pm != nil else { break }
            let coords: [CLLocationCoordinate2D] = t.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).compactMap { triple in
                let parts = triple.split(separator: ",")
                guard parts.count >= 2, let lon = Double(parts[0]), let lat = Double(parts[1]) else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            guard !coords.isEmpty else { break }
            switch geomKind {
            case "Point": pm!.geoms.append(.point(coords[0]))
            case "LineString": pm!.geoms.append(.line(coords))
            case "Polygon": if path.contains("outerBoundaryIs") || !path.contains("innerBoundaryIs") { pm!.geoms.append(.polygon(coords)) }
            default: break
            }
        case "Placemark":
            if let p = pm {
                let style = resolve(p.styleURL)
                for g in p.geoms {
                    let color: Color
                    var width: CGFloat = 3
                    switch g {
                    case .point: color = style?.iconColor ?? Brand.accent
                    case .line: color = style?.lineColor ?? Brand.accent; width = min(max((style?.lineWidth ?? 3), 2), 7)
                    case .polygon: color = style?.polyColor ?? style?.lineColor ?? Brand.accent
                    }
                    nextID += 1
                    let f = MapFeature(id: nextID, name: p.name.isEmpty ? "Untitled" : p.name, description: p.description,
                                       geometry: g, color: color, lineWidth: width, layer: inFolder ? folderName : "")
                    if inFolder { folderFeatures.append(f) } else { rootFeatures.append(f) }
                }
            }
            pm = nil
        case "Folder":
            if !folderFeatures.isEmpty { layers.append(MapLayer(name: folderName.isEmpty ? "Layer \(layers.count + 1)" : folderName, features: folderFeatures)) }
            inFolder = false
        default: break
        }
        path.removeLast()
        text = ""
    }

    private func resolve(_ url: String) -> Style? {
        var id = url.replacingOccurrences(of: "#", with: "")
        if let mapped = styleMaps[id] { id = mapped }
        return styles[id]
    }

    /// KML colors are aabbggrr.
    private static func color(kml: String) -> Color? {
        let h = kml.trimmingCharacters(in: .whitespaces)
        guard h.count == 8, let v = UInt32(h, radix: 16) else { return nil }
        let r = Double(v & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double((v >> 16) & 0xFF) / 255
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    private static func hexFromID(_ id: String) -> UInt? {
        for part in id.split(separator: "-") where part.count == 6 {
            if let v = UInt(part, radix: 16) { return v }
        }
        return nil
    }
}

// MARK: - Loading

@MainActor
@Observable
final class MapsStore {
    private(set) var maps: [RailMap] = []
    private(set) var fetched = ""
    private var byMid: [String: RailMap] = [:]
    private var docs: [String: MapDocument] = [:]

    init() {
        if let url = Bundle.module.url(forResource: "MapsCatalog", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let c = try? JSONDecoder().decode(MapsCatalog.self, from: data) {
            maps = c.maps
            fetched = c.fetched
            for m in c.maps where byMid[m.mid] == nil { byMid[m.mid] = m }
        }
    }

    var sections: [(String, [RailMap])] {
        var order: [String] = []
        var by: [String: [RailMap]] = [:]
        for m in maps {
            if by[m.section] == nil { order.append(m.section) }
            by[m.section, default: []].append(m)
        }
        return order.map { ($0, by[$0]!) }
    }

    var uniqueCount: Int { byMid.count }

    func map(mid: String) -> RailMap? { byMid[mid] }

    /// The map for a Google My Maps link met in an article, if it's one of the site's.
    func map(for url: URL) -> RailMap? {
        guard (url.host ?? "").contains("google."), url.path.contains("/maps/d/"),
              let mid = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "mid" })?.value else { return nil }
        return byMid[mid] ?? RailMap(title: "Map", mid: mid, blurb: "", related: nil, section: "")
    }

    /// Live copy when reachable (Don edits these), else the bundled one.
    func document(for map: RailMap) async -> MapDocument? {
        if let d = docs[map.mid] { return d }
        var doc: MapDocument? = nil
        if let (data, response) = try? await URLSession.shared.data(from: map.kmlURL),
           (response as? HTTPURLResponse)?.statusCode == 200, data.count > 200 {
            doc = await Task.detached { KMLParser.parse(data) }.value
        }
        if doc == nil, let url = Bundle.module.url(forResource: map.mid, withExtension: "kml"), let data = try? Data(contentsOf: url) {
            doc = await Task.detached { KMLParser.parse(data) }.value
        }
        if let doc { docs[map.mid] = doc }
        return doc
    }
}
