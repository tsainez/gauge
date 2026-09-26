//
//  Cleanup.swift
//  gauge
//
//  Sorts marketable items into buckets by the user's rules. Pure and
//  synchronous so it can run on every rule change and be unit tested.
//

import Foundation

nonisolated enum CleanupBucket: String, Codable, CaseIterable, Identifiable, Sendable {
    case sell
    case floor
    case review
    case keep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sell: "Sell"
        case .floor: "Floor items"
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
    var keepSets = true
    /// Keep every piece of a set once this many of its pieces are owned.
    var setThreshold = 3
    var keepStarred = true
    var pricing: ListingPriceStrategy = .lowestListing
    /// Never list below this buyer price. Steam's own floor is $0.03.
    var floorCents = SteamFees.floorBuyerCents
    var holdRising = false
    /// 0.20 holds anything up 20% or more over the last 30 days.
    var risingThreshold = 0.20
    var reviewExpensive = true
    /// Items at or above this buyer price go to "Worth a look" instead of being sold.
    var reviewAboveCents = 500
    /// Floor items only pay $0.01 each. Sell them in bulk, or keep them.
    var sellFloorItems = false
}

/// Decodes with defaults so rules saved by an older version keep working.
extension CleanupRules {
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CleanupRules()
        keepSets = (try? c.decodeIfPresent(Bool.self, forKey: .keepSets)) ?? d.keepSets
        setThreshold = (try? c.decodeIfPresent(Int.self, forKey: .setThreshold)) ?? d.setThreshold
        keepStarred = (try? c.decodeIfPresent(Bool.self, forKey: .keepStarred)) ?? d.keepStarred
        pricing = (try? c.decodeIfPresent(ListingPriceStrategy.self, forKey: .pricing)) ?? d.pricing
        floorCents = (try? c.decodeIfPresent(Int.self, forKey: .floorCents)) ?? d.floorCents
        holdRising = (try? c.decodeIfPresent(Bool.self, forKey: .holdRising)) ?? d.holdRising
        risingThreshold = (try? c.decodeIfPresent(Double.self, forKey: .risingThreshold)) ?? d.risingThreshold
        reviewExpensive = (try? c.decodeIfPresent(Bool.self, forKey: .reviewExpensive)) ?? d.reviewExpensive
        reviewAboveCents = (try? c.decodeIfPresent(Int.self, forKey: .reviewAboveCents)) ?? d.reviewAboveCents
        sellFloorItems = (try? c.decodeIfPresent(Bool.self, forKey: .sellFloorItems)) ?? d.sellFloorItems
    }
}

nonisolated struct CleanupEntry: Identifiable, Hashable, Sendable {
    var item: InventoryItem
    var bucket: CleanupBucket
    var reason: String
    /// Price a buyer pays per unit when listed, if the item is priced.
    var buyerCents: Int?
    /// What the seller receives per unit after fees.
    var sellerCents: Int?

    var id: String { item.id }
    var totalSellerCents: Int { (sellerCents ?? 0) * item.amount }
}

nonisolated struct CleanupPlan: Sendable {
    var entries: [CleanupBucket: [CleanupEntry]]
    var unpricedCount: Int

    func entries(in bucket: CleanupBucket) -> [CleanupEntry] { entries[bucket] ?? [] }

    func receive(in bucket: CleanupBucket) -> Int {
        entries(in: bucket).reduce(0) { $0 + $1.totalSellerCents }
    }

    /// Entries that will be listed when the user confirms.
    func listings(sellFloorItems: Bool) -> [CleanupEntry] {
        var result = entries(in: .sell)
        if sellFloorItems { result += entries(in: .floor) }
        return result.filter { $0.buyerCents != nil }
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
        var buckets: [CleanupBucket: [CleanupEntry]] = [:]
        var unpriced = 0

        for item in items where item.marketable {
            let quote = prices[item.priceKey]
            let buyer = quote.flatMap { listingPrice(for: $0, rules: rules) }
            let seller = buyer.map { SteamFees.sellerReceives(buyerPays: $0) }
            if buyer == nil { unpriced += 1 }

            func add(_ bucket: CleanupBucket, _ reason: String) {
                buckets[bucket, default: []].append(
                    CleanupEntry(item: item, bucket: bucket, reason: reason, buyerCents: buyer, sellerCents: seller)
                )
            }

            if rules.keepStarred && starred.contains(item.id) {
                add(.keep, "Starred")
                continue
            }
            if let bucket = overrides[item.id] {
                add(bucket, "Moved by you")
                continue
            }
            if rules.keepSets, let set = item.itemSet {
                let owned = ownership.owned(set, appID: item.appID)
                if owned >= rules.setThreshold {
                    add(.keep, "Set: \(owned) of \(set.members.count)")
                    continue
                }
            }
            guard let buyer, let seller else {
                add(.keep, "Not priced yet")
                continue
            }
            if rules.holdRising, let change = trends[item.priceKey], change >= rules.risingThreshold {
                add(.keep, "Up \(Int((change * 100).rounded()))% this month")
                continue
            }
            if rules.reviewExpensive && buyer >= rules.reviewAboveCents {
                add(.review, "Worth \(Money.format(buyer, currency))")
                continue
            }
            if seller <= 1 {
                add(.floor, "Pays \(Money.format(seller, currency))")
                continue
            }
            add(.sell, "Pays \(Money.format(seller, currency))")
        }

        for bucket in CleanupBucket.allCases {
            buckets[bucket]?.sort { lhs, rhs in
                let left = lhs.buyerCents ?? -1
                let right = rhs.buyerCents ?? -1
                return left != right ? left > right : lhs.item.name < rhs.item.name
            }
        }
        return CleanupPlan(entries: buckets, unpricedCount: unpriced)
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
