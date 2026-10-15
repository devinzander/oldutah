//
//  ArcGIS.swift
//  City Cemetery
//
//  The two mapped cemeteries publish the same "Spatial Generations" layer
//  set on ArcGIS servers: a Grave polygon layer with the sexton's fields,
//  lots, plats or sections, and the furniture (streets, buildings, water).
//  This is a thin REST client — queries by name, by envelope, by object id —
//  that returns rings in WGS84 and attributes as plain dictionaries.
//

import Foundation
import CoreLocation

struct ArcGISConfig: Hashable, Codable {
    let base: String
    let graves: Int
    let lots: Int?
    let blocks: Int?
    let plats: Int
    let boundary: Int?
    let structures: [Int]
    let streets: [Int]
    let walkways: [Int]
    let water: [Int]
    let gates: Int?
    /// The server's page size for envelope queries.
    let pageSize: Int
    /// Where plat labels come from — the plats layer's LABEL1 on both.
    let platLabelField: String

    func layer(_ id: Int) -> URL { URL(string: "\(base)/\(id)")! }

    static let saltLakeCity = ArcGISConfig(
        base: "https://maps.slc.gov/mapservices/rest/services/Cemetery/CemeteryPublicMap/MapServer",
        graves: 6, lots: 5, blocks: 0, plats: 4, boundary: 7,
        structures: [2], streets: [3], walkways: [], water: [], gates: nil,
        pageSize: 12000, platLabelField: "LABEL1")

    static let mountOlivet = ArcGISConfig(
        base: "https://services8.arcgis.com/hH6UHtphUopyoDc2/arcgis/rest/services/Spatial_Generations_Mount_Olivet_Cemetery_VIEW_ONLY_layer/FeatureServer",
        graves: 10, lots: 20, blocks: nil, plats: 40, boundary: 50,
        structures: [80, 202], streets: [60], walkways: [70], water: [201], gates: 205,
        pageSize: 2000, platLabelField: "LABEL1")
}

/// One feature back from a query.
struct ArcGISFeature {
    let attributes: [String: Any]
    let rings: [[CLLocationCoordinate2D]]
    let point: CLLocationCoordinate2D?

    func string(_ key: String) -> String? {
        guard let v = attributes[key] else { return nil }
        if v is NSNull { return nil }
        if let s = v as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    func int(_ key: String) -> Int? {
        guard let v = attributes[key] else { return nil }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) }
        return nil
    }

    var outerRing: [CLLocationCoordinate2D]? { rings.max { $0.count < $1.count } }

    var centroid: CLLocationCoordinate2D? {
        if let point { return point }
        guard let ring = outerRing, !ring.isEmpty else { return nil }
        let lat = ring.reduce(0) { $0 + $1.latitude } / Double(ring.count)
        let lon = ring.reduce(0) { $0 + $1.longitude } / Double(ring.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

enum ArcGISError: Error, LocalizedError {
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .server(let m): return m
        case .badResponse: return "The map server sent something unexpected."
        }
    }
}

enum ArcGIS {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.urlCache = URLCache.shared
        return URLSession(configuration: c)
    }()

    struct Query {
        var whereClause = "1=1"
        var outFields = "*"
        var envelope: (minLon: Double, minLat: Double, maxLon: Double, maxLat: Double)? = nil
        var objectIDs: [Int]? = nil
        var returnGeometry = true
        var orderBy: String? = nil
        var limit: Int? = nil
        var offset: Int? = nil
        var precision = 6
    }

    /// One page of features. Pages until the server stops flagging
    /// `exceededTransferLimit`, unless `q.limit` caps it.
    static func query(_ layer: URL, _ q: Query) async throws -> [ArcGISFeature] {
        var all: [ArcGISFeature] = []
        var offset = q.offset ?? 0
        while true {
            var items = [
                URLQueryItem(name: "f", value: "json"),
                URLQueryItem(name: "where", value: q.whereClause),
                URLQueryItem(name: "outFields", value: q.outFields),
                URLQueryItem(name: "returnGeometry", value: q.returnGeometry ? "true" : "false"),
                URLQueryItem(name: "outSR", value: "4326"),
                URLQueryItem(name: "geometryPrecision", value: String(q.precision)),
            ]
            if let e = q.envelope {
                items += [
                    URLQueryItem(name: "geometry", value: "\(e.minLon),\(e.minLat),\(e.maxLon),\(e.maxLat)"),
                    URLQueryItem(name: "geometryType", value: "esriGeometryEnvelope"),
                    URLQueryItem(name: "inSR", value: "4326"),
                    URLQueryItem(name: "spatialRel", value: "esriSpatialRelIntersects"),
                ]
            }
            if let ids = q.objectIDs { items.append(URLQueryItem(name: "objectIds", value: ids.map(String.init).joined(separator: ","))) }
            if let o = q.orderBy { items.append(URLQueryItem(name: "orderByFields", value: o)) }
            if let l = q.limit { items.append(URLQueryItem(name: "resultRecordCount", value: String(l))) }
            if offset > 0 { items.append(URLQueryItem(name: "resultOffset", value: String(offset))) }

            var comps = URLComponents(url: layer.appendingPathComponent("query"), resolvingAgainstBaseURL: false)!
            comps.queryItems = items
            let (data, response) = try await session.data(from: comps.url!)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw ArcGISError.badResponse }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ArcGISError.badResponse }
            if let err = json["error"] as? [String: Any] {
                throw ArcGISError.server((err["message"] as? String) ?? "Query failed")
            }
            let page = (json["features"] as? [[String: Any]] ?? []).map(parse)
            all += page
            let exceeded = (json["exceededTransferLimit"] as? Bool) ?? false
            if q.limit != nil || !exceeded || page.isEmpty { break }
            offset += page.count
        }
        return all
    }

    private static func parse(_ f: [String: Any]) -> ArcGISFeature {
        let attrs = f["attributes"] as? [String: Any] ?? [:]
        var rings: [[CLLocationCoordinate2D]] = []
        var point: CLLocationCoordinate2D?
        if let g = f["geometry"] as? [String: Any] {
            if let rs = g["rings"] as? [[[Double]]] {
                rings = rs.map { $0.compactMap { p in p.count >= 2 ? CLLocationCoordinate2D(latitude: p[1], longitude: p[0]) : nil } }
            } else if let x = g["x"] as? Double, let y = g["y"] as? Double {
                point = CLLocationCoordinate2D(latitude: y, longitude: x)
            }
        }
        return ArcGISFeature(attributes: attrs, rings: rings, point: point)
    }

    // MARK: - Graves

    /// The fields the map and the result rows need; the full record is fetched on open.
    static let lightFields = "OBJECTID,ID_,Address,Deceased,Status,Birth_Year,Death_Year,Veteran"

    /// `UPPER(Deceased) LIKE 'ZANDER%'`, with the first name matched anywhere after the comma.
    static func nameClause(_ q: NameQuery) -> String {
        var parts: [String] = []
        if !q.last.isEmpty { parts.append("UPPER(Deceased) LIKE '\(NameQuery.sql(q.last))%'") }
        if !q.first.isEmpty { parts.append("UPPER(Deceased) LIKE '%, \(NameQuery.sql(q.first))%'") }
        if parts.isEmpty { parts.append("Deceased IS NOT NULL") }
        return parts.joined(separator: " AND ")
    }

    static func searchGraves(_ config: ArcGISConfig, cemeteryID: String, query: NameQuery, limit: Int = 200) async throws -> [GraveRecord] {
        var q = Query()
        q.whereClause = nameClause(query)
        q.outFields = lightFields
        q.orderBy = "Deceased"
        q.limit = limit
        let features = try await ArcGIS.query(config.layer(config.graves), q)
        return features.compactMap { record(from: $0, cemeteryID: cemeteryID, full: false) }
    }

    static func grave(_ config: ArcGISConfig, cemeteryID: String, objectID: Int) async throws -> GraveRecord? {
        var q = Query()
        q.objectIDs = [objectID]
        let features = try await ArcGIS.query(config.layer(config.graves), q)
        return features.first.flatMap { record(from: $0, cemeteryID: cemeteryID, full: true) }
    }

    /// Everyone recorded in the same lot. `_` is a SQL wildcard, hence the escape.
    static func lotMates(_ config: ArcGISConfig, cemeteryID: String, lotPrefix: String) async throws -> [GraveRecord] {
        let escaped = lotPrefix.replacingOccurrences(of: "'", with: "''").replacingOccurrences(of: "_", with: "\\_")
        var q = Query()
        q.whereClause = "Address LIKE '\(escaped)\\_%' ESCAPE '\\' AND Deceased IS NOT NULL"
        q.outFields = lightFields
        q.orderBy = "Address"
        q.limit = 200
        let features = try await ArcGIS.query(config.layer(config.graves), q)
        return features.compactMap { record(from: $0, cemeteryID: cemeteryID, full: false) }
    }

    /// The whole sexton's ledger, grouped the way the record screen prints it.
    static func record(from f: ArcGISFeature, cemeteryID: String, full: Bool) -> GraveRecord? {
        guard let oid = f.int("OBJECTID") else { return nil }
        let name = f.string("Deceased") ?? ""
        let status = f.string("Status")
        guard !name.isEmpty || status == "OCCUPIED" else { return nil }
        let ring = f.outerRing?.map(Coordinate.init)
        let centroid = f.centroid.map(Coordinate.init)
        let veteranText = (f.string("Veteran") ?? "").uppercased()
        let veteran = veteranText.hasPrefix("Y") || !(f.string("Branch") ?? "").isEmpty || !(f.string("Conflict") ?? "").isEmpty

        var sections: [RecordSection] = []
        if full {
            func field(_ label: String, _ key: String) -> RecordField? {
                f.string(key).map { RecordField(label: label, value: $0) }
            }
            func date(_ label: String, _ prefix: String) -> RecordField? {
                let d = PartialDate(year: f.int("\(prefix)_Year"), month: f.int("\(prefix)_Month"), day: f.int("\(prefix)_Day"))
                return d.isEmpty ? nil : RecordField(label: label, value: d.longText)
            }
            let life: [RecordField] = [
                date("Born", "Birth"), field("Birthplace", "Birth_Place"),
                date("Died", "Death"), field("Place of death", "Death_Place"),
                field("Age", "Age"), field("Gender", "Gender"),
                field("Marital status", "Marital_Status"), field("Occupation", "Occupation"),
                field("Residence", "Residence"), field("Cause of death", "Cause"),
                field("Notes", "Deceased_Comments"),
            ].compactMap { $0 }
            let burial: [RecordField] = [
                date("Buried", "Burial"), field("Time", "Burial_Time"),
                field("Burial type", "Burial_Type"), field("Burial number", "Burial_Number"),
                field("Permit", "Burial_Permit"), field("Source", "Source"),
                field("Moved from", "Moved_From"), field("Disinterred", "Disinterred"),
                field("Disinterred to", "Disinterred_To"),
                field("Casket", "Casket_Type"), field("Vault", "Vault"), field("Vault type", "Vault_Type"),
                field("Vault company", "Vault_Company"),
                date("Service", "Service"), field("Service place", "Service_Place"),
                field("Notes", "Burial_Comments"),
            ].compactMap { $0 }
            let service: [RecordField] = [
                field("Veteran", "Veteran"), field("Rank", "Rank"), field("Branch", "Branch"),
                field("Conflict", "Conflict"), field("Notes", "Veteran_Notes"),
            ].compactMap { $0 }
            let marker: [RecordField] = [
                field("Marker", "Marker"), field("Material", "Marker_Material"),
                field("Type", "Marker_Type"), field("Imagery", "Marker_Imagery"),
                field("Artisan", "Marker_Artisan"), field("Epitaph", "Marker_Epitaph"),
                field("Restriction", "Marker_Restriction"), field("Notes", "Marker_Comments"),
            ].compactMap { $0 }
            let plot: [RecordField] = [
                field("Status", "Status"), field("Hold", "Hold"), field("Status notes", "Status_Comments"),
                field("Grave ID", "ID_"), field("Deceased ID", "Deceased_ID"),
            ].compactMap { $0 }
            for (title, fields) in [("Life", life), ("Burial", burial), ("Service", service), ("Marker", marker), ("Plot", plot)] where !fields.isEmpty {
                sections.append(RecordSection(title: title, fields: fields))
            }
        }

        return GraveRecord(
            id: "\(cemeteryID):\(oid)",
            cemeteryID: cemeteryID,
            name: name,
            objectID: oid,
            plot: f.string("Address"),
            status: status,
            birth: full ? PartialDate(year: f.int("Birth_Year"), month: f.int("Birth_Month"), day: f.int("Birth_Day")) : PartialDate(year: f.int("Birth_Year"), month: nil, day: nil),
            death: full ? PartialDate(year: f.int("Death_Year"), month: f.int("Death_Month"), day: f.int("Death_Day")) : PartialDate(year: f.int("Death_Year"), month: nil, day: nil),
            burial: full ? PartialDate(year: f.int("Burial_Year"), month: f.int("Burial_Month"), day: f.int("Burial_Day")) : nil,
            birthPlace: f.string("Birth_Place"),
            deathPlace: f.string("Death_Place"),
            age: f.string("Age"),
            veteran: veteran,
            sections: sections,
            ring: ring,
            centroid: centroid,
            source: cemeteryID == Cemeteries.slc ? "Salt Lake City Cemetery records, via the city's public map server" : "Mount Olivet Cemetery records, via the cemetery's public map layer")
    }
}
