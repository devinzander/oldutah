//
//  NewsScreen.swift
//  Utah Rails
//
//  What's New: Don's dated change log, newest first, plus the site's
//  auto-generated list of every page touched this month and last.
//

import SwiftUI

enum NewsMode: String, CaseIterable, Identifiable {
    case changes = "What's New"
    case recent = "Recent Updates"
    var id: String { rawValue }
}

struct NewsScreen: View {
    var body: some View {
        NavigationStack {
            NewsContent()
                .utahRailsDestinations()
        }
    }
}

/// What's New, pushable from anywhere.
struct NewsContent: View {
    @AppStorage("rails.newsMode") private var mode: NewsMode = .changes
    @State private var entries: [NewsEntry] = []
    @State private var recent: [RecentUpdate] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        Group {
            switch mode {
            case .changes: ChangesList(entries: entries, error: error, loaded: loaded) { await load(force: true) }
            case .recent: RecentList(updates: recent, error: error, loaded: loaded) { await load(force: true) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Show", selection: $mode) {
                ForEach(NewsMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .onChange(of: mode) { Haptics.select() }
        }
        .navigationTitle("What's New")
        .navigationBarTitleDisplayMode(.large)
        .task { await load(force: false) }
    }

    private func load(force: Bool) async {
        if loaded && !force { return }
        error = nil
        do {
            async let e = SiteClient.shared.whatsNew()
            async let r = SiteClient.shared.recentUpdates()
            let (ee, rr) = try await (e, r)
            entries = ee
            recent = rr
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ChangesList: View {
    let entries: [NewsEntry]
    let error: String?
    let loaded: Bool
    let refresh: () async -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(entry.date)
                                .font(.system(.title3, design: .serif, weight: .semibold))
                                .fixedSize()
                            Rectangle().fill(.quaternary).frame(height: 1)
                        }
                        ArticleBody(blocks: entry.blocks, nested: true)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .refreshable { await refresh() }
        .overlay {
            if entries.isEmpty {
                if let error {
                    ContentUnavailableView {
                        Label("Couldn't load What's New", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Try Again") { Task { await refresh() } }.buttonStyle(.glass)
                    }
                } else if !loaded {
                    ProgressView()
                }
            }
        }
    }
}

struct RecentList: View {
    let updates: [RecentUpdate]
    let error: String?
    let loaded: Bool
    let refresh: () async -> Void

    private var groups: [(String, [RecentUpdate])] {
        var order: [String] = []
        var by: [String: [RecentUpdate]] = [:]
        for u in updates {
            if by[u.date] == nil { order.append(u.date) }
            by[u.date, default: []].append(u)
        }
        return order.map { ($0, by[$0]!) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    SerifNumeral(text: updates.count.formatted(), unit: updates.count == 1 ? "page touched" : "pages touched", size: 30)
                    Text("Every page with a new \"last updated\" date this month and last — major rewrites and small fixes alike.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
            }
            ForEach(groups, id: \.0) { date, items in
                Section {
                    ForEach(items) { u in
                        NavigationLink(value: u.page) { PageRow(page: u.page) }
                            .contextMenu { PageMenu(page: u.page) }
                    }
                } header: {
                    SectionLabel(text: date)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await refresh() }
        .overlay {
            if updates.isEmpty {
                if let error {
                    ContentUnavailableView {
                        Label("Couldn't load recent updates", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Try Again") { Task { await refresh() } }.buttonStyle(.glass)
                    }
                } else if !loaded {
                    ProgressView()
                }
            }
        }
    }
}
