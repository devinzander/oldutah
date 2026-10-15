//
//  BrowseScreen.swift
//  Utah Rails
//
//  The site's front door: the home page's index sections (Union Pacific,
//  Rio Grande, Mining…) and the site map by folder. Both render from the
//  bundled catalog and refresh live.
//

import SwiftUI

enum BrowseMode: String, CaseIterable, Identifiable {
    case index = "Index"
    case siteMap = "Site Map"
    var id: String { rawValue }
}

struct BrowseScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @AppStorage("rails.browseMode") private var mode: BrowseMode = .index
    @State private var filter = ""

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .index: IndexList(filter: filter)
                case .siteMap: SiteMapList(filter: filter)
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
            .navigationTitle("Railroads")
            .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: mode == .index ? "Filter the index" : "Filter folders")
            .utahRailsDestinations()
        }
    }
}

/// A leading row that opens one of the section's own screens.
struct SectionLink<Value: Hashable>: View {
    let value: Value
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        NavigationLink(value: value) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body.weight(.light))
                    .foregroundStyle(Brand.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.body, design: .serif, weight: .semibold))
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// The home page's sections, each a list of index pages with the site's
/// own one-line descriptions.
struct IndexList: View {
    @Environment(CatalogStore.self) private var catalog
    let filter: String

    private var sections: [IndexSection] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return catalog.sections }
        return catalog.sections.compactMap { s in
            let hits = s.entries.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.blurb.localizedCaseInsensitiveContains(q) }
            return hits.isEmpty ? nil : IndexSection(title: s.title, entries: hits)
        }
    }

    var body: some View {
        List {
            if filter.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Railroading in Utah, in depth.")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        Text("Don Strack's research notes on Utah's railroads, the mines and industries they served, and the locomotives and cars that ran here — \(catalog.htmlPageCount.formatted()) pages and \(catalog.pdfCount.formatted()) documents, read natively.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .listRowSeparator(.hidden)
                    SectionLink(value: NewsRoute(), symbol: "clock", title: "What's New",
                                detail: "Don's change log and every page touched this month and last.")
                    SectionLink(value: PhotosRoute(), symbol: "photo.on.rectangle", title: "Photographs",
                                detail: "Don Strack's photo albums, folder by folder.")
                    SectionLink(value: MapsRoute(), symbol: "map", title: "Maps",
                                detail: "Rail lines, stations and mines on the map.")
                }
            }
            ForEach(sections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        IndexEntryRow(entry: entry)
                    }
                } header: {
                    SectionLabel(text: section.title)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView.search(text: filter)
            }
        }
    }
}

struct IndexEntryRow: View {
    let entry: IndexEntry

    var body: some View {
        if entry.isExternal, let url = URL(string: entry.path) {
            if Site.isSmugMug(url) {
                NavigationLink(value: SmugLink(url: url)) { label(symbol: "photo.on.rectangle") }
            } else {
                Link(destination: url) { label(symbol: "arrow.up.right") }
                    .foregroundStyle(.primary)
            }
        } else {
            NavigationLink(value: entry.page) { label(symbol: entry.page.isPDF ? "doc.richtext" : nil) }
        }
    }

    private func label(symbol: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(entry.title)
                    .font(.system(.body, design: .serif, weight: .semibold))
                if let symbol {
                    Image(systemName: symbol).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !entry.blurb.isEmpty {
                Text(entry.blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Folders of the site map with page counts.
struct SiteMapList: View {
    @Environment(CatalogStore.self) private var catalog
    let filter: String

    private var folders: [SiteFolder] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return catalog.folders }
        return catalog.folders.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.slug.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            if filter.isEmpty {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        SerifNumeral(text: catalog.pageCount.formatted(), unit: "pages", size: 34)
                        SerifNumeral(text: catalog.folders.count.formatted(), unit: "folders", size: 34)
                    }
                    .listRowSeparator(.hidden)
                }
            }
            ForEach(folders) { folder in
                NavigationLink(value: folder) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.body.weight(.light))
                            .foregroundStyle(Brand.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.name)
                                .font(.system(.body, design: .serif, weight: .semibold))
                            Text(folder.slug == "/" ? "utahrails.net/" : "utahrails.net/\(folder.slug)/")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .monospaced()
                        }
                        Spacer()
                        Text(folder.pages.count.formatted())
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if folders.isEmpty {
                ContentUnavailableView.search(text: filter)
            }
        }
    }
}

/// Every page in one site-map folder.
struct FolderScreen: View {
    let folder: SiteFolder
    @State private var filter = ""

    private var pages: [PageRef] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return folder.pages }
        return folder.pages.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.path.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            Section {
                SerifNumeral(text: folder.pages.count.formatted(), unit: folder.pages.count == 1 ? "page" : "pages", size: 30)
                    .listRowSeparator(.hidden)
            }
            ForEach(pages) { page in
                NavigationLink(value: page) { PageRow(page: page) }
                    .contextMenu { PageMenu(page: page) }
            }
        }
        .listStyle(.plain)
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Filter \(folder.name)")
        .overlay {
            if pages.isEmpty { ContentUnavailableView.search(text: filter) }
        }
    }
}

/// One index section on its own screen (reached from search suggestions).
struct SectionScreen: View {
    let section: IndexSection
    var body: some View {
        List(section.entries) { IndexEntryRow(entry: $0) }
            .listStyle(.plain)
            .navigationTitle(section.title)
            .navigationBarTitleDisplayMode(.large)
    }
}

/// A page in a list: title, path, PDF mark.
struct PageRow: View {
    let page: PageRef
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: page.isPDF ? "doc.richtext" : "doc.text")
                .font(.body.weight(.light))
                .foregroundStyle(page.isPDF ? Brand.navy : Brand.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                    .font(.system(.body, design: .serif, weight: .semibold))
                    .lineLimit(2)
                Text(subtitle ?? page.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Long-press actions shared by every page row.
struct PageMenu: View {
    @Environment(SavedStore.self) private var saved
    let page: PageRef

    var body: some View {
        Button {
            saved.toggle(page)
            Haptics.success()
        } label: {
            Label(saved.isSaved(page.path) ? "Remove from Saved" : "Save", systemImage: saved.isSaved(page.path) ? "bookmark.slash" : "bookmark")
        }
        ShareLink(item: page.url, subject: Text(page.title), message: Text(page.title)) {
            Label("Share Link", systemImage: "square.and.arrow.up")
        }
        Link(destination: page.url) {
            Label("Open on utahrails.net", systemImage: "safari")
        }
    }
}
