//
//  CleanupTests.swift
//  gaugeTests
//

import Foundation
import Testing
@testable import gauge

struct CleanupPlannerTests {
    static func item(
        _ asset: String,
        _ name: String,
        set: ItemSetInfo? = nil,
        marketable: Bool = true,
        amount: Int = 1
    ) -> InventoryItem {
        InventoryItem(
            appID: 570, contextID: "2", assetID: asset, classID: asset, instanceID: "0",
            amount: amount, name: name, baseName: name, marketHashName: name, type: "Wearable",
            iconHash: nil, nameColor: nil, marketable: marketable, tradable: true, commodity: false,
            tags: [], details: [], itemSet: set
        )
    }

    static func quote(_ lowest: Int?, median: Int? = nil) -> PriceQuote {
        PriceQuote(lowestCents: lowest, medianCents: median, volume: 10, checkedAt: Date(), currency: .usd)
    }

    static let solstice = ItemSetInfo(name: "Song of the Solstice", members: ["Neck", "Arms", "Belt", "Head", "Weapon"])

    func plan(
        _ items: [InventoryItem],
        _ prices: [String: Int?],
        starred: Set<String> = [],
        overrides: [String: CleanupBucket] = [:],
        trends: [String: Double] = [:],
        rules: CleanupRules = CleanupRules()
    ) -> CleanupPlan {
        var quotes: [String: PriceQuote] = [:]
        for (name, cents) in prices { quotes["570|\(name)"] = Self.quote(cents) }
        return CleanupPlanner.plan(items: items, prices: quotes, trends: trends, starred: starred, overrides: overrides, rules: rules, currency: .usd)
    }

    @Test func sortsByPayout() {
        let items = [
            Self.item("1", "Crest"),
            Self.item("2", "Dust"),
            Self.item("3", "Relic"),
            Self.item("4", "Unknown"),
            Self.item("5", "Locked", marketable: false),
        ]
        let result = plan(items, ["Crest": 367, "Dust": 3, "Relic": 2_500])

        #expect(result.entries(in: .sell).map(\.item.name) == ["Crest"])
        #expect(result.entries(in: .floor).map(\.item.name) == ["Dust"])
        #expect(result.entries(in: .review).map(\.item.name) == ["Relic"])
        #expect(result.entries(in: .keep).map(\.reason) == ["Not priced yet"])
        #expect(result.unpricedCount == 1)
        #expect(result.receive(in: .sell) == 319)
    }

    @Test func starredItemsAreAlwaysKept() {
        let items = [Self.item("1", "Crest")]
        let result = plan(items, ["Crest": 367], starred: ["570_2_1"], overrides: ["570_2_1": .sell])
        #expect(result.entries(in: .keep).first?.reason == "Starred")
        #expect(result.entries(in: .sell).isEmpty)
    }

    @Test func keepsSetsAboveThreshold() {
        let set = Self.solstice
        let three = [Self.item("1", "Neck", set: set), Self.item("2", "Arms", set: set), Self.item("3", "Belt", set: set)]
        let kept = plan(three, ["Neck": 10, "Arms": 10, "Belt": 10])
        #expect(kept.entries(in: .keep).count == 3)
        #expect(kept.entries(in: .keep).first?.reason == "Set: 3 of 5")

        let two = Array(three.prefix(2))
        let sold = plan(two, ["Neck": 10, "Arms": 10])
        #expect(sold.entries(in: .sell).count == 2)
    }

    @Test func holdsRisingItemsWhenAsked() {
        var rules = CleanupRules()
        rules.holdRising = true
        let result = plan([Self.item("1", "Crest")], ["Crest": 100], trends: ["570|Crest": 0.35], rules: rules)
        #expect(result.entries(in: .keep).first?.reason == "Up 35% this month")
    }

    @Test func overridesMoveItems() {
        let result = plan([Self.item("1", "Relic")], ["Relic": 2_500], overrides: ["570_2_1": .sell])
        #expect(result.entries(in: .sell).count == 1)
        #expect(result.listings(sellFloorItems: false).count == 1)
    }

    @Test func floorItemsOnlyListWhenChosen() {
        let result = plan([Self.item("1", "Dust"), Self.item("2", "Crest")], ["Dust": 3, "Crest": 50])
        #expect(result.listings(sellFloorItems: false).map(\.item.name) == ["Crest"])
        #expect(result.listings(sellFloorItems: true).count == 2)
    }

    @Test func listingPriceNeverDropsBelowFloor() {
        var rules = CleanupRules()
        rules.pricing = .undercutLowest
        #expect(CleanupPlanner.listingPrice(for: Self.quote(3), rules: rules) == 3)
        #expect(CleanupPlanner.listingPrice(for: Self.quote(50), rules: rules) == 49)
        rules.pricing = .medianSale
        #expect(CleanupPlanner.listingPrice(for: Self.quote(50, median: 40), rules: rules) == 40)
        #expect(CleanupPlanner.listingPrice(for: Self.quote(nil), rules: rules) == nil)
    }
}

struct ValuationTests {
    @Test func valuesMarketableItemsAtLowestListing() {
        let items = [
            CleanupPlannerTests.item("1", "Crest"),
            CleanupPlannerTests.item("2", "Gems", amount: 10),
            CleanupPlannerTests.item("3", "Unknown"),
            CleanupPlannerTests.item("4", "Locked", marketable: false),
        ]
        let prices = [
            "570|Crest": CleanupPlannerTests.quote(367),
            "570|Gems": CleanupPlannerTests.quote(3),
            "570|Locked": CleanupPlannerTests.quote(9_999),
        ]
        let value = Valuation.of(items, prices: prices)
        #expect(value.buyerCents == 367 + 30)
        #expect(value.sellerCents == 319 + 10)
        #expect(value.marketableCount == 12)
        #expect(value.unpricedCount == 1)
    }
}

struct PriceTrendTests {
    @Test func measuresChangeOverWindow() {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let history = [
            PricePoint(day: now.addingTimeInterval(-31 * 86_400), cents: 100),
            PricePoint(day: now.addingTimeInterval(-10 * 86_400), cents: 110),
            PricePoint(day: now, cents: 125),
        ]
        let change = PriceTrend.change(history, days: 30, now: now)
        #expect(change == 0.25)
        #expect(PriceTrend.change(Array(history.suffix(1)), days: 30, now: now) == nil)
    }

    @Test func appendingReplacesSameDayAndCaps() {
        let day = Date(timeIntervalSince1970: 0)
        var history = PriceTrend.appending(10, on: day, to: [])
        history = PriceTrend.appending(12, on: day, to: history)
        #expect(history == [PricePoint(day: day, cents: 12)])

        for offset in 1...10 {
            history = PriceTrend.appending(offset, on: day.addingTimeInterval(Double(offset) * 86_400), to: history, limit: 5)
        }
        #expect(history.count == 5)
        #expect(history.last?.cents == 10)
    }
}

struct DemoDataTests {
    @Test func matchesTheStoryboardCounts() {
        let demo = DemoData.make(now: Date(timeIntervalSince1970: 1_790_000_000))
        let dota = demo.itemsByContext["570_2"] ?? []
        #expect(dota.count == 3_029)
        #expect(dota.filter(\.marketable).count == 1_071)
        #expect(demo.itemsByContext["753_6"]?.count == 540)
        #expect(demo.contexts.count == 11)
        #expect(demo.starred.count >= 2)
        #expect(demo.snapshots.count == 150)
    }

    @Test func isDeterministic() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let first = DemoData.make(now: now)
        let second = DemoData.make(now: now)
        #expect(first.itemsByContext["570_2"]?.map(\.id) == second.itemsByContext["570_2"]?.map(\.id))
        #expect(first.prices == second.prices)
    }

    @Test func everyMarketableItemIsPriced() {
        let demo = DemoData.make()
        let all = demo.itemsByContext.values.flatMap { $0 }
        #expect(Valuation.of(all, prices: demo.prices).unpricedCount == 0)
    }

    @Test func completeSetIsDetectable() {
        let demo = DemoData.make()
        let dota = demo.itemsByContext["570_2"] ?? []
        let plan = CleanupPlanner.plan(items: dota, prices: demo.prices, trends: [:], starred: [], overrides: [:], rules: CleanupRules(), currency: .usd)
        #expect(plan.entries(in: .keep).contains { $0.reason == "Set: 5 of 5" })
    }
}
