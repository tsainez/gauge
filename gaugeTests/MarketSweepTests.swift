//
//  MarketSweepTests.swift
//  gaugeTests
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftData
import Testing
@testable import gauge

struct MarketSweepTests {
    static func result(_ name: String, price: String? = "$0.03", listings: Int = 12, appID: Int = 570) -> String {
        let priceJSON = price.map { #","sell_price_text":"\#($0)""# } ?? ""
        return #"{"name":"\#(name)","hash_name":"\#(name)","sell_listings":\#(listings)\#(priceJSON),"asset_description":{"appid":\#(appID)}}"#
    }

    static func searchPage(_ results: [String], start: Int = 0, total: Int) -> String {
        #"{"success":true,"start":\#(start),"pagesize":100,"total_count":\#(total),"results":[\#(results.joined(separator: ","))]}"#
    }

    static func page(_ names: [String], start: Int = 0, total: Int = 10_000, price: String = "$0.03") -> MarketSearchPage {
        let results = names.map { MarketSearchResult(hashName: $0, appID: 570, sellListings: 5, lowestCents: PriceParser.cents(from: price), priceText: price) }
        return MarketSearchPage(start: start, totalCount: total, results: results, currencyMatches: true)
    }

    // MARK: Parsing

    @Test func parsesSearchResults() throws {
        let json = Self.searchPage([
            Self.result("Cheap Thing"),
            Self.result("Unsold Thing", price: "$0.00", listings: 0),
            Self.result("Pricey Thing", price: "$1,234.56"),
        ], total: 34_000)
        let page = try MarketSearchParser.parse(Data(json.utf8), currency: .usd)
        #expect(page.totalCount == 34_000)
        #expect(page.currencyMatches)
        #expect(page.results.map(\.hashName) == ["Cheap Thing", "Unsold Thing", "Pricey Thing"])
        #expect(page.results.map(\.lowestCents) == [3, nil, 123_456])
        #expect(page.results.first?.appID == 570)
    }

    @Test func flagsPricesInAnotherCurrency() throws {
        let json = Self.searchPage([Self.result("Thing", price: "CDN$ 0.04")], total: 1)
        let page = try MarketSearchParser.parse(Data(json.utf8), currency: .usd)
        #expect(!page.currencyMatches)
        #expect(page.results.first?.lowestCents == nil)
    }

    @Test func rejectsUnsuccessfulSearch() {
        #expect(throws: MarketSearchParser.ParseError.unsuccessful) {
            try MarketSearchParser.parse(Data(#"{"success":false}"#.utf8), currency: .usd)
        }
    }

    @Test func recognizesEachCurrencysPriceText() {
        #expect(SteamCurrency.usd.matchesPriceText("$0.03"))
        #expect(SteamCurrency.usd.matchesPriceText("$1,234.56"))
        #expect(!SteamCurrency.usd.matchesPriceText("CDN$ 0.04"))
        #expect(!SteamCurrency.usd.matchesPriceText("A$ 0.04"))
        #expect(SteamCurrency.cad.matchesPriceText("CDN$ 0.04"))
        #expect(SteamCurrency.eur.matchesPriceText("0,03€"))
        #expect(SteamCurrency.eur.matchesPriceText("12,--€"))
        #expect(!SteamCurrency.eur.matchesPriceText("$0.03"))
        #expect(SteamCurrency.brl.matchesPriceText("R$ 0,03"))
        #expect(SteamCurrency.rub.matchesPriceText("1 234,56 руб."))
        // Yen is written the same for JPY and CNY, so it never counts.
        #expect(!SteamCurrency.jpy.matchesPriceText("¥ 4"))
        #expect(!SteamCurrency.cny.matchesPriceText("¥ 0.35"))
    }

    // MARK: When to stop

    @Test func finishesWhenEveryNameIsFound() {
        var sweep = MarketSweep(appID: 570, wanted: ["A", "B"])
        let hits = sweep.absorb(Self.page(["A", "X", "B"]))
        #expect(hits.map(\.hashName) == ["A", "B"])
        #expect(sweep.wanted.isEmpty)
        #expect(sweep.isFinished)
    }

    @Test func finishesAtTheEndOfTheCatalog() {
        var sweep = MarketSweep(appID: 570, wanted: ["A", "Z"])
        _ = sweep.absorb(Self.page(["A", "B"], total: 2))
        #expect(sweep.isFinished)
        #expect(sweep.wanted == ["Z"])
    }

    @Test func keepsGoingWhilePagesPayOff() {
        let wanted = Set((0..<500).map { "Item \($0)" })
        var sweep = MarketSweep(appID: 570, wanted: wanted)
        for pageIndex in 0..<5 {
            let names = (0..<100).map { $0 < 10 ? "Item \(pageIndex * 10 + $0)" : "Other \(pageIndex)-\($0)" }
            _ = sweep.absorb(Self.page(names, start: pageIndex * 100))
            #expect(!sweep.isFinished)
        }
        #expect(sweep.nextStart == 500)
        #expect(sweep.wanted.count == 450)
    }

    @Test func handsBackToSingleChecksWhenPagesStopPayingOff() {
        let wanted = Set((0..<500).map { "Item \($0)" })
        var sweep = MarketSweep(appID: 570, wanted: wanted)
        _ = sweep.absorb(Self.page((0..<100).map { "Other \($0)" }))
        // One empty page isn't enough to give up on.
        #expect(!sweep.isFinished)
        _ = sweep.absorb(Self.page((0..<100).map { $0 == 0 ? "Item 0" : "Other b\($0)" }, start: 100))
        #expect(sweep.isFinished)
        #expect(sweep.pagesFetched == 2)
    }

    @Test func ignoresUnsoldItemsAndOtherGames() {
        var sweep = MarketSweep(appID: 570, wanted: ["A", "B"])
        let page = MarketSearchPage(start: 0, totalCount: 10_000, results: [
            MarketSearchResult(hashName: "A", appID: 570, sellListings: 0, lowestCents: nil, priceText: nil),
            MarketSearchResult(hashName: "B", appID: 730, sellListings: 3, lowestCents: 3, priceText: "$0.03"),
        ], currencyMatches: true)
        #expect(sweep.absorb(page).isEmpty)
        #expect(sweep.wanted == ["A", "B"])
    }
}

/// Serves canned responses for the sweep tests. Separate from the other suites' mocks,
/// whose shared routes would be swapped out from under them while suites run in parallel.
final class SweepMockSteam: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var routes: [(match: String, status: Int, body: String)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    static let lock = NSLock()

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SweepMockSteam.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        Self.lock.lock()
        Self.requests.append(request)
        let route = Self.routes.first { url.contains($0.match) }
        Self.lock.unlock()
        let status = route?.status ?? 404
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((route?.body ?? "").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The sweep inside the pricing queue, against a mocked Steam.
@Suite(.serialized)
@MainActor
struct MarketSweepPricingTests {
    static let context = InventoryContext(appID: 570, contextID: "2", name: "Dota 2", iconURL: nil, assetCount: 50)

    /// An inventory of `count` different marketable items named "Item 0", "Item 1", ….
    static func inventory(_ count: Int) throws -> [InventoryItem] {
        let assets = (0..<count).map { #"{"appid":570,"contextid":"2","assetid":"\#($0 + 1)","classid":"\#($0 + 1)","instanceid":"0","amount":"1"}"# }
        let descriptions = (0..<count).map { #"{"appid":570,"classid":"\#($0 + 1)","instanceid":"0","name":"Item \#($0)","market_hash_name":"Item \#($0)","marketable":1,"tradable":1}"# }
        let json = #"{"assets":[\#(assets.joined(separator: ","))],"descriptions":[\#(descriptions.joined(separator: ","))],"total_inventory_count":\#(count),"success":1}"#
        return try InventoryPageParser.parse(Data(json.utf8)).items
    }

    func makeModel(items: [InventoryItem]) async -> (AppModel, UserDefaults, String) {
        let suite = "GaugeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let client = SteamClient(configuration: SweepMockSteam.configuration(), intervalScale: 0)
        let model = AppModel(container: GaugeSchema.makeContainer(inMemory: true), defaults: defaults, client: client, networkLog: nil)
        model.contexts = [Self.context]
        await model.store(items, for: Self.context)
        model.rebuildDerived()
        return (model, defaults, suite)
    }

    func route(_ routes: [(match: String, status: Int, body: String)]) {
        SweepMockSteam.lock.lock()
        SweepMockSteam.requests = []
        SweepMockSteam.routes = routes
        SweepMockSteam.lock.unlock()
    }

    var marketRequests: [String] {
        SweepMockSteam.lock.lock()
        defer { SweepMockSteam.lock.unlock() }
        return SweepMockSteam.requests.compactMap { $0.url?.absoluteString }.filter { $0.contains("/market/") }
    }

    @Test func sweepPricesMostNamesInOneRequest() async throws {
        let (model, defaults, suite) = await makeModel(items: try Self.inventory(50))
        defer { defaults.removePersistentDomain(forName: suite) }
        let found = (0..<45).map { MarketSweepTests.result("Item \($0)") }
        let others = (0..<55).map { MarketSweepTests.result("Someone Else's \($0)") }
        route([
            ("/market/search/render/", 200, MarketSweepTests.searchPage(found + others, total: 100)),
            ("/market/priceoverview/", 200, #"{"success":true,"lowest_price":"$0.05","median_price":"$0.04","volume":"7"}"#),
        ])

        model.rebuildPricingQueue()
        #expect(model.pricingQueue.count == 50)
        model.ensurePricing()
        await model.pricingTask?.value

        #expect(model.pricingQueue.isEmpty)
        #expect(model.prices.count == 50)
        #expect(model.prices[PriceKey.make(appID: 570, marketHashName: "Item 0")]?.lowestCents == 3)
        #expect(model.prices[PriceKey.make(appID: 570, marketHashName: "Item 49")]?.lowestCents == 5)
        // One search page plus five single checks, instead of fifty single checks.
        let requests = marketRequests
        #expect(requests.filter { $0.contains("/search/render/") }.count == 1)
        #expect(requests.filter { $0.contains("/priceoverview/") }.count == 5)
        #expect(requests.first?.contains("sort_column=price") == true)
        #expect(requests.first?.contains("sort_dir=asc") == true)
        #expect(model.marketSweptAt[570] != nil)
    }

    @Test func smallInventoriesAreNotSwept() async throws {
        let (model, defaults, suite) = await makeModel(items: try Self.inventory(MarketSweep.minimumNames - 1))
        defer { defaults.removePersistentDomain(forName: suite) }
        route([("/market/priceoverview/", 200, #"{"success":true,"lowest_price":"$0.05"}"#)])

        model.rebuildPricingQueue()
        #expect(model.planMarketSweeps().isEmpty)
        model.ensurePricing()
        await model.pricingTask?.value

        #expect(model.prices.count == MarketSweep.minimumNames - 1)
        #expect(!marketRequests.contains { $0.contains("/search/render/") })
    }

    @Test func pricesInAnotherCurrencyFallBackToSingleChecks() async throws {
        let (model, defaults, suite) = await makeModel(items: try Self.inventory(50))
        defer { defaults.removePersistentDomain(forName: suite) }
        let results = (0..<50).map { MarketSweepTests.result("Item \($0)", price: "CDN$ 0.04") }
        route([
            ("/market/search/render/", 200, MarketSweepTests.searchPage(results, total: 100)),
            ("/market/priceoverview/", 200, #"{"success":true,"lowest_price":"$0.05"}"#),
        ])

        model.rebuildPricingQueue()
        model.ensurePricing()
        await model.pricingTask?.value

        #expect(model.marketSweepUnavailable)
        #expect(model.prices.values.allSatisfy { $0.lowestCents == 5 })
        #expect(model.prices.count == 50)
        #expect(model.planMarketSweeps().isEmpty)
    }

    @Test func recentlySweptGamesWaitForTheCooldown() async throws {
        let (model, defaults, suite) = await makeModel(items: try Self.inventory(50))
        defer { defaults.removePersistentDomain(forName: suite) }
        model.rebuildPricingQueue()
        #expect(model.planMarketSweeps().map(\.appID) == [570])
        model.marketSweptAt[570] = Date()
        #expect(model.planMarketSweeps().isEmpty)
        model.marketSweptAt[570] = Date().addingTimeInterval(-AppModel.marketSweepCooldown - 1)
        #expect(model.planMarketSweeps().map(\.appID) == [570])
    }
}
