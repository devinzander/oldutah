//
//  ArticleScreen.swift
//  Utah Rails
//
//  One page, rendered natively: serif title, the site's "last updated" line,
//  return-to links, then the blocks — headings, paragraphs with live links,
//  block quotes, rosters as tables, lists. Links to other utahrails.net
//  pages push in place; PDFs open in the reader; SmugMug links open the
//  album or photo natively; everything else hands off to Safari.
//

import SwiftUI
import PDFKit

struct ArticleScreen: View {
    let page: PageRef

    @Environment(ArticleStore.self) private var articles
    @Environment(CatalogStore.self) private var catalog
    @Environment(SavedStore.self) private var saved
    @Environment(MapsStore.self) private var railMaps
    @Environment(\.openURL) private var systemOpen
    @State private var article: Article?
    @State private var error: String?
    @State private var pending: PageRef?
    @State private var pendingPDF: PDFRef?
    @State private var pendingSmug: SmugLink?
    @State private var pendingMap: RailMap?
    @State private var scrollTarget: String?
    @State private var toast: Toast?

    private var isSaved: Bool { saved.isSaved(page.path) }
    private var title: String { article?.title ?? page.title }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let article {
                        ArticleBody(blocks: article.blocks)
                        footer(article)
                    } else if let error {
                        ContentUnavailableView {
                            Label("Couldn't load the page", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Try Again") { Task { await load(reload: true) } }
                                .buttonStyle(.glass)
                            Link("Open on utahrails.net", destination: page.url)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .onChange(of: scrollTarget) {
                if let t = scrollTarget {
                    withAnimation { proxy.scrollTo(t, anchor: .top) }
                    scrollTarget = nil
                }
            }
        }
        .navigationTitle(article == nil ? "" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .toast($toast)
        .environment(\.openURL, OpenURLAction { url in handle(url) })
        .navigationDestination(item: $pending) { p in
            if p.isPDF { PDFScreen(pdf: PDFRef(url: p.url, title: p.title)) } else { ArticleScreen(page: p) }
        }
        .navigationDestination(item: $pendingPDF) { PDFScreen(pdf: $0) }
        .navigationDestination(item: $pendingSmug) { SmugLinkScreen(link: $0) }
        .navigationDestination(item: $pendingMap) { RailMapScreen(map: $0) }
        .task(id: page.path) { await load() }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let sub = article?.subtitle {
                Text(sub)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let updated = article?.updated {
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.caption2)
                    Text("Updated \(updated)")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            if let article, !article.returnTo.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(article.returnTo) { r in
                        NavigationLink(value: r) {
                            Label(r.title, systemImage: "arrow.turn.up.left")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    private func footer(_ article: Article) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().padding(.top, 8)
            Text("Written and maintained by Don Strack at UtahRails.net. Utah Rails is an independent reader; the text, tables and photos are his.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Link(destination: article.url) {
                    Label("Open on utahrails.net", systemImage: "safari")
                }
                .buttonStyle(SecondaryButton())
            }
        }
        .padding(.top, 12)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let article, article.headings.contains(where: \.inContents) {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(article.headings.filter(\.inContents)) { h in
                        Button {
                            Haptics.select()
                            scrollTarget = h.anchor
                        } label: {
                            Text(h.level > 2 ? "    " + h.text : h.text)
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Contents")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                saved.toggle(page)
                Haptics.success()
                toast = Toast(text: isSaved ? "Saved" : "Removed", symbol: isSaved ? "bookmark.fill" : "bookmark.slash")
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
            }
            .accessibilityLabel(isSaved ? "Remove from Saved" : "Save")
        }
        ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: page.url, subject: Text(title), message: Text(title)) {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    // MARK: Loading & links

    private func load(reload: Bool = false) async {
        if !reload, let cached = articles.cached(page.path) { article = cached }
        do {
            let a = try await articles.article(page, reload: reload)
            article = a
            error = nil
            saved.noteVisit(PageRef(path: page.path, title: a.title))
        } catch {
            if article == nil { self.error = error.localizedDescription }
        }
    }

    /// Every link in the article's text comes through here.
    private func handle(_ url: URL) -> OpenURLAction.Result {
        Haptics.tap()
        // Same-page anchor.
        if let frag = url.fragment, Site.path(of: url) == page.path || url.absoluteString.hasPrefix("#") {
            if article?.headings.contains(where: { $0.anchor == frag }) == true {
                scrollTarget = frag
                return .handled
            }
        }
        if let path = Site.path(of: url) {
            let lower = path.lowercased()
            if lower.hasSuffix(".pdf") {
                pendingPDF = PDFRef(url: url, title: catalog.title(for: path))
                return .handled
            }
            if lower.hasSuffix(".html") || lower.hasSuffix(".htm") || lower.hasSuffix("/") {
                if path == page.path, let frag = url.fragment {
                    scrollTarget = frag
                    return .handled
                }
                pending = PageRef(path: path, title: catalog.title(for: path))
                return .handled
            }
            return .systemAction
        }
        if Site.isSmugMug(url) {
            pendingSmug = SmugLink(url: url)
            return .handled
        }
        if let m = railMaps.map(for: url) {
            pendingMap = m
            return .handled
        }
        return .systemAction
    }
}

// MARK: - Blocks

struct ArticleBody: View {
    let blocks: [Block]
    var nested = false

    var body: some View {
        LazyVStack(alignment: .leading, spacing: nested ? 10 : 14) {
            ForEach(blocks) { block in
                BlockView(block: block, nested: nested)
            }
        }
    }
}

struct BlockView: View {
    let block: Block
    var nested = false

    var body: some View {
        switch block {
        case .heading(let h):
            HeadingView(heading: h)
                .id(h.anchor)
        case .paragraph(let text):
            Text(text.attributed)
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .tint(Brand.accent)
        case .entry(let date, let body):
            VStack(alignment: .leading, spacing: 4) {
                Text(date)
                    .font(.system(.body, design: .serif, weight: .bold))
                    .foregroundStyle(Brand.ink)
                    .tracking(0.3)
                if !body.isEmpty {
                    Text(body.attributed)
                        .font(.body)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .tint(Brand.accent)
                }
            }
            .padding(.top, 2)
        case .linkRow(let url, let title, let blurb):
            LinkRowView(url: url, title: title, blurb: blurb)
        case .quote(let inner):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5).fill(Brand.gold).frame(width: 3)
                ArticleBody(blocks: inner, nested: true)
            }
            .padding(.leading, 4)
        case .sidebar(let inner):
            ArticleBody(blocks: inner, nested: true)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(ordered ? "\(i + 1)." : "•")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(item.attributed)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.leading, 4)
        case .table(let table):
            TableView(table: table)
        case .image(let url, let alt):
            VStack(alignment: .leading, spacing: 6) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        Brand.paper.frame(height: 160).overlay { ProgressView() }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if !alt.isEmpty {
                    Text(alt).font(.caption).foregroundStyle(.secondary)
                }
            }
        case .rule:
            Divider().padding(.vertical, 4)
        case .pre(let text):
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct HeadingView: View {
    let heading: Heading

    var body: some View {
        switch heading.level {
        case 1, 2:
            Text(heading.text)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case 3:
            Text(heading.text)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        default:
            Text(heading.text)
                .font(.headline)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

/// `<p><a>Title</a> -- description</p>` as a tappable row. Internal pages
/// push; PDFs open the reader; SmugMug opens the album; other sites open
/// Safari.
struct LinkRowView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(MapsStore.self) private var railMaps
    let url: URL
    let title: String
    let blurb: RichText?

    private enum Kind { case page(PageRef), pdf(PDFRef), smug(SmugLink), map(RailMap), external }

    private var kind: Kind {
        if let path = Site.path(of: url) {
            if path.lowercased().hasSuffix(".pdf") { return .pdf(PDFRef(url: url, title: title)) }
            return .page(PageRef(path: path, title: title))
        }
        if Site.isSmugMug(url) { return .smug(SmugLink(url: url)) }
        if let m = railMaps.map(for: url) { return .map(RailMap(title: title, mid: m.mid, blurb: m.blurb, related: m.related, section: m.section)) }
        return .external
    }

    var body: some View {
        switch kind {
        case .page(let p): NavigationLink(value: p) { label(symbol: nil) }.buttonStyle(.plain)
        case .pdf(let p): NavigationLink(value: p) { label(symbol: "doc.richtext") }.buttonStyle(.plain)
        case .smug(let s): NavigationLink(value: s) { label(symbol: "photo.on.rectangle") }.buttonStyle(.plain)
        case .map(let m): NavigationLink(value: m) { label(symbol: "map") }.buttonStyle(.plain)
        case .external: Link(destination: url) { label(symbol: "arrow.up.right") }.buttonStyle(.plain)
        }
    }

    private func label(symbol: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(.body, design: .serif, weight: .semibold))
                        .foregroundStyle(Brand.accent)
                        .multilineTextAlignment(.leading)
                    if let symbol {
                        Image(systemName: symbol).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let blurb {
                    Text(blurb.attributed)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Rosters and data tables. Narrow, short tables render as a grid; wide
/// ones become one card per row with the column heads as labels — the
/// phone-first way to read a 20-column roster.
struct TableView: View {
    let table: TableBlock

    private var compact: Bool {
        table.columnCount <= 4 && table.rows.allSatisfy { $0.allSatisfy { $0.plain.count <= 22 } }
            && (table.header ?? []).allSatisfy { $0.count <= 22 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let caption = table.caption, !caption.isEmpty {
                Text(caption).font(.subheadline.weight(.semibold))
            }
            if compact { grid } else { cards }
        }
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            if let header = table.header {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, h in
                        Text(h.uppercased())
                            .font(.caption2.weight(.semibold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.leading)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell.attributed)
                            .font(.subheadline.monospacedDigit())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var cards: some View {
        VStack(spacing: 8) {
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(row.enumerated()), id: \.offset) { i, cell in
                        if !cell.isEmpty {
                            if let header = table.header, i < header.count, !header[i].isEmpty {
                                if i == 0 {
                                    Text(cell.attributed)
                                        .font(.system(.body, design: .serif, weight: .semibold))
                                } else {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(header[i].uppercased())
                                            .font(.caption2.weight(.semibold))
                                            .tracking(0.8)
                                            .foregroundStyle(.secondary)
                                        Text(cell.attributed)
                                            .font(.subheadline)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            } else {
                                Text(cell.attributed)
                                    .font(i == 0 ? .subheadline.weight(.semibold) : .subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .textSelection(.enabled)
            }
        }
    }
}

// MARK: - PDF reader

struct PDFScreen: View {
    let pdf: PDFRef
    @State private var document: PDFDocument?
    @State private var error: String?
    @State private var fileURL: URL?

    var body: some View {
        Group {
            if let document {
                PDFKitView(document: document)
                    .ignoresSafeArea(edges: .bottom)
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't load the document", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await load() } }.buttonStyle(.glass)
                    Link("Open on utahrails.net", destination: pdf.url)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Fetching the document…").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(pdf.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let fileURL {
                    ShareLink(item: fileURL, subject: Text(pdf.title)) { Image(systemName: "square.and.arrow.up") }
                } else {
                    ShareLink(item: pdf.url, subject: Text(pdf.title), message: Text(pdf.title)) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        error = nil
        do {
            let data = try await SiteClient.shared.data(pdf.url)
            guard let doc = PDFDocument(data: data) else { error = "That file isn't a readable PDF."; return }
            document = doc
            // A named copy so sharing carries the file name.
            let name = pdf.url.lastPathComponent.isEmpty ? "document.pdf" : pdf.url.lastPathComponent
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? data.write(to: tmp, options: .atomic)
            fileURL = tmp
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document { uiView.document = document }
    }
}

/// Wrapping row of capsules.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
