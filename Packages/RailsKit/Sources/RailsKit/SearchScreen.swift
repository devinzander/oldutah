//
//  SearchScreen.swift
//  Old Utah — Railroads
//
//  The search tab: system search field in the tab bar, scopes for pages
//  and documents, results from the site map's titles on-device. The site
//  has no search of its own beyond Google, so a full-text search hands off
//  to a Google site: query.
//

import SwiftUI

struct SearchResults: View {
    let query: String
    let results: [PageRef]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("“\(query)”")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .lineLimit(2)
                    SerifNumeral(text: results.count.formatted(), unit: results.count == 1 ? "title" : "titles", size: 28)
                }
                .listRowSeparator(.hidden)
            }
            ForEach(results) { page in
                NavigationLink(value: page) { PageRow(page: page) }
                    .contextMenu { PageMenu(page: page) }
            }
            Section {
                Link(destination: Site.googleSearch(query)) {
                    Label("Search the full text on Google", systemImage: "magnifyingglass")
                }
                Text("Titles are matched on this device. Road numbers, builder numbers and anything inside a page need the site's Google search.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .overlay {
            if results.isEmpty {
                ContentUnavailableView {
                    Label("No titles match", systemImage: "magnifyingglass")
                } description: {
                    Text("Try fewer words, or search the full text on Google.")
                } actions: {
                    Link(destination: Site.googleSearch(query)) {
                        Label("Search on Google", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }
}

/// What the tab shows before a search.
struct SearchLanding: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(SavedStore.self) private var saved
    let onPick: (String) -> Void

    private let starters = ["Ogden", "Bingham", "Park City", "roster", "caboose", "streetcar", "Promontory", "Tintic", "Big Boy", "coal"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Find a page.")
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    Text("Every one of the site's \(catalog.pageCount.formatted()) page and document titles, matched as you type. For road numbers and text inside a page, hand off to Google.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Try")
                    FlowLayout(spacing: 8) {
                        ForEach(starters, id: \.self) { term in
                            Button {
                                Haptics.tap()
                                onPick(term)
                            } label: {
                                Text(term)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                        }
                    }
                }

                if !saved.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionLabel(text: "Recent searches")
                            Spacer()
                            Button("Clear") { Haptics.tap(); saved.clearSearches() }
                                .font(.caption.weight(.semibold))
                        }
                        ForEach(saved.recentSearches, id: \.self) { term in
                            Button {
                                Haptics.tap()
                                onPick(term)
                            } label: {
                                HStack {
                                    Image(systemName: "clock").foregroundStyle(.secondary)
                                    Text(term).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
    }
}
