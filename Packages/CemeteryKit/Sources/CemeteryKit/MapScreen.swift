//
//  MapScreen.swift
//  City Cemetery
//
//  The plat map: the whole cemetery on satellite, plats lettered, lots and
//  graves drawn in as you zoom, any grave tappable. With a target set, a
//  dashed line runs from the blue dot to the grave and the card counts the
//  feet down.
//

import SwiftUI
import MapKit

struct MapScreen: View {
    @Environment(Router.self) private var router
    @Environment(PlatStore.self) private var plats
    @Environment(LocationStore.self) private var location
    @Environment(SavedStore.self) private var saved

    @State private var satellite = true
    @State private var selected: GraveRecord?
    @State private var selectedPlat: String?
    @State private var focus: MapFocus?
    @State private var region: MKCoordinateRegion?
    @State private var showCemeteries = false

    private var cemetery: Cemetery { Cemeteries.byID[router.mapCemeteryID] ?? Cemeteries.all[0] }

    var body: some View {
        ZStack {
            if let data = plats.data(for: cemetery) {
                PlatMapView(
                    data: data,
                    satellite: satellite,
                    selected: selected,
                    target: router.walkTarget,
                    userCoordinate: location.location?.coordinate,
                    focus: focus,
                    onTap: { poly in
                        if let poly, let r = poly.record ?? emptyRecord(poly, data: data) {
                            Haptics.select()
                            selected = r
                            selectedPlat = data.plat(at: poly.bbox.center)?.label
                        } else if selected != nil {
                            selected = nil
                        }
                    },
                    onRegionChange: { r in
                        region = r
                        data.ensure(region: r)
                    })
                .ignoresSafeArea(edges: .bottom)
                .task(id: cemetery.id) {
                    data.loadBase()
                    if router.walkTarget == nil { fit(data) }
                }
                .onChange(of: data.baseLoaded) {
                    // The boundary is what "fit" needs; frame it once it arrives.
                    if data.baseLoaded, router.walkTarget == nil { fit(data) }
                }
                .overlay(alignment: .topLeading) {
                    if data.isLoading || (region?.span.latitudeDelta ?? 1) >= PlatLayer.lots.maxSpan {
                        zoomHint(data)
                    }
                }
            }
        }
        .navigationTitle(cemetery.shortName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Cemetery", selection: Bindable(router).mapCemeteryID) {
                        ForEach(Cemeteries.mapped) { c in Text(c.name).tag(c.id) }
                    }
                } label: {
                    Label(cemetery.shortName, systemImage: "chevron.down")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.select()
                    satellite.toggle()
                } label: {
                    Image(systemName: satellite ? "map" : "globe.americas.fill")
                }
                .accessibilityLabel(satellite ? "Standard map" : "Satellite")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    if let data = plats.data(for: cemetery) { fit(data) }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel("Fit the cemetery")
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let target = router.walkTarget, target.cemeteryID == cemetery.id {
                    WalkCard(target: target, selectedID: selected?.id) {
                        router.walkTarget = nil
                    } recenter: {
                        if let c = target.centroid?.cl { focus = MapFocus(center: c, meters: 90, animated: true) }
                    }
                }
                if let selected {
                    GraveCard(record: selected, plat: selectedPlat) {
                        self.selected = nil
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .animation(.spring(duration: 0.3), value: selected?.id)
            .animation(.spring(duration: 0.3), value: router.walkTarget?.id)
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 10) {
                GlassCircleButton(systemName: "location", size: 34) {
                    location.request()
                    if let l = location.location?.coordinate {
                        focus = MapFocus(center: l, meters: 160, animated: true)
                    }
                }
            }
            .padding(.trailing, 12)
            .padding(.bottom, (selected != nil || router.walkTarget != nil) ? 0 : 12)
            .opacity((selected != nil || router.walkTarget != nil) ? 0 : 1)
        }
        .onAppear { location.start() }
        .onDisappear { location.stop() }
        .task(id: router.walkTarget?.id) {
            // Runs on appear too, so a target set from another tab is honored.
            guard let t = router.walkTarget else { return }
            if t.cemeteryID != router.mapCemeteryID { router.mapCemeteryID = t.cemeteryID }
            selected = nil
            if let c = t.centroid?.cl {
                // Give a cemetery switch a beat before moving the camera.
                try? await Task.sleep(for: .milliseconds(120))
                focus = MapFocus(center: c, meters: 90, animated: true)
            }
        }
        .onChange(of: router.mapFocus?.id) {
            guard let f = router.mapFocus else { return }
            router.mapFocus = nil
            focus = f
        }
    }

    private func fit(_ data: PlatData) {
        let target = data.bounds.map { b in
            (CLLocationCoordinate2D(latitude: (b.minLat + b.maxLat) / 2, longitude: (b.minLon + b.maxLon) / 2),
             max(LocationStore.distance(from: CLLocationCoordinate2D(latitude: b.minLat, longitude: b.minLon), to: CLLocationCoordinate2D(latitude: b.maxLat, longitude: b.maxLon)) * 0.72, 400))
        } ?? (cemetery.coordinate.cl, 1100)
        focus = MapFocus(center: target.0, meters: target.1, animated: true)
    }

    /// An empty grave has no record; make a stub so the card can still name the plot.
    private func emptyRecord(_ poly: MapPoly, data: PlatData) -> GraveRecord? {
        GraveRecord(id: "\(cemetery.id):\(poly.id)", cemeteryID: cemetery.id, name: "", objectID: poly.id, plot: nil, status: "AVAILABLE",
                    birth: nil, death: nil, burial: nil, birthPlace: nil, deathPlace: nil, age: nil, veteran: false, sections: [],
                    ring: poly.ring.map(Coordinate.init), centroid: Coordinate(poly.bbox.center), source: "")
    }

    @ViewBuilder
    private func zoomHint(_ data: PlatData) -> some View {
        HStack(spacing: 6) {
            if data.isLoading {
                ProgressView().controlSize(.small)
                Text(data.baseLoaded ? "Loading graves" : "Loading the plat")
            } else {
                Image(systemName: "plus.magnifyingglass")
                Text("Zoom in for graves")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassCapsule()
        .padding(12)
        .animation(.easeOut(duration: 0.2), value: data.isLoading)
    }
}

/// The tapped grave: name, dates, plot, and the way in.
struct GraveCard: View {
    let record: GraveRecord
    let plat: String?
    let dismiss: () -> Void
    @Environment(Router.self) private var router
    @Environment(SavedStore.self) private var saved
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.name.isEmpty ? "Empty grave" : record.displayName)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if !record.lifespan.isEmpty { Text(record.lifespan) }
                        if record.veteran { Chip(label: "Veteran", color: Brand.navy, systemImage: "shield") }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button { Haptics.tap(); dismiss() } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
            }
            if !record.plotFields.isEmpty {
                HStack(spacing: 6) {
                    ForEach(record.plotFields) { f in
                        Chip(label: "\(f.label) \(f.value)", color: Brand.granite)
                    }
                }
            }
            if !record.name.isEmpty {
                HStack(spacing: 10) {
                    NavigationLink(value: record) {
                        Label("Record", systemImage: "doc.text")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(colorScheme == .dark ? Color.white : Brand.accent)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    GlassCircleButton(systemName: "car", size: 30) {
                        guard let c = record.centroid?.cl else { return }
                        let item = MKMapItem(location: CLLocation(latitude: c.latitude, longitude: c.longitude), address: nil)
                        item.name = record.displayName
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    }
                    Button {
                        Haptics.tap()
                        router.walkTarget = record
                    } label: {
                        Label("Walk here", systemImage: "figure.walk")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Brand.accentRail)
                    .buttonBorderShape(.capsule)
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Distance and bearing to the target grave, live.
struct WalkCard: View {
    let target: GraveRecord
    let selectedID: String?
    let stop: () -> Void
    let recenter: () -> Void
    @Environment(LocationStore.self) private var location

    private var distance: CLLocationDistance? {
        guard let u = location.location?.coordinate, let t = target.centroid?.cl else { return nil }
        return LocationStore.distance(from: u, to: t)
    }

    private var arrow: Angle? {
        guard let u = location.location?.coordinate, let t = target.centroid?.cl else { return nil }
        let bearing = LocationStore.bearing(from: u, to: t)
        return .degrees(bearing - (location.heading ?? 0))
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Brand.accent).frame(width: 44, height: 44)
                if let arrow {
                    Image(systemName: "location.north.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .rotationEffect(arrow)
                        .animation(.easeOut(duration: 0.25), value: arrow.degrees)
                } else {
                    Image(systemName: "figure.walk").font(.title3.weight(.semibold)).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(target.displayName)
                    .font(.system(.headline, design: .serif))
                    .lineLimit(1)
                if let distance {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(LocationStore.distanceText(distance))
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(distance < 8 ? "you're here" : "to the grave")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if location.isDenied {
                    Text("Location is off for this app in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Finding you…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            GlassCircleButton(systemName: "scope", size: 30, action: recenter)
            Button { Haptics.tap(); stop() } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 18)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
