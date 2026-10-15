//
//  CemeterySection.swift
//  Old Utah — Cemeteries
//
//  The grave finder for the burial grounds inside Salt Lake City, as one
//  section of Old Utah: its stores, the screens the app's tabs host, and
//  the plat map, which opens full screen from wherever a grave is shown.
//

import SwiftUI

/// Everything the section keeps alive for the life of the app.
@MainActor
public final class CemeteryKitStores {
    let router = Router()
    let search = SearchStore()
    let saved = SavedStore()
    let plats = PlatStore()
    let location = LocationStore()

    public init() {
        #if DEBUG
        // `-OUMap 1` opens on the plat map, for simulator screenshots.
        if UserDefaults.standard.bool(forKey: "OUMap") { router.mapPresented = true }
        #endif
    }

    /// Called when a screen asks to search one cemetery; the host switches
    /// to its search tab with graves in scope.
    public var onRequestSearch: () -> Void {
        get { router.onRequestSearch }
        set { router.onRequestSearch = newValue }
    }
}

/// Cross-screen intents: open the map on a cemetery, walk to a grave.
@MainActor
@Observable
final class Router {
    var mapPresented = false
    var mapCemeteryID: String = Cemeteries.slc
    var walkTarget: GraveRecord?
    var mapFocus: MapFocus?
    @ObservationIgnored var onRequestSearch: () -> Void = {}

    func requestSearch() { onRequestSearch() }
}

public extension View {
    /// Puts the section's stores in the environment and hangs the plat map
    /// off the whole app.
    func cemeteryKit(_ stores: CemeteryKitStores) -> some View {
        modifier(CemeteryKitHost())
            .environment(stores.router)
            .environment(stores.search)
            .environment(stores.saved)
            .environment(stores.plats)
            .environment(stores.location)
    }

    /// Navigation destinations for cemetery values, for any stack that
    /// shows them.
    func cemeteryDestinations() -> some View {
        cityCemeteryDestinations()
    }
}

private struct CemeteryKitHost: ViewModifier {
    @Environment(Router.self) private var router

    func body(content: Content) -> some View {
        @Bindable var router = router
        content
            .fullScreenCover(isPresented: $router.mapPresented) {
                NavigationStack {
                    MapScreen()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    Haptics.tap()
                                    router.mapPresented = false
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .accessibilityLabel("Close the map")
                            }
                        }
                        .cityCemeteryDestinations()
                }
                .tint(Brand.accent)
            }
    }
}

/// The Cemeteries tab.
public struct CemeteriesTab: View {
    public init() {}
    public var body: some View { CemeteriesScreen() }
}

/// Saved graves, for the shared Saved tab. Brings no navigation stack.
public struct CemeterySavedList: View {
    public init() {}
    public var body: some View { SavedScreen() }
}

/// Grave search for the shared Search tab. Brings no navigation stack;
/// the host owns the search field and passes the submitted text.
public struct CemeterySearchResults: View {
    @Environment(SearchStore.self) private var search
    @Environment(SavedStore.self) private var saved
    let query: String

    public init(query: String) { self.query = query }

    public var body: some View {
        SearchResults()
            .safeAreaInset(edge: .top, spacing: 0) { ScopeBar() }
            .task(id: query) {
                saved.noteSearch(query)
                search.search(query)
            }
    }
}

/// Which cemetery a grave search covers.
private struct ScopeBar: View {
    @Environment(SearchStore.self) private var search

    var body: some View {
        @Bindable var search = search
        HStack {
            Menu {
                Picker("Cemetery", selection: $search.scope) {
                    Text("Every cemetery").tag(String?.none)
                    ForEach(Cemeteries.withRecords) { c in Text(c.name).tag(String?.some(c.id)) }
                }
            } label: {
                Label(search.scopeCemetery?.name ?? "Every cemetery", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .onChange(of: search.scope) {
            Haptics.select()
            if let q = search.submitted { search.search("\(q.last), \(q.first)") }
        }
    }
}

/// The landing copy and starter names, for the shared Search tab.
public struct CemeterySearchLanding: View {
    let onPick: (String) -> Void
    public init(onPick: @escaping (String) -> Void) { self.onPick = onPick }
    public var body: some View { SearchLanding(onPick: onPick) }
}

extension View {
    /// Every navigation stack resolves the same value types.
    func cityCemeteryDestinations() -> some View {
        self
            .navigationDestination(for: GraveRecord.self) { GraveScreen(record: $0) }
            .navigationDestination(for: Cemetery.self) { CemeteryScreen(cemetery: $0) }
    }
}
