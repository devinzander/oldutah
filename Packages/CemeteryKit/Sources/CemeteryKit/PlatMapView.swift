//
//  PlatMapView.swift
//  City Cemetery
//
//  MKMapView wrapped for SwiftUI, because a cemetery at walking zoom is a
//  few thousand polygons and MapKit's overlay renderers handle that where a
//  SwiftUI Map would not. Each loaded cell becomes one MKMultiPolygon per
//  style; the selected grave and the walk line sit on top.
//

import SwiftUI
import MapKit

/// A one-shot camera request; the id makes each request distinct.
struct MapFocus: Equatable {
    let id = UUID()
    let center: CLLocationCoordinate2D
    let meters: Double
    let animated: Bool
    static func == (a: MapFocus, b: MapFocus) -> Bool { a.id == b.id }
}

final class LayerOverlay: MKMultiPolygon {
    var key = ""
    var layer: PlatLayer = .graves
    var occupied = true
}

final class SelectionOverlay: MKPolygon {}
final class TargetOverlay: MKPolygon {}
final class WalkLine: MKPolyline {}

final class LabelAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let layer: PlatLayer
    let key: String
    init(coordinate: CLLocationCoordinate2D, title: String, layer: PlatLayer, key: String) {
        self.coordinate = coordinate; self.title = title; self.layer = layer; self.key = key
    }
}

struct PlatMapView: UIViewRepresentable {
    let data: PlatData
    let satellite: Bool
    let selected: GraveRecord?
    let target: GraveRecord?
    let userCoordinate: CLLocationCoordinate2D?
    let focus: MapFocus?
    let onTap: (MapPoly?) -> Void
    let onRegionChange: (MKCoordinateRegion) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true
        map.isPitchEnabled = false
        map.isRotateEnabled = true
        map.pointOfInterestFilter = .excludingAll
        map.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 25)
        map.register(LabelView.self, forAnnotationViewWithReuseIdentifier: LabelView.reuseID)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        context.coordinator.map = map
        applyStyle(map)
        // Start on the cemetery.
        let c = data.cemetery.coordinate.cl
        map.setRegion(MKCoordinateRegion(center: c, latitudinalMeters: 1100, longitudinalMeters: 1100), animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let co = context.coordinator
        co.parent = self
        if co.satellite != satellite { co.satellite = satellite; applyStyle(map) }
        if let focus, co.lastFocus != focus {
            co.lastFocus = focus
            co.pendingFocus = focus
        }
        co.applyFocusIfReady(map)
        co.sync(map)
    }

    private func applyStyle(_ map: MKMapView) {
        if satellite {
            let c = MKHybridMapConfiguration(elevationStyle: .flat)
            c.pointOfInterestFilter = .excludingAll
            c.showsTraffic = false
            map.preferredConfiguration = c
        } else {
            let c = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            c.pointOfInterestFilter = .excludingAll
            map.preferredConfiguration = c
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: PlatMapView
        weak var map: MKMapView?
        var satellite = true
        var lastFocus: MapFocus?
        var pendingFocus: MapFocus?
        private var overlays: [String: LayerOverlay] = [:]
        private var labels: [String: LabelAnnotation] = [:]
        private var selection: SelectionOverlay?
        private var selectionID: String?
        private var targetOverlay: TargetOverlay?
        private var targetID: String?
        private var walk: WalkLine?
        private var lastVersion = -1
        private var lastSpanBucket = -1
        private var lastRegion: MKCoordinateRegion?

        init(_ parent: PlatMapView) { self.parent = parent }

        // MARK: Focus

        /// A region set before the view has a size comes out wrong; hold it until layout.
        func applyFocusIfReady(_ map: MKMapView) {
            guard let f = pendingFocus, map.bounds.width > 10, map.bounds.height > 10 else { return }
            pendingFocus = nil
            map.setRegion(MKCoordinateRegion(center: f.center, latitudinalMeters: f.meters, longitudinalMeters: f.meters), animated: f.animated)
        }

        // MARK: Sync

        func sync(_ map: MKMapView) {
            let region = map.region
            let data = parent.data
            let bucket = spanBucket(region.span.latitudeDelta)
            let moved = lastRegion.map { abs($0.center.latitude - region.center.latitude) > region.span.latitudeDelta * 0.2 || abs($0.center.longitude - region.center.longitude) > region.span.longitudeDelta * 0.2 } ?? true
            if data.version != lastVersion || bucket != lastSpanBucket || moved {
                lastVersion = data.version
                lastSpanBucket = bucket
                lastRegion = region
                syncLayers(map, region: region)
                syncLabels(map, region: region)
            }
            syncSelection(map)
            syncTarget(map)
            syncWalk(map)
        }

        private func spanBucket(_ d: Double) -> Int {
            if d < PlatLayer.graves.maxSpan { return 3 }
            if d < PlatLayer.lots.maxSpan { return 2 }
            if d < PlatLayer.blocks.maxSpan { return 1 }
            return 0
        }

        private func syncLayers(_ map: MKMapView, region: MKCoordinateRegion) {
            let data = parent.data
            var wanted: [String: () -> LayerOverlay] = [:]
            for (layer, polys) in data.base where !polys.isEmpty {
                if layer == .blocks, region.span.latitudeDelta >= PlatLayer.blocks.maxSpan { continue }
                wanted["base:\(layer.rawValue)"] = { Self.overlay(polys, key: "base:\(layer.rawValue)", layer: layer, occupied: true) }
            }
            if region.span.latitudeDelta < PlatLayer.lots.maxSpan {
                for key in CellKey.keys(covering: region, layer: .lots) {
                    guard let polys = data.cells[key], !polys.isEmpty else { continue }
                    let k = "lots:\(key.x):\(key.y)"
                    wanted[k] = { Self.overlay(polys, key: k, layer: .lots, occupied: true) }
                }
            }
            if region.span.latitudeDelta < PlatLayer.graves.maxSpan {
                for key in CellKey.keys(covering: region, layer: .graves) {
                    guard let polys = data.cells[key], !polys.isEmpty else { continue }
                    let occ = polys.filter(\.occupied), empty = polys.filter { !$0.occupied }
                    if !occ.isEmpty {
                        let k = "graves:\(key.x):\(key.y):o"
                        wanted[k] = { Self.overlay(occ, key: k, layer: .graves, occupied: true) }
                    }
                    if !empty.isEmpty {
                        let k = "graves:\(key.x):\(key.y):e"
                        wanted[k] = { Self.overlay(empty, key: k, layer: .graves, occupied: false) }
                    }
                }
            }
            for (k, o) in overlays where wanted[k] == nil {
                map.removeOverlay(o)
                overlays[k] = nil
            }
            for (k, make) in wanted where overlays[k] == nil {
                let o = make()
                overlays[k] = o
                map.addOverlay(o, level: .aboveRoads)
            }
        }

        private static func overlay(_ polys: [MapPoly], key: String, layer: PlatLayer, occupied: Bool) -> LayerOverlay {
            let shapes = polys.map { MKPolygon(coordinates: $0.ring, count: $0.ring.count) }
            let o = LayerOverlay(shapes)
            o.key = key; o.layer = layer; o.occupied = occupied
            return o
        }

        private func syncLabels(_ map: MKMapView, region: MKCoordinateRegion) {
            let data = parent.data
            var wanted: [String: LabelAnnotation] = [:]
            let span = region.span.latitudeDelta
            if span < 0.03, let plats = data.base[.plats] {
                // A plat is often several polygons (roads cut it); letter only the biggest piece.
                var biggest: [String: MapPoly] = [:]
                for p in plats {
                    guard let t = p.label, !t.isEmpty else { continue }
                    if let b = biggest[t], Self.area(b.bbox) >= Self.area(p.bbox) { continue }
                    biggest[t] = p
                }
                for (t, p) in biggest {
                    let k = "plat:\(p.id)"
                    wanted[k] = labels[k] ?? LabelAnnotation(coordinate: p.bbox.center, title: t, layer: .plats, key: k)
                }
            }
            if span < 0.008, let blocks = data.base[.blocks] {
                for p in blocks {
                    guard let t = p.label, !t.isEmpty, p.bbox.contains(region.center) || regionIntersects(region, p.bbox) else { continue }
                    let k = "block:\(p.id)"
                    wanted[k] = labels[k] ?? LabelAnnotation(coordinate: p.bbox.center, title: t, layer: .blocks, key: k)
                }
            }
            if span < 0.003 {
                for p in data.lots(in: region) {
                    guard let t = p.label, !t.isEmpty, t.uppercased() != "EMPTY" else { continue }
                    let k = "lot:\(p.id)"
                    wanted[k] = labels[k] ?? LabelAnnotation(coordinate: p.bbox.center, title: t, layer: .lots, key: k)
                }
            }
            for (k, a) in labels where wanted[k] == nil {
                map.removeAnnotation(a)
                labels[k] = nil
            }
            let new = wanted.filter { labels[$0.key] == nil }
            labels.merge(new) { $1 }
            map.addAnnotations(Array(new.values))
        }

        private static func area(_ b: BBox) -> Double { (b.maxLat - b.minLat) * (b.maxLon - b.minLon) }

        private func regionIntersects(_ r: MKCoordinateRegion, _ b: BBox) -> Bool {
            let minLat = r.center.latitude - r.span.latitudeDelta / 2, maxLat = r.center.latitude + r.span.latitudeDelta / 2
            let minLon = r.center.longitude - r.span.longitudeDelta / 2, maxLon = r.center.longitude + r.span.longitudeDelta / 2
            return b.maxLat >= minLat && b.minLat <= maxLat && b.maxLon >= minLon && b.minLon <= maxLon
        }

        private func syncSelection(_ map: MKMapView) {
            let id = parent.selected?.id
            guard id != selectionID else { return }
            selectionID = id
            if let s = selection { map.removeOverlay(s); selection = nil }
            if let ring = parent.selected?.ring, ring.count > 2 {
                let cs = ring.map(\.cl)
                let o = SelectionOverlay(coordinates: cs, count: cs.count)
                selection = o
                map.addOverlay(o, level: .aboveLabels)
            }
        }

        private func syncTarget(_ map: MKMapView) {
            let id = parent.target?.id
            guard id != targetID else { return }
            targetID = id
            if let t = targetOverlay { map.removeOverlay(t); targetOverlay = nil }
            if let ring = parent.target?.ring, ring.count > 2, parent.target?.id != parent.selected?.id {
                let cs = ring.map(\.cl)
                let o = TargetOverlay(coordinates: cs, count: cs.count)
                targetOverlay = o
                map.addOverlay(o, level: .aboveLabels)
            }
        }

        private func syncWalk(_ map: MKMapView) {
            if let w = walk { map.removeOverlay(w); walk = nil }
            guard let t = parent.target?.centroid?.cl, let u = parent.userCoordinate else { return }
            var cs = [u, t]
            let line = WalkLine(coordinates: &cs, count: 2)
            walk = line
            map.addOverlay(line, level: .aboveLabels)
        }

        // MARK: Delegate

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            applyFocusIfReady(mapView)
            parent.onRegionChange(mapView.region)
            sync(mapView)
        }

        func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
            applyFocusIfReady(mapView)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let sat = satellite
            if let o = overlay as? LayerOverlay {
                let r = MKMultiPolygonRenderer(multiPolygon: o)
                style(r, layer: o.layer, occupied: o.occupied, satellite: sat)
                return r
            }
            if let s = overlay as? SelectionOverlay {
                let r = MKPolygonRenderer(polygon: s)
                r.fillColor = UIColor(Brand.accent).withAlphaComponent(0.85)
                r.strokeColor = .white
                r.lineWidth = 2.5
                return r
            }
            if let t = overlay as? TargetOverlay {
                let r = MKPolygonRenderer(polygon: t)
                r.fillColor = UIColor(Brand.accent).withAlphaComponent(0.55)
                r.strokeColor = .white
                r.lineWidth = 2
                return r
            }
            if let w = overlay as? WalkLine {
                let r = MKPolylineRenderer(polyline: w)
                r.strokeColor = UIColor(Brand.accent)
                r.lineWidth = 4
                r.lineDashPattern = [2, 8]
                r.lineCap = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        private func style(_ r: MKMultiPolygonRenderer, layer: PlatLayer, occupied: Bool, satellite: Bool) {
            let ink = satellite ? UIColor.white : UIColor(Brand.ink)
            let accent = UIColor(Brand.accent)
            switch layer {
            case .boundary:
                r.fillColor = nil
                r.strokeColor = satellite ? UIColor.white.withAlphaComponent(0.9) : accent
                r.lineWidth = 2
            case .plats:
                r.fillColor = satellite ? UIColor.white.withAlphaComponent(0.04) : accent.withAlphaComponent(0.06)
                r.strokeColor = satellite ? UIColor.white.withAlphaComponent(0.7) : accent.withAlphaComponent(0.9)
                r.lineWidth = 1
            case .blocks:
                r.fillColor = nil
                r.strokeColor = ink.withAlphaComponent(0.55)
                r.lineWidth = 0.8
            case .lots:
                r.fillColor = nil
                r.strokeColor = ink.withAlphaComponent(0.4)
                r.lineWidth = 0.5
            case .graves:
                if occupied {
                    r.fillColor = satellite ? UIColor.white.withAlphaComponent(0.26) : UIColor(Brand.lichen).withAlphaComponent(0.45)
                    r.strokeColor = ink.withAlphaComponent(0.7)
                } else {
                    r.fillColor = nil
                    r.strokeColor = ink.withAlphaComponent(0.3)
                }
                r.lineWidth = 0.5
            case .structures:
                r.fillColor = UIColor(Brand.granite).withAlphaComponent(satellite ? 0.55 : 0.7)
                r.strokeColor = ink.withAlphaComponent(0.6)
                r.lineWidth = 0.8
            case .streets:
                r.fillColor = satellite ? UIColor.black.withAlphaComponent(0.18) : UIColor(Brand.granite).withAlphaComponent(0.22)
                r.strokeColor = nil
                r.lineWidth = 0
            case .walkways:
                r.fillColor = satellite ? UIColor.white.withAlphaComponent(0.25) : UIColor(Brand.paper)
                r.strokeColor = nil
                r.lineWidth = 0
            case .water:
                r.fillColor = UIColor(Brand.navy).withAlphaComponent(0.5)
                r.strokeColor = nil
                r.lineWidth = 0
            case .gates:
                r.fillColor = accent.withAlphaComponent(0.8)
                r.strokeColor = .white
                r.lineWidth = 1
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let a = annotation as? LabelAnnotation else { return nil }
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: LabelView.reuseID, for: a) as! LabelView
            v.configure(a, satellite: satellite)
            return v
        }

        // MARK: Tap

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let map else { return }
            let point = g.location(in: map)
            let c = map.convert(point, toCoordinateFrom: map)
            if map.region.span.latitudeDelta < PlatLayer.graves.maxSpan, let hit = parent.data.grave(at: c) {
                parent.onTap(hit)
            } else {
                parent.onTap(nil)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// Plat letters, block and lot numbers. Sections read like Apple Maps' own
/// area labels: SF Pro, tracked capitals; blocks a quieter semibold.
final class LabelView: MKAnnotationView {
    static let reuseID = "label"
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        isEnabled = false
        canShowCallout = false
        displayPriority = .required
        label.textAlignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ a: LabelAnnotation, satellite: Bool) {
        let title = a.title ?? ""
        switch a.layer {
        case .plats:
            label.attributedText = NSAttributedString(string: title.uppercased(), attributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .bold),
                .kern: 1.1,
                .foregroundColor: satellite ? UIColor.white : UIColor(Brand.accent),
            ])
            label.layer.shadowOpacity = satellite ? 0.9 : 0
            displayPriority = .required
        case .blocks:
            label.attributedText = NSAttributedString(string: title, attributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .kern: 0.3,
                .foregroundColor: satellite ? UIColor.white.withAlphaComponent(0.95) : UIColor(Brand.ink),
            ])
            label.layer.shadowOpacity = satellite ? 0.9 : 0
            displayPriority = .defaultHigh
        default:
            label.attributedText = nil
            label.text = title
            label.font = .monospacedDigitSystemFont(ofSize: 9, weight: .medium)
            label.textColor = satellite ? UIColor.white.withAlphaComponent(0.85) : UIColor(Brand.sepia)
            label.layer.shadowOpacity = satellite ? 0.8 : 0
            displayPriority = .defaultLow
        }
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowRadius = 2
        label.layer.shadowOffset = .zero
        label.sizeToFit()
        bounds = CGRect(origin: .zero, size: CGSize(width: label.bounds.width + 6, height: label.bounds.height + 2))
        label.center = CGPoint(x: bounds.midX, y: bounds.midY)
        centerOffset = .zero
    }
}

extension UIFont {
    /// EB Garamond is a variable font; dial the weight through its wght axis.
    func withWeight(_ w: Int) -> UIFont {
        let wght = 0x77676874
        let variation = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let d = fontDescriptor.addingAttributes([variation: [wght: w]])
        return UIFont(descriptor: d, size: pointSize)
    }
}
