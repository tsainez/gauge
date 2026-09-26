//
//  InventoryItem.swift
//  gauge
//
//  The in-memory shape of one inventory asset, with its Steam description
//  already merged in. Everything the UI filters, sorts, and prices works on
//  arrays of these, so they are plain values that are cheap to copy and cache.
//

import Foundation

/// One of a profile's inventories, such as Dota 2 (570/2) or Steam community items (753/6).
nonisolated struct InventoryContext: Codable, Hashable, Sendable, Identifiable {
    var appID: Int
    var contextID: String
    var name: String
    var iconURL: String?
    var assetCount: Int

    var id: String { Self.key(appID: appID, contextID: contextID) }

    static func key(appID: Int, contextID: String) -> String { "\(appID)_\(contextID)" }

    /// Inventories most people with Market items have. Used when the profile's
    /// inventory page can't be read to discover the real list.
    static let common: [InventoryContext] = [
        InventoryContext(appID: 570, contextID: "2", name: "Dota 2", iconURL: nil, assetCount: 0),
        InventoryContext(appID: 753, contextID: "6", name: "Steam", iconURL: nil, assetCount: 0),
        InventoryContext(appID: 440, contextID: "2", name: "Team Fortress 2", iconURL: nil, assetCount: 0),
        InventoryContext(appID: 730, contextID: "2", name: "Counter-Strike 2", iconURL: nil, assetCount: 0),
        InventoryContext(appID: 232090, contextID: "2", name: "Killing Floor 2", iconURL: nil, assetCount: 0),
        InventoryContext(appID: 252490, contextID: "2", name: "Rust", iconURL: nil, assetCount: 0),
    ]
}

nonisolated struct ItemTag: Codable, Hashable, Sendable {
    /// Stable category id, e.g. "Rarity", "Quality", "Type", "Slot", "Hero".
    var category: String
    /// Localized category label.
    var categoryName: String
    var internalName: String
    /// Localized value, e.g. "Mythical".
    var name: String
    /// Hex color without "#", when Steam provides one.
    var color: String?
}

/// A cosmetic set this item belongs to, read from the item's description.
nonisolated struct ItemSetInfo: Codable, Hashable, Sendable {
    var name: String
    var members: [String]
}

nonisolated struct InventoryItem: Codable, Hashable, Sendable, Identifiable {
    var appID: Int
    var contextID: String
    var assetID: String
    var classID: String
    var instanceID: String
    /// Stack size. Most cosmetics are 1; gems and some commodities stack.
    var amount: Int
    var name: String
    /// The name without a quality prefix such as "Inscribed", used to match set pieces.
    var baseName: String
    var marketHashName: String
    var type: String
    var iconHash: String?
    var nameColor: String?
    var marketable: Bool
    var tradable: Bool
    var commodity: Bool
    var tags: [ItemTag]
    /// Plain-text description lines, blank lines removed.
    var details: [String]
    var itemSet: ItemSetInfo?

    var id: String { Self.key(appID: appID, contextID: contextID, assetID: assetID) }

    static func key(appID: Int, contextID: String, assetID: String) -> String { "\(appID)_\(contextID)_\(assetID)" }

    var contextKey: String { InventoryContext.key(appID: appID, contextID: contextID) }
    var priceKey: String { PriceKey.make(appID: appID, marketHashName: marketHashName) }

    func tag(_ category: String) -> ItemTag? {
        tags.first { $0.category == category }
    }

    var rarity: ItemTag? { tag("Rarity") }

    /// The color Steam uses for the item's rarity, falling back to quality and name color.
    var accentHex: String? { rarity?.color ?? tag("Quality")?.color ?? nameColor }

    /// "Mythical Neck", "Trading Card", and so on.
    var subtitle: String {
        if let rarity, let slot = tag("Slot") { return "\(rarity.name) \(slot.name)" }
        return type
    }

    var usedBy: String? {
        if let hero = tag("Hero") { return hero.name }
        if let line = details.first(where: { $0.hasPrefix("Used By:") }) {
            return line.dropFirst("Used By:".count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    func imageURL(size: Int) -> URL? {
        guard let iconHash, !iconHash.isEmpty else { return nil }
        if iconHash.hasPrefix("http") { return URL(string: iconHash) }
        return URL(string: "https://community.akamai.steamstatic.com/economy/image/\(iconHash)/\(size)fx\(size)f")
    }

    var marketURL: URL? {
        let name = PriceKey.percentEncode(marketHashName)
        return URL(string: "https://steamcommunity.com/market/listings/\(appID)/\(name)")
    }
}

nonisolated enum PriceKey {
    static func make(appID: Int, marketHashName: String) -> String { "\(appID)|\(marketHashName)" }

    static func split(_ key: String) -> (appID: Int, marketHashName: String)? {
        guard let bar = key.firstIndex(of: "|"), let app = Int(key[..<bar]) else { return nil }
        return (app, String(key[key.index(after: bar)...]))
    }

    /// Strict RFC 3986 encoding. Market hash names can contain "+", "&", "/" and "|".
    static func percentEncode(_ text: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
