//
//  GraveScreen.swift
//  City Cemetery
//
//  The sexton's record, printed in full: who, when, where in the ground,
//  what the marker says, who shares the lot. Mapped graves get the outline
//  on satellite and a Walk button; the rest get the plot text and the way
//  to the gate.
//

import SwiftUI
import MapKit

struct GraveScreen: View {
    let record: GraveRecord

    @Environment(Router.self) private var router
    @Environment(SavedStore.self) private var saved
    @Environment(PlatStore.self) private var plats
    @Environment(\.openURL) private var openURL
    @State private var full: GraveRecord?
    @State private var lotMates: [GraveRecord] = []
    @State private var loadFailed = false
    @State private var toast: Toast?

    private var current: GraveRecord { full ?? record }
    private var cemetery: Cemetery { record.cemetery }

    var body: some View {
        List {
            header
            if current.isMapped { miniMap }
            actions
            ForEach(current.sections) { section in
                Section {
                    ForEach(section.fields) { f in
                        LabeledContent(f.label) {
                            Text(f.value)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    SectionLabel(text: section.title)
                }
            }
            if !current.sections.isEmpty || !current.plotFields.isEmpty {
                plotSection
            }
            if !lotMates.isEmpty {
                Section {
                    ForEach(lotMates) { mate in
                        NavigationLink(value: mate) { GraveRow(record: mate, showCemetery: false) }
                    }
                } header: {
                    SectionLabel(text: "Same lot")
                } footer: {
                    Text("Everyone the sexton has recorded in lot \(current.lotPrefix?.split(separator: "_").last.map(String.init) ?? "").")
                }
            }
            Section {
                Text(current.source)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link(destination: cemetery.findAGraveSearch(NameQuery(current.name))) {
                    Label("Look up on Find a Grave", systemImage: "arrow.up.right")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(current.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    saved.toggle(current)
                    toast = Toast(text: saved.isSaved(current.id) ? "Saved" : "Removed", symbol: saved.isSaved(current.id) ? "bookmark.fill" : "bookmark")
                } label: {
                    Image(systemName: saved.isSaved(current.id) ? "bookmark.fill" : "bookmark")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: current.shareText, subject: Text(current.displayName)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .toast($toast)
        .task(id: record.id) { await load() }
    }

    // MARK: Pieces

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(current.displayName)
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                // Died and age on one line, born on its own line beneath.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 28) {
                        if let d = current.death, !d.isEmpty {
                            VStack(alignment: .leading, spacing: 1) {
                                SectionLabel(text: "Died")
                                Text(d.text).font(.system(.body, design: .serif))
                            }
                        }
                        if let age = current.age ?? current.computedAge.map(String.init), !age.isEmpty {
                            VStack(alignment: .leading, spacing: 1) {
                                SectionLabel(text: "Age")
                                Text(age).font(.system(.body, design: .serif))
                            }
                        }
                    }
                    if let b = current.birth, !b.isEmpty {
                        VStack(alignment: .leading, spacing: 1) {
                            SectionLabel(text: "Born")
                            Text(b.text).font(.system(.body, design: .serif))
                        }
                    }
                }
                HStack(spacing: 6) {
                    Chip(label: cemetery.shortName, color: Brand.accent, systemImage: "building.columns")
                    if current.veteran { Chip(label: "Veteran", color: Brand.navy, systemImage: "shield") }
                }
                if current.name != current.displayName {
                    Text("Recorded as \(current.name)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .listRowSeparator(.hidden)
        }
    }

    private var miniMap: some View {
        Section {
            RecordMap(record: current)
                .frame(height: 220)
                .listRowInsets(EdgeInsets())
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var actions: some View {
        Section {
            VStack(spacing: 10) {
                if current.isMapped {
                    Button {
                        Haptics.tap()
                        router.mapCemeteryID = current.cemeteryID
                        router.walkTarget = current
                        router.mapPresented = true
                    } label: {
                        Label("Walk to this grave", systemImage: "figure.walk")
                    }
                    .buttonStyle(PrimaryButton())
                }
                Button {
                    Haptics.tap()
                    directions()
                } label: {
                    Label("Directions", systemImage: "car")
                }
                .buttonStyle(SecondaryButton())
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var plotSection: some View {
        Section {
            if current.plotFields.isEmpty {
                Text("The register doesn't give a plot. The office at \(cemetery.shortName) can place the grave.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(current.plotFields) { f in
                    LabeledContent(f.label, value: f.value)
                }
            }
            if let phone = cemetery.phone, let url = URL(string: "tel:" + phone.filter(\.isNumber)) {
                Link(destination: url) { Label("Call the office · \(phone)", systemImage: "phone") }
            }
        } header: {
            SectionLabel(text: "Where")
        }
    }

    // MARK: Work

    private func load() async {
        if record.sections.isEmpty, case .arcgis(let config) = cemetery.source, let oid = record.objectID {
            if let r = try? await ArcGIS.grave(config, cemeteryID: cemetery.id, objectID: oid) {
                full = r
                saved.refresh(r)
            } else {
                loadFailed = true
            }
        }
        if case .arcgis(let config) = cemetery.source, let prefix = current.lotPrefix {
            let mates = (try? await ArcGIS.lotMates(config, cemeteryID: cemetery.id, lotPrefix: prefix)) ?? []
            lotMates = mates.filter { $0.id != current.id }
        }
    }

    /// Apple Maps has the cemetery roads, so the grave itself is the destination:
    /// it drives you to the nearest road and pins the plot.
    private func directions() {
        let dest = current.centroid?.cl ?? cemetery.coordinate.cl
        let item = MKMapItem(location: CLLocation(latitude: dest.latitude, longitude: dest.longitude), address: nil)
        item.name = current.isMapped ? "\(current.displayName) · \(cemetery.shortName)" : cemetery.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

/// The grave outline on satellite, framed tight.
struct RecordMap: View {
    let record: GraveRecord

    var body: some View {
        let cs = (record.ring ?? []).map(\.cl)
        let center = record.centroid?.cl ?? record.cemetery.coordinate.cl
        Map(initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: 22, longitudinalMeters: 22)), interactionModes: []) {
            if cs.count > 2 {
                MapPolygon(coordinates: cs)
                    .foregroundStyle(Brand.accent.opacity(0.7))
                    .stroke(.white, lineWidth: 2)
            }
        }
        .mapStyle(.hybrid(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
    }
}

/// A result or list row: name, dates, plot.
struct GraveRow: View {
    let record: GraveRecord
    var showCemetery = true

    /// "1872 – 1936 · R 90 6 · Mount Olivet", skipping whatever the register left blank.
    private var subtitle: String {
        var parts: [String] = []
        if !record.lifespan.isEmpty { parts.append(record.lifespan) }
        let plot = record.plotFields
        if let last = plot.last {
            parts.append(plot.count > 1 ? plot.map(\.value).joined(separator: " ") : "\(last.label) \(last.value)")
        }
        if showCemetery { parts.append(record.cemetery.shortName) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.isMapped ? "mappin.and.ellipse" : "doc.text")
                .font(.body.weight(.light))
                .foregroundStyle(record.isMapped ? Brand.accent : Brand.granite)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayName)
                    .font(.system(.body, design: .serif, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if record.veteran {
                Image(systemName: "shield").font(.caption).foregroundStyle(Brand.navy)
            }
        }
        .padding(.vertical, 2)
    }
}
