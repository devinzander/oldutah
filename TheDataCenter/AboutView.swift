//
//  AboutView.swift
//  The Data Center
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogStore.self) private var catalog

    private static let legalBase = "https://devinzander.github.io/the-prequel/thedatacenter/"

    private var feedbackURL: URL {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        let body = "\n\n—\nThe Data Center \(version) (\(build)) · \(device) · iOS \(UIDevice.current.systemVersion)"
        var c = URLComponents(string: "mailto:devin@zanderdevelopment.com")!
        c.queryItems = [URLQueryItem(name: "subject", value: "The Data Center Feedback"),
                        URLQueryItem(name: "body", value: body)]
        return c.url ?? URL(string: "mailto:devin@zanderdevelopment.com")!
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("The Data Center reads the Utah digital collections published by the J. Willard Marriott Library at the University of Utah. Images, documents and recordings load directly from the library's site.")
                        Text("The app has no account, advertising, purchases or analytics. Saved items and recent searches are stored on this device only.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                }

                Section("The archive") {
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
                    Text("Rights vary by item; each record lists its rights statement. The Data Center is an independent app and is not affiliated with the University of Utah.")
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
