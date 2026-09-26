//
//  Components.swift
//  gauge
//
//  Small building blocks shared by every tab: beveled panels, buttons,
//  checkboxes, section labels, and item artwork.
//

import SwiftUI

// MARK: - Panels

/// The 1px raised edge around classic panels: light on the top and left, dark on the bottom and right.
struct Bevel: View {
    var light: Color
    var dark: Color

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                light.frame(height: 1)
                Spacer(minLength: 0)
                dark.frame(height: 1)
            }
            HStack(spacing: 0) {
                light.frame(width: 1)
                Spacer(minLength: 0)
                dark.frame(width: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// A raised panel with a bevel.
    func classicPanel(_ p: Palette, fill: Color? = nil) -> some View {
        background(fill ?? p.panel)
            .overlay(Bevel(light: p.bevelLight.opacity(0.55), dark: p.bevelDark))
    }

    /// A sunken well for lists and grids.
    func classicInset(_ p: Palette) -> some View {
        background(p.inset)
            .overlay(Bevel(light: p.bevelDark, dark: p.bevelLight.opacity(0.35)))
    }

    func classicButton(_ kind: ClassicButtonStyle.Kind, _ p: Palette) -> some View {
        buttonStyle(ClassicButtonStyle(kind: kind, palette: p))
    }

    /// A plain text field drawn as a dark well.
    func classicField(_ p: Palette) -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .classicInset(p)
    }
}

// MARK: - Buttons

struct ClassicButtonStyle: ButtonStyle {
    enum Kind: Equatable {
        case primary
        case secondary
        case tab(selected: Bool)
        case card
    }

    var kind: Kind
    var palette: Palette

    func makeBody(configuration: Configuration) -> some View {
        ClassicButtonBody(configuration: configuration, kind: kind, palette: palette)
    }
}

private struct ClassicButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: ClassicButtonStyle.Kind
    let palette: Palette
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let p = palette
        let pressed = configuration.isPressed
        configuration.label
            .font(kind == .primary ? p.font(12.5, .bold) : p.font(12.5))
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .card ? 12 : 14)
            .padding(.vertical, kind == .card ? 9 : 6)
            .frame(maxWidth: kind == .card ? .infinity : nil, alignment: .leading)
            .background(background.opacity(pressed ? 0.8 : 1))
            .overlay(Bevel(light: pressed ? p.bevelDark : p.bevelLight.opacity(0.7), dark: pressed ? p.bevelLight.opacity(0.7) : p.bevelDark))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch kind {
        case .primary: palette.onPrimary
        case .tab(let selected): selected ? palette.accent : palette.text
        case .secondary, .card: palette.text
        }
    }

    private var background: Color {
        switch kind {
        case .primary: palette.primary
        case .tab(let selected): selected ? palette.control : palette.raised
        case .secondary, .card: palette.control
        }
    }
}

// MARK: - Checkboxes

struct ClassicCheckboxStyle: ToggleStyle {
    var palette: Palette

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Rectangle()
                        .fill(configuration.isOn ? palette.primary : palette.inset)
                        .frame(width: 13, height: 13)
                        .overlay(Rectangle().strokeBorder(palette.bevelDark, lineWidth: 1))
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(palette.onPrimary)
                    }
                }
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A radio button for the appearance picker.
struct RadioDot: View {
    var isOn: Bool
    var palette: Palette

    var body: some View {
        Circle()
            .fill(palette.inset)
            .frame(width: 13, height: 13)
            .overlay(Circle().strokeBorder(palette.bevelLight.opacity(0.6), lineWidth: 1))
            .overlay(Circle().fill(palette.primary).frame(width: 7, height: 7).opacity(isOn ? 1 : 0))
    }
}

// MARK: - Labels

struct SectionLabel: View {
    var title: String
    var palette: Palette

    init(_ title: String, _ palette: Palette) {
        self.title = title
        self.palette = palette
    }

    var body: some View {
        Text(title.uppercased())
            .font(palette.font(11.5))
            .foregroundStyle(palette.accent)
    }
}

/// "— Quick" when open, "+ Quality" when closed, with an optional count on the right.
struct DisclosureRow: View {
    var title: String
    var isOpen: Bool
    var trailing: String?
    var palette: Palette
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text("\(isOpen ? "—" : "+") \(title)")
                    .foregroundStyle(palette.accent)
                Spacer()
                if let trailing, !isOpen {
                    Text(trailing).foregroundStyle(palette.secondaryText)
                }
            }
            .font(palette.font(12.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A sidebar row: title on the left, a count on the right, highlighted when selected.
struct SidebarRow: View {
    var title: String
    var detail: String?
    var isSelected = false
    var titleColor: Color?
    var palette: Palette
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(titleColor ?? palette.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail).foregroundStyle(palette.secondaryText)
                }
            }
            .font(palette.font(12.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? palette.selection : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A removable filter chip: "Mythical ×".
struct FilterChip: View {
    var title: String
    var palette: Palette
    var remove: () -> Void

    var body: some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                Text(title)
                Text("×").foregroundStyle(palette.secondaryText)
            }
            .font(palette.font(12))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .classicPanel(palette, fill: palette.panel)
        }
        .buttonStyle(.plain)
    }
}

/// The strip along the bottom of the window.
struct StatusBar: View {
    var leading: String
    var middle: String?
    var trailing: String?
    var palette: Palette

    var body: some View {
        HStack(spacing: 24) {
            Text(leading)
            if let middle { Text(middle) }
            Spacer()
            if let trailing { Text(trailing) }
        }
        .font(palette.font(11.5))
        .foregroundStyle(palette.text.opacity(0.85))
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(palette.header)
        .overlay(alignment: .top) { palette.bevelDark.frame(height: 1) }
    }
}

// MARK: - Item artwork

/// Steam's item image, with a rarity-tinted placeholder while it loads or when there is none.
struct ItemArtwork: View {
    var item: InventoryItem
    var size: Int
    var palette: Palette

    var body: some View {
        ZStack {
            placeholder
            if let url = item.imageURL(size: size) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.15))) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit().padding(4)
                    }
                }
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [palette.rarity(item).opacity(0.28), palette.raised],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: Self.symbol(for: item))
                .font(.system(size: CGFloat(size) * 0.28, weight: .light))
                .foregroundStyle(palette.rarity(item).opacity(0.75))
        }
    }

    static func symbol(for item: InventoryItem) -> String {
        let type = (item.tag("Type")?.name ?? item.type).lowercased()
        if type.contains("courier") { return "hare" }
        if type.contains("ward") { return "eye" }
        if type.contains("music") { return "music.note" }
        if type.contains("loading screen") || type.contains("background") { return "photo" }
        if type.contains("taunt") || type.contains("emote") || type.contains("emoticon") { return "face.smiling" }
        if type.contains("treasure") || type.contains("case") || type.contains("crate") || type.contains("chest") { return "shippingbox" }
        if type.contains("key") || type.contains("ticket") { return "key" }
        if type.contains("card") { return "rectangle.portrait" }
        if type.contains("gem") { return "diamond" }
        if type.contains("sticker") || type.contains("graffiti") { return "seal" }
        return "shield.lefthalf.filled"
    }
}

/// The star toggle drawn in the corner of item tiles.
struct StarToggle: View {
    var isOn: Bool
    var palette: Palette
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "star.fill" : "star")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? palette.accent : palette.text)
                .frame(width: 22, height: 22)
                .background(palette.inset.opacity(0.85))
                .overlay(Rectangle().strokeBorder(palette.bevelDark, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(isOn ? "Unstar. Clean up may sell this item." : "Star. Clean up never sells starred items.")
    }
}

// MARK: - Formatting

enum RelativeTime {
    static func short(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "never" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) hr ago" }
        let days = Int(seconds / 86_400)
        return days == 1 ? "yesterday" : "\(days) days ago"
    }

    static func day(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
