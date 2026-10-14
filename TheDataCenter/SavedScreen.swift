//
//  SavedScreen.swift
//  The Data Center
//
//  Bookmarked records, kept on this device.
//

import SwiftUI

struct SavedScreen: View {
    @Environment(SavedStore.self) private var saved

    var body: some View {
        NavigationStack {
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
                    ContentUnavailableView("Nothing saved yet", systemImage: "bookmark",
                                           description: Text("Tap the bookmark on any record to keep it here. Saved items stay on this device."))
                }
            }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !saved.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", role: .destructive) { Haptics.tap(); saved.removeAll() }
                    }
                }
            }
            .dataCenterDestinations()
        }
    }
}
