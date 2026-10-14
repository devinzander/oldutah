//
//  ItemView.swift
//  The Data Center
//
//  One record: the image, PDF, audio or video the site serves, the full
//  metadata table, the reference (ARK) link and download. Scans save to
//  Photos and share as images in one tap; everything else shares its link.
//

import SwiftUI
import AVKit
import PDFKit

struct ItemView: View {
    let id: Int
    /// The list row that opened this record — shown while the page loads.
    var seed: SearchHit? = nil
    /// False for the off-screen neighbours in the swipe pager, so only the
    /// visible record contributes toolbar buttons.
    var isActive = true

    @Environment(CatalogStore.self) private var catalog
    @Environment(SavedStore.self) private var saved
    @Environment(\.openURL) private var openURL
    @State private var record: ItemRecord?
    @State private var error: String?
    @State private var fullscreen = false
    /// The full-resolution scan, fetched once for display, Photos and sharing.
    @State private var fullImage: UIImage?
    @State private var saving = false
    @State private var toast: Toast?

    private var isSaved: Bool { saved.isSaved(id) }
    private var title: String { record?.title ?? seed?.title ?? "" }
    private var shareURL: URL {
        record?.referenceURL ?? UDL.base.appendingPathComponent("details")
            .appending(queryItems: [URLQueryItem(name: "id", value: String(id))])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                media
                titleBlock
                if let record {
                    actions(record)
                    if let description = record.description {
                        Text(description)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    metadata(record)
                    footer(record)
                } else if let error {
                    ContentUnavailableView {
                        Label("Couldn't load the record", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Try Again") { Task { await load() } }.buttonStyle(.bordered)
                    }
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 30)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        // A solid edge under the bar: the scan scrolls behind a clean line
        // instead of showing through the glass.
        .scrollEdgeEffectStyle(.hard, for: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isActive {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        saved.toggle(record?.asHit ?? seed ?? SearchHit(id: id, title: "Item \(id)", date: "", type: "", setname: "", thumbnail: nil))
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    }
                    .accessibilityLabel(isSaved ? "Remove from Saved" : "Save")
                    shareLink
                }
            }
        }
        .overlay(alignment: .bottom) { toastView }
        .fullScreenCover(isPresented: $fullscreen) {
            if let record {
                MediaFullscreen(record: record, image: fullImage, onSave: { await saveToPhotos() })
            }
        }
        .task(id: id) { await load() }
    }

    private func load() async {
        error = nil
        do {
            let r = try await UDLClient.shared.item(id)
            record = r
            if case .image(let url) = r.media {
                fullImage = await PhotoSaver.image(at: url)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Share & save

    /// Scans share as the image itself (with the reference link in the
    /// message); everything else shares its permanent link.
    @ViewBuilder
    private var shareLink: some View {
        if let ui = fullImage {
            ShareLink(item: Image(uiImage: ui),
                      subject: Text(title),
                      message: Text("\(title)\n\(shareURL.absoluteString)"),
                      preview: SharePreview(title, image: Image(uiImage: ui)))
        } else {
            ShareLink(item: shareURL, subject: Text(title), message: Text(title))
        }
    }

    private func saveToPhotos() async {
        guard let ui = fullImage, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            try await PhotoSaver.save(ui)
            Haptics.success()
            show(Toast(text: "Saved to Photos", systemImage: "checkmark.circle.fill"))
        } catch {
            Haptics.failure()
            show(Toast(text: error.localizedDescription, systemImage: "exclamationmark.triangle.fill"))
        }
    }

    private func show(_ t: Toast) {
        withAnimation(.snappy) { toast = t }
        Task {
            try? await Task.sleep(for: .seconds(t.text.count > 40 ? 4 : 1.8))
            if toast == t { withAnimation(.easeOut) { toast = nil } }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            HStack(spacing: 8) {
                Image(systemName: toast.systemImage)
                    .foregroundStyle(toast.systemImage.hasPrefix("checkmark") ? Brand.field : Brand.clay)
                Text(toast.text)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassCapsule()
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var media: some View {
        let type = record?.type ?? seed?.type
        switch record?.media {
        case .image:
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let ui = fullImage {
                        Image(uiImage: ui).resizable().scaledToFit()
                    } else {
                        // The listing thumbnail bridges the wait for the full scan.
                        AsyncImage(url: record?.thumbnail ?? seed?.thumbnail) { p in
                            if let img = p.image { img.resizable().scaledToFit().blur(radius: 1) }
                            else { Brand.paper.frame(height: 260) }
                        }
                        .overlay { ProgressView() }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 460)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture { Haptics.tap(); fullscreen = true }
                .contextMenu { imageMenu }
                GlassCircleButton(systemName: "arrow.up.left.and.arrow.down.right", filled: true) {
                    fullscreen = true
                }
                .accessibilityLabel("View full screen")
                .padding(10)
            }
            .padding(.top, 4)
        case .pdf(let url):
            ZStack(alignment: .bottomTrailing) {
                PDFKitView(url: url)
                    .frame(height: 480)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
                GlassCircleButton(systemName: "arrow.up.left.and.arrow.down.right", filled: true) {
                    fullscreen = true
                }
                .padding(10)
            }
            .padding(.top, 4)
        case .audio(let url):
            AudioPlayerView(url: url, title: record?.title ?? "")
                .padding(.top, 4)
        case .video(let url):
            VideoPlayer(player: AVPlayer(url: url))
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 4)
        case .some(.none), nil:
            if let thumb = record?.thumbnail ?? seed?.thumbnail {
                AsyncImage(url: thumb) { phase in
                    if let img = phase.image { img.resizable().scaledToFit() }
                    else { Brand.paper.frame(height: 200) }
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 4)
                .overlay(alignment: .bottomLeading) {
                    if record != nil {
                        Text(Brand.typeSymbol(type) == "archivebox" ? "No online preview" : "Preview only")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .glassCapsule()
                            .padding(10)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var imageMenu: some View {
        if let ui = fullImage {
            Button { Task { await saveToPhotos() } } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
            }
            ShareLink(item: Image(uiImage: ui), subject: Text(title),
                      message: Text("\(title)\n\(shareURL.absoluteString)"),
                      preview: SharePreview(title, image: Image(uiImage: ui))) {
                Label("Share Image", systemImage: "square.and.arrow.up")
            }
            Button {
                UIPasteboard.general.image = ui
                Haptics.success()
                show(Toast(text: "Copied", systemImage: "checkmark.circle.fill"))
            } label: {
                Label("Copy Image", systemImage: "doc.on.doc")
            }
        }
        ShareLink(item: shareURL, subject: Text(title), message: Text(title)) {
            Label("Share Link", systemImage: "link")
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .textSelection(.enabled)
            HStack(spacing: 8) {
                let type = record?.type ?? seed?.type
                if let type, !type.isEmpty {
                    Chip(label: Brand.typeLabel(type), color: Brand.typeColor(type), systemImage: Brand.typeSymbol(type))
                }
                if let date = record?.date ?? seed?.date, !date.isEmpty {
                    Text(date.replacingOccurrences(of: ";", with: " ·"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let setname = record?.collectionSetname ?? seed?.setname, !setname.isEmpty {
                let name = record?.collectionTitle ?? catalog.title(forSetname: setname)
                if let c = catalog.collection(setname) {
                    NavigationLink(value: c) { collectionLine(name) }.buttonStyle(.plain)
                } else {
                    NavigationLink(value: ResultsRoute(title: name, subtitle: nil,
                                                       query: SearchQuery(filters: [FacetFilter(field: "facet_setname_s", value: setname, label: name)]))) {
                        collectionLine(name)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func collectionLine(_ name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "books.vertical").font(.caption)
            Text(name).font(.subheadline.weight(.medium))
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
        }
        .foregroundStyle(Brand.accent)
    }

    /// One full-width action: Save to Photos for scans, Download for
    /// documents and recordings. Sharing lives in the toolbar only.
    @ViewBuilder
    private func actions(_ record: ItemRecord) -> some View {
        if case .image = record.media {
            Button {
                Task { await saveToPhotos() }
            } label: {
                Label(saving ? "Saving…" : "Save to Photos", systemImage: "square.and.arrow.down")
                    .lineLimit(1)
            }
            .buttonStyle(PrimaryButton())
            .disabled(fullImage == nil || saving)
        } else if let dl = record.downloadURL {
            Button {
                openURL(dl)
            } label: {
                Label(record.downloadSize.map { "Download · \($0)" } ?? "Download", systemImage: "arrow.down.circle")
                    .lineLimit(1)
            }
            .buttonStyle(PrimaryButton())
        }
    }

    private func metadata(_ record: ItemRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Record")
                .padding(.bottom, 6)
            ForEach(record.fields.filter { $0.field != "description_t" && $0.field != "title_t" }) { f in
                VStack(alignment: .leading, spacing: 3) {
                    Text(f.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let link = f.link {
                        Button { openURL(link) } label: {
                            Text(f.value)
                                .font(.callout)
                                .foregroundStyle(Brand.accent)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                    } else if f.field == "subject_t" || f.field == "spatial_coverage_t" || f.field == "keywords_t" {
                        subjectLinks(f)
                    } else {
                        Text(f.value)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9)
                Divider()
            }
        }
    }

    /// Subjects and places search the archive on tap, as the site's do.
    private func subjectLinks(_ f: ItemField) -> some View {
        let terms = f.value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return FlowLayout(spacing: 6) {
            ForEach(terms, id: \.self) { term in
                NavigationLink(value: ResultsRoute(title: term, subtitle: f.label, query: SearchQuery(text: "\"\(term)\""))) {
                    Text(term)
                        .font(.callout)
                        .foregroundStyle(Brand.accent)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Brand.accent.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func footer(_ record: ItemRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let ref = record.referenceURL {
                Text("Reference URL")
                    .font(.caption).foregroundStyle(.secondary)
                Text(ref.absoluteString)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Brand.accent)
                    .textSelection(.enabled)
            }
            Button {
                openURL(record.webURL)
            } label: {
                Label("Open on collections.lib.utah.edu", systemImage: "safari")
                    .font(.footnote.weight(.medium))
            }
            .padding(.top, 2)
            Text("Held and digitized by \(record.value("contributing_institution_t") ?? record.collectionTitle ?? "the contributing institution"); served by the J. Willard Marriott Library, University of Utah.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
    }
}

// MARK: - Fullscreen media

struct MediaFullscreen: View {
    let record: ItemRecord
    var image: UIImage?
    var onSave: () async -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch record.media {
            case .image(let url):
                ZoomableImage(url: url, preloaded: image).ignoresSafeArea()
            case .pdf(let url):
                PDFKitView(url: url).ignoresSafeArea(edges: .bottom)
            default:
                EmptyView()
            }
        }
        // Close and share up top; Save to Photos sits bottom-right, under
        // the thumb.
        .overlay(alignment: .top) {
            HStack {
                GlassCircleButton(systemName: "xmark") { dismiss() }
                Spacer()
                if let image {
                    ShareLink(item: Image(uiImage: image), subject: Text(record.title),
                              message: Text("\(record.title)\n\(record.referenceURL?.absoluteString ?? record.webURL.absoluteString)"),
                              preview: SharePreview(record.title, image: Image(uiImage: image))) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .medium))
                            .offset(y: Brand.glyphNudge("square.and.arrow.up"))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                }
            }
            .padding(16)
        }
        .overlay(alignment: .bottomTrailing) {
            if image != nil {
                GlassCircleButton(systemName: saved ? "checkmark" : "square.and.arrow.down", filled: true) {
                    Task {
                        await onSave()
                        withAnimation { saved = true }
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation { saved = false }
                    }
                }
                .accessibilityLabel("Save to Photos")
                .padding(16)
            }
        }
        .statusBarHidden()
    }
}

/// Pinch-to-zoom scan viewer (UIScrollView — SwiftUI's magnification
/// gestures don't pan-while-zoomed as smoothly).
struct ZoomableImage: UIViewRepresentable {
    let url: URL
    var preloaded: UIImage?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
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
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let scroll = g.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = g.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 3, height: scroll.bounds.height / 3)
                scroll.zoom(to: CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size), animated: true)
            }
        }
    }
}

/// PDFKit reader for the site's scanned documents.
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url), let doc = PDFDocument(data: data) {
                await MainActor.run { view.document = doc }
            }
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

/// Oral histories and recordings: a card with play/pause and a scrubber.
struct AudioPlayerView: View {
    let url: URL
    let title: String
    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var progress: Double = 0
    @State private var duration: Double = 0
    @State private var observer: Any?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Button {
                        Haptics.tap()
                        toggle()
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Brand.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel(text: "Recording")
                        Text(title)
                            .font(.system(.headline, design: .serif))
                            .lineLimit(2)
                    }
                }
                Slider(value: Binding(get: { progress },
                                      set: { v in progress = v; seek(to: v) }),
                       in: 0...max(duration, 1))
                .tint(Brand.accent)
                HStack {
                    Text(time(progress)).monospacedDigit()
                    Spacer()
                    Text(time(duration)).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onAppear { setup() }
        .onDisappear {
            player?.pause()
            if let observer { player?.removeTimeObserver(observer) }
            observer = nil
        }
    }

    private func setup() {
        guard player == nil else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        let p = AVPlayer(url: url)
        player = p
        observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { t in
            progress = t.seconds
            if let d = p.currentItem?.duration.seconds, d.isFinite { duration = d }
            playing = p.timeControlStatus == .playing
        }
    }

    private func toggle() {
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if playing { player.pause() } else { player.play() }
        playing.toggle()
    }

    private func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    private func time(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
