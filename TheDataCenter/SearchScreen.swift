//
//  SearchScreen.swift
//  The Data Center
//
//  The search tab: system search field in the tab bar, scopes for the
//  archive's media types, suggestions from recent searches and collection
//  names, then the shared results view.
//

import SwiftUI

enum SearchScope: String, CaseIterable, Identifiable {
    case all, images, text, sound, video
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .images: return "Images"
        case .text: return "Text"
        case .sound: return "Audio"
        case .video: return "Video"
        }
    }
    /// The site's type facet for the scope — wildcard for the two image
    /// vocabularies it uses.
    var filter: FacetFilter? {
        switch self {
        case .all: return nil
        case .images: return FacetFilter(field: "facet_type_t", value: "Image*", label: "Images")
        case .text: return FacetFilter(field: "facet_type_t", value: "\"Text\"", label: "Text")
        case .sound: return FacetFilter(field: "facet_type_t", value: "\"Sound\"", label: "Audio")
        case .video: return FacetFilter(field: "facet_type_t", value: "Image/MovingImage", label: "Video")
        }
    }
}

struct SearchScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(SavedStore.self) private var saved
    @State private var text = ""
    @State private var scope: SearchScope = .all
    @State private var model = ResultsModel(query: SearchQuery())
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            Group {
                if submitted {
                    ResultsView(model: model) {
                        Text(model.query.text.isEmpty ? "Everything" : "“\(model.query.text)”")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                            .lineLimit(2)
                    }
                } else {
                    SearchLanding(onPick: { term in
                        text = term
                        submit()
                    })
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .dataCenterDestinations()
        }
        .searchable(text: $text, prompt: "Search titles, subjects and full text")
        .searchScopes($scope, activation: .onSearchPresentation) {
            ForEach(SearchScope.allCases) { Text($0.label).tag($0) }
        }
        .searchSuggestions { suggestions }
        .searchToolbarBehavior(.minimize)
        .onSubmit(of: .search) { submit() }
        .onChange(of: scope) {
            Haptics.select()
            if submitted { model.setType(scope.filter) }
        }
        .onChange(of: text) {
            // Clearing the field returns to the landing page.
            if text.isEmpty && submitted && model.query.text.isEmpty == false {
                submitted = false
            }
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        let q = text.trimmingCharacters(in: .whitespaces)
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

    private func submit() {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var q = SearchQuery(text: term)
        if let f = scope.filter { q.filters = [f] }
        saved.noteSearch(term)
        model.query = q
        submitted = true
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
                    Text("Quote a phrase to match it exactly. Use the scope bar to limit results to images, text, audio or video, then refine by institution, collection and year.")
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
