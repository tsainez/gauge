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

    @Test func sellsExtraCopiesAndCheapItemsByDefault() {
        let items = [
            Self.item("11", "Crest"),
            Self.item("12", "Crest"),
            Self.item("10", "Crest"),
            Self.item("2", "Dust"),
            Self.item("3", "Relic"),
            Self.item("4", "Unknown"),
            Self.item("5", "Locked", marketable: false),
        ]
        let result = plan(items, ["Crest": 367, "Dust": 3, "Relic": 2_500])

        let sell = result.entries(in: .sell)
        #expect(sell.map(\.item.assetID) == ["11", "12", "2"])
        #expect(sell.first?.reason == CleanupReason(kind: .extraCopy, text: "Extra copy · you have 3"))
        #expect(sell.last?.reason == CleanupReason(kind: .cheap, text: "Under \(Money.format(10, .usd))"))
        #expect(sell.first?.copies == 3)

        let keep = result.entries(in: .keep)
        // The oldest copy is the one kept.
        #expect(keep.first { $0.item.name == "Crest" }?.item.assetID == "10")
        #expect(keep.first { $0.item.name == "Crest" }?.reason.text == "Keeping 1 of 3")
        #expect(keep.first { $0.item.name == "Relic" }?.reason.text == "Only copy")
        #expect(keep.first { $0.item.name == "Unknown" }?.reason.kind == .notPriced)
        #expect(result.entries(in: .review).isEmpty)
        #expect(result.unpricedCount == 1)
        #expect(result.receive(in: .sell) == 319 * 2 + 1)
        #expect(result.listings.count == 3)
    }

    @Test func keepsTheCopyThatCantBeSoldOrIsStarred() {
        let locked = [Self.item("1", "Crest", marketable: false), Self.item("2", "Crest"), Self.item("3", "Crest")]
        let lockedPlan = plan(locked, ["Crest": 367])
        #expect(lockedPlan.entries(in: .sell).map(\.item.assetID) == ["2", "3"])

        let loose = [Self.item("1", "Crest"), Self.item("2", "Crest"), Self.item("3", "Crest")]
        let starredPlan = plan(loose, ["Crest": 367], starred: ["570_2_3"])
        #expect(starredPlan.entries(in: .sell).map(\.item.assetID) == ["1", "2"])
        #expect(starredPlan.entries(in: .keep).map(\.reason.kind) == [.starred])
    }

    @Test func aStackIsOneCopy() {
        let result = plan([Self.item("1", "Gems", amount: 10)], ["Gems": 42])
        #expect(result.entries(in: .keep).first?.reason.text == "Only copy")
        #expect(result.itemCount(in: .keep) == 10)
    }

    @Test func everythingElseSellsTheRestAndHoldsExpensiveItems() {
        var rules = CleanupRules()
        rules.sellEverythingElse = true
        let result = plan([Self.item("1", "Crest"), Self.item("2", "Relic")], ["Crest": 367, "Relic": 2_500], rules: rules)
        #expect(result.entries(in: .sell).map(\.reason.kind) == [.everythingElse])
        #expect(result.entries(in: .review).first?.reason.text == "Worth \(Money.format(2_500, .usd))")
    }

    @Test func expensiveExtraCopiesWaitForALook() {
        let result = plan([Self.item("1", "Relic"), Self.item("2", "Relic")], ["Relic": 2_500])
        #expect(result.entries(in: .review).map(\.item.assetID) == ["2"])
        #expect(result.entries(in: .review).first?.reason.text == "Worth \(Money.format(2_500, .usd)) · extra copy")
        #expect(result.entries(in: .keep).map(\.item.assetID) == ["1"])
    }

    @Test func floorItemsCanBeKept() {
        var rules = CleanupRules()
        rules.sellFloorItems = false
        let result = plan([Self.item("1", "Dust"), Self.item("2", "Lint")], ["Dust": 3, "Lint": 8], rules: rules)
        #expect(result.entries(in: .keep).map(\.reason.text) == ["Pays only \(Money.format(1, .usd))"])
        #expect(result.entries(in: .sell).map(\.item.name) == ["Lint"])
        #expect(result.entries(in: .sell).first?.paysFloor == false)
    }

    @Test func rulesCanBeTurnedOff() {
        var rules = CleanupRules()
        rules.sellDuplicates = false
        let items = [Self.item("1", "Crest"), Self.item("2", "Crest"), Self.item("3", "Dust")]
        let noDuplicates = plan(items, ["Crest": 367, "Dust": 3], rules: rules)
        #expect(noDuplicates.entries(in: .sell).map(\.item.name) == ["Dust"])
        #expect(noDuplicates.entries(in: .keep).first?.reason.text == "\(Money.format(10, .usd)) or more")

        rules.sellCheap = false
        let nothing = plan(items, ["Crest": 367, "Dust": 3], rules: rules)
        #expect(nothing.entries(in: .sell).isEmpty)
        #expect(nothing.entries(in: .keep).allSatisfy { $0.reason.kind == .noRule })
    }

    @Test func starredItemsAreAlwaysKept() {
        let items = [Self.item("1", "Crest")]
        let result = plan(items, ["Crest": 367], starred: ["570_2_1"], overrides: ["570_2_1": .sell])
        #expect(result.entries(in: .keep).first?.reason.text == "Starred")
        #expect(result.entries(in: .sell).isEmpty)
    }

    @Test func setPiecesAreOnlyKeptWhenAsked() {
        let set = Self.solstice
        let three = [
            Self.item("1", "Neck", set: set), Self.item("2", "Arms", set: set), Self.item("3", "Belt", set: set),
            Self.item("4", "Neck", set: set),
        ]
        let prices: [String: Int?] = ["Neck": 5, "Arms": 5, "Belt": 5]
        #expect(plan(three, prices).entries(in: .sell).count == 4)

        var rules = CleanupRules()
        rules.keepSetPieces = true
        let kept = plan(three, prices, rules: rules)
        #expect(kept.entries(in: .keep).count == 3)
        #expect(kept.entries(in: .keep).first?.reason.text == "Set: 3 of 5")
        // The second Neck isn't needed for the set.
        #expect(kept.entries(in: .sell).map(\.item.assetID) == ["4"])

        rules.setThreshold = 4
        #expect(plan(three, prices, rules: rules).entries(in: .keep).isEmpty)
    }

    @Test func holdsRisingItemsWhenAsked() {
        var rules = CleanupRules()
        rules.holdRising = true
        let result = plan([Self.item("1", "Crest")], ["Crest": 100], trends: ["570|Crest": 0.35], rules: rules)
        #expect(result.entries(in: .keep).first?.reason.text == "Up 35% this month")
    }

    @Test func overridesMoveItems() {
        let result = plan([Self.item("1", "Relic")], ["Relic": 2_500], overrides: ["570_2_1": .sell])
        #expect(result.entries(in: .sell).first?.reason.kind == .movedByYou)
        #expect(result.listings.count == 1)
    }

    @Test func unpricedItemsAreNeverListed() {
        let result = plan([Self.item("1", "Unknown")], [:], overrides: ["570_2_1": .sell])
        #expect(result.entries(in: .sell).count == 1)
        #expect(result.listings.isEmpty)
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

    @Test func olderRulesDecodeWithTheNewDefaults() throws {
        let json = Data(#"{"keepSets":true,"sellFloorItems":false,"reviewAboveCents":1000}"#.utf8)
        let rules = try JSONDecoder().decode(CleanupRules.self, from: json)
        #expect(!rules.keepSetPieces)
        #expect(!rules.sellFloorItems)
        #expect(rules.reviewAboveCents == 1_000)
        #expect(rules.sellDuplicates && rules.sellCheap && !rules.sellEverythingElse)
    }
}

struct CleanupRowTests {
    let plan: CleanupPlan = {
        var crest = [CleanupPlannerTests.item("10", "Crest"), CleanupPlannerTests.item("11", "Crest"), CleanupPlannerTests.item("12", "Crest")]
        crest[0].tags = [ItemTag(category: "Hero", categoryName: "Hero", internalName: "lc", name: "Legion Commander", color: nil)]
        let items = crest + [
            CleanupPlannerTests.item("2", "Dust"),
            CleanupPlannerTests.item("3", "Lint"),
            CleanupPlannerTests.item("4", "Lint"),
        ]
        var quotes: [String: PriceQuote] = [:]
        for (name, cents) in ["Crest": 367, "Dust": 3, "Lint": 8] { quotes["570|\(name)"] = CleanupPlannerTests.quote(cents) }
        return CleanupPlanner.plan(items: items, prices: quotes, trends: [:], starred: [], overrides: [:], rules: CleanupRules(), currency: .usd)
    }()

    @Test func collapsesCopiesInABucket() {
        let sell = CleanupRow.rows(from: plan.entries(in: .sell))
        #expect(sell.map(\.item.name) == ["Crest", "Lint", "Dust"])
        #expect(sell.map(\.count) == [2, 2, 1])
        #expect(sell.first?.copies == 3)
        #expect(sell.first?.totalSellerCents == 319 * 2)
        #expect(sell.first?.id == "sell|570|Crest")
        // Two Lint copies: one is an extra, the other is simply cheap.
        #expect(sell[1].reasons.map(\.kind) == [.extraCopy, .cheap])

        let keep = CleanupRow.rows(from: plan.entries(in: .keep))
        #expect(keep.map(\.itemIDs) == [["570_2_10"]])
    }

    @Test func searchesFiltersAndSorts() {
        let entries = plan.entries(in: .sell)
        #expect(CleanupRow.rows(from: entries, search: " lint ").map(\.item.name) == ["Lint"])
        #expect(CleanupRow.rows(from: plan.entries(in: .keep), search: "legion").count == 1)
        #expect(CleanupRow.rows(from: entries, filter: .reason(.cheap)).map(\.item.name) == ["Lint", "Dust"])
        #expect(CleanupRow.rows(from: entries, filter: .paysFloor).map(\.item.name) == ["Dust"])
        #expect(CleanupRow.rows(from: entries, sort: .name).map(\.item.name) == ["Crest", "Dust", "Lint"])
        #expect(CleanupRow.rows(from: entries, sort: .copies).map(\.item.name) == ["Crest", "Lint", "Dust"])
        #expect(CleanupRow.rows(from: entries, sort: .newest).map(\.item.name) == ["Crest", "Lint", "Dust"])
    }

    @Test func findsARowsItemsAfterADrag() {
        let payload = CleanupDrag.payload(rowIDs: ["sell|570|Crest", "sell|570|Dust"])
        let rowIDs = CleanupDrag.rowIDs(from: [payload, "some other text"])
        #expect(rowIDs == ["sell|570|Crest", "sell|570|Dust"])
        #expect(plan.itemIDs(inRow: rowIDs[0]) == ["570_2_11", "570_2_12"])
        #expect(plan.itemIDs(inRow: "nowhere|570|Crest").isEmpty)
        #expect(plan.bucketsByItem["570_2_10"] == .keep)
    }

    @Test func selectionMovesOnAfterRowsLeave() {
        let rows = CleanupRow.rows(from: plan.entries(in: .sell))
        let ids = rows.map(\.id)
        #expect(CleanupRow.nextID(after: [ids[0]], in: rows) == ids[1])
        #expect(CleanupRow.nextID(after: [ids[1], ids[2]], in: rows) == ids[0])
        #expect(CleanupRow.nextID(after: Set(ids), in: rows) == nil)
        #expect(CleanupRow.nextID(after: ["elsewhere"], in: rows) == nil)
    }

    @Test func offersAFilterPerReason() {
        let filters = CleanupRow.filters(for: plan.entries(in: .sell))
        #expect(filters.map(\.filter) == [.reason(.extraCopy), .reason(.cheap), .paysFloor])
        #expect(filters.map(\.count) == [2, 2, 1])
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
        var rules = CleanupRules()
        rules.keepSetPieces = true
        let plan = CleanupPlanner.plan(items: dota, prices: demo.prices, trends: [:], starred: [], overrides: [:], rules: rules, currency: .usd)
        #expect(plan.entries(in: .keep).contains { $0.reason.text == "Set: 5 of 5" })
    }
}
