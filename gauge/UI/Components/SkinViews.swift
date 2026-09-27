//
//  SkinViews.swift
//  gauge
//
//  How a Counter-Strike 2 item's float, pattern, finish, and stickers are
//  drawn: a badge on tiles, and a box in the Inventory and Clean up
//  inspectors with the float on a bar of the five exteriors.
//

import SwiftUI

extension Exterior {
    /// Green for Factory New through red for Battle-Scarred, as float tools color them.
    var color: Color {
        switch self {
        case .factoryNew: Color(hex: "4CAF50")!
        case .minimalWear: Color(hex: "8BC34A")!
        case .fieldTested: Color(hex: "F2C037")!
        case .wellWorn: Color(hex: "F28C28")!
        case .battleScarred: Color(hex: "E0584B")!
        }
    }
}

/// "P2 ● 0.0712 #661" in a tile's corner: what tells copies with the same name apart.
struct FloatBadge: View {
    let skin: SkinDetails
    let palette: Palette

    var body: some View {
        let p = palette
        HStack(spacing: 4) {
            if let phase = skin.phase {
                Text(DopplerPhase.shortName(phase)).foregroundStyle(p.accent)
            }
            if let wear = skin.wear {
                Circle()
                    .fill(Exterior.of(wear).color)
                    .frame(width: 6, height: 6)
                Text(FloatText.short(wear))
            }
            if let pattern = skin.pattern {
                Text(verbatim: "#\(pattern)").foregroundStyle(p.secondaryText)
            }
        }
        .font(p.font(10.5))
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(p.inset.opacity(0.85))
    }
}

/// The five exteriors laid end to end from 0 to 1, with a mark at this float.
struct WearBar: View {
    let wear: Double
    let palette: Palette

    var body: some View {
        let current = Exterior.of(wear)
        GeometryReader { proxy in
            let width = proxy.size.width
            let marker = min(max(width * CGFloat(wear) - 1, 0), max(width - 2, 0))
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Exterior.allCases, id: \.self) { exterior in
                        exterior.color
                            .opacity(exterior == current ? 1 : 0.3)
                            .frame(width: width * CGFloat(exterior.bounds.upper - exterior.bounds.lower))
                    }
                }
                .frame(height: 5)
                .clipShape(Capsule())
                palette.text
                    .frame(width: 2, height: 11)
                    .offset(x: marker)
            }
            .frame(height: 11)
        }
        .frame(height: 11)
        .help("Factory New under 0.07, Minimal Wear to 0.15, Field-Tested to 0.38, Well-Worn to 0.45, then Battle-Scarred")
    }
}

/// A CS2 item's float, pattern, finish, and what's applied to it, for the inspectors.
struct SkinDetailsBox: View {
    @Environment(\.openURL) private var openURL
    let skin: SkinDetails
    let palette: Palette

    var body: some View {
        let p = palette
        VStack(alignment: .leading, spacing: 5) {
            if let wear = skin.wear {
                HStack(alignment: .firstTextBaseline) {
                    Text("Float").foregroundStyle(p.secondaryText)
                    Spacer()
                    Text(FloatText.full(wear))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .textSelection(.enabled)
                }
                WearBar(wear: wear, palette: p)
                Text(exteriorLine(wear))
                    .font(p.font(11))
                    .foregroundStyle(Exterior.of(wear).color)
            }
            if let pattern = skin.pattern {
                row("Pattern", String(pattern))
            }
            if let phase = skin.phase {
                row("Phase", phase)
            }
            if let paintIndex = skin.paintIndex {
                row("Finish", "#" + String(paintIndex))
            }
            if let count = skin.statTrak {
                row("StatTrak™", count.formatted())
            }
            if let name = skin.nameTag {
                row("Name tag", "“\(name)”")
            }
            if let origin = skin.originName {
                row("Origin", origin)
            }
            if !skin.stickers.isEmpty {
                pieces(skin.stickers, title: skin.stickers.count == 1 ? "Sticker" : "Stickers", unnamed: "Sticker")
            }
            if !skin.charms.isEmpty {
                pieces(skin.charms, title: "Charm", unnamed: "Charm")
            }
            if let url = skin.databaseURL {
                Button("Find it in CSFloat's database") { openURL(url) }
                    .buttonStyle(.plain)
                    .foregroundStyle(p.accent)
                    .padding(.top, 2)
                    .help("CSFloat records where skins have been seen, often including earlier owners. Opens in your browser.")
            }
        }
        .font(p.font(12))
        .padding(10)
        .classicInset(p)
    }

    /// "Factory New · cleanest 2%" for low floats, else the exterior's range.
    private func exteriorLine(_ wear: Double) -> String {
        let exterior = Exterior.of(wear)
        if Exterior.position(of: wear) < 0.1 {
            return "\(exterior.title) · cleanest \(Exterior.cleanestPercent(of: wear))%"
        }
        return "\(exterior.title) · \(Self.number(exterior.bounds.lower)) to \(Self.number(exterior.bounds.upper))"
    }

    private static func number(_ value: Double) -> String {
        value == 0 || value == 1 ? String(Int(value)) : String(value)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(palette.secondaryText)
            Spacer()
            Text(value).textSelection(.enabled)
        }
    }

    private func pieces(_ pieces: [SkinAccessory], title: String, unnamed: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(palette.secondaryText)
            ForEach(pieces.indices, id: \.self) { index in
                let piece = pieces[index]
                HStack(spacing: 6) {
                    Text(piece.name ?? (pieces.count == 1 ? unnamed : "\(unnamed) \(index + 1)"))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let wear = piece.wear, wear > 0 {
                        Text("scraped \(Int((wear * 100).rounded()))%")
                            .foregroundStyle(palette.secondaryText)
                    }
                    if let pattern = piece.pattern {
                        Text(verbatim: "#\(pattern)")
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .padding(.leading, 8)
            }
        }
    }
}
