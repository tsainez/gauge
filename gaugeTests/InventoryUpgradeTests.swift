//
//  InventoryUpgradeTests.swift
//  gaugeTests
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftData
import Testing
@testable import gauge

/// Serves a profile with one CS2 inventory and a price, and counts the inventory downloads.
nonisolated final class SkinSteam: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var inventoryRequests = 0
    static let lock = NSLock()

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SkinSteam.self]
        return configuration
    }

    static func reset() {
        lock.lock()
        inventoryRequests = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        var status = 200
        let body: Data
        if url.contains("/profiles/") {
            body = Data(#"<script>var g_rgAppContextData = {"730":{"appid":730,"name":"Counter-Strike 2","rgContexts":{"2":{"asset_count":2,"id":"2","name":"Backpack"}}}};</script>"#.utf8)
        } else if url.contains("/inventory/") {
            Self.lock.lock()
            Self.inventoryRequests += 1
            Self.lock.unlock()
            body = SkinDetailsParsingTests.page
        } else if url.contains("/market/priceoverview/") {
            body = Data(#"{"success":true,"lowest_price":"$151.20","volume":"4","median_price":"$149.00"}"#.utf8)
        } else {
            status = 404
            body = Data()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct InventoryUpgradeTests {
    static let context = InventoryContext(appID: 730, contextID: "2", name: "Counter-Strike 2", iconURL: nil, assetCount: 2)

    /// A signed-out model for a real profile, whose CS2 inventory was cached by an older
    /// Gauge: the same two items Steam has now, without skin details.
    func makeModel(defaults: UserDefaults) async throws -> AppModel {
        let client = SteamClient(configuration: SkinSteam.configuration(), intervalScale: 0)
        let model = AppModel(container: GaugeSchema.makeContainer(inMemory: true), defaults: defaults, client: client, networkLog: nil)
        model.updateSettings { $0.profile = DemoModeTests.profile }
        let cached = try InventoryPageParser.parse(SkinDetailsParsingTests.page).items.map { item in
            var item = item
            item.skin = nil
            return item
        }
        await model.store(cached, for: Self.context)
        model.contexts = [Self.context]
        model.rebuildDerived()
        SkinSteam.reset()
        return model
    }

    @Test func cachedSkinsAreDownloadedOnceMoreForTheirDetails() async throws {
        let suite = "GaugeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = try await makeModel(defaults: defaults)
        #expect(model.allItems.allSatisfy { $0.skin == nil })

        await model.syncInventories(force: false)
        #expect(SkinSteam.inventoryRequests == 1)
        #expect(model.allItems.first?.skin?.pattern == 661)
        #expect(defaults.integer(forKey: AppModel.inventoryFormatKey) == AppModel.inventoryFormat)

        // From then on, an unchanged inventory isn't downloaded again.
        await model.syncInventories(force: false)
        #expect(SkinSteam.inventoryRequests == 1)
        model.stopPricing()
    }

    @Test func outdatedInventoriesAreCheckedAtLaunch() async throws {
        let suite = "GaugeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = try await makeModel(defaults: defaults)
        // The last check was a minute ago, so none is due for hours.
        model.lastInventoryCheck = Date().addingTimeInterval(-60)
        #expect(!model.inventoryCheckIsDue)
        #expect(model.inventoriesAreOutdated)

        await model.schedulerTick()
        #expect(SkinSteam.inventoryRequests == 1)
        #expect(model.allItems.first?.skin?.wear != nil)
        #expect(!model.inventoriesAreOutdated)

        await model.schedulerTick()
        #expect(SkinSteam.inventoryRequests == 1)
        model.stopPricing()
    }

    @Test func refreshingAnItemDownloadsItsInventoryAndPrice() async throws {
        let suite = "GaugeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = try await makeModel(defaults: defaults)
        let ak = try #require(model.allItems.first)
        #expect(model.canRefreshItems)

        await model.refresh(ak)
        #expect(SkinSteam.inventoryRequests == 1)
        #expect(model.item(withID: ak.id)?.skin?.pattern == 661)
        #expect(model.prices[ak.priceKey]?.lowestCents == 15_120)
        #expect(model.notice == "Counter-Strike 2 refreshed: 2 items, 1 with a float")
        #expect(!model.syncPhase.isBusy)
        model.stopPricing()
    }

    @Test func refreshNeedsARealProfile() async throws {
        let suite = "GaugeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = SteamClient(configuration: SkinSteam.configuration(), intervalScale: 0)
        let model = AppModel(container: GaugeSchema.makeContainer(inMemory: true), defaults: defaults, client: client, networkLog: nil)
        #expect(!model.canRefreshItems)

        model.enterDemo()
        let item = try #require(model.allItems.first)
        #expect(!model.canRefreshItems)
        SkinSteam.reset()
        await model.refresh(item)
        #expect(SkinSteam.inventoryRequests == 0)
    }
}
