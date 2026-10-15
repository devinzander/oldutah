//
//  CemeteriesScreen.swift
//  City Cemetery
//
//  Every burial ground inside the city limits, what is known about it, and
//  which register holds its names.
//

import SwiftUI
import MapKit

struct CemeteriesScreen: View {
    @Environment(Router.self) private var router

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        SerifNumeral(text: Cemeteries.all.count.formatted(), unit: "cemeteries", size: 34)
                        Text("Inside Salt Lake City proper, from Brigham Young's walled garden to the big lawn parks. Two are mapped grave by grave; five more keep registers the state publishes; the other seven have never published one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .listRowSeparator(.hidden)
                    Button {
                        Haptics.tap()
                        router.mapPresented = true
                    } label: {
                        Label("Open the plat map", systemImage: "map")
                    }
                    .buttonStyle(PrimaryButton())
                    .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(Cemeteries.mapped) { c in
                        NavigationLink(value: c) { CemeteryRow(cemetery: c) }
                    }
                } header: {
                    SectionLabel(text: "Mapped, grave by grave")
                }
                Section {
                    ForEach(Cemeteries.all.filter { $0.source.hasRecords && !$0.source.isMapped }) { c in
                        NavigationLink(value: c) { CemeteryRow(cemetery: c) }
                    }
                } header: {
                    SectionLabel(text: "Registers on record")
                }
                Section {
                    ForEach(Cemeteries.all.filter { !$0.source.hasRecords }) { c in
                        NavigationLink(value: c) { CemeteryRow(cemetery: c) }
                    }
                } header: {
                    SectionLabel(text: "Private books")
                } footer: {
                    Text("These grounds haven't published a register. The office places graves; Find a Grave often has the stone.")
                }
            }
            .listStyle(.plain)
            .navigationTitle("Cemeteries")
            .navigationBarTitleDisplayMode(.large)
            .cityCemeteryDestinations()
        }
    }
}

struct CemeteryRow: View {
    let cemetery: Cemetery

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: cemetery.source.isMapped ? "map" : cemetery.source.hasRecords ? "doc.text" : "building.columns")
                .font(.body.weight(.light))
                .foregroundStyle(cemetery.source.isMapped ? Brand.accent : Brand.granite)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(cemetery.name)
                    .font(.system(.body, design: .serif, weight: .semibold))
                HStack(spacing: 6) {
                    if let e = cemetery.established { Text("est. \(String(e))") }
                    if let b = cemetery.burials { Text("·"); Text("\(b) burials") }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct CemeteryScreen: View {
    let cemetery: Cemetery
    @Environment(Router.self) private var router
    @Environment(SearchStore.self) private var search

    var body: some View {
        List {
            Section {
                Map(initialPosition: .region(MKCoordinateRegion(center: cemetery.coordinate.cl, latitudinalMeters: 900, longitudinalMeters: 900)), interactionModes: []) {
                    Marker(cemetery.shortName, systemImage: "building.columns", coordinate: cemetery.coordinate.cl)
                        .tint(Brand.accent)
                }
                .mapStyle(.hybrid(elevation: .flat, pointsOfInterest: .excludingAll))
                .mapControlVisibility(.hidden)
                .frame(height: 200)
                .listRowInsets(EdgeInsets())
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(cemetery.blurb)
                        .font(.system(.body, design: .serif))
                    HStack(spacing: 6) {
                        switch cemetery.source {
                        case .arcgis: Chip(label: "Every grave mapped", color: Brand.accent, systemImage: "map")
                        case .state: Chip(label: "State register", color: Brand.granite, systemImage: "doc.text")
                        case .va: Chip(label: "VA register", color: Brand.navy, systemImage: "shield")
                        case .none: Chip(label: "Private records", color: Brand.rust, systemImage: "lock")
                        }
                    }
                }
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)
            }
            Section {
                VStack(spacing: 10) {
                    if cemetery.source.isMapped {
                        Button {
                            Haptics.tap()
                            router.mapCemeteryID = cemetery.id
                            router.mapPresented = true
                        } label: {
                            Label("Open the plat map", systemImage: "map")
                        }
                        .buttonStyle(PrimaryButton())
                    }
                    if cemetery.source.hasRecords {
                        Button {
                            Haptics.tap()
                            search.scope = cemetery.id
                            router.requestSearch()
                        } label: {
                            Label("Search this cemetery", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(cemetery.source.isMapped ? SecondaryButton() : SecondaryButton())
                    }
                    Button {
                        Haptics.tap()
                        let item = MKMapItem(location: CLLocation(latitude: cemetery.coordinate.lat, longitude: cemetery.coordinate.lon), address: nil)
                        item.name = cemetery.name
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    } label: {
                        Label("Directions", systemImage: "car")
                    }
                    .buttonStyle(SecondaryButton())
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            Section {
                LabeledContent("Address", value: cemetery.address)
                if let e = cemetery.established { LabeledContent("Established", value: String(e)) }
                if let a = cemetery.acres { LabeledContent("Acres", value: String(a)) }
                if let b = cemetery.burials { LabeledContent("Burials", value: "about \(b)") }
                LabeledContent("Run by", value: cemetery.owner)
                if let phone = cemetery.phone, let url = URL(string: "tel:" + phone.filter(\.isNumber)) {
                    Link(destination: url) { LabeledContent("Office", value: phone) }
                }
                if let site = cemetery.website {
                    Link(destination: site) { Label(site.host ?? "Website", systemImage: "safari") }
                }
            } header: {
                SectionLabel(text: "Facts")
            }
            if !cemetery.entrances.isEmpty {
                Section {
                    ForEach(cemetery.entrances, id: \.name) { gate in
                        Button {
                            Haptics.tap()
                            let item = MKMapItem(location: CLLocation(latitude: gate.coordinate.lat, longitude: gate.coordinate.lon), address: nil)
                            item.name = "\(cemetery.shortName) · \(gate.name)"
                            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                        } label: {
                            Label(gate.name, systemImage: "door.left.hand.open").foregroundStyle(.primary)
                        }
                    }
                } header: {
                    SectionLabel(text: "Gates")
                }
            }
            Section {
                Link(destination: cemetery.findAGraveURL) {
                    Label("This cemetery on Find a Grave", systemImage: "arrow.up.right")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(cemetery.shortName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
