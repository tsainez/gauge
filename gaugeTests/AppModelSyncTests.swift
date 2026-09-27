//
//  AppModelSyncTests.swift
//  gaugeTests
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftData
import Testing
@testable import gauge

@MainActor
struct AppModelSyncTests {
    static let profile = ProfileSummary(steamID64: "76561197960287930", personaName: "Real Profile", avatarURL: nil, isPublic: true)

    static let directoryHtml = """
    <script>
    var g_rgAppContextData = {"570":{"appid":570,"name":"Dota 2","icon":"https://cdn/570.jpg","link":"https://steamcommunity.com/app/570","asset_count":3029,"rgContexts":{"2":{"asset_count":3029,"id":"2","name":"Backpack"}}},"753":{"appid":753,"name":"Steam","icon":"https://cdn/753.jpg","asset_count":540,"rgContexts":{"1":{"asset_count":0,"id":"1","name":"Gifts"},"6":{"asset_count":540,"id":"6","name":"Community"}}}};
    </script>
    """

    func makeModel() -> (AppModel, UserDefaults, String) {
        let suite = "GaugeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let client = SteamClient(configuration: MockSteam.configuration(), intervalScale: 0)
        let model = AppModel(container: GaugeSchema.makeContainer(inMemory: true), defaults: defaults, client: client, networkLog: nil)
        return (model, defaults, suite)
    }

    @Test func syncSucceedsAndUpdatesContexts() async throws {
        let (model, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        MockSteam.requests = []
        MockSteam.routes = [
            ("/inventory/", 200, Self.directoryHtml),
            ("/inventory/76561197960287930/570/2", 200, SteamClientTests.page(["1", "2"], more: nil)),
            ("/inventory/76561197960287930/753/6", 200, SteamClientTests.page(["3"], more: nil))
        ]

        model.updateSettings { $0.profile = Self.profile }

        await model.syncInventories(force: true)

        #expect(model.contexts.count == 2)
        #expect(model.contexts.map(\.id).sorted() == ["570_2", "753_6"])
        #expect(model.itemsByContext["570_2"]?.count == 2)
        #expect(model.itemsByContext["753_6"]?.count == 1)
        #expect(model.notice == nil)
    }

    @Test func syncFailsWithRateLimitOnDirectory() async throws {
        let (model, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        MockSteam.requests = []
        MockSteam.routes = [
            ("/inventory/", 429, "")
        ]

        model.updateSettings { $0.profile = Self.profile }

        await model.syncInventories(force: true)

        #expect(model.contexts.isEmpty)
        #expect(model.notice?.contains("rate limit") == true || model.notice?.contains("wait") == true || model.notice?.contains("Steam") == true)
    }

    @Test func syncHandlesPrivateInventoryGracefully() async throws {
        let (model, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        MockSteam.requests = []
        MockSteam.routes = [
            ("/inventory/", 403, "null")
        ]

        model.updateSettings { $0.profile = Self.profile }

        await model.syncInventories(force: true)

        // When directory fails with something other than rate limit, it falls back to known contexts or common
        // but then probing the items for the fallback will hit 403 again
        #expect(model.notice?.contains("private") == true)
    }

    @Test func forceFalseSkipsUnchangedInventories() async throws {
        let (model, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        MockSteam.requests = []
        MockSteam.routes = [
            ("/inventory/", 200, Self.directoryHtml),
            ("/inventory/76561197960287930/570/2", 200, SteamClientTests.page(["1", "2"], more: nil)),
            ("/inventory/76561197960287930/753/6", 200, SteamClientTests.page(["3"], more: nil))
        ]

        model.updateSettings { $0.profile = Self.profile }

        // Initial sync
        await model.syncInventories(force: true)
        #expect(MockSteam.requests.count == 3)

        // Change one route to reflect a change
        MockSteam.requests = []
        MockSteam.routes = [
            ("/inventory/", 200, Self.directoryHtml.replacingOccurrences(of: "\"asset_count\":540", with: "\"asset_count\":541")),
            ("/inventory/76561197960287930/570/2", 200, SteamClientTests.page(["1", "2"], more: nil)),
            ("/inventory/76561197960287930/753/6", 200, SteamClientTests.page(["3", "4"], more: nil))
        ]

        // Second sync with force=false. Since 570 hasn't changed its count, it shouldn't be fetched again.
        await model.syncInventories(force: false)

        // One request for directory, one for the changed inventory 753_6
        #expect(MockSteam.requests.count == 2)
        #expect(model.itemsByContext["570_2"]?.count == 2) // Unchanged
        #expect(model.itemsByContext["753_6"]?.count == 2) // Updated
    }

    @Test func rateLimitOnInventoryFetchRetainsExistingItems() async throws {
        let (model, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        MockSteam.requests = []
        MockSteam.routes = [
            ("/inventory/", 200, Self.directoryHtml),
            ("/inventory/76561197960287930/570/2", 200, SteamClientTests.page(["1", "2"], more: nil)),
            ("/inventory/76561197960287930/753/6", 200, SteamClientTests.page(["3"], more: nil))
        ]

        model.updateSettings { $0.profile = Self.profile }

        // Initial sync
        await model.syncInventories(force: true)
        #expect(model.itemsByContext["570_2"]?.count == 2)

        // Second sync that hits a rate limit on the first inventory
        MockSteam.requests = []
        MockSteam.routes = [
            ("/inventory/", 200, Self.directoryHtml),
            ("/inventory/76561197960287930/570/2", 429, "")
        ]

        await model.syncInventories(force: true)

        // Should have a notice and still retain the previously synced items
        #expect(model.notice != nil)
        #expect(model.itemsByContext["570_2"]?.count == 2)
    }
}
