//
//  DataCenterApp.swift
//  The Data Center
//
//  A free, native reader for the Utah digital collections hosted by the
//  J. Willard Marriott Library at the University of Utah.
//

import SwiftUI

@main
struct DataCenterApp: App {
    @State private var catalog = CatalogStore()
    @State private var saved = SavedStore()

    init() {
        // Thumbnails and page images come through AsyncImage → URLCache.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
        Self.styleLargeTitles()
    }

    /// Large navigation titles ("The Data Center") set in EB Garamond — the
    /// same bundled face Plat of Zion uses for its display type. The font is
    /// variable, so the semibold weight is dialed in through the wght axis.
    private static func styleLargeTitles() {
        guard let base = UIFont(name: "EBGaramond-Regular", size: 38) else { return }
        let wght = 0x77676874   // 'wght'
        let variation = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = base.fontDescriptor.addingAttributes([variation: [wght: 600]])
        let font = UIFont(descriptor: descriptor, size: 38)
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: font,
            // Ink in light mode, white in dark — a fixed ink went invisible on
            // the dark bar.
            .foregroundColor: UIColor { $0.userInterfaceStyle == .dark ? .white : UIColor(Brand.ink) },
        ]
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(catalog)
                .environment(saved)
                .tint(Brand.accent)
        }
    }
}

enum AppTab: Hashable {
    case browse, saved, search
}

struct RootView: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var selection: AppTab = .browse

    var body: some View {
        TabView(selection: $selection) {
            Tab("Library", systemImage: "building.columns", value: .browse) {
                BrowseScreen()
            }
            Tab("Saved", systemImage: "bookmark", value: .saved) {
                SavedScreen()
            }
            Tab(value: .search, role: .search) {
                SearchScreen()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .task { await catalog.refresh() }
    }
}

/// A results screen reached by value — an institution's items, a topic, a
/// facet tapped on an item.
struct ResultsRoute: Hashable {
    let title: String
    let subtitle: String?
    let query: SearchQuery
}

extension View {
    /// Every navigation stack in the app resolves the same value types.
    func dataCenterDestinations() -> some View {
        self
            .navigationDestination(for: SearchHit.self) { ItemView(id: $0.id, seed: $0) }
            .navigationDestination(for: ItemPage.self) { ItemPagerView(page: $0) }
            .navigationDestination(for: Collection.self) { CollectionView(collection: $0) }
            .navigationDestination(for: Institution.self) { InstitutionView(institution: $0) }
            .navigationDestination(for: Topic.self) { TopicView(topic: $0) }
            .navigationDestination(for: ResultsRoute.self) { ResultsScreen(route: $0) }
    }
}
