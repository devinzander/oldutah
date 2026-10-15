//
//  SavedScreen.swift
//  Old Utah — Railroads
//
//  Bookmarked pages and the pages you've read, on this device only. Shown
//  inside the app's shared Saved tab, so it brings no navigation stack.
//

import SwiftUI

struct SavedScreen: View {
    @Environment(SavedStore.self) private var saved

    private var recent: [SavedPage] { Array(saved.history.prefix(20)) }

    var body: some View {
        List {
            if !saved.items.isEmpty {
                Section {
                    ForEach(saved.items) { item in
                        NavigationLink(value: item.page) {
                            PageRow(page: item.page, subtitle: item.savedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        .contextMenu { PageMenu(page: item.page) }
                        .swipeActions {
                            Button(role: .destructive) { saved.remove(item.id) } label: {
                                Label("Remove", systemImage: "bookmark.slash")
                            }
                        }
                    }
                } header: {
                    SectionLabel(text: "Saved pages")
                }
            }
            if !recent.isEmpty {
                Section {
                    ForEach(recent) { item in
                        NavigationLink(value: item.page) {
                            PageRow(page: item.page, subtitle: item.savedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        .contextMenu { PageMenu(page: item.page) }
                    }
                    Button("Clear reading history", role: .destructive) {
                        Haptics.tap()
                        saved.clearHistory()
                    }
                    .font(.subheadline)
                } header: {
                    SectionLabel(text: "Recently read")
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if saved.items.isEmpty && recent.isEmpty {
                ContentUnavailableView("No railroad pages yet", systemImage: "bookmark",
                                       description: Text("Tap the bookmark on any railroad page to keep it here. Pages you open are listed too. Everything stays on this device."))
            }
        }
    }
}
