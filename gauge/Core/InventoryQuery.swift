//
//  InventoryQuery.swift
//  gauge
//
//  Filtering and sorting for the Inventory tab. Within one tag category the
//  checked values are alternatives (Mythical or Legendary); across categories
//  every group must match (Mythical and Neck).
//

import Foundation

nonisolated enum QuickFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case starred
    case marketable
    case tradable
    case fluff
    case completeSets
    case priceMoved

    var id: String { rawValue }
}

nonisolated enum InventorySort: String, Codable, CaseIterable, Identifiable, Sendable {
    case value
    case name
    case rarity
    case newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .value: "Value"
        case .name: "Name"
        case .rarity: "Rarity"
        case .newest: "Newest"
        }
    }

    /// Whether this sort reads ascending (low-to-high, A-Z, oldest-first) by default.
    var defaultAscending: Bool {
        switch self {
        case .value: false
        case .name: true
        case .rarity: false
        case .newest: false
        }
    }
}

/// What the filters need to know beyond the items themselves.
nonisolated struct InventoryFacts: Sendable {
    var prices: [String: PriceQuote] = [:]
    var starred: Set<String> = []
    var fluffThresholdCents = 5
    /// Relative price change over the last week, by price key.
    var weeklyChange: [String: Double] = [:]
    var ownership = SetOwnership(items: [])

    func value(of item: InventoryItem) -> Int? { prices[item.priceKey]?.valueCents }

    func isFluff(_ item: InventoryItem) -> Bool {
        guard item.marketable, let value = value(of: item) else { return false }
        return value < fluffThresholdCents
    }

    func completesSet(_ item: InventoryItem) -> Bool {
        guard let set = item.itemSet else { return false }
        return ownership.owned(set, appID: item.appID) >= set.members.count
    }

    func priceMoved(_ item: InventoryItem, threshold: Double = 0.10) -> Bool {
        guard let change = weeklyChange[item.priceKey] else { return false }
        return abs(change) >= threshold
    }
}

nonisolated struct InventoryQuery: Equatable, Sendable {
    var search = ""
    var quick: Set<QuickFilter> = []
    /// Checked tag values (by display name) for each category id.
    var tags: [String: Set<String>] = [:]
    var sort: InventorySort = .value
    var ascending: Bool = InventorySort.value.defaultAscending

    var isEmpty: Bool { search.isEmpty && quick.isEmpty && tags.values.allSatisfy(\.isEmpty) }

    func apply(to items: [InventoryItem], facts: InventoryFacts) -> [InventoryItem] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = items.filter { matches($0, facts: facts, needle: needle) }
        return sorted(filtered, facts: facts)
    }

    func matches(_ item: InventoryItem, facts: InventoryFacts, needle: String) -> Bool {
        for filter in quick {
            switch filter {
            case .starred: if !facts.starred.contains(item.id) { return false }
            case .marketable: if !item.marketable { return false }
            case .tradable: if !item.tradable { return false }
            case .fluff: if !facts.isFluff(item) { return false }
            case .completeSets: if !facts.completesSet(item) { return false }
            case .priceMoved: if !facts.priceMoved(item) { return false }
            }
        }
        for (category, values) in tags where !values.isEmpty {
            guard let tag = item.tag(category), values.contains(tag.name) else { return false }
        }
        if !needle.isEmpty {
            let haystack = item.name.lowercased()
            if !haystack.contains(needle) && !(item.usedBy?.lowercased().contains(needle) ?? false) && !item.type.lowercased().contains(needle) {
                return false
            }
        }
        return true
    }

    func sorted(_ items: [InventoryItem], facts: InventoryFacts) -> [InventoryItem] {
        switch sort {
        case .value:
            let values = Dictionary(items.map { ($0.id, facts.value(of: $0) ?? -1) }, uniquingKeysWith: { first, _ in first })
            return items.sorted { lhs, rhs in
                let l = values[lhs.id] ?? -1, r = values[rhs.id] ?? -1
                return l != r ? (ascending ? l < r : l > r) : lhs.name < rhs.name
            }
        case .name:
            return items.sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return ascending ? order == .orderedAscending : order == .orderedDescending
            }
        case .rarity:
            return items.sorted { lhs, rhs in
                let l = RarityOrder.rank(lhs.rarity?.name), r = RarityOrder.rank(rhs.rarity?.name)
                return l != r ? (ascending ? l < r : l > r) : lhs.name < rhs.name
            }
        case .newest:
            // Asset ids grow over time, so the longest/largest id is the most recent.
            return items.sorted { lhs, rhs in
                if lhs.assetID.count != rhs.assetID.count {
                    return ascending ? lhs.assetID.count < rhs.assetID.count : lhs.assetID.count > rhs.assetID.count
                }
                return ascending ? lhs.assetID < rhs.assetID : lhs.assetID > rhs.assetID
            }
        }
    }
}

/// One checkbox in a sidebar tag section.
nonisolated struct TagFacet: Identifiable, Hashable, Sendable {
    var name: String
    var color: String?
    var count: Int
    var id: String { name }
}

/// A sidebar section: every value of one tag category, with counts.
nonisolated struct TagCategoryFacet: Identifiable, Hashable, Sendable {
    var category: String
    var title: String
    var values: [TagFacet]
    var id: String { category }

    /// Categories Steam uses that are worth filtering on, in sidebar order.
    static let preferredOrder = ["Rarity", "Quality", "Type", "Slot", "Hero", "item_class", "Game", "Exterior", "Weapon", "Collection"]

    static func facets(for items: [InventoryItem]) -> [TagCategoryFacet] {
        var counts: [String: [String: Int]] = [:]
        var titles: [String: String] = [:]
        var colors: [String: String] = [:]
        for item in items {
            for tag in item.tags {
                counts[tag.category, default: [:]][tag.name, default: 0] += 1
                titles[tag.category] = tag.categoryName
                if let color = tag.color { colors["\(tag.category)|\(tag.name)"] = color }
            }
        }
        let categories = counts.keys.sorted { lhs, rhs in
            let l = preferredOrder.firstIndex(of: lhs) ?? Int.max, r = preferredOrder.firstIndex(of: rhs) ?? Int.max
            return l != r ? l < r : lhs < rhs
        }
        return categories.compactMap { category in
            guard let values = counts[category], values.count > 1 || category == "Rarity" else { return nil }
            let facets = values.map { TagFacet(name: $0.key, color: colors["\(category)|\($0.key)"], count: $0.value) }
                .sorted { lhs, rhs in
                    if category == "Rarity" { return RarityOrder.rank(lhs.name) > RarityOrder.rank(rhs.name) }
                    return lhs.count != rhs.count ? lhs.count > rhs.count : lhs.name < rhs.name
                }
            return TagCategoryFacet(category: category, title: titles[category] ?? category, values: facets)
        }
    }
}

nonisolated enum RarityOrder {
    private static let ranks: [String: Int] = [
        "Common": 0, "Base Grade": 0, "Consumer Grade": 0,
        "Uncommon": 1, "Industrial Grade": 1,
        "Rare": 2, "Mil-Spec Grade": 2, "High Grade": 2,
        "Mythical": 3, "Restricted": 3, "Remarkable": 3,
        "Legendary": 4, "Classified": 4, "Exotic": 4,
        "Immortal": 5, "Covert": 5, "Extraordinary": 5,
        "Arcana": 6, "Contraband": 6,
        "Ancient": 7,
    ]

    static func rank(_ name: String?) -> Int {
        guard let name else { return -1 }
        return ranks[name] ?? 0
    }
}
