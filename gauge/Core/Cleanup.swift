//
//  Cleanup.swift
//  gauge
//
//  Sorts marketable items into buckets by the user's rules. Pure and
//  synchronous so it can run on every rule change and be unit tested.
//
//  Selling rules pick candidates (extra copies, cheap items, or everything
//  else); protections then keep some of them anyway (starred items, set
//  pieces, rising prices, items that only pay a cent) or hold some for a
//  second look: expensive items, and CS2 skins whose float or stickers may
//  be worth more than the Market price, which is the same for every copy.
//

import Foundation

nonisolated enum CleanupBucket: String, Codable, CaseIterable, Identifiable, Sendable {
    case sell
    case review
    case keep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sell: "Sell"
        case .review: "Worth a look"
        case .keep: "Keep"
        }
    }
}

nonisolated enum ListingPriceStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case lowestListing
    case undercutLowest
    case medianSale

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lowestListing: "lowest listing"
        case .undercutLowest: "1¢ under lowest listing"
        case .medianSale: "median sale price"
        }
    }
}

nonisolated struct CleanupRules: Codable, Equatable, Sendable {
    // What to sell
    /// Sell every copy of an item after the one you keep.
    var sellDuplicates = true
    /// Sell every copy of anything listed below `cheapBelowCents`.
    var sellCheap = true
    var cheapBelowCents = 10
    /// Sell every other priced item too.
    var sellEverythingElse = false
    /// Items at Steam's floor pay the seller $0.01. Off keeps them.
    var sellFloorItems = true

    // What to keep or look at first
    var keepStarred = true
    var reviewExpensive = true
    /// Items at or above this buyer price go to "Worth a look" instead of being sold.
    var reviewAboveCents = 500

    // Counter-Strike 2
    /// Skins with a float in the cleanest `lowFloatShare` of their exterior go to "Worth a look".
    var reviewLowFloats = true
    /// 0.05 is the cleanest 5%: under 0.0035 for Factory New, under 0.1615 for Field-Tested.
    var lowFloatShare = 0.05
    /// Skins with stickers, patches, or a charm applied go to "Worth a look".
    var reviewApplied = true

    // Advanced
    /// Keep one copy of each piece of a set once this many of its pieces are owned.
    var keepSetPieces = false
    var setThreshold = 3
    var holdRising = false
    /// 0.20 holds anything up 20% or more over the last 30 days.
    var risingThreshold = 0.20
    var pricing: ListingPriceStrategy = .lowestListing
    /// Never list below this buyer price. Steam's own floor is $0.03.
    var floorCents = SteamFees.floorBuyerCents
}

extension CleanupRules {
    /// What holds an item a rule picks back for a second look, for "Worth a look":
    /// "worth $5.00 or more, a skin with a low float, or a skin with stickers or a charm".
    /// The skin checks are left out when there are no CS2 skins to apply them to.
    func reviewSummary(currency: SteamCurrency, skins: Bool) -> String? {
        var parts: [String] = []
        if reviewExpensive { parts.append("worth \(Money.format(reviewAboveCents, currency)) or more") }
        if skins && reviewLowFloats { parts.append("a skin with a low float") }
        if skins && reviewApplied { parts.append("a skin with stickers or a charm") }
        guard let last = parts.popLast() else { return nil }
        if parts.isEmpty { return last }
        return parts.joined(separator: ", ") + (parts.count > 1 ? ", or " : " or ") + last
    }
}

/// Decodes with defaults so rules saved by an older version keep working.
/// Older versions kept every set piece by default under `keepSets`; that key
/// is ignored, so set pieces start out unprotected, as they now do by default.
extension CleanupRules {
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CleanupRules()
        sellDuplicates = (try? c.decodeIfPresent(Bool.self, forKey: .sellDuplicates)) ?? d.sellDuplicates
        sellCheap = (try? c.decodeIfPresent(Bool.self, forKey: .sellCheap)) ?? d.sellCheap
        cheapBelowCents = (try? c.decodeIfPresent(Int.self, forKey: .cheapBelowCents)) ?? d.cheapBelowCents
        sellEverythingElse = (try? c.decodeIfPresent(Bool.self, forKey: .sellEverythingElse)) ?? d.sellEverythingElse
        sellFloorItems = (try? c.decodeIfPresent(Bool.self, forKey: .sellFloorItems)) ?? d.sellFloorItems
        keepStarred = (try? c.decodeIfPresent(Bool.self, forKey: .keepStarred)) ?? d.keepStarred
        reviewExpensive = (try? c.decodeIfPresent(Bool.self, forKey: .reviewExpensive)) ?? d.reviewExpensive
        reviewAboveCents = (try? c.decodeIfPresent(Int.self, forKey: .reviewAboveCents)) ?? d.reviewAboveCents
        reviewLowFloats = (try? c.decodeIfPresent(Bool.self, forKey: .reviewLowFloats)) ?? d.reviewLowFloats
        lowFloatShare = (try? c.decodeIfPresent(Double.self, forKey: .lowFloatShare)) ?? d.lowFloatShare
        reviewApplied = (try? c.decodeIfPresent(Bool.self, forKey: .reviewApplied)) ?? d.reviewApplied
        keepSetPieces = (try? c.decodeIfPresent(Bool.self, forKey: .keepSetPieces)) ?? d.keepSetPieces
        setThreshold = (try? c.decodeIfPresent(Int.self, forKey: .setThreshold)) ?? d.setThreshold
        holdRising = (try? c.decodeIfPresent(Bool.self, forKey: .holdRising)) ?? d.holdRising
        risingThreshold = (try? c.decodeIfPresent(Double.self, forKey: .risingThreshold)) ?? d.risingThreshold
        pricing = (try? c.decodeIfPresent(ListingPriceStrategy.self, forKey: .pricing)) ?? d.pricing
        floorCents = (try? c.decodeIfPresent(Int.self, forKey: .floorCents)) ?? d.floorCents
    }
}

/// Why an item landed in its bucket. `kind` drives the filters in Clean up;
/// `text` is what the row shows.
nonisolated struct CleanupReason: Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        // Sell
        case extraCopy
        case cheap
        case everythingElse
        // Worth a look
        case expensive
        case lowFloat
        case applied
        // Keep
        case starred
        case setPiece
        case notPriced
        case rising
        case floorPrice
        case keptCopy
        case noRule
        // Any bucket
        case movedByYou

        /// Order for showing several reasons at once, in declaration order.
        var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    }

    var kind: Kind
    var text: String
}

nonisolated struct CleanupEntry: Identifiable, Hashable, Sendable {
    var item: InventoryItem
    var bucket: CleanupBucket
    var reason: CleanupReason
    /// Price a buyer pays per unit when listed, if the item is priced.
    var buyerCents: Int?
    /// What the seller receives per unit after fees.
    var sellerCents: Int?
    /// How many copies of this item are in the inventories being cleaned up,
    /// including ones that can't be sold.
    var copies = 1

    var id: String { item.id }
    var totalSellerCents: Int { (sellerCents ?? 0) * item.amount }
    var totalBuyerCents: Int { (buyerCents ?? 0) * item.amount }
    /// Listed at Steam's floor, so the seller gets a single cent.
    var paysFloor: Bool { (sellerCents ?? 2) <= 1 }
}

nonisolated struct CleanupPlan: Sendable {
    var entries: [CleanupBucket: [CleanupEntry]]
    var unpricedCount: Int

    func entries(in bucket: CleanupBucket) -> [CleanupEntry] { entries[bucket] ?? [] }

    func receive(in bucket: CleanupBucket) -> Int {
        entries(in: bucket).reduce(0) { $0 + $1.totalSellerCents }
    }

    /// Items in a bucket, counting every unit of a stack.
    func itemCount(in bucket: CleanupBucket) -> Int {
        entries(in: bucket).reduce(0) { $0 + $1.item.amount }
    }

    /// What gets listed when the user confirms: the Sell bucket, minus anything without a price.
    var listings: [CleanupEntry] {
        entries(in: .sell).filter { $0.buyerCents != nil }
    }
}

nonisolated enum CleanupPlanner {
    static func plan(
        items: [InventoryItem],
        prices: [String: PriceQuote],
        trends: [String: Double],
        starred: Set<String>,
        overrides: [String: CleanupBucket],
        rules: CleanupRules,
        currency: SteamCurrency
    ) -> CleanupPlan {
        let ownership = SetOwnership(items: items)
        let protected = rules.keepStarred ? starred : []
        let copyIndex = CopyIndex(items: items, protected: protected)
        var buckets: [CleanupBucket: [CleanupEntry]] = [:]
        var unpriced = 0

        for item in items where item.marketable {
            let quote = prices[item.priceKey]
            let buyer = quote.flatMap { listingPrice(for: $0, rules: rules) }
            let seller = buyer.map { SteamFees.sellerReceives(buyerPays: $0) }
            let copies = copyIndex.copies(of: item)
            let isExtra = rules.sellDuplicates && copyIndex.isExtra(item)
            if buyer == nil { unpriced += 1 }

            func add(_ bucket: CleanupBucket, _ kind: CleanupReason.Kind, _ text: String) {
                buckets[bucket, default: []].append(CleanupEntry(
                    item: item,
                    bucket: bucket,
                    reason: CleanupReason(kind: kind, text: text),
                    buyerCents: buyer,
                    sellerCents: seller,
                    copies: copies
                ))
            }

            if protected.contains(item.id) {
                add(.keep, .starred, "Starred")
                continue
            }
            if let bucket = overrides[item.id] {
                add(bucket, .movedByYou, "Moved by you")
                continue
            }
            // One copy of a piece is enough for the set; extra copies can still go.
            if rules.keepSetPieces, !isExtra, let set = item.itemSet {
                let owned = ownership.owned(set, appID: item.appID)
                if owned >= rules.setThreshold {
                    add(.keep, .setPiece, "Set: \(owned) of \(set.members.count)")
                    continue
                }
            }
            guard let buyer, let seller else {
                add(.keep, .notPriced, "Not priced yet")
                continue
            }
            if rules.holdRising, let change = trends[item.priceKey], change >= rules.risingThreshold {
                add(.keep, .rising, "Up \(Int((change * 100).rounded()))% this month")
                continue
            }

            let candidate: (kind: CleanupReason.Kind, text: String)
            if isExtra {
                candidate = (.extraCopy, "Extra copy · you have \(copies)")
            } else if rules.sellCheap && buyer < rules.cheapBelowCents {
                candidate = (.cheap, "Under \(Money.format(rules.cheapBelowCents, currency))")
            } else if rules.sellEverythingElse {
                candidate = (.everythingElse, "Everything else")
            } else if rules.sellDuplicates && copies > 1 {
                add(.keep, .keptCopy, item.wear == nil ? "Keeping 1 of \(copies)" : "Lowest float of \(copies)")
                continue
            } else {
                add(.keep, .noRule, keepText(rules, currency: currency))
                continue
            }

            let extra = isExtra ? " · extra copy" : ""
            if rules.reviewExpensive && buyer >= rules.reviewAboveCents {
                add(.review, .expensive, "Worth \(Money.format(buyer, currency))" + extra)
                continue
            }
            if rules.reviewLowFloats, let wear = item.wear, Exterior.position(of: wear) < rules.lowFloatShare {
                add(.review, .lowFloat, "Float \(FloatText.short(wear)) · \(lowFloatText(wear))" + extra)
                continue
            }
            if rules.reviewApplied, let applied = item.skin?.appliedSummary {
                add(.review, .applied, "With \(applied)" + extra)
                continue
            }
            if seller <= 1 && !rules.sellFloorItems {
                add(.keep, .floorPrice, "Pays only \(Money.format(seller, currency))")
                continue
            }
            add(.sell, candidate.kind, candidate.text)
        }

        for bucket in CleanupBucket.allCases {
            buckets[bucket]?.sort { lhs, rhs in
                let left = lhs.buyerCents ?? -1
                let right = rhs.buyerCents ?? -1
                if left != right { return left > right }
                if lhs.item.name != rhs.item.name { return lhs.item.name < rhs.item.name }
                return CopyIndex.isOlder(lhs.item, rhs.item)
            }
        }
        return CleanupPlan(entries: buckets, unpricedCount: unpriced)
    }

    /// "cleanest 2% of Factory New"
    static func lowFloatText(_ wear: Double) -> String {
        "cleanest \(Exterior.cleanestPercent(of: wear))% of \(Exterior.of(wear).title)"
    }

    /// Why a priced item no selling rule picked is kept.
    private static func keepText(_ rules: CleanupRules, currency: SteamCurrency) -> String {
        if rules.sellDuplicates { return "Only copy" }
        if rules.sellCheap { return "\(Money.format(rules.cheapBelowCents, currency)) or more" }
        return "No selling rule"
    }

    /// The buyer price to list at, clamped to the floor.
    static func listingPrice(for quote: PriceQuote, rules: CleanupRules) -> Int? {
        let raw: Int?
        switch rules.pricing {
        case .lowestListing: raw = quote.lowestCents ?? quote.medianCents
        case .undercutLowest: raw = (quote.lowestCents ?? quote.medianCents).map { $0 - 1 }
        case .medianSale: raw = quote.medianCents ?? quote.lowestCents
        }
        guard let raw else { return nil }
        return max(raw, rules.floorCents, SteamFees.floorBuyerCents)
    }
}

/// Which assets are extra copies of an item. Copies share a market hash name
/// (and, for a Doppler, a phase), and a stack counts as one copy. The copy kept
/// is a starred one; failing that, for CS2 skins, the lowest float, even if it
/// can't be sold; for anything else, one that can't be sold anyway, or the oldest.
nonisolated struct CopyIndex: Sendable {
    private var counts: [String: Int] = [:]
    private var extras: Set<String> = []

    init(items: [InventoryItem], protected: Set<String> = []) {
        var groups: [String: [InventoryItem]] = [:]
        for item in items {
            groups[item.copyKey, default: []].append(item)
        }
        for (key, group) in groups {
            counts[key] = group.count
            guard group.count > 1 else { continue }
            var sellable = group.filter { $0.marketable && !protected.contains($0.id) }
            if let kept = Self.keeper(of: group, protected: protected) {
                sellable.removeAll { $0.id == kept.id }
            }
            extras.formUnion(sellable.map(\.id))
        }
    }

    /// The copy to keep, or nil when a starred or unsellable copy already stays.
    private static func keeper(of group: [InventoryItem], protected: Set<String>) -> InventoryItem? {
        if group.contains(where: { protected.contains($0.id) }) { return nil }
        if group.contains(where: { $0.wear != nil }) { return group.min(by: isBetter) }
        if group.contains(where: { !$0.marketable }) { return nil }
        return group.min(by: isOlder)
    }

    /// Copies of this item, counting ones that can't be sold.
    func copies(of item: InventoryItem) -> Int { counts[item.copyKey] ?? 1 }

    func isExtra(_ item: InventoryItem) -> Bool { extras.contains(item.id) }

    /// Asset ids grow over time, so a shorter or smaller id is older.
    static func isOlder(_ lhs: InventoryItem, _ rhs: InventoryItem) -> Bool {
        lhs.assetID.count != rhs.assetID.count ? lhs.assetID.count < rhs.assetID.count : lhs.assetID < rhs.assetID
    }

    /// The lower float first, then the older copy. Copies without a float come last.
    static func isBetter(_ lhs: InventoryItem, _ rhs: InventoryItem) -> Bool {
        switch (lhs.wear, rhs.wear) {
        case let (left?, right?) where left != right: left < right
        case (.some, nil): true
        case (nil, .some): false
        default: isOlder(lhs, rhs)
        }
    }
}

/// Counts how many distinct pieces of each set a profile owns.
nonisolated struct SetOwnership: Sendable {
    private var namesByApp: [Int: Set<String>] = [:]

    init(items: [InventoryItem]) {
        for item in items {
            namesByApp[item.appID, default: []].insert(item.baseName.lowercased())
        }
    }

    func owned(_ set: ItemSetInfo, appID: Int) -> Int {
        guard let names = namesByApp[appID] else { return 0 }
        return Set(set.members.map { $0.lowercased() }).filter { names.contains($0) }.count
    }
}

// MARK: - Valuation

nonisolated struct Valuation: Equatable, Sendable {
    /// Sum of what buyers would pay at current prices.
    var buyerCents = 0
    /// Sum of what would reach the Steam Wallet after fees.
    var sellerCents = 0
    var marketableCount = 0
    var pricedCount = 0

    var unpricedCount: Int { marketableCount - pricedCount }

    static func of(_ items: [InventoryItem], prices: [String: PriceQuote]) -> Valuation {
        var result = Valuation()
        for item in items where item.marketable {
            result.marketableCount += item.amount
            guard let value = prices[item.priceKey]?.valueCents else { continue }
            result.pricedCount += item.amount
            result.buyerCents += value * item.amount
            result.sellerCents += SteamFees.sellerReceives(buyerPays: value) * item.amount
        }
        return result
    }
}

/// A day's price for one market hash name, kept so trends can be computed locally.
nonisolated struct PricePoint: Codable, Hashable, Sendable {
    var day: Date
    var cents: Int
}

nonisolated enum PriceTrend {
    /// Relative change from the point closest to `days` ago to the latest point.
    /// Returns nil without at least two points spanning a day.
    static func change(_ history: [PricePoint], days: Int, now: Date = Date()) -> Double? {
        guard let latest = history.max(by: { $0.day < $1.day }) else { return nil }
        let target = now.addingTimeInterval(-Double(days) * 86_400)
        guard let base = history
            .filter({ $0.day < latest.day })
            .min(by: { abs($0.day.timeIntervalSince(target)) < abs($1.day.timeIntervalSince(target)) }),
              base.cents > 0
        else { return nil }
        return Double(latest.cents - base.cents) / Double(base.cents)
    }

    /// Adds or replaces today's point and keeps the most recent `limit` days.
    static func appending(_ cents: Int, on day: Date, to history: [PricePoint], limit: Int = 120) -> [PricePoint] {
        var result = history.filter { $0.day != day }
        result.append(PricePoint(day: day, cents: cents))
        result.sort { $0.day < $1.day }
        if result.count > limit { result.removeFirst(result.count - limit) }
        return result
    }
}
