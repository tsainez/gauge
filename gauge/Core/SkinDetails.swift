//
//  SkinDetails.swift
//  gauge
//
//  What sets one copy of a Counter-Strike 2 item apart from another with
//  the same name, and so the same Market price: its float (wear), its
//  pattern, its finish, and whatever is applied to it. Steam reports these
//  per asset in the inventory (see `SkinDetailsReader`).
//

import Foundation

/// The float, pattern, finish, and applied stickers and charm of one CS2 item.
nonisolated struct SkinDetails: Codable, Hashable, Sendable {
    /// Wear from 0 (pristine) to 1, Steam's "Wear Rating". Players call it the float.
    var wear: Double?
    /// Steam's "Pattern Template", also called the paint seed or pattern index (0 to 1,000).
    /// For a charm, its charm template.
    var pattern: Int?
    /// The finish's paint index, e.g. 415 for a Ruby Doppler. Only the certificate has it.
    var paintIndex: Int?
    /// The item's definition, e.g. 7 for the AK-47.
    var defIndex: Int?
    /// The StatTrak counter, when the item has one.
    var statTrak: Int?
    var nameTag: String?
    /// How the item came to exist, such as unboxed or traded up (`SkinDetails.originName`).
    var origin: Int?
    var stickers: [SkinAccessory] = []
    var charms: [SkinAccessory] = []
    /// The certificate as Steam sent it. It's also the payload of the item's inspect link.
    var certificate: String?

    var exterior: Exterior? { wear.map(Exterior.of) }

    /// "Phase 2", "Ruby", and so on. Doppler phases share a Market name but not a price.
    var phase: String? { paintIndex.flatMap(DopplerPhase.name(paintIndex:)) }

    var originName: String? { origin.flatMap(Self.originName) }

    /// "P2 · 0.0123 · #412": the phase, float, and pattern that tell copies apart.
    var summary: String? {
        let parts = [phase.map(DopplerPhase.shortName), wear.map(FloatText.short), pattern.map { "#\($0)" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Stickers, patches, or a charm someone applied: value the Market price doesn't include.
    var hasApplied: Bool { !stickers.isEmpty || !charms.isEmpty }

    /// "4 stickers and a charm", for Clean up's reasons.
    var appliedSummary: String? {
        var parts: [String] = []
        if !stickers.isEmpty { parts.append(stickers.count == 1 ? "a sticker" : "\(stickers.count) stickers") }
        if !charms.isEmpty { parts.append(charms.count == 1 ? "a charm" : "\(charms.count) charms") }
        return parts.isEmpty ? nil : parts.joined(separator: " and ")
    }

    var isEmpty: Bool {
        wear == nil && pattern == nil && paintIndex == nil && statTrak == nil && nameTag == nil && !hasApplied
    }

    /// The link that opens this exact item in an inspect viewer.
    var inspectLink: String? {
        certificate.map { "steam://run/730//+csgo_econ_action_preview%20\($0)" }
    }

    /// CSFloat's database, filtered to this finish and pattern. It records where skins
    /// have been seen, which is the closest thing to an ownership history outside Steam.
    var databaseURL: URL? {
        guard let defIndex, let paintIndex else { return nil }
        var components = URLComponents(string: "https://csfloat.com/db")
        components?.queryItems = [
            URLQueryItem(name: "defIndex", value: String(defIndex)),
            URLQueryItem(name: "paintIndex", value: String(paintIndex)),
        ] + (pattern.map { [URLQueryItem(name: "paintSeed", value: String($0))] } ?? [])
        return components?.url
    }

    /// Valve's item origins (`eEconItemOrigin`), in the words CS players use for the common ones.
    static func originName(_ origin: Int) -> String? {
        switch origin {
        case 0: "Timed drop"
        case 1: "Achievement"
        case 2: "Purchased"
        case 3: "Traded"
        case 4: "Trade-up"
        case 5: "Store promotion"
        case 6: "Gift"
        case 8: "Unboxed"
        case 11: "Wrapped gift"
        case 12: "Halloween drop"
        case 13: "Steam purchase"
        case 16: "Collection reward"
        case 21: "Tournament drop"
        case 22: "Default item"
        case 23: "Mission reward"
        case 24: "Level-up drop"
        default: nil
        }
    }
}

/// A sticker, patch, or charm applied to an item.
nonisolated struct SkinAccessory: Codable, Hashable, Sendable {
    var slot: Int
    /// Steam's sticker or charm kit id.
    var kitID: Int?
    /// The name from the item's description, when every piece could be matched to one.
    var name: String?
    /// How scraped a sticker is, 0 (new) to 1.
    var wear: Double?
    /// A charm's pattern (its charm template).
    var pattern: Int?
}

// MARK: - Exterior

/// The five wear ranges Steam names in Market listings.
nonisolated enum Exterior: Int, CaseIterable, Comparable, Sendable {
    case factoryNew
    case minimalWear
    case fieldTested
    case wellWorn
    case battleScarred

    static func < (lhs: Exterior, rhs: Exterior) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .factoryNew: "Factory New"
        case .minimalWear: "Minimal Wear"
        case .fieldTested: "Field-Tested"
        case .wellWorn: "Well-Worn"
        case .battleScarred: "Battle-Scarred"
        }
    }

    var abbreviation: String {
        switch self {
        case .factoryNew: "FN"
        case .minimalWear: "MW"
        case .fieldTested: "FT"
        case .wellWorn: "WW"
        case .battleScarred: "BS"
        }
    }

    /// The floats this exterior covers. A float on a boundary belongs to the worse exterior.
    var bounds: (lower: Double, upper: Double) {
        switch self {
        case .factoryNew: (0, 0.07)
        case .minimalWear: (0.07, 0.15)
        case .fieldTested: (0.15, 0.38)
        case .wellWorn: (0.38, 0.45)
        case .battleScarred: (0.45, 1)
        }
    }

    static func of(_ wear: Double) -> Exterior {
        allCases.first { wear < $0.bounds.upper } ?? .battleScarred
    }

    /// Where a float sits within its exterior: 0 at the clean end, 1 at the worn end.
    /// This uses the exterior's full range; a finish that can't reach 0 never scores near it.
    static func position(of wear: Double) -> Double {
        let bounds = of(wear).bounds
        return min(max((wear - bounds.lower) / (bounds.upper - bounds.lower), 0), 1)
    }

    /// The cleanest whole percent of its exterior a float falls in: 2 for 0.0012.
    static func cleanestPercent(of wear: Double) -> Int {
        max(1, Int((position(of: wear) * 100).rounded(.up)))
    }
}

// MARK: - Doppler phases

/// Doppler and Gamma Doppler finishes come in phases, each its own paint index.
nonisolated enum DopplerPhase {
    static func name(paintIndex: Int) -> String? {
        switch paintIndex {
        case 415: "Ruby"
        case 416, 619: "Sapphire"
        case 417, 617: "Black Pearl"
        case 568, 1119: "Emerald"
        case 418, 569, 852, 1120: "Phase 1"
        case 419, 570, 618, 853, 1121: "Phase 2"
        case 420, 571, 854, 1122: "Phase 3"
        case 421, 572, 855, 1123: "Phase 4"
        default: nil
        }
    }

    /// "P2" for tiles; gems keep their names.
    static func shortName(_ name: String) -> String {
        name.hasPrefix("Phase ") ? "P" + name.dropFirst("Phase ".count) : name
    }
}

// MARK: - Formatting floats

nonisolated enum FloatText {
    /// Every digit, as players quote floats: "0.07123456814885139". Never in exponent form.
    static func full(_ wear: Double) -> String {
        let text = "\(wear)"
        guard let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }),
              let exponent = Int(text[text.index(after: e)...])
        else { return text }
        let mantissa = text[..<e]
        let sign = mantissa.hasPrefix("-") ? "-" : ""
        let unsigned = mantissa.drop { $0 == "-" }
        let digits = unsigned.filter(\.isNumber)
        let whole = unsigned.firstIndex(of: ".").map { unsigned.distance(from: unsigned.startIndex, to: $0) } ?? unsigned.count
        let point = whole + exponent
        if point <= 0 {
            return sign + "0." + String(repeating: "0", count: -point) + digits
        }
        if point >= digits.count {
            return sign + digits + String(repeating: "0", count: point - digits.count)
        }
        return sign + digits.prefix(point) + "." + digits.dropFirst(point)
    }

    /// Four decimals, or three significant digits under 0.01: "0.0712", "0.00331".
    static func short(_ wear: Double) -> String {
        guard wear > 0, wear < 0.01 else { return String(format: "%.4f", wear) }
        let decimals = min(2 - Int(log10(wear).rounded(.down)), 12)
        return String(format: "%.\(decimals)f", wear)
    }
}
