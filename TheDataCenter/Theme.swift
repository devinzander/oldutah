//
//  Theme.swift
//  The Data Center
//
//  Editorial register carried over from Plat of Zion: serif display type,
//  warm ink, one accent, Liquid Glass controls. Button styles are ported
//  verbatim (PrimaryButton, the glass circle control, the tinted chips).
//

import SwiftUI
import UIKit

extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

enum Brand {
    /// Utah red — the University's own.
    static let accent = Color(hex: 0xBE2A1F)
    /// Navy for the still-image chip so the accent stays the app's alone.
    static let navy   = Color(hex: 0x2C4A6E)
    /// The accent softened a step, for the secondary action buttons
    /// (same relationship as Plat of Zion's rail tint).
    static let accentRail = accent.opacity(0.8)
    static let ink    = Color(hex: 0x1B1712)   // warm ledger ink
    static let paper  = Color(hex: 0xF4EFE6)   // archival paper
    static let sepia  = Color(hex: 0x6B5E4F)   // text / manuscripts
    static let field  = Color(hex: 0x3E6B4F)   // sound
    static let lake   = Color(hex: 0x52707F)   // moving image
    static let clay   = Color(hex: 0x96432B)   // objects / other

    /// Restrained hue per item type, for the type chip.
    static func typeColor(_ type: String?) -> Color {
        let t = (type ?? "").lowercased()
        if t.contains("moving") || t.contains("video") { return lake }
        if t.contains("image") { return navy }
        if t.contains("text") { return sepia }
        if t.contains("sound") || t.contains("audio") { return field }
        if t.isEmpty { return .secondary }
        return clay
    }

    /// SF Symbol per item type.
    static func typeSymbol(_ type: String?) -> String {
        let t = (type ?? "").lowercased()
        if t.contains("moving") || t.contains("video") { return "film" }
        if t.contains("image") { return "photo" }
        if t.contains("text") { return "doc.text" }
        if t.contains("sound") || t.contains("audio") { return "waveform" }
        if t.contains("physical") { return "cube" }
        return "archivebox"
    }

    /// Optical correction for glyphs whose bounding box isn't their visual
    /// center — the square-and-arrow family carries its weight low, so it
    /// reads ~2pt below center inside a circle.
    static func glyphNudge(_ systemName: String) -> CGFloat {
        systemName.hasPrefix("square.and.arrow") ? -2 : 0
    }

    /// MIME type → the name people use for the file.
    static func formatLabel(_ mime: String) -> String {
        switch mime.lowercased() {
        case "application/pdf": return "PDF"
        case "image/jpeg", "image/jpg": return "JPEG"
        case "image/png": return "PNG"
        case "image/tiff": return "TIFF"
        case "image/gif": return "GIF"
        case "audio/mpeg", "audio/mp3": return "MP3"
        case "audio/wav", "audio/x-wav": return "WAV"
        case "video/mp4": return "MP4"
        case "video/quicktime": return "MOV"
        case "application/xml", "text/xml": return "XML"
        case "text/plain": return "Text file"
        case "text/html": return "HTML"
        default:
            // "application/vnd.ms-excel" → "VND.MS-EXCEL" is worse than the raw string.
            let tail = mime.split(separator: "/").last.map(String.init) ?? mime
            return tail.count <= 5 ? tail.uppercased() : mime
        }
    }

    /// Short human label for the site's type vocabulary.
    static func typeLabel(_ type: String?) -> String {
        guard let type, !type.isEmpty else { return "Item" }
        switch type {
        case "Image/StillImage", "Image": return "Image"
        case "Image/MovingImage": return "Video"
        case "PhysicalObject": return "Object"
        default: return type
        }
    }
}

enum UI {
    static let radius: CGFloat = 20
}

/// App-wide haptics. Impact for button presses, selection ticks for
/// toggles and pickers.
enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let selection = UISelectionFeedbackGenerator()

    private static let notice = UINotificationFeedbackGenerator()

    static func tap() { impact.impactOccurred() }
    static func select() { selection.selectionChanged() }
    static func success() { notice.notificationOccurred(.success) }
    static func failure() { notice.notificationOccurred(.error) }
}

/// Big serif figure — result counts, collection counts.
struct SerifNumeral: View {
    let text: String
    let unit: String?
    var size: CGFloat = 40

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(text)
                .font(.system(size: size, weight: .semibold, design: .serif))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let unit {
                Text(unit)
                    .font(.system(size: size * 0.38, weight: .regular, design: .serif))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Uppercase tracked label above a value — the ledger's column head.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

/// Tinted glass capsule — type of item, applied filter, count.
struct Chip: View {
    let label: String
    let color: Color
    var systemImage: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2.weight(.semibold))
            }
            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(colorScheme == .dark ? Color.white : color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .glassEffect(.regular.tint(color.opacity(0.18)), in: .capsule)
    }
}

/// Solid capsule call to action — the Plat of Zion primary button.
struct PrimaryButton: ButtonStyle {
    var tint: Color = Brand.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(tint, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule())
            .onChange(of: configuration.isPressed) {
                if configuration.isPressed { Haptics.tap() }
            }
    }
}

/// Quiet capsule — secondary actions that sit next to a PrimaryButton.
struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Brand.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .glassEffect(.regular, in: .capsule)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule())
            .onChange(of: configuration.isPressed) {
                if configuration.isPressed { Haptics.tap() }
            }
    }
}

struct Card<Content: View>: View {
    var glass = false
    @ViewBuilder var content: Content
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: UI.radius)
        if glass {
            base.glassEffect(.regular, in: shape)
        } else {
            base.background(.background.secondary, in: shape)
        }
    }
    private var base: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Circular Liquid Glass button — the Plat of Zion map control, reused for
/// the viewer and header actions. `filled` renders the accent-filled twin
/// (white glyph on blue) so it reads as the brand over any image.
struct GlassCircleButton: View {
    let systemName: String
    var filled = false
    var size: CGFloat = 30
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if filled {
            Button(action: { Haptics.tap(); action() }) {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .offset(y: Brand.glyphNudge(systemName))
                    .frame(width: size, height: size)
            }
            .buttonStyle(.glassProminent)
            .tint(Brand.accentRail)
            .buttonBorderShape(.circle)
        } else {
            Button(action: { Haptics.tap(); action() }) {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? .white : Brand.accentRail)
                    .offset(y: Brand.glyphNudge(systemName))
                    .frame(width: size, height: size)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        }
    }
}

extension View {
    /// Liquid Glass for a NON-INTERACTIVE pill (chips, captions). Don't
    /// wrap Buttons in this — it breaks their hit-testing.
    func glassCapsule() -> some View {
        self.glassEffect(.regular, in: .capsule)
    }

    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Remote thumbnail with a paper placeholder — every list and grid uses it.
struct Thumb: View {
    let url: URL?
    var cornerRadius: CGFloat = 10
    var body: some View {
        Color.clear
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder(symbol: "photo")
                    default:
                        placeholder(symbol: nil)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
    }

    private func placeholder(symbol: String?) -> some View {
        ZStack {
            Brand.paper
            if let symbol {
                Image(systemName: symbol)
                    .font(.title3.weight(.light))
                    .foregroundStyle(Brand.sepia.opacity(0.5))
            }
        }
    }
}
