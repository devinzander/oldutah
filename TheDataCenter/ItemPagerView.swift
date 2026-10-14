//
//  ItemPagerView.swift
//  The Data Center
//
//  Swipe left and right through a result set — photographs in an album,
//  the consecutive pages of a scanned volume (the site files each page as
//  its own record). Opened from any list or gallery tap.
//

import SwiftUI

/// A position inside a result set. Carries a snapshot of the hits so the
/// pager can render immediately, and the live model (when there is one) so
/// swiping to the end keeps loading.
struct ItemPage: Hashable {
    let hits: [SearchHit]
    let index: Int
    let source: ResultsModel?

    init(hits: [SearchHit], index: Int, source: ResultsModel? = nil) {
        self.hits = hits
        self.index = index
        self.source = source
    }

    static func == (a: ItemPage, b: ItemPage) -> Bool {
        a.index == b.index && a.hits.map(\.id) == b.hits.map(\.id)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(index)
        hasher.combine(hits.count)
        hasher.combine(hits.first?.id)
    }
}

struct ItemPagerView: View {
    let page: ItemPage
    @State private var selection: Int

    init(page: ItemPage) {
        self.page = page
        _selection = State(initialValue: page.index)
    }

    /// Live hits when the source is still around (more pages may arrive),
    /// the snapshot otherwise.
    private var hits: [SearchHit] {
        if let live = page.source?.hits, live.count >= page.hits.count { return live }
        return page.hits
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                ItemView(id: hit.id, seed: hit, isActive: i == selection)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(hits.count > 1 ? "\(selection + 1) of \(hits.count)" : "")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selection) {
            Haptics.select()
            // Swiping toward the end pulls the next page of results in.
            if let source = page.source, selection >= hits.count - 3, selection < hits.count {
                source.loadMore(after: hits[selection])
            }
        }
    }
}
