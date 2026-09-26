//
//  Theme.swift
//  gauge
//
//  The three looks from the Settings storyboard. "Classic" follows the
//  olive-and-gold Steam client of the mid-2000s: flat panels with a 1px
//  bevel, gold section labels, and a gold primary button.
//

import SwiftUI

struct Palette {
    var window: Color
    var header: Color
    var panel: Color
    var raised: Color
    var inset: Color
    var control: Color
    var selection: Color
    var bevelLight: Color
    var bevelDark: Color
    var text: Color
    var secondaryText: Color
    var mutedText: Color
    var accent: Color
    var primary: Color
    var onPrimary: Color
    var positive: Color
    var negative: Color
    var neutral: Color
    var gridLine: Color
    /// Nil uses the system font.
    var fontName: String?

    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard let fontName else { return .system(size: size, weight: weight) }
        let base = Font.custom(fontName, size: size)
        return weight == .regular ? base : base.weight(weight)
    }

    /// The rarity or quality color Steam gives an item, or a neutral fallback.
    func rarity(_ item: InventoryItem) -> Color {
        Color(hex: item.accentHex) ?? mutedText
    }

    static func named(_ theme: ThemeChoice) -> Palette {
        switch theme {
        case .classic: .classic
        case .classicDark: .classicDark
        case .modern: .modern
        }
    }

    static let classic = Palette(
        window: Color(hex: "4C5844")!,
        header: Color(hex: "3E4637")!,
        panel: Color(hex: "3E4637")!,
        raised: Color(hex: "4C5844")!,
        inset: Color(hex: "2A2E23")!,
        control: Color(hex: "5A6A50")!,
        selection: Color(hex: "5A6A50")!,
        bevelLight: Color(hex: "8C9284")!,
        bevelDark: Color(hex: "292C21")!,
        text: Color(hex: "DEE5D7")!,
        secondaryText: Color(hex: "A0AA95")!,
        mutedText: Color(hex: "7E8773")!,
        accent: Color(hex: "C4B550")!,
        primary: Color(hex: "C4B550")!,
        onPrimary: Color(hex: "1F2318")!,
        positive: Color(hex: "A4C66B")!,
        negative: Color(hex: "D96B5B")!,
        neutral: Color(hex: "8C9284")!,
        gridLine: Color(hex: "3A3F31")!,
        fontName: "Tahoma"
    )

    static let classicDark = Palette(
        window: Color(hex: "1D2019")!,
        header: Color(hex: "181A14")!,
        panel: Color(hex: "23271E")!,
        raised: Color(hex: "2B3025")!,
        inset: Color(hex: "121410")!,
        control: Color(hex: "33392C")!,
        selection: Color(hex: "3A4232")!,
        bevelLight: Color(hex: "4A5242")!,
        bevelDark: Color(hex: "0E100C")!,
        text: Color(hex: "D8DED3")!,
        secondaryText: Color(hex: "98A18E")!,
        mutedText: Color(hex: "6E7665")!,
        accent: Color(hex: "C4B550")!,
        primary: Color(hex: "C4B550")!,
        onPrimary: Color(hex: "1F2318")!,
        positive: Color(hex: "A4C66B")!,
        negative: Color(hex: "D96B5B")!,
        neutral: Color(hex: "6E7665")!,
        gridLine: Color(hex: "262A21")!,
        fontName: "Tahoma"
    )

    static let modern = Palette(
        window: Color(hex: "171A21")!,
        header: Color(hex: "0E141B")!,
        panel: Color(hex: "1B2838")!,
        raised: Color(hex: "213244")!,
        inset: Color(hex: "101822")!,
        control: Color(hex: "2A475E")!,
        selection: Color(hex: "2A475E")!,
        bevelLight: Color(hex: "2F4A63")!,
        bevelDark: Color(hex: "0B1016")!,
        text: Color(hex: "C7D5E0")!,
        secondaryText: Color(hex: "8F98A0")!,
        mutedText: Color(hex: "67707B")!,
        accent: Color(hex: "66C0F4")!,
        primary: Color(hex: "A4D007")!,
        onPrimary: Color(hex: "0E141B")!,
        positive: Color(hex: "A4D007")!,
        negative: Color(hex: "E0584B")!,
        neutral: Color(hex: "67707B")!,
        gridLine: Color(hex: "1E2A38")!,
        fontName: nil
    )

    /// Swatches for the appearance picker.
    var swatches: [Color] { [panel, raised, control, primary] }
}

extension Color {
    /// "8847ff" or "#8847FF". Returns nil for anything else.
    init?(hex: String?) {
        guard var text = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
