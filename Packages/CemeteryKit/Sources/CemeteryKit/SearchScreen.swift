//
//  SearchScreen.swift
//  City Cemetery
//
//  A name, every register. Results arrive cemetery by cemetery; the two
//  with maps lead.
//

import SwiftUI

struct SearchResults: View {
    @Environment(SearchStore.self) private var search

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if let q = search.submitted {
                        Text(q.first.isEmpty ? q.last : "\(q.first) \(q.last)")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                            .lineLimit(2)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        SerifNumeral(text: search.total.formatted(), unit: search.total == 1 ? "grave" : "graves", size: 28)
                        if search.isSearching { ProgressView().controlSize(.small) }
                    }
                }
                .listRowSeparator(.hidden)
            }
            ForEach(search.groups) { group in
                if !group.records.isEmpty || group.error != nil {
                    Section {
                        ForEach(group.records) { r in
                            NavigationLink(value: r) { GraveRow(record: r, showCemetery: false) }
                        }
                        if let e = group.error {
                            Label(e, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if group.records.count >= 50, !group.cemetery.source.isMapped {
                            Text("The state database shows the first 50. Add a first name to narrow it.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        HStack {
                            SectionLabel(text: group.cemetery.name)
                            Spacer()
                            if group.cemetery.source.isMapped {
                                Image(systemName: "mappin.and.ellipse").font(.caption2).foregroundStyle(Brand.accent)
                            }
                        }
                    }
                }
            }
            if !search.isSearching {
                Section {
                    let missing = Cemeteries.all.filter { !$0.source.hasRecords }
                    Text("Not in these registers? \(missing.map(\.shortName).formatted(.list(type: .and))) keep their own books; try Find a Grave, or call the office.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let q = search.submitted {
                        Link(destination: Cemeteries.all[0].findAGraveSearch(q)) {
                            Label("Search Find a Grave for Salt Lake City", systemImage: "arrow.up.right")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if !search.isSearching, search.total == 0, search.groups.allSatisfy({ $0.error == nil }) {
                ContentUnavailableView {
                    Label("No one by that name", systemImage: "magnifyingglass")
                } description: {
                    Text("Try the last name alone, or an older spelling. Sextons wrote what they heard.")
                }
            }
        }
    }
}

/// What the tab shows before a search.
struct SearchLanding: View {
    @Environment(SavedStore.self) private var saved
    let onPick: (String) -> Void

    private let starters = ["Young", "Kimball", "Dern", "Wells", "Eccles", "Walker", "Auerbach", "Keith"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Find a grave.")
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    Text("The Salt Lake City Cemetery and Mount Olivet are mapped grave by grave: search either one and the app draws the plot on satellite and walks you to it. Five smaller grounds are searched through the registers the state and the VA publish.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Try a name")
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

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "How the registers file names")
                    Text("Last name first, then given names: \"Zander, Rhea\". Typing \"Rhea Zander\" works too. Married women are usually under the married name; older entries may use initials.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

/// Wrapping row of chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
