//
//  BrowseScreen.swift
//  The Data Center
//
//  The site's Browse page: by institution (default), by collection A–Z, by
//  topic. Institutions and collections render from the bundled catalog and
//  refresh live; topic pages load on demand.
//

import SwiftUI

enum BrowseMode: String, CaseIterable, Identifiable {
    case institutions = "Institutions"
    case collections = "Collections"
    case topics = "Topics"
    var id: String { rawValue }
}

struct BrowseScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(SavedStore.self) private var saved
    @AppStorage("browseMode") private var mode: BrowseMode = .institutions
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var showAbout = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch mode {
                case .institutions: InstitutionsList(filter: "")
                case .collections: CollectionsAZ(filter: "")
                case .topics: TopicsGrid(filter: "")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Browse by", selection: $mode) {
                    ForEach(BrowseMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .onChange(of: mode) { Haptics.select() }
            }
            .navigationTitle("The Data Center")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Haptics.tap(); showAbout = true } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("About")
                }
            }
            // The header field searches the whole archive — submitting pushes
            // the results; typing offers matching collections.
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "Search all items")
            .searchSuggestions { suggestions }
            .onSubmit(of: .search) { submit() }
            .sheet(isPresented: $showAbout) { AboutView() }
            .dataCenterDestinations()
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            ForEach(saved.recentSearches, id: \.self) { term in
                Label(term, systemImage: "clock").searchCompletion(term)
            }
        } else {
            let collections = catalog.allCollections.filter { $0.title.localizedCaseInsensitiveContains(q) }.prefix(6)
            if !collections.isEmpty {
                Section("Collections") {
                    ForEach(Array(collections)) { c in
                        NavigationLink(value: c) {
                            Label(c.title, systemImage: "books.vertical")
                        }
                    }
                }
            }
        }
    }

    private func submit() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        saved.noteSearch(term)
        path.append(ResultsRoute(title: "“\(term)”", subtitle: nil, query: SearchQuery(text: term)))
    }
}

// MARK: - Institutions

struct InstitutionsList: View {
    @Environment(CatalogStore.self) private var catalog
    let filter: String

    private var rows: [Institution] {
        let f = filter.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return catalog.institutions }
        return catalog.institutions.filter {
            $0.name.localizedCaseInsensitiveContains(f)
                || $0.collections.contains { c in c.title.localizedCaseInsensitiveContains(f) }
        }
    }

    var body: some View {
        List {
            if filter.isEmpty {
                Section {
                    Text("Photographs, manuscripts, newspapers, oral histories and films from \(catalog.institutions.count) Utah institutions: \(catalog.collectionCount.formatted()) collections, more than a million items, published by the J. Willard Marriott Library at the University of Utah.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .listRowSeparator(.hidden)
                }
            }
            Section {
                ForEach(rows) { inst in
                    NavigationLink(value: inst) {
                        HStack(spacing: 12) {
                            InstitutionMark(prefix: inst.prefix)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(inst.name).font(.body.weight(.medium))
                                Text("^[\(inst.collections.count) collection](inflect: true)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView.search(text: filter)
            }
        }
    }
}

/// Two-letter serif monogram on paper — a stamp per institution.
struct InstitutionMark: View {
    let prefix: String
    var size: CGFloat = 44
    var body: some View {
        Text(prefix.prefix(2).uppercased())
            .font(.system(size: size * 0.38, weight: .semibold, design: .serif))
            .foregroundStyle(Brand.accent)
            .frame(width: size, height: size)
            .background(Brand.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Brand.accent.opacity(0.2), lineWidth: 0.5))
    }
}

struct InstitutionView: View {
    @Environment(CatalogStore.self) private var catalog
    let institution: Institution
    @State private var filter = ""
    @AppStorage("browseGallery") private var gallery = false

    private var live: Institution { catalog.institution(prefix: institution.prefix) ?? institution }

    private var institutionHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(live.name)
                .font(.system(.title, design: .serif, weight: .semibold))
            SerifNumeral(text: live.collections.count.formatted(), unit: "collections", size: 34)
            NavigationLink(value: ResultsRoute(title: live.name, subtitle: "All items",
                                               query: SearchQuery(filters: [live.filter]))) {
                Label("Every item from this institution", systemImage: "archivebox")
                    .font(.subheadline.weight(.medium))
            }
        }
    }
    private var collections: [Collection] {
        let f = filter.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return live.collections }
        return live.collections.filter {
            $0.title.localizedCaseInsensitiveContains(f) || $0.description.localizedCaseInsensitiveContains(f)
        }
    }

    var body: some View {
        Group {
            if gallery {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        institutionHeader
                        HStack {
                            SectionLabel(text: "Collections")
                            Spacer()
                            LayoutToggle(gallery: $gallery)
                        }
                        CollectionGrid(collections: collections)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            } else {
                List {
                    Section {
                        institutionHeader
                            .padding(.vertical, 6)
                            .listRowSeparator(.hidden)
                    }
                    Section {
                        ForEach(collections) { c in
                            NavigationLink(value: c) { CollectionRow(collection: c) }
                        }
                    } header: {
                        HStack {
                            SectionLabel(text: "Collections")
                            Spacer()
                            LayoutToggle(gallery: $gallery)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $filter, prompt: "Filter collections")
    }
}

/// List ↔ gallery switch, the site's two browse views.
struct LayoutToggle: View {
    @Binding var gallery: Bool
    var body: some View {
        Picker("Layout", selection: Binding(
            get: { gallery ? 1 : 0 },
            set: { v in
                Haptics.select()
                withAnimation(.snappy) { gallery = v == 1 }
            })) {
            Image(systemName: "list.bullet").tag(0)
                .accessibilityLabel("List")
            Image(systemName: "square.grid.2x2").tag(1)
                .accessibilityLabel("Gallery")
        }
        .pickerStyle(.segmented)
        .frame(width: 96)
    }
}

struct CollectionRow: View {
    let collection: Collection
    var showInstitution = false
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Thumb(url: collection.thumbnailURL)
                .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(collection.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                if showInstitution, let inst = catalog.institution(forSetname: collection.setname) {
                    Text(inst.name).font(.caption).foregroundStyle(Brand.accent)
                }
                if !collection.description.isEmpty {
                    Text(collection.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

struct CollectionGrid: View {
    let collections: [Collection]
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(collections) { c in
                NavigationLink(value: c) {
                    VStack(alignment: .leading, spacing: 6) {
                        Thumb(url: c.thumbnailURL, cornerRadius: 14)
                            .aspectRatio(1, contentMode: .fit)
                        Text(c.title)
                            .font(.footnote.weight(.medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Collections A–Z

struct CollectionsAZ: View {
    @Environment(CatalogStore.self) private var catalog
    let filter: String

    private var sections: [(letter: String, items: [Collection])] {
        let f = filter.trimmingCharacters(in: .whitespaces)
        let source = f.isEmpty ? catalog.allCollections : catalog.allCollections.filter {
            $0.title.localizedCaseInsensitiveContains(f) || $0.description.localizedCaseInsensitiveContains(f)
        }
        var groups: [String: [Collection]] = [:]
        for c in source {
            let first = c.title.first.map { String($0).uppercased() } ?? "#"
            let key = first.rangeOfCharacter(from: .letters) == nil ? "#" : first
            groups[key, default: []].append(c)
        }
        return groups.keys.sorted { a, b in
            if a == "#" { return true }
            if b == "#" { return false }
            return a < b
        }.map { ($0, groups[$0]!) }
    }

    var body: some View {
        List {
            ForEach(sections, id: \.letter) { section in
                Section {
                    ForEach(section.items) { c in
                        NavigationLink(value: c) { CollectionRow(collection: c, showInstitution: true) }
                    }
                } header: {
                    Text(section.letter)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(Brand.accent)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if sections.isEmpty { ContentUnavailableView.search(text: filter) }
        }
    }
}

// MARK: - Topics

struct TopicsGrid: View {
    @Environment(CatalogStore.self) private var catalog
    let filter: String
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    private var topics: [Topic] {
        let f = filter.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return catalog.topics }
        return catalog.topics.filter { $0.name.localizedCaseInsensitiveContains(f) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(topics) { t in
                    NavigationLink(value: t) {
                        Text(t.name)
                            .font(.system(.subheadline, design: .serif, weight: .medium))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .overlay {
            if topics.isEmpty { ContentUnavailableView.search(text: filter) }
        }
    }
}

struct TopicView: View {
    let topic: Topic
    @State private var collections: [Collection]?
    @State private var error: String?
    @AppStorage("browseGallery") private var gallery = false

    var body: some View {
        Group {
            if let collections, gallery {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        HStack {
                            SectionLabel(text: "^[\(collections.count) collection](inflect: true)")
                            Spacer()
                            LayoutToggle(gallery: $gallery)
                        }
                        CollectionGrid(collections: collections)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            } else {
                List {
                    if let collections {
                        Section {
                            ForEach(collections) { c in
                                NavigationLink(value: c) { CollectionRow(collection: c, showInstitution: true) }
                            }
                        } header: {
                            HStack {
                                SectionLabel(text: "^[\(collections.count) collection](inflect: true)")
                                Spacer()
                                LayoutToggle(gallery: $gallery)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(topic.name)
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if collections == nil {
                if let error {
                    ContentUnavailableView {
                        Label("Couldn't load topic", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Try Again") { Task { await load() } }.buttonStyle(.bordered)
                    }
                } else {
                    ProgressView()
                }
            } else if collections?.isEmpty == true {
                ContentUnavailableView("No collections", systemImage: "tray", description: Text("Nothing is filed under this topic yet."))
            }
        }
        .task { await load() }
    }

    private func load() async {
        error = nil
        do { collections = try await UDLClient.shared.topic(topic.slug) }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - Collection

struct CollectionView: View {
    @Environment(CatalogStore.self) private var catalog
    let collection: Collection
    @State private var model: ResultsModel

    init(collection: Collection) {
        self.collection = collection
        _model = State(initialValue: ResultsModel(query: SearchQuery(filters: [collection.filter])))
    }

    var body: some View {
        ResultsView(model: model, showsCollection: false, pinned: [collection.filter]) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    Thumb(url: collection.thumbnailURL, cornerRadius: 14)
                        .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(collection.title)
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        if let inst = catalog.institution(forSetname: collection.setname) {
                            NavigationLink(value: inst) {
                                Text(inst.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Brand.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !collection.description.isEmpty {
                    ExpandableText(text: collection.description)
                }
            }
        }
        // The serif header names the collection; the bar stays quiet.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Long collection descriptions fold to four lines with a "More" toggle.
struct ExpandableText: View {
    let text: String
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 4)
            if text.count > 220 {
                Button(expanded ? "Less" : "More") {
                    Haptics.select()
                    withAnimation(.snappy) { expanded.toggle() }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }
}

// MARK: - Generic results screen

struct ResultsScreen: View {
    let route: ResultsRoute
    @State private var model: ResultsModel

    init(route: ResultsRoute) {
        self.route = route
        _model = State(initialValue: ResultsModel(query: route.query))
    }

    var body: some View {
        ResultsView(model: model) {
            if let subtitle = route.subtitle {
                Text(subtitle)
                    .font(.system(.title3, design: .serif, weight: .semibold))
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
