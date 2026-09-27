//
//  Insights.swift
//  gauge
//
//  What the Portfolio tab lists under the chart: the most valuable items,
//  the biggest price moves this week, and the items owned in the most
//  copies. Items are grouped by market hash name, since copies of an item
//  share a price.
//

import Foundation

/// Every copy of one marketable item.
nonisolated struct Holding: Identifiable, Hashable, Sendable {
    /// The oldest copy, standing in for the rest.
    var item: InventoryItem
    /// Separate copies. A stack counts once, as in Clean up.
    var copies: Int
    /// Units across every copy, counting whole stacks.
    var units: Int
    /// What a buyer pays for one, when priced.
    var unitCents: Int?
    /// Relative price change over the last week, when there's enough history.
    var weeklyChange: Double?

    var id: String { item.priceKey }
    var totalCents: Int { (unitCents ?? 0) * units }
}

nonisolated enum PortfolioInsights {
    static func holdings(_ items: [InventoryItem], prices: [String: PriceQuote], weeklyChange: [String: Double] = [:]) -> [Holding] {
        var order: [String] = []
        var groups: [String: [InventoryItem]] = [:]
        for item in items where item.marketable {
            if groups[item.priceKey] == nil { order.append(item.priceKey) }
            groups[item.priceKey, default: []].append(item)
        }
        return order.compactMap { key in
            guard let group = groups[key], let oldest = group.min(by: CopyIndex.isOlder) else { return nil }
            return Holding(
                item: oldest,
                copies: group.count,
                units: group.reduce(0) { $0 + $1.amount },
                unitCents: prices[key]?.valueCents,
                weeklyChange: weeklyChange[key]
            )
        }
    }

    /// Priced items, most expensive first.
    static func mostValuable(_ holdings: [Holding], limit: Int = 8) -> [Holding] {
        let priced = holdings.filter { $0.unitCents != nil }
        return Array(priced.sorted { lhs, rhs in
            let l = lhs.unitCents ?? 0, r = rhs.unitCents ?? 0
            return l != r ? l > r : byName(lhs, rhs)
        }.prefix(limit))
    }

    /// The biggest moves either way over the last week. Items under `minimumCents`
    /// are left out, since a cent's change on a $0.03 item reads as a 33% swing.
    static func movers(_ holdings: [Holding], minimumCents: Int, limit: Int = 8) -> [Holding] {
        let moving = holdings.filter { holding in
            guard let change = holding.weeklyChange, let cents = holding.unitCents else { return false }
            return cents >= minimumCents && abs(change) >= 0.01
        }
        return Array(moving.sorted { lhs, rhs in
            let l = abs(lhs.weeklyChange ?? 0), r = abs(rhs.weeklyChange ?? 0)
            return l != r ? l > r : byName(lhs, rhs)
        }.prefix(limit))
    }

    /// Items owned more than once, most copies first.
    static func mostCopies(_ holdings: [Holding], limit: Int = 8) -> [Holding] {
        let repeated = holdings.filter { $0.copies > 1 }
        return Array(repeated.sorted { lhs, rhs in
            if lhs.copies != rhs.copies { return lhs.copies > rhs.copies }
            let l = lhs.unitCents ?? -1, r = rhs.unitCents ?? -1
            return l != r ? l > r : byName(lhs, rhs)
        }.prefix(limit))
    }

    private static func byName(_ lhs: Holding, _ rhs: Holding) -> Bool {
        let order = lhs.item.name.localizedStandardCompare(rhs.item.name)
        return order != .orderedSame ? order == .orderedAscending : lhs.id < rhs.id
    }
}

/// Scales for the Portfolio chart.
nonisolated enum NetWorthAxis {
    /// The value axis, in whole currency units: the lowest and highest values with
    /// room around them, so a flat or one-day history still gets a readable scale.
    static func valueDomain(_ cents: [Int]) -> ClosedRange<Double> {
        guard let low = cents.min(), let high = cents.max() else { return 0...1 }
        let lo = Double(low) / 100, hi = Double(high) / 100
        let pad = hi > lo ? (hi - lo) * 0.2 : max(hi * 0.05, 1)
        return max(0, lo - pad)...(hi + pad)
    }

    /// The date axis covers the whole range even before history fills it, so a new
    /// history reads as starting partway through. Lifetime spans at least a week.
    /// Half a day of margin keeps the first and last points off the edges.
    static func dayDomain(_ days: [Date], window: Int?, now: Date = Date(), calendar: Calendar = .current) -> ClosedRange<Date> {
        let today = calendar.startOfDay(for: now)
        let latest = max(today, days.max() ?? today)
        let earliest = days.min() ?? latest
        let span = window ?? max(7, calendar.dateComponents([.day], from: earliest, to: latest).day ?? 7)
        let start = calendar.date(byAdding: .day, value: -span, to: latest) ?? latest
        let half: TimeInterval = 12 * 3_600
        return start.addingTimeInterval(-half)...latest.addingTimeInterval(half)
    }
}
