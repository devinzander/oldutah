//
//  PlatData.swift
//  City Cemetery
//
//  The polygons behind a mapped cemetery. The furniture and the plats load
//  once; lots and graves load by cell as the map zooms in, so 230,000 grave
//  outlines never have to arrive at once. Everything stays in memory for
//  the session and the URL cache keeps the second visit quick.
//

import Foundation
import MapKit
import Observation

enum PlatLayer: String, Hashable, CaseIterable {
    case boundary, plats, blocks, lots, structures, streets, walkways, water, gates, graves

    /// Cell size in degrees for the layers that load by cell.
    var cell: (lat: Double, lon: Double)? {
        switch self {
        case .lots: return (0.004, 0.005)
        case .graves: return (0.0015, 0.002)
        default: return nil
        }
    }

    /// Show the layer once the visible span is narrower than this.
    var maxSpan: Double {
        switch self {
        case .lots: return 0.009
        case .graves: return 0.0055
        case .blocks: return 0.02
        default: return 1
        }
    }
}

struct BBox: Hashable {
    var minLat = Double.greatestFiniteMagnitude, minLon = Double.greatestFiniteMagnitude
    var maxLat = -Double.greatestFiniteMagnitude, maxLon = -Double.greatestFiniteMagnitude
    init(_ ring: [CLLocationCoordinate2D]) {
        for c in ring {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
    }
    func contains(_ c: CLLocationCoordinate2D) -> Bool {
        c.latitude >= minLat && c.latitude <= maxLat && c.longitude >= minLon && c.longitude <= maxLon
    }
    var center: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2) }
}

struct MapPoly: Identifiable, Hashable {
    let id: Int
    let layer: PlatLayer
    let label: String?
    let ring: [CLLocationCoordinate2D]
    let bbox: BBox
    /// Light record for graves; nil for furniture.
    let record: GraveRecord?

    static func == (a: MapPoly, b: MapPoly) -> Bool { a.id == b.id && a.layer == b.layer }
    func hash(into h: inout Hasher) { h.combine(id); h.combine(layer) }

    var occupied: Bool { record?.status == "OCCUPIED" || !(record?.name.isEmpty ?? true) }

    /// Ray cast; the rings are small so there's no need to be clever.
    func contains(_ p: CLLocationCoordinate2D) -> Bool {
        guard bbox.contains(p), ring.count > 2 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = ring[i], b = ring[j]
            if (a.latitude > p.latitude) != (b.latitude > p.latitude) {
                let x = (b.longitude - a.longitude) * (p.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude
                if p.longitude < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}

struct CellKey: Hashable {
    let layer: PlatLayer
    let x: Int
    let y: Int

    var envelope: (minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        let s = layer.cell!
        return (Double(x) * s.lon, Double(y) * s.lat, Double(x + 1) * s.lon, Double(y + 1) * s.lat)
    }

    static func key(for c: CLLocationCoordinate2D, layer: PlatLayer) -> CellKey {
        let s = layer.cell!
        return CellKey(layer: layer, x: Int(floor(c.longitude / s.lon)), y: Int(floor(c.latitude / s.lat)))
    }

    static func keys(covering region: MKCoordinateRegion, layer: PlatLayer) -> [CellKey] {
        let s = layer.cell!
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2
        let x0 = Int(floor(minLon / s.lon)), x1 = Int(floor(maxLon / s.lon))
        let y0 = Int(floor(minLat / s.lat)), y1 = Int(floor(maxLat / s.lat))
        guard (x1 - x0 + 1) * (y1 - y0 + 1) <= 30 else { return [] }
        var out: [CellKey] = []
        for x in x0...x1 { for y in y0...y1 { out.append(CellKey(layer: layer, x: x, y: y)) } }
        return out
    }
}

@MainActor
@Observable
final class PlatData {
    let cemetery: Cemetery
    let config: ArcGISConfig

    private(set) var base: [PlatLayer: [MapPoly]] = [:]
    private(set) var cells: [CellKey: [MapPoly]] = [:]
    /// Bumps whenever polygons arrive, so the map view knows to resync.
    private(set) var version = 0
    private(set) var baseLoaded = false
    private(set) var loadError: String?
    /// Date stamp of the shipped plat, when it was used.
    private(set) var bundledPlat: String?
    private var baseTask: Task<Void, Never>?
    private var loading: Set<CellKey> = []
    private var failed: [CellKey: Date] = [:]

    init(cemetery: Cemetery, config: ArcGISConfig) {
        self.cemetery = cemetery
        self.config = config
    }

    var bounds: BBox? {
        if let b = base[.boundary]?.first { return b.bbox }
        guard let plats = base[.plats], !plats.isEmpty else { return nil }
        var all: [CLLocationCoordinate2D] = []
        for p in plats { all += [CLLocationCoordinate2D(latitude: p.bbox.minLat, longitude: p.bbox.minLon), CLLocationCoordinate2D(latitude: p.bbox.maxLat, longitude: p.bbox.maxLon)] }
        return BBox(all)
    }

    var isLoading: Bool { !loading.isEmpty || (!baseLoaded && baseTask != nil) }

    func loadBase() {
        guard baseTask == nil else { return }
        baseTask = Task { [weak self] in
            guard let self else { return }
            // The shipped plat first: instant, and the whole answer when there's no signal.
            let id = cemetery.id
            if let bundle = await Task.detached(priority: .userInitiated, operation: { PlatBundle.load(cemeteryID: id) }).value {
                for (layer, polys) in bundle.layers where layer != .lots { base[layer] = polys }
                if let lots = bundle.layers[.lots] { seedLots(lots) }
                bundledPlat = bundle.generated
                baseLoaded = true
                version += 1
                return
            }
            await withTaskGroup(of: (PlatLayer, [MapPoly]).self) { group in
                let jobs: [(PlatLayer, [Int])] = [
                    (.boundary, config.boundary.map { [$0] } ?? []),
                    (.plats, [config.plats]),
                    (.blocks, config.blocks.map { [$0] } ?? []),
                    (.structures, config.structures),
                    (.streets, config.streets),
                    (.walkways, config.walkways),
                    (.water, config.water),
                    (.gates, config.gates.map { [$0] } ?? []),
                ]
                for (layer, ids) in jobs where !ids.isEmpty {
                    group.addTask {
                        var polys: [MapPoly] = []
                        for id in ids {
                            var q = ArcGIS.Query()
                            q.outFields = "OBJECTID,LABEL1"
                            q.precision = 6
                            if let fs = try? await ArcGIS.query(self.config.layer(id), q) {
                                polys += fs.compactMap { Self.poly(from: $0, layer: layer, cemeteryID: self.cemetery.id) }
                            }
                        }
                        return (layer, polys)
                    }
                }
                for await (layer, polys) in group {
                    base[layer] = polys
                    version += 1
                }
            }
            baseLoaded = true
            if base[.plats]?.isEmpty ?? true { loadError = "The cemetery's map server didn't answer." }
            version += 1
        }
    }

    /// Bundled lots go into the same cells the live loader would fill, so the
    /// map code has one path. A lot spanning a cell edge lands in every cell it touches.
    private func seedLots(_ lots: [MapPoly]) {
        let s = PlatLayer.lots.cell!
        var buckets: [CellKey: [MapPoly]] = [:]
        for p in lots {
            let x0 = Int(floor(p.bbox.minLon / s.lon)), x1 = Int(floor(p.bbox.maxLon / s.lon))
            let y0 = Int(floor(p.bbox.minLat / s.lat)), y1 = Int(floor(p.bbox.maxLat / s.lat))
            for x in x0...x1 { for y in y0...y1 { buckets[CellKey(layer: .lots, x: x, y: y), default: []].append(p) } }
        }
        // Every cell inside the boundary counts as loaded, even the empty ones.
        if let b = bounds {
            let x0 = Int(floor(b.minLon / s.lon)), x1 = Int(floor(b.maxLon / s.lon))
            let y0 = Int(floor(b.minLat / s.lat)), y1 = Int(floor(b.maxLat / s.lat))
            for x in x0...x1 { for y in y0...y1 { let k = CellKey(layer: .lots, x: x, y: y); if buckets[k] == nil { buckets[k] = [] } } }
        }
        for (k, v) in buckets { cells[k] = v }
    }

    /// Ask for every cell the region needs at this zoom; already-loaded and in-flight cells are skipped.
    func ensure(region: MKCoordinateRegion) {
        loadBase()
        for layer in [PlatLayer.lots, .graves] where region.span.latitudeDelta < layer.maxSpan {
            if layer == .lots, config.lots == nil { continue }
            for key in CellKey.keys(covering: region, layer: layer) {
                guard cells[key] == nil, !loading.contains(key) else { continue }
                if let when = failed[key], Date().timeIntervalSince(when) < 20 { continue }
                loading.insert(key)
                Task { [weak self] in await self?.load(key) }
            }
        }
    }

    private func load(_ key: CellKey) async {
        defer { loading.remove(key) }
        let layerID = key.layer == .graves ? config.graves : config.lots!
        var q = ArcGIS.Query()
        q.envelope = key.envelope
        q.outFields = key.layer == .graves ? ArcGIS.lightFields : "OBJECTID,LABEL1"
        q.precision = 6
        do {
            let fs = try await ArcGIS.query(config.layer(layerID), q)
            cells[key] = fs.compactMap { Self.poly(from: $0, layer: key.layer, cemeteryID: cemetery.id) }
            version += 1
        } catch {
            failed[key] = Date()
        }
    }

    nonisolated private static func poly(from f: ArcGISFeature, layer: PlatLayer, cemeteryID: String) -> MapPoly? {
        guard let id = f.int("OBJECTID"), let ring = f.outerRing, ring.count > 2 else { return nil }
        let record = layer == .graves ? ArcGIS.record(from: f, cemeteryID: cemeteryID, full: false) : nil
        if layer == .graves, record == nil {
            // Unnamed, unoccupied grave: still drawn, just empty.
            return MapPoly(id: id, layer: layer, label: nil, ring: ring, bbox: BBox(ring), record: nil)
        }
        return MapPoly(id: id, layer: layer, label: f.string("LABEL1"), ring: ring, bbox: BBox(ring), record: record)
    }

    /// Loaded graves within the region (duplicates across cells removed).
    func graves(in region: MKCoordinateRegion) -> [MapPoly] {
        var seen = Set<Int>()
        var out: [MapPoly] = []
        for key in CellKey.keys(covering: region, layer: .graves) {
            for p in cells[key] ?? [] where seen.insert(p.id).inserted { out.append(p) }
        }
        return out
    }

    func lots(in region: MKCoordinateRegion) -> [MapPoly] {
        var seen = Set<Int>()
        var out: [MapPoly] = []
        for key in CellKey.keys(covering: region, layer: .lots) {
            for p in cells[key] ?? [] where seen.insert(p.id).inserted { out.append(p) }
        }
        return out
    }

    /// The grave under a fingertip, if its cell has loaded.
    func grave(at c: CLLocationCoordinate2D) -> MapPoly? {
        let key = CellKey.key(for: c, layer: .graves)
        return cells[key]?.first { $0.contains(c) }
    }

    /// The plat (or section) a point falls in, for the card's breadcrumb.
    func plat(at c: CLLocationCoordinate2D) -> MapPoly? {
        base[.plats]?.first { $0.contains(c) }
    }

    /// Fetches the grave polygon by object id, for a record that arrived without one.
    func ring(for record: GraveRecord) async -> [Coordinate]? {
        guard let oid = record.objectID else { return nil }
        var q = ArcGIS.Query()
        q.objectIDs = [oid]
        q.outFields = "OBJECTID"
        let fs = try? await ArcGIS.query(config.layer(config.graves), q)
        return fs?.first?.outerRing?.map(Coordinate.init)
    }
}

/// One PlatData per mapped cemetery, made on first use.
@MainActor
@Observable
final class PlatStore {
    private var stores: [String: PlatData] = [:]

    func data(for cemetery: Cemetery) -> PlatData? {
        guard case .arcgis(let config) = cemetery.source else { return nil }
        if let s = stores[cemetery.id] { return s }
        let s = PlatData(cemetery: cemetery, config: config)
        stores[cemetery.id] = s
        return s
    }
}
