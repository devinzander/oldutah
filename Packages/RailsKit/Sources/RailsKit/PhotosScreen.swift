//
//  PhotosScreen.swift
//  Utah Rails
//
//  Don Strack's photo albums on SmugMug, natively: folders and albums with
//  their cover photos, album grids that page in as you scroll, and a
//  zoomable viewer with the caption, keywords, Save to Photos and sharing.
//  A SmugMug link met anywhere in an article lands here too.
//

import SwiftUI
import UIKit

/// The album root, pushed from the Railroads index.
struct PhotosScreen: View {
    var body: some View {
        SmugFolderScreen(node: SmugNode(nodeID: "kXkRj", name: "Photos", type: .folder, urlPath: Smug.rootPath,
                                        description: "", dateModified: "", hasChildren: true, albumKey: nil, highlight: nil),
                         isRoot: true)
    }
}

// MARK: - Folder

struct SmugFolderScreen: View {
    let node: SmugNode
    var isRoot = false

    @State private var nodes: [SmugNode] = []
    @State private var error: String?
    @State private var loaded = false
    @State private var filter = ""

    private var folders: [SmugNode] { visible.filter { $0.type == .folder } }
    private var albums: [SmugNode] { visible.filter { $0.type == .album } }
    private var visible: [SmugNode] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nodes }
        return nodes.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.description.localizedCaseInsensitiveContains(q) }
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if isRoot && filter.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Don Strack's photo albums.")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                        Text("Historical photos, scanned maps, timetables, equipment diagrams and detail shots for modelers, hosted on SmugMug and shown here natively.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if !node.description.isEmpty && filter.isEmpty {
                    Text(node.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !folders.isEmpty {
                    SectionLabel(text: "Folders")
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(folders) { n in
                            NavigationLink(value: n) { NodeTile(node: n) }.buttonStyle(.plain)
                        }
                    }
                }
                if !albums.isEmpty {
                    SectionLabel(text: "Albums")
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(albums) { n in
                            NavigationLink(value: SmugAlbum(albumKey: n.albumKey ?? "", nodeID: n.nodeID, name: n.name, description: n.description,
                                                            imageCount: 0, urlPath: n.urlPath, lastUpdated: n.dateModified)) {
                                NodeTile(node: n)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle(node.name)
        .navigationBarTitleDisplayMode(isRoot ? .large : .large)
        .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Filter albums")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Link(destination: node.webURL) { Image(systemName: "safari") }
                    .accessibilityLabel("Open on SmugMug")
            }
        }
        .overlay {
            if nodes.isEmpty {
                if let error {
                    ContentUnavailableView {
                        Label("Couldn't load the albums", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Try Again") { Task { await load() } }.buttonStyle(.glass)
                        Link("Open on SmugMug", destination: node.webURL)
                    }
                } else if !loaded {
                    ProgressView()
                }
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: filter)
            }
        }
        .refreshable { await load() }
        .task { if !loaded { await load() } }
    }

    private func load() async {
        error = nil
        do {
            var all: [SmugNode] = []
            var start: Int? = 1
            while let s = start {
                let page = try await SmugClient.shared.children(of: node.nodeID, start: s, count: 100)
                all += page.items
                start = page.next
                if all.count > 1000 { break }
            }
            nodes = all
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct NodeTile: View {
    let node: SmugNode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Thumb(url: node.highlight.map { SmugImage.sized($0, "M") }, cornerRadius: 12, symbol: node.type == .folder ? "folder" : "photo")
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if node.type == .folder {
                        Image(systemName: "folder.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.35), in: Circle())
                            .padding(8)
                    }
                }
            Text(node.name)
                .font(.system(.subheadline, design: .serif, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !node.dateModified.isEmpty {
                Text(node.dateModified.isoDateLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

extension SmugImage {
    /// Size-substitute any SmugMug photo URL (thumbnail form).
    static func sized(_ url: URL, _ size: String) -> URL {
        let s = url.absoluteString
            .replacingOccurrences(of: "/Th/", with: "/\(size)/")
            .replacingOccurrences(of: "-Th.", with: "-\(size).")
        return URL(string: s) ?? url
    }
}

// MARK: - Album

struct SmugAlbumScreen: View {
    let album: SmugAlbum

    @State private var meta: SmugAlbum?
    @State private var images: [SmugImage] = []
    @State private var next: Int? = 1
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var pager: PagerStart?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 3)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    if total > 0 {
                        SerifNumeral(text: total.formatted(), unit: total == 1 ? "photo" : "photos", size: 30)
                    }
                    if let d = meta?.description ?? (album.description.isEmpty ? nil : album.description), !d.isEmpty {
                        Text(d).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let u = meta?.lastUpdated, !u.isEmpty {
                        Text("Updated \(u.isoDateLabel)").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 20)

                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                        Button {
                            Haptics.tap()
                            pager = PagerStart(index: index)
                        } label: {
                            Thumb(url: image.url(size: "S"), cornerRadius: 4)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(alignment: .bottomTrailing) {
                                    if image.isVideo {
                                        Image(systemName: "play.fill").font(.caption).foregroundStyle(.white).padding(6)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            NavigationLink(value: image) { Label("Details", systemImage: "info.circle") }
                            PhotoMenu(image: image)
                        }
                        .onAppear {
                            if image.id == images.last?.id { Task { await loadMore() } }
                        }
                    }
                }
                .padding(.horizontal, 3)

                if loading && !images.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding()
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle(meta?.name ?? album.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: album.webURL, subject: Text(album.name), message: Text(album.name)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Link(destination: album.webURL) { Image(systemName: "safari") }
                    .accessibilityLabel("Open on SmugMug")
            }
        }
        .overlay {
            if images.isEmpty {
                if let error {
                    ContentUnavailableView {
                        Label("Couldn't load the album", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Try Again") { Task { await loadMore() } }.buttonStyle(.glass)
                        Link("Open on SmugMug", destination: album.webURL)
                    }
                } else if loading {
                    ProgressView()
                }
            }
        }
        .fullScreenCover(item: $pager) { start in
            PhotoPager(images: $images, start: start.index, title: meta?.name ?? album.name, hasMore: next != nil) {
                await loadMore()
            }
        }
        .task {
            if images.isEmpty {
                async let m: SmugAlbum? = try? SmugClient.shared.album(key: album.albumKey)
                await loadMore()
                meta = await m
            }
        }
    }

    private func loadMore() async {
        guard !loading, let start = next else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let page = try await SmugClient.shared.images(album: album.albumKey, start: start, count: 60)
            images += page.items
            total = page.total
            next = page.next
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Resolves a SmugMug web link (folder, album or single photo) to its
/// native screen.
struct SmugLinkScreen: View {
    let link: SmugLink
    @State private var lookup: SmugClient.Lookup?
    @State private var image: SmugImage?
    @State private var error: String?

    var body: some View {
        Group {
            if let image {
                PhotoScreen(image: image)
            } else if let lookup {
                switch lookup {
                case .album(let a): SmugAlbumScreen(album: a)
                case .folder(let f): SmugFolderScreen(node: f)
                }
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't open the album", systemImage: "wifi.exclamationmark")
                } description: { Text(error) } actions: {
                    Button("Try Again") { Task { await resolve() } }.buttonStyle(.glass)
                    Link("Open on SmugMug", destination: link.url)
                }
            } else {
                ProgressView()
            }
        }
        .task { await resolve() }
    }

    private func resolve() async {
        error = nil
        do {
            if let key = link.imageKey {
                image = try await SmugClient.shared.image(key: key)
            } else {
                lookup = try await SmugClient.shared.lookup(path: link.nodePath.isEmpty ? Smug.rootPath : link.nodePath)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - One photo

struct PhotoScreen: View {
    let image: SmugImage

    @State private var full: UIImage?
    @State private var saving = false
    @State private var toast: Toast?
    @State private var fullscreen = false

    /// Big enough for a phone or iPad at full zoom, without the multi-MB
    /// originals of the scanned maps.
    private var viewURL: URL { image.url(size: max(image.width, image.height) > 2048 ? "X3" : "X2") }
    private var webURL: URL { URL(string: "https://donstrack.smugmug.com/UtahRails/i-\(image.imageKey)")! }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    Brand.paper
                    if let full {
                        Image(uiImage: full).resizable().scaledToFit()
                    } else {
                        AsyncImage(url: image.url(size: "L")) { phase in
                            if let img = phase.image { img.resizable().scaledToFit() } else { ProgressView() }
                        }
                    }
                }
                .aspectRatio(image.aspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    GlassCircleButton(systemName: "arrow.up.left.and.arrow.down.right") { fullscreen = true }
                        .padding(10)
                }
                .onTapGesture { Haptics.tap(); fullscreen = true }

                VStack(alignment: .leading, spacing: 8) {
                    Text(image.headline)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .textSelection(.enabled)
                    if !image.caption.isEmpty && image.caption != image.headline {
                        Text(image.caption)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    if !image.realKeywords.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(image.realKeywords, id: \.self) { k in
                                Chip(label: k, color: Brand.sepia)
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await save() }
                    } label: {
                        Label(saving ? "Saving…" : "Save to Photos", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(PrimaryButton())
                    .disabled(saving || full == nil)
                    if let full {
                        ShareLink(item: Image(uiImage: full), subject: Text(image.headline), message: Text(image.headline),
                                  preview: SharePreview(image.headline, image: Image(uiImage: full))) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(SecondaryButton())
                    } else {
                        ShareLink(item: webURL, subject: Text(image.headline), message: Text(image.headline)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(SecondaryButton())
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Details")
                    LabeledContent("File", value: image.fileName)
                    if image.width > 0 { LabeledContent("Size", value: "\(image.width) × \(image.height)") }
                    if !image.date.isEmpty { LabeledContent("Uploaded", value: image.date.isoDateLabel) }
                    Link(destination: webURL) {
                        Label("Open on SmugMug", systemImage: "safari")
                    }
                    .padding(.top, 4)
                }
                .font(.subheadline)

                Text("Photo from Don Strack's UtahRails albums on SmugMug. Rights belong to the photographer or collection named in the caption.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
        .fullScreenCover(isPresented: $fullscreen) {
            PhotoFullscreen(image: image, preloaded: full, url: viewURL) { await save() }
        }
        .task { full = await PhotoSaver.image(at: viewURL) }
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        // Save the original scan when it's there; fall back to what's on screen.
        let original = await PhotoSaver.image(at: image.url(size: "O")) ?? full
        guard let ui = original else { toast = Toast(text: "Couldn't fetch the photo", symbol: "xmark"); return }
        do {
            try await PhotoSaver.save(ui)
            Haptics.success()
            toast = Toast(text: "Saved to Photos", symbol: "checkmark")
        } catch {
            Haptics.failure()
            toast = Toast(text: error.localizedDescription, symbol: "xmark")
        }
    }
}

struct PhotoMenu: View {
    let image: SmugImage
    var body: some View {
        ShareLink(item: URL(string: "https://donstrack.smugmug.com/UtahRails/i-\(image.imageKey)")!, subject: Text(image.headline)) {
            Label("Share Link", systemImage: "square.and.arrow.up")
        }
    }
}

struct PhotoFullscreen: View {
    let image: SmugImage
    let preloaded: UIImage?
    let url: URL
    let onSave: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chrome = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ZoomableImage(url: url, preloaded: preloaded)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { chrome.toggle() } }
            if chrome {
                VStack {
                    HStack {
                        Spacer()
                        GlassCircleButton(systemName: "xmark", size: 34) { dismiss() }
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Text(image.headline)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassCapsule()
                        Spacer()
                        GlassCircleButton(systemName: "square.and.arrow.down", filled: true, size: 34) { Task { await onSave() } }
                    }
                }
                .padding(16)
            }
        }
        .statusBarHidden(!chrome)
    }
}

/// Pinch-zoom image viewer.
struct ZoomableImage: UIViewRepresentable {
    let url: URL
    var preloaded: UIImage?
    var onZoomChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator { let c = Coordinator(); c.onZoomChange = onZoomChange; return c }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 8
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .black
        scroll.contentInsetAdjustmentBehavior = .never
        let image = UIImageView()
        image.contentMode = .scaleAspectFit
        image.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(image)
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            image.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            image.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            image.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            image.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            image.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.imageView = image
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        if let preloaded {
            image.image = preloaded
        } else {
            let spinner = UIActivityIndicatorView(style: .large)
            spinner.color = .white
            spinner.startAnimating()
            spinner.translatesAutoresizingMaskIntoConstraints = false
            scroll.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerYAnchor),
            ])
            Task {
                let ui = await PhotoSaver.image(at: url)
                await MainActor.run {
                    image.image = ui
                    spinner.removeFromSuperview()
                }
            }
        }
        return scroll
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {}

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var onZoomChange: ((Bool) -> Void)?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { onZoomChange?(scrollView.zoomScale > 1.01) }
        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let scroll = g.view as? UIScrollView else { return }
            if scroll.zoomScale > 1 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let p = g.location(in: imageView)
                let w = scroll.bounds.width / 3, h = scroll.bounds.height / 3
                scroll.zoom(to: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), animated: true)
            }
        }
    }
}


// MARK: - Swipe-through viewer

struct PagerStart: Identifiable {
    let index: Int
    var id: Int { index }
}

/// Fullscreen, swipe between photos, pinch to zoom, tap for the chrome —
/// the Photos app's viewer, for an album.
struct PhotoPager: View {
    @Binding var images: [SmugImage]
    let start: Int
    let title: String
    let hasMore: Bool
    let loadMore: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var chrome = true
    @State private var zoomed = false
    @State private var saving = false
    @State private var toast: Toast?
    @State private var showDetails = false
    @State private var dragOffset: CGFloat = 0
    @State private var captionExpanded = false

    init(images: Binding<[SmugImage]>, start: Int, title: String, hasMore: Bool, loadMore: @escaping () async -> Void) {
        _images = images
        self.start = start
        self.title = title
        self.hasMore = hasMore
        self.loadMore = loadMore
        _index = State(initialValue: start)
    }

    private var current: SmugImage? { images.indices.contains(index) ? images[index] : nil }

    private static func viewURL(_ image: SmugImage) -> URL {
        image.url(size: max(image.width, image.height) > 2048 ? "X3" : "X2")
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(images.enumerated()), id: \.element.id) { i, image in
                    ZoomableImage(url: Self.viewURL(image)) { z in
                        if i == index { zoomed = z }
                    }
                    .ignoresSafeArea()
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: dragOffset)
            .opacity(1 - Double(min(abs(dragOffset) / 600, 0.5)))
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { v in
                        guard !zoomed, abs(v.translation.height) > abs(v.translation.width) * 1.5 else { return }
                        dragOffset = v.translation.height
                    }
                    .onEnded { v in
                        if !zoomed, dragOffset > 110 || v.predictedEndTranslation.height > 300 {
                            dismiss()
                        } else {
                            withAnimation(.spring(duration: 0.3)) { dragOffset = 0 }
                        }
                    }
            )
            .onTapGesture { withAnimation { chrome.toggle() } }
            .onChange(of: index) {
                zoomed = false
                captionExpanded = false
                Haptics.select()
                if hasMore, index >= images.count - 6 { Task { await loadMore() } }
            }

            if chrome {
                VStack {
                    HStack(alignment: .top) {
                        GlassCircleButton(systemName: "xmark", size: 34) { dismiss() }
                        Spacer()
                        VStack(spacing: 2) {
                            Text(title)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                            Text("\(index + 1) of \(images.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .glassCapsule()
                        Spacer()
                        GlassCircleButton(systemName: "info", size: 34) { showDetails = true }
                    }
                    Spacer()
                    if let current {
                        // Caption on the left; share as a circle top-right, Save bottom-right.
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 12) {
                                // Tap the caption to read all of it.
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(current.headline)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(captionExpanded ? 6 : 2)
                                    if !current.caption.isEmpty && current.caption != current.headline {
                                        Text(current.caption)
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.85))
                                            .lineLimit(captionExpanded ? 14 : 3)
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Haptics.tap()
                                    withAnimation(.spring(duration: 0.3)) { captionExpanded.toggle() }
                                }
                                Spacer(minLength: 0)
                                ShareLink(item: URL(string: "https://donstrack.smugmug.com/UtahRails/i-\(current.imageKey)")!, subject: Text(current.headline)) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 15, weight: .medium))
                                        .frame(width: 30, height: 30)
                                }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.circle)
                                .accessibilityLabel("Share")
                            }
                            HStack {
                                Spacer()
                                Button {
                                    Task { await save(current) }
                                } label: {
                                    Group {
                                        if saving {
                                            ProgressView().tint(.white)
                                        } else {
                                            Image(systemName: "square.and.arrow.down")
                                                .font(.system(size: 15, weight: .medium))
                                        }
                                    }
                                    .frame(width: 30, height: 30)
                                }
                                .buttonStyle(.glassProminent)
                                .tint(Brand.accentRail)
                                .buttonBorderShape(.circle)
                                .disabled(saving)
                                .accessibilityLabel("Save to Photos")
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: 18)
                        .environment(\.colorScheme, .dark)
                    }
                }
                .padding(16)
                .transition(.opacity)
            }
        }
        .statusBarHidden(!chrome)
        .toast($toast)
        .sheet(isPresented: $showDetails) {
            if let current {
                NavigationStack {
                    PhotoScreen(image: current)
                        .utahRailsDestinations()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { showDetails = false } }
                        }
                }
            }
        }
    }

    private func save(_ image: SmugImage) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        var ui = await PhotoSaver.image(at: image.url(size: "O"))
        if ui == nil { ui = await PhotoSaver.image(at: Self.viewURL(image)) }
        guard let ui else { toast = Toast(text: "Couldn't fetch the photo", symbol: "xmark"); return }
        do {
            try await PhotoSaver.save(ui)
            Haptics.success()
            toast = Toast(text: "Saved to Photos", symbol: "checkmark")
        } catch {
            Haptics.failure()
            toast = Toast(text: error.localizedDescription, symbol: "xmark")
        }
    }
}
