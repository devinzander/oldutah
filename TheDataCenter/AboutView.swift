//
//  AboutView.swift
//  Old Utah
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalog

    private static let legalBase = "https://devinzander.github.io/the-prequel/oldutah/"

    private var feedbackURL: URL {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        let body = "\n\n—\nOld Utah \(version) (\(build)) · \(device) · iOS \(UIDevice.current.systemVersion)"
        var c = URLComponents(string: "mailto:devin@zanderdevelopment.com")!
        c.queryItems = [URLQueryItem(name: "subject", value: "Old Utah Feedback"),
                        URLQueryItem(name: "body", value: body)]
        return c.url ?? URL(string: "mailto:devin@zanderdevelopment.com")!
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Old Utah reads three public records of the state's past: the digital collections of the J. Willard Marriott Library, Don Strack's history of Utah's railroads, and the burial registers of Salt Lake City's cemeteries. Everything loads from its source.")
                        Text("The app has no account, advertising, purchases or analytics. Saved items and recent searches are stored on this device only.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                }

                Section("Library") {
                    LabeledContent("Institutions", value: catalog.institutions.count.formatted())
                    LabeledContent("Collections", value: catalog.collectionCount.formatted())
                    Link(destination: UDL.base) {
                        Label("collections.lib.utah.edu", systemImage: "safari")
                    }
                    Link(destination: UDL.askURL) {
                        Label("Ask the library", systemImage: "questionmark.bubble")
                    }
                    Link(destination: UDL.harmfulLanguageURL) {
                        Label("Harmful language statement", systemImage: "text.book.closed")
                    }
                    Text("Rights vary by item; each record lists its rights statement. Old Utah is an independent app and is not affiliated with the University of Utah.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Railroads") {
                    Link(destination: URL(string: "https://utahrails.net/")!) {
                        Label("utahrails.net", systemImage: "safari")
                    }
                    Link(destination: URL(string: "https://donstrack.smugmug.com/")!) {
                        Label("donstrack.smugmug.com", systemImage: "photo.on.rectangle")
                    }
                    Link(destination: URL(string: "https://utahrails.net/copyright-info.html")!) {
                        Label("Copyright at UtahRails.net", systemImage: "c.circle")
                    }
                    Text("The railroad pages, documents and photographs are Don Strack's, presented here with his permission. UtahRails.net is a private, non-commercial site he has kept since 2002.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Cemeteries") {
                    Link(destination: URL(string: "https://www.slc.gov/cemetery/")!) {
                        Label("Salt Lake City Cemetery", systemImage: "building.columns")
                    }
                    Link(destination: URL(string: "https://www.mountolivetcemetery.org/")!) {
                        Label("Mount Olivet Cemetery", systemImage: "building.columns")
                    }
                    Link(destination: URL(string: "https://ushpo.utah.gov/cemetery/")!) {
                        Label("Utah Cemeteries & Burials Database", systemImage: "doc.text")
                    }
                    Link(destination: URL(string: "https://gravelocator.cem.va.gov/")!) {
                        Label("VA Nationwide Gravesite Locator", systemImage: "shield")
                    }
                    Text("Records are read live from each source and can lag the office's ledger by days. Corrections go to the cemetery. Old Utah is not affiliated with any cemetery, Salt Lake City, the State of Utah or the VA.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Feedback") {
                    Link("Send Feedback", destination: feedbackURL)
                }

                Section("Legal") {
                    Link("Privacy Policy", destination: URL(string: Self.legalBase + "privacy.html")!)
                    Link("Terms of Use", destination: URL(string: Self.legalBase + "terms.html")!)
                    Link("Support", destination: URL(string: Self.legalBase + "support.html")!)
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    if !catalog.fetched.isEmpty {
                        LabeledContent("Catalog", value: String(catalog.fetched.prefix(10)))
                    }
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Haptics.tap(); dismiss() }
                }
            }
        }
    }
}
