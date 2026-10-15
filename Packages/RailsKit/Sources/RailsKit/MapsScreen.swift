//
//  MapsScreen.swift
//  Utah Rails
//
//  The site's railroad maps, drawn in Apple Maps: every line, pin and area
//  from Don's Google My Maps, with his layers, colors and notes. Tap a pin
//  or a line for its note; hand any spot to Apple Maps for directions.
//

import SwiftUI
import MapKit

struct MapsScreen: View {
    @Environment(MapsStore.self) private var maps
    @State private var filter = ""

    private var sections: [(String, [RailMap])] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return maps.sections }
        return maps.sections.compactMap { name, list in
            let hits = list.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.blurb.localizedCaseInsensitiveContains(q) }
            return hits.isEmpty ? nil : (name, hits)
        }
    }

    var body: some View {
        List {
            if filter.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        SerifNumeral(text: maps.uniqueCount.formatted(), unit: "maps", size: 34)
                        Text("Routes, branches, spurs, mines and smelters that Don Strack traced onto Google Maps, redrawn here in Apple Maps with his layers and notes.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .listRowSeparator(.hidden)
                }
            }
            ForEach(sections, id: \.0) { name, list in
                Section {
                    ForEach(list) { map in
                        NavigationLink(value: map) { RailMapRow(map: map) }
                    }
                } header: {
                    SectionLabel(text: name.replacingOccurrences(of: "Google Maps of ", with: "").replacingOccurrences(of: "Google ", with: ""))
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Maps")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Filter maps")
        .overlay {
            if sections.isEmpty { ContentUnavailableView.search(text: filter) }
        }
    }
}

struct RailMapRow: View {
    let map: RailMap
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "map")
                .font(.body.weight(.light))
                .foregroundStyle(Brand.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(map.title)
                    .font(.system(.body, design: .serif, weight: .semibold))
                if !map.cleanBlurb.isEmpty {
                    Text(map.cleanBlurb)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - One map

struct RailMapScreen: View {
    let map: RailMap

    @Environment(MapsStore.self) private var maps
    @Environment(CatalogStore.self) private var catalog
    @State private var document: MapDocument?
    @State private var failed = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var hiddenLayers: Set<String> = []
    @State private var selected: MapFeature?
    @State private var showList = false
    @State private var style: MapStyleChoice = .standard

    enum MapStyleChoice: String, CaseIterable, Identifiable {
        case standard = "Standard", hybrid = "Satellite"
        var id: String { rawValue }
    }

    private var visible: [MapFeature] {
        document?.layers.filter { !hiddenLayers.contains($0.name) }.flatMap(\.features) ?? []
    }

    var body: some View {
        ZStack {
            if let document {
                MapReader { proxy in
                    Map(position: $camera, selection: $selected) {
                        ForEach(visible) { f in
                            switch f.geometry {
                            case .line(let cs):
                                MapPolyline(coordinates: cs)
                                    .stroke(f.color, style: StrokeStyle(lineWidth: f.lineWidth, lineCap: .round, lineJoin: .round))
                            case .polygon(let cs):
                                MapPolygon(coordinates: cs)
                                    .foregroundStyle(f.color.opacity(0.22))
                                    .stroke(f.color, lineWidth: 1.5)
                            case .point(let c):
                                Annotation(f.name, coordinate: c, anchor: .center) {
                                    Circle()
                                        .fill(f.color)
                                        .frame(width: selected == f ? 16 : 11, height: selected == f ? 16 : 11)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                                        .shadow(radius: 1.5)
                                }
                                .tag(f)
                                .annotationTitles(.hidden)
                            }
                        }
                    }
                    .mapStyle(style == .hybrid ? .hybrid(elevation: .flat) : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                        MapUserLocationButton()
                    }
                    .onTapGesture { point in
                        // Nearest line or area within a fingertip.
                        guard let tapped = proxy.convert(point, from: .local) else { return }
                        if let hit = nearestLine(to: point, tapped: tapped, proxy: proxy) {
                            Haptics.select()
                            selected = hit
                        } else if selected != nil {
                            selected = nil
                        }
                    }
                }
                .ignoresSafeArea(edges: .bottom)
            } else if failed {
                ContentUnavailableView {
                    Label("Couldn't load the map", systemImage: "map")
                } description: {
                    Text("Neither the live copy nor the bundled one could be read.")
                } actions: {
                    Link("Open in Google Maps", destination: map.googleURL)
                }
            } else {
                ProgressView("Drawing the map…")
            }
        }
        .navigationTitle(map.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Map", selection: $style) {
                        ForEach(MapStyleChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if let document, document.layers.count > 1 {
                        Section("Layers") {
                            ForEach(document.layers) { layer in
                                Button {
                                    Haptics.select()
                                    if hiddenLayers.contains(layer.name) { hiddenLayers.remove(layer.name) } else { hiddenLayers.insert(layer.name) }
                                } label: {
                                    Label(layer.name, systemImage: hiddenLayers.contains(layer.name) ? "circle" : "checkmark.circle.fill")
                                }
                            }
                        }
                    }
                    Section {
                        Button { Haptics.tap(); showList = true } label: { Label("All places", systemImage: "list.bullet") }
                        Button { Haptics.tap(); fit() } label: { Label("Fit to map", systemImage: "arrow.up.left.and.arrow.down.right") }
                        if let related = map.related {
                            NavigationLink(value: PageRef(path: related, title: catalog.title(for: related))) {
                                Label("Read the page", systemImage: "doc.text")
                            }
                        }
                        Link(destination: map.googleURL) { Label("Open in Google Maps", systemImage: "arrow.up.right") }
                    }
                } label: {
                    Image(systemName: "square.3.layers.3d")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: map.googleURL, subject: Text(map.title), message: Text(map.title)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let selected {
                FeatureCard(feature: selected, mapTitle: map.title) { self.selected = nil }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let document, !map.cleanBlurb.isEmpty || !document.description.isEmpty {
                Text(map.cleanBlurb.isEmpty ? document.description : map.cleanBlurb)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(cornerRadius: 14)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .animation(.spring(duration: 0.3), value: selected)
        .sheet(isPresented: $showList) {
            FeatureList(document: document, selected: $selected) { f in
                selected = f
                camera = .region(MKCoordinateRegion(center: f.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))
            }
        }
        .task {
            if document == nil {
                document = await maps.document(for: map)
                if document == nil { failed = true } else { fit() }
            }
        }
    }

    private func fit() {
        guard let b = document?.bounds else { return }
        let span = MKCoordinateSpan(latitudeDelta: max((b.max.latitude - b.min.latitude) * 1.25, 0.01),
                                    longitudeDelta: max((b.max.longitude - b.min.longitude) * 1.25, 0.01))
        let center = CLLocationCoordinate2D(latitude: (b.min.latitude + b.max.latitude) / 2, longitude: (b.min.longitude + b.max.longitude) / 2)
        withAnimation { camera = .region(MKCoordinateRegion(center: center, span: span)) }
    }

    /// Screen-space distance from the tap to each visible line or area edge.
    private func nearestLine(to point: CGPoint, tapped: CLLocationCoordinate2D, proxy: MapProxy) -> MapFeature? {
        var best: (MapFeature, CGFloat)? = nil
        for f in visible {
            let cs: [CLLocationCoordinate2D]
            switch f.geometry {
            case .line(let l): cs = l
            case .polygon(let p): cs = p + [p[0]]
            case .point: continue
            }
            // Coarse reject by coordinate box before projecting.
            var pts: [CGPoint] = []
            pts.reserveCapacity(cs.count)
            for c in cs { if let p = proxy.convert(c, to: .local) { pts.append(p) } }
            guard pts.count > 1 else { continue }
            for i in 1..<pts.count {
                let d = Self.distance(point, pts[i - 1], pts[i])
                if d < 22, best == nil || d < best!.1 { best = (f, d) }
            }
        }
        return best?.0
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

/// Name, note and hand-offs for the selected pin or line.
struct FeatureCard: View {
    let feature: MapFeature
    let mapTitle: String
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                HStack(spacing: 8) {
                    Circle().fill(feature.color).frame(width: 10, height: 10)
                    Text(feature.name)
                        .font(.system(.headline, design: .serif))
                }
                Spacer()
                Button { Haptics.tap(); dismiss() } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
            }
            if !feature.description.isEmpty {
                Text(feature.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
            HStack(spacing: 10) {
                if !feature.layer.isEmpty {
                    Chip(label: feature.layer, color: Brand.sepia, systemImage: "square.3.layers.3d")
                }
                Spacer()
                Button {
                    Haptics.tap()
                    let item = MKMapItem(location: CLLocation(latitude: feature.coordinate.latitude, longitude: feature.coordinate.longitude), address: nil)
                    item.name = feature.name
                    item.openInMaps()
                } label: {
                    Label("Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glassProminent)
                .tint(Brand.accentRail)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
    }
}

/// Every pin and line on the map, by layer.
struct FeatureList: View {
    let document: MapDocument?
    @Binding var selected: MapFeature?
    let onPick: (MapFeature) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(document?.layers ?? []) { layer in
                    let items = layer.features.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.description.localizedCaseInsensitiveContains(filter) }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { f in
                                Button {
                                    Haptics.tap()
                                    onPick(f)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: f.kindSymbol).foregroundStyle(f.color).frame(width: 22)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(f.name).foregroundStyle(.primary)
                                            if !f.description.isEmpty {
                                                Text(f.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                            }
                                        }
                                    }
                                }
                            }
                        } header: {
                            SectionLabel(text: layer.name)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $filter, prompt: "Filter places")
            .navigationTitle("Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
