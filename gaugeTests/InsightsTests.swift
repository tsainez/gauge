//
//  InsightsTests.swift
//  gaugeTests
//

import Foundation
import Testing
@testable import gauge

struct InsightsTests {
    let holdings: [Holding] = {
        let items = [
            CleanupPlannerTests.item("3", "Crest"),
            CleanupPlannerTests.item("2", "Crest"),
            CleanupPlannerTests.item("4", "Relic"),
            CleanupPlannerTests.item("5", "Dust"),
            CleanupPlannerTests.item("6", "Dust"),
            CleanupPlannerTests.item("7", "Dust"),
            CleanupPlannerTests.item("8", "Gems", amount: 12),
            CleanupPlannerTests.item("9", "Unknown"),
            CleanupPlannerTests.item("10", "Locked", marketable: false),
        ]
        var prices: [String: PriceQuote] = [:]
        for (name, cents) in ["Crest": 367, "Relic": 2_500, "Dust": 3, "Gems": 42, "Locked": 9_999] {
            prices["570|\(name)"] = CleanupPlannerTests.quote(cents)
        }
        let changes = ["570|Crest": 0.12, "570|Relic": -0.30, "570|Dust": 0.66, "570|Gems": 0.005]
        return PortfolioInsights.holdings(items, prices: prices, weeklyChange: changes)
    }()

    @Test func groupsCopiesAndSkipsWhatCantBeSold() {
        #expect(holdings.map(\.item.name) == ["Crest", "Relic", "Dust", "Gems", "Unknown"])
        let crest = holdings[0]
        #expect(crest.copies == 2)
        #expect(crest.item.assetID == "2")
        #expect(crest.totalCents == 734)
        let gems = holdings[3]
        #expect(gems.copies == 1)
        #expect(gems.units == 12)
        #expect(gems.totalCents == 504)
    }

    @Test func ranksMostValuable() {
        #expect(PortfolioInsights.mostValuable(holdings).map(\.item.name) == ["Relic", "Crest", "Gems", "Dust"])
        #expect(PortfolioInsights.mostValuable(holdings, limit: 1).count == 1)
    }

    @Test func moversIgnoreCheapNoiseAndTinyChanges() {
        let movers = PortfolioInsights.movers(holdings, minimumCents: 10)
        #expect(movers.map(\.item.name) == ["Relic", "Crest"])
    }

    @Test func mostCopiesPutsDuplicatesFirst() {
        #expect(PortfolioInsights.mostCopies(holdings).map(\.item.name) == ["Dust", "Crest"])
    }
}

struct NetWorthAxisTests {
    @Test func valueAxisLeavesRoom() {
        #expect(NetWorthAxis.valueDomain([20_000, 30_000]) == 180...320)
        // A single day still gets a scale around its value.
        let one = NetWorthAxis.valueDomain([26_414])
        #expect(one.lowerBound < 264.14 && one.upperBound > 264.14)
        #expect(NetWorthAxis.valueDomain([0]) == 0...1)
        #expect(NetWorthAxis.valueDomain([]) == 0...1)
    }

    @Test func dateAxisSpansTheWholeRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 100 * 86_400 + 3_600)
        let today = calendar.startOfDay(for: now)
        let half: TimeInterval = 12 * 3_600

        let month = NetWorthAxis.dayDomain([today], window: 30, now: now, calendar: calendar)
        #expect(month.lowerBound == today.addingTimeInterval(-30 * 86_400 - half))
        #expect(month.upperBound == today.addingTimeInterval(half))

        let shortLifetime = NetWorthAxis.dayDomain([today.addingTimeInterval(-2 * 86_400), today], window: nil, now: now, calendar: calendar)
        #expect(shortLifetime.lowerBound == today.addingTimeInterval(-7 * 86_400 - half))

        let longLifetime = NetWorthAxis.dayDomain([today.addingTimeInterval(-90 * 86_400), today], window: nil, now: now, calendar: calendar)
        #expect(longLifetime.lowerBound == today.addingTimeInterval(-90 * 86_400 - half))
    }
}
