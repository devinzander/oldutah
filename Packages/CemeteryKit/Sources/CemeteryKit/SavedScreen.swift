//
//  SavedScreen.swift
//  Old Utah — Cemeteries
//

import SwiftUI

struct SavedScreen: View {
    @Environment(SavedStore.self) private var saved

    private var groups: [(Cemetery, [SavedGrave])] {
        let byCemetery = Dictionary(grouping: saved.items) { $0.record.cemeteryID }
        return Cemeteries.all.compactMap { c in byCemetery[c.id].map { (c, $0) } }
    }

    var body: some View {
        List {
            if saved.items.isEmpty {
                ContentUnavailableView {
                    Label("No saved graves", systemImage: "bookmark")
                } description: {
                    Text("Bookmark a record and it's kept here, outline and all, for the next visit.")
                }
                .listRowSeparator(.hidden)
            } else {
                ForEach(groups, id: \.0.id) { cemetery, items in
                    Section {
                        ForEach(items) { item in
                            NavigationLink(value: item.record) { GraveRow(record: item.record, showCemetery: false) }
                                .swipeActions {
                                    Button(role: .destructive) { saved.remove(item.id) } label: { Label("Remove", systemImage: "bookmark.slash") }
                                }
                        }
                    } header: {
                        SectionLabel(text: cemetery.name)
                    }
                }
            }
        }
        .listStyle(.plain)
        .toolbar {
            if !saved.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) { saved.removeAll() } label: { Label("Remove all graves", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
    }
}
