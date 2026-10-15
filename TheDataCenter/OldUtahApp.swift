//
//  OldUtahApp.swift
//  Old Utah
//
//  Utah's history, read natively: the University of Utah's digital
//  collections, Don Strack's railroad history and photographs, and the
//  burial registers of Salt Lake City's cemeteries — one search, one
//  saved list.
//

import SwiftUI
import RailsKit
import CemeteryKit

@main
struct OldUtahApp: App {
    @State private var catalog = CatalogStore()
    @State private var saved = SavedStore()
    @State private var router = AppRouter()
    private let rails = RailsKitStores()
    private let cemeteries = CemeteryKitStores()

    init() {
        // Thumbnails, page images and photos come through AsyncImage → URLCache.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 768 << 20)
        Self.styleLargeTitles()
    }

    /// Large navigation titles set in EB Garamond — the same bundled face
    /// Plat of Zion uses for its display type. The font is variable, so the
    /// semibold weight is dialed in through the wght axis.
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
            RootView(rails: rails)
                .environment(catalog)
                .environment(saved)
                .environment(router)
                .railsKit(rails)
                .cemeteryKit(cemeteries)
                .tint(Brand.accent)
                .onAppear {
                    cemeteries.onRequestSearch = { [router] in
                        router.searchScope = .graves
                        router.tab = .search
                    }
                }
        }
    }
}

enum AppTab: Hashable {
    case library, railroads, cemeteries, saved, search
}

/// Which part of the app a search or the saved list is looking at.
enum Archive: String, CaseIterable, Identifiable {
    case library, railroads, graves
    var id: String { rawValue }
    var label: String {
        switch self {
        case .library: return "Library"
        case .railroads: return "Railroads"
        case .graves: return "Graves"
        }
    }
}

/// Cross-tab intents.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .library
    var searchScope: Archive = .library
    /// A search to run on launch; debug builds only.
    var pendingQuery: String?

    init() {
        #if DEBUG
        // `-OUSearch graves:Young` opens Search with that scope and query.
        if let raw = UserDefaults.standard.string(forKey: "OUSearch"),
           let colon = raw.firstIndex(of: ":"),
           let scope = Archive(rawValue: String(raw[..<colon])) {
            searchScope = scope
            pendingQuery = String(raw[raw.index(after: colon)...])
            tab = .search
        }
        // `-OUTab railroads` opens on that tab, for simulator screenshots.
        switch UserDefaults.standard.string(forKey: "OUTab") {
        case "railroads": tab = .railroads
        case "cemeteries": tab = .cemeteries
        case "saved": tab = .saved
        case "search": tab = .search
        default: break
        }
        #endif
    }
}

struct RootView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(AppRouter.self) private var router
    let rails: RailsKitStores

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Library", systemImage: "books.vertical", value: .library) {
                BrowseScreen()
            }
            Tab("Railroads", systemImage: "train.side.front.car", value: .railroads) {
                RailsTab()
            }
            Tab("Cemeteries", systemImage: "building.columns", value: .cemeteries) {
                CemeteriesTab()
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
        .task { await rails.refresh() }
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
            .railsDestinations()
            .cemeteryDestinations()
            .navigationDestination(for: SearchHit.self) { ItemView(id: $0.id, seed: $0) }
            .navigationDestination(for: ItemPage.self) { ItemPagerView(page: $0) }
            .navigationDestination(for: Collection.self) { CollectionView(collection: $0) }
            .navigationDestination(for: Institution.self) { InstitutionView(institution: $0) }
            .navigationDestination(for: Topic.self) { TopicView(topic: $0) }
            .navigationDestination(for: ResultsRoute.self) { ResultsScreen(route: $0) }
    }
}
