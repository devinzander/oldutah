//
//  SavedScreen.swift
//  Old Utah
//
//  Everything kept on this device, in one tab: library records, railroad
//  pages and graves.
//

import SwiftUI
import RailsKit
import CemeteryKit

struct SavedScreen: View {
    @AppStorage("savedArchive") private var archive: Archive = .library

    var body: some View {
        NavigationStack {
            Group {
                switch archive {
                case .library: LibrarySavedList()
                case .railroads: RailsSavedList()
                case .graves: CemeterySavedList()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Show", selection: $archive) {
                    ForEach(Archive.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .onChange(of: archive) { Haptics.select() }
            }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
            .dataCenterDestinations()
        }
    }
}

/// Bookmarked library records.
struct LibrarySavedList: View {
    @Environment(SavedStore.self) private var saved

    var body: some View {
        List {
            if !saved.items.isEmpty {
                Section {
                    SerifNumeral(text: saved.items.count.formatted(),
                                 unit: saved.items.count == 1 ? "item" : "items", size: 30)
                        .listRowSeparator(.hidden)
                }
            }
            ForEach(Array(saved.items.enumerated()), id: \.element.id) { i, item in
                NavigationLink(value: ItemPage(hits: saved.items.map(\.hit), index: i)) { HitRow(hit: item.hit) }
                    .contextMenu { HitMenu(hit: item.hit) }
                    .swipeActions {
                        Button(role: .destructive) { saved.remove(item.id) } label: {
                            Label("Remove", systemImage: "bookmark.slash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .overlay {
            if saved.items.isEmpty {
                ContentUnavailableView("No library records yet", systemImage: "bookmark",
                                       description: Text("Tap the bookmark on any record to keep it here. Saved items stay on this device."))
            }
        }
        .toolbar {
            if !saved.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) { Haptics.tap(); saved.removeAll() }
                }
            }
        }
    }
}
