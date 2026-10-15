//
//  Theme.swift
//  City Cemetery
//
//  Editorial register carried over from Plat of Zion and Utah Rails:
//  serif display type, warm ink, one accent, Liquid Glass controls. The
//  accent is verdigris — weathered bronze on granite — dark enough to hold
//  up as link and button color on white; lichen is the garnish.
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
    /// Verdigris — weathered bronze, for text and buttons.
    static let accent = Color(hex: 0x2F5D50)
    /// Lichen — pale green garnish only (never text on white).
    static let lichen = Color(hex: 0x8FA89A)
    /// The accent softened a step, for the secondary action buttons.
    static let accentRail = accent.opacity(0.8)
    static let ink    = Color(hex: 0x1B1712)   // warm ledger ink
    static let paper  = Color(hex: 0xF4EFE6)   // archival paper
    static let sepia  = Color(hex: 0x6B5E4F)   // secondary text
    /// Granite — headstone grey, for empty graves and quiet chips.
    static let granite = Color(hex: 0x5B6770)
    static let navy   = Color(hex: 0x2C4A6E)   // veteran chip
    static let rust   = Color(hex: 0x8A4B2A)   // "no records" chip
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

/// Big serif figure — page counts, photo counts.
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

/// Tinted glass capsule — kind of page, count, date.
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
/// the viewer and header actions. `filled` renders the accent-filled twin.
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

/// Remote thumbnail with a paper placeholder — every grid uses it.
struct Thumb: View {
    let url: URL?
    var cornerRadius: CGFloat = 10
    var symbol = "photo"
    var body: some View {
        Color.clear
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder(symbol: symbol)
                    default:
                        placeholder(symbol: url == nil ? symbol : nil)
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

/// Brief confirmation banner ("Saved to Photos").
struct Toast: Equatable {
    let text: String
    let symbol: String
}

struct ToastView: View {
    let toast: Toast
    var body: some View {
        Label(toast.text, systemImage: toast.symbol)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassCapsule()
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View {
        overlay(alignment: .bottom) {
            if let t = toast.wrappedValue {
                ToastView(toast: t)
                    .padding(.bottom, 24)
                    .task {
                        try? await Task.sleep(for: .seconds(2.2))
                        withAnimation { toast.wrappedValue = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: toast.wrappedValue)
    }
}
