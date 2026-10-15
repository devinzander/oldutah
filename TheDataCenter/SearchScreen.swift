//
//  SearchScreen.swift
//  Old Utah
//
//  The search tab: one search field in the tab bar, scoped to the library,
//  the railroad pages or the cemetery registers. Library results narrow
//  further by format, institution and year once they arrive.
//

import SwiftUI
import RailsKit
import CemeteryKit

struct SearchScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(SavedStore.self) private var saved
    @Environment(AppRouter.self) private var router
    @State private var text = ""
    @State private var model = ResultsModel(query: SearchQuery())
    /// The submitted text; empty shows the scope's landing page.
    @State private var submitted = ""

    private var prompt: String {
        switch router.searchScope {
        case .library: return "Search titles, subjects and full text"
        case .railroads: return "Search railroad page titles"
        case .graves: return "Last name, or Last, First"
        }
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            Group {
                if submitted.isEmpty {
                    landing
                } else {
                    switch router.searchScope {
                    case .library:
                        ResultsView(model: model) {
                            Text("“\(submitted)”")
                                .font(.system(.title2, design: .serif, weight: .semibold))
                                .lineLimit(2)
                        }
                    case .railroads:
                        RailsSearchResults(query: submitted)
                    case .graves:
                        CemeterySearchResults(query: submitted)
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .dataCenterDestinations()
        }
        .searchable(text: $text, prompt: prompt)
        .searchScopes($router.searchScope, activation: .onSearchPresentation) {
            ForEach(Archive.allCases) { Text($0.label).tag($0) }
        }
        .searchSuggestions { suggestions }
        .searchToolbarBehavior(.minimize)
        .onSubmit(of: .search) { submit() }
        .onChange(of: router.searchScope) {
            Haptics.select()
            if !submitted.isEmpty { submit() }
        }
        .onChange(of: text) {
            // Clearing the field returns to the landing page.
            if text.isEmpty { submitted = "" }
        }
        .onAppear {
            if let q = router.pendingQuery {
                router.pendingQuery = nil
                pick(q)
            }
        }
    }

    @ViewBuilder
    private var landing: some View {
        switch router.searchScope {
        case .library: SearchLanding(onPick: pick)
        case .railroads: RailsSearchLanding(onPick: pick)
        case .graves: CemeterySearchLanding(onPick: pick)
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        let q = text.trimmingCharacters(in: .whitespaces)
        if router.searchScope == .library {
            if q.isEmpty {
                ForEach(saved.recentSearches, id: \.self) { term in
                    Label(term, systemImage: "clock").searchCompletion(term)
                }
            } else {
                let recents = saved.recentSearches.filter { $0.localizedCaseInsensitiveContains(q) && $0 != q }.prefix(3)
                ForEach(Array(recents), id: \.self) { term in
                    Label(term, systemImage: "clock").searchCompletion(term)
                }
                let collections = catalog.allCollections.filter { $0.title.localizedCaseInsensitiveContains(q) }.prefix(5)
                if !collections.isEmpty {
                    Section("Collections") {
                        ForEach(Array(collections)) { c in
                            NavigationLink(value: c) {
                                Label {
                                    Text(c.title)
                                } icon: {
                                    Image(systemName: "books.vertical")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func pick(_ term: String) {
        text = term
        submit()
    }

    private func submit() {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        if router.searchScope == .library {
            saved.noteSearch(term)
            model.query = SearchQuery(text: term)
        }
        submitted = term
    }
}

/// What the tab shows before a search — the site's landing strip of
/// popular topics plus this device's recent searches.
struct SearchLanding: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(SavedStore.self) private var saved
    let onPick: (String) -> Void

    private let popular: [(String, String)] = [
        ("architecture", "Architecture"), ("audiovisual", "Audiovisual"),
        ("manuscripts", "Manuscripts"), ("oral histories", "Oral Histories"),
        ("photographs", "Photographs"), ("university of utah", "University of Utah"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Search the archive.")
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    Text("Titles, subjects, descriptions and the full text of scanned pages, across \(catalog.collectionCount.formatted()) collections.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Popular topics")
                    FlowLayout(spacing: 8) {
                        ForEach(popular, id: \.0) { slug, name in
                            NavigationLink(value: Topic(slug: slug, name: name)) {
                                Text(name)
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

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Tips")
                    Text("Quote a phrase to match it exactly. Results can be narrowed by format, institution, collection and year.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
    }
}

/// Wrapping row of capsules.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
