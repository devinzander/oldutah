//
//  ResultsView.swift
//  The Data Center
//
//  The site's search-results page: count, list or gallery, sort, facets
//  (Type, Format, Institution, Collection, Year), endless paging.
//

import SwiftUI

struct ResultsView<Header: View>: View {
    @Bindable var model: ResultsModel
    var showsCollection = true
    /// Filters that define this screen (a collection's own setname) — kept
    /// out of the removable chip row.
    var pinned: [FacetFilter] = []
    @ViewBuilder var header: Header

    private var removable: [FacetFilter] {
        model.query.filters.filter { !pinned.contains($0) && $0.field != "facet_format_t" }
    }

    @Environment(CatalogStore.self) private var catalog
    @AppStorage("resultsGallery") private var gallery = false
    @State private var showFilters = false

    var body: some View {
        Group {
            if gallery {
                galleryBody
            } else {
                listBody
            }
        }
        .refreshable { model.reload() }
        .overlay { stateOverlay }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                sortMenu
                Button {
                    Haptics.tap()
                    showFilters = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .accessibilityLabel("Refine")
            }
        }
        .sheet(isPresented: $showFilters) {
            FiltersSheet(model: model)
        }
        .task { model.loadIfNeeded() }
    }

    private var hasChipRow: Bool {
        !removable.isEmpty || model.query.yearStart != nil || model.query.yearEnd != nil
    }

    private var listBody: some View {
        List {
            Section {
                header
                    .listRowSeparator(.hidden)
                countRow
                    .listRowSeparator(.hidden)
                if !model.formatOptions.isEmpty {
                    formatChips(model.formatOptions)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 6, trailing: 0))
                }
                if hasChipRow {
                    filterChips
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                }
            }
            Section {
                ForEach(Array(model.hits.enumerated()), id: \.element.id) { i, hit in
                    NavigationLink(value: ItemPage(hits: model.hits, index: i, source: model)) {
                        HitRow(hit: hit, showsCollection: showsCollection)
                    }
                    .contextMenu { HitMenu(hit: hit) }
                    .onAppear { model.loadMore(after: hit) }
                }
            }
            if model.isLoadingMore {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
    }

    /// Gallery mode lives in a ScrollView, not a List — a List would stamp a
    /// disclosure chevron on every tile.
    private var galleryBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                header
                    .padding(.horizontal, 16)
                countRow
                    .padding(.horizontal, 16)
                if !model.formatOptions.isEmpty {
                    formatChips(model.formatOptions)
                }
                if hasChipRow {
                    filterChips
                }
                HitGrid(hits: model.hits, source: model, onAppear: model.loadMore)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                if model.isLoadingMore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.vertical, 12)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private var countRow: some View {
        HStack(alignment: .firstTextBaseline) {
            if let total = model.total {
                SerifNumeral(text: total.formatted(), unit: total == 1 ? "item" : "items", size: 30)
                    .contentTransition(.numericText())
            } else {
                Text("Searching…")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            LayoutToggle(gallery: $gallery)
        }
        .padding(.top, 2)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(removable) { f in
                    Button {
                        Haptics.select()
                        model.remove(f)
                    } label: {
                        HStack(spacing: 5) {
                            Text(catalog.label(for: f))
                            Image(systemName: "xmark").font(.caption2.weight(.bold))
                        }
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Brand.accentRail)
                    .buttonBorderShape(.capsule)
                }
                if model.query.yearStart != nil || model.query.yearEnd != nil {
                    Button {
                        Haptics.select()
                        model.setYears(nil)
                    } label: {
                        HStack(spacing: 5) {
                            Text(yearLabel)
                            Image(systemName: "xmark").font(.caption2.weight(.bold))
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Brand.accentRail)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// One-tap file-format filter — PDF, JPEG, MP3… — from the site's Format
    /// facet for the current results. Tap again to clear.
    private func formatChips(_ values: [FacetValue]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SectionLabel(text: "Format")
                    .padding(.trailing, 2)
                ForEach(values.prefix(8)) { v in
                    let applied = model.query.filters.contains(v.filter)
                    Button {
                        Haptics.select()
                        if applied { model.remove(v.filter) } else { model.apply(v.filter) }
                    } label: {
                        HStack(spacing: 5) {
                            Text(catalog.label(for: v.filter))
                            Text(v.count.formatted())
                                .foregroundStyle(applied ? .white.opacity(0.8) : .secondary)
                                .monospacedDigit()
                        }
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(applied ? Brand.accentRail : Color.clear)
                    .foregroundStyle(applied ? .white : .primary)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var yearLabel: String {
        switch (model.query.yearStart, model.query.yearEnd) {
        case let (s?, e?): return "\(s)–\(e)"
        case let (s?, nil): return "From \(s)"
        case let (nil, e?): return "To \(e)"
        default: return ""
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: Binding(get: { model.query.sort },
                                             set: { Haptics.select(); model.setSort($0) })) {
                ForEach(SortOrder.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort")
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if model.isLoading && model.hits.isEmpty {
            ProgressView().controlSize(.large)
        } else if let error = model.error, model.hits.isEmpty {
            ContentUnavailableView {
                Label("Couldn't reach the archive", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Haptics.tap(); model.reload() }
                    .buttonStyle(.borderedProminent)
            }
        } else if model.loaded && model.hits.isEmpty {
            ContentUnavailableView("No items", systemImage: "archivebox",
                                   description: Text("Nothing in the archive matches. Try fewer filters or another spelling."))
        }
    }
}

// MARK: - Rows

struct HitRow: View {
    let hit: SearchHit
    var showsCollection = true
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Thumb(url: hit.thumbnail)
                .frame(width: 68, height: 68)
            VStack(alignment: .leading, spacing: 5) {
                Text(hit.title)
                    .font(.body.weight(.medium))
                    .lineLimit(3)
                if let subtitle = hit.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if !hit.type.isEmpty {
                        Chip(label: Brand.typeLabel(hit.type), color: Brand.typeColor(hit.type),
                             systemImage: Brand.typeSymbol(hit.type))
                    }
                    if !hit.date.isEmpty {
                        Text(dateLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if showsCollection && !hit.setname.isEmpty {
                    Text(catalog.title(forSetname: hit.setname))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }

    /// "1942; 1943; 1944; 1945" → "1942–1945".
    private var dateLabel: String {
        let parts = hit.date.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count > 2, let f = parts.first, let l = parts.last { return "\(f)–\(l)" }
        return parts.joined(separator: ", ")
    }
}

struct HitGrid: View {
    let hits: [SearchHit]
    var source: ResultsModel? = nil
    let onAppear: (SearchHit) -> Void
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                NavigationLink(value: ItemPage(hits: hits, index: i, source: source)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Thumb(url: hit.thumbnail, cornerRadius: 12)
                            .aspectRatio(1, contentMode: .fit)
                        Text(hit.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu { HitMenu(hit: hit) }
                .onAppear { onAppear(hit) }
            }
        }
    }
}

/// Long-press actions on any result: bookmark, share its link, open the
/// record on the web.
struct HitMenu: View {
    let hit: SearchHit
    @Environment(SavedStore.self) private var saved
    @Environment(\.openURL) private var openURL

    private var url: URL {
        UDL.base.appendingPathComponent("details").appending(queryItems: [URLQueryItem(name: "id", value: String(hit.id))])
    }

    var body: some View {
        Button {
            Haptics.tap()
            saved.toggle(hit)
        } label: {
            Label(saved.isSaved(hit.id) ? "Remove from Saved" : "Save",
                  systemImage: saved.isSaved(hit.id) ? "bookmark.slash" : "bookmark")
        }
        ShareLink(item: url, subject: Text(hit.title), message: Text(hit.title)) {
            Label("Share Link", systemImage: "square.and.arrow.up")
        }
        Button { openURL(url) } label: {
            Label("Open on the Web", systemImage: "safari")
        }
    }
}

// MARK: - Filters

struct FiltersSheet: View {
    @Bindable var model: ResultsModel
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss

    private var years: ClosedRange<Int> {
        model.yearRange ?? 1800...Calendar.current.component(.year, from: .now)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Sort") {
                    Picker("Sort", selection: Binding(get: { model.query.sort },
                                                     set: { Haptics.select(); model.setSort($0) })) {
                        ForEach(SortOrder.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Picker("From", selection: Binding(
                        get: { model.query.yearStart ?? 0 },
                        set: { v in
                            Haptics.select()
                            let start = v == 0 ? nil : v
                            var end = model.query.yearEnd
                            if let s = start, let e = end, e < s { end = s }
                            model.setYears(range(start, end))
                        })) {
                        Text("Any").tag(0)
                        ForEach(Array(stride(from: years.upperBound, through: years.lowerBound, by: -1)), id: \.self) {
                            Text(String($0)).tag($0)
                        }
                    }
                    Picker("To", selection: Binding(
                        get: { model.query.yearEnd ?? 0 },
                        set: { v in
                            Haptics.select()
                            let end = v == 0 ? nil : v
                            var start = model.query.yearStart
                            if let s = start, let e = end, e < s { start = e }
                            model.setYears(range(start, end))
                        })) {
                        Text("Any").tag(0)
                        ForEach(Array(stride(from: years.upperBound, through: years.lowerBound, by: -1)), id: \.self) {
                            Text(String($0)).tag($0)
                        }
                    }
                } header: {
                    Text("Years")
                } footer: {
                    if let r = model.yearRange {
                        Text("Dated items in these results span \(String(r.lowerBound))–\(String(r.upperBound)).")
                    }
                }

                ForEach(model.facets) { group in
                    Section(group.title) {
                        ForEach(group.values) { v in
                            let applied = model.query.filters.contains(v.filter)
                            Button {
                                Haptics.select()
                                if applied { model.remove(v.filter) } else { model.apply(v.filter) }
                            } label: {
                                HStack {
                                    Text(catalog.label(for: v.filter))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Spacer()
                                    Text(v.count.formatted())
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    if applied {
                                        Image(systemName: "checkmark")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(Brand.accent)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Refine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !model.query.filters.isEmpty || model.query.yearStart != nil || model.query.yearEnd != nil {
                        Button("Clear") {
                            Haptics.tap()
                            var q = model.query
                            q.filters.removeAll()
                            q.yearStart = nil; q.yearEnd = nil; q.page = 1
                            model.query = q
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Haptics.tap(); dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func range(_ s: Int?, _ e: Int?) -> ClosedRange<Int>? {
        switch (s, e) {
        case let (s?, e?): return min(s, e)...max(s, e)
        case let (s?, nil): return s...years.upperBound
        case let (nil, e?): return years.lowerBound...e
        default: return nil
        }
    }
}
