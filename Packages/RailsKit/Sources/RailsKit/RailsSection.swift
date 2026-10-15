//
//  RailsSection.swift
//  Old Utah — Railroads
//
//  UtahRails.net — Don Strack's history of railroading in Utah — and his
//  photo albums on SmugMug, as one section of Old Utah: its stores and the
//  screens the app's tabs host.
//

import SwiftUI

/// Everything the section keeps alive for the life of the app.
@MainActor
public final class RailsKitStores {
    let catalog = CatalogStore()
    let articles = ArticleStore()
    let saved = SavedStore()
    let railMaps = MapsStore()

    public init() {}

    /// Refreshes the bundled site map from the live site.
    public func refresh() async { await catalog.refresh() }
}

public extension View {
    /// Puts the section's stores in the environment.
    func railsKit(_ stores: RailsKitStores) -> some View {
        self
            .environment(stores.catalog)
            .environment(stores.articles)
            .environment(stores.saved)
            .environment(stores.railMaps)
    }

    /// Navigation destinations for railroad values, for any stack that
    /// shows them.
    func railsDestinations() -> some View {
        utahRailsDestinations()
    }
}

/// The Railroads tab.
public struct RailsTab: View {
    public init() {}
    public var body: some View { BrowseScreen() }
}

/// Saved and recently read pages, for the shared Saved tab. Brings no
/// navigation stack.
public struct RailsSavedList: View {
    public init() {}
    public var body: some View { SavedScreen() }
}

/// Page-title matches for the shared Search tab. Brings no navigation
/// stack; the host owns the search field and passes the submitted text.
public struct RailsSearchResults: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(SavedStore.self) private var saved
    let query: String

    public init(query: String) { self.query = query }

    public var body: some View {
        SearchResults(query: query, results: catalog.search(query, pdfs: nil))
            .task(id: query) { saved.noteSearch(query) }
    }
}

/// The landing copy and starter terms, for the shared Search tab.
public struct RailsSearchLanding: View {
    let onPick: (String) -> Void
    public init(onPick: @escaping (String) -> Void) { self.onPick = onPick }
    public var body: some View { SearchLanding(onPick: onPick) }
}

extension View {
    /// Every navigation stack in the app resolves the same value types.
    func utahRailsDestinations() -> some View {
        self
            .navigationDestination(for: PageRef.self) { page in
                if page.isPDF { PDFScreen(pdf: PDFRef(url: page.url, title: page.title)) } else { ArticleScreen(page: page) }
            }
            .navigationDestination(for: PDFRef.self) { PDFScreen(pdf: $0) }
            .navigationDestination(for: SiteFolder.self) { FolderScreen(folder: $0) }
            .navigationDestination(for: IndexSection.self) { SectionScreen(section: $0) }
            .navigationDestination(for: SmugNode.self) { SmugFolderScreen(node: $0) }
            .navigationDestination(for: SmugAlbum.self) { SmugAlbumScreen(album: $0) }
            .navigationDestination(for: SmugLink.self) { SmugLinkScreen(link: $0) }
            .navigationDestination(for: SmugImage.self) { PhotoScreen(image: $0) }
            .navigationDestination(for: RailMap.self) { RailMapScreen(map: $0) }
            .navigationDestination(for: MapsRoute.self) { _ in MapsScreen() }
            .navigationDestination(for: NewsRoute.self) { _ in NewsContent() }
            .navigationDestination(for: PhotosRoute.self) { _ in PhotosScreen() }
    }
}

/// Navigation value for the maps list.
struct MapsRoute: Hashable {}

/// Navigation value for What's New.
struct NewsRoute: Hashable {}

/// Navigation value for the photo albums.
struct PhotosRoute: Hashable {}
