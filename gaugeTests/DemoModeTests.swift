//
//  DemoModeTests.swift
//  gaugeTests
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftData
import Testing
@testable import gauge

/// Answers every request with a 503 so model tests never reach the real Steam.
nonisolated final class OfflineSteam: URLProtocol, @unchecked Sendable {
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineSteam.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
struct DemoModeTests {
    static let profile = ProfileSummary(steamID64: "76561197960287930", personaName: "Real Profile", avatarURL: nil, isPublic: true)

    func makeModel() -> (AppModel, UserDefaults, String) {
        let suite = "GaugeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let client = SteamClient(configuration: OfflineSteam.configuration(), intervalScale: 0)
        let model = AppModel(container: GaugeSchema.makeContainer(inMemory: true), defaults: defaults, client: client, networkLog: nil)
        return (model, defaults, suite)
    }

    @Test func exitingDemoWithoutAProfileReturnsToOnboarding() async {
        let (model, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        model.enterDemo()
        #expect(model.settings.demoMode)
        #expect(model.hasProfile)
        #expect(model.allItems.count > 3_000)

        await model.exitDemo()
        #expect(!model.settings.demoMode)
        #expect(!model.hasProfile)
        #expect(model.allItems.isEmpty)
        #expect(model.prices.isEmpty)
        #expect(model.snapshots.isEmpty)
    }

    @Test func demoLeavesTheRealCacheAlone() async throws {
        let (model, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        model.updateSettings { $0.profile = Self.profile }
        let dota = InventoryContext(appID: 570, contextID: "2", name: "Dota 2", iconURL: nil, assetCount: 1)
        await model.store([CleanupPlannerTests.item("1", "Crest")], for: dota)

        model.enterDemo()
        let demoItem = try #require(model.allItems.first)
        model.toggleStar(demoItem)
        #expect(model.isStarred(demoItem))

        await model.exitDemo()
        #expect(!model.settings.demoMode)
        #expect(model.settings.profile == Self.profile)
        #expect(model.items(in: dota.id).map(\.name) == ["Crest"])
        #expect(!model.starred.contains(demoItem.id))
    }

    @Test func demoSurvivesRelaunchAndCanStillExit() async {
        let (model, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        model.enterDemo()

        // A new launch reads the saved settings and comes back in demo mode.
        let relaunched = AppModel(container: GaugeSchema.makeContainer(inMemory: true), defaults: defaults, client: model.client, networkLog: nil)
        await relaunched.start()
        #expect(relaunched.settings.demoMode)
        #expect(!relaunched.allItems.isEmpty)

        await relaunched.exitDemo()
        #expect(!relaunched.settings.demoMode)
        #expect(!relaunched.hasProfile)
    }
}
