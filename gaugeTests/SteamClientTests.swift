//
//  SteamClientTests.swift
//  gaugeTests
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import gauge

/// Serves canned responses by URL substring so SteamClient can run without the network.
nonisolated final class MockSteam: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var routes: [(match: String, status: Int, body: String)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    static let lock = NSLock()

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockSteam.self]
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

@Suite(.serialized)
struct SteamClientTests {
    static let context = InventoryContext(appID: 570, contextID: "2", name: "Dota 2", iconURL: nil, assetCount: 3)

    static func page(_ assets: [String], more: String?) -> String {
        let assetJSON = assets.map { #"{"appid":570,"contextid":"2","assetid":"\#($0)","classid":"1","instanceid":"0","amount":"1"}"# }
        let moreJSON = more.map { #","more_items":1,"last_assetid":"\#($0)""# } ?? ""
        return #"{"assets":[\#(assetJSON.joined(separator: ","))],"descriptions":[{"appid":570,"classid":"1","instanceid":"0","name":"Thing","market_hash_name":"Thing","marketable":1,"tradable":1}],"total_inventory_count":3,"success":1\#(moreJSON)}"#
    }

    @Test func followsInventoryPages() async throws {
        MockSteam.requests = []
        MockSteam.routes = [
            ("start_assetid=2", 200, Self.page(["3"], more: nil)),
            ("/inventory/7656119", 200, Self.page(["1", "2"], more: "2")),
        ]
        let client = SteamClient(configuration: MockSteam.configuration(), intervalScale: 0)
        let items = try await client.inventory(steamID64: "76561197960287930", context: Self.context)
        #expect(items.map(\.assetID) == ["1", "2", "3"])
        #expect(MockSteam.requests.count == 2)
    }

    @Test func privateInventoryIsReported() async {
        MockSteam.routes = [("/inventory/", 403, "null")]
        let client = SteamClient(configuration: MockSteam.configuration(), intervalScale: 0)
        await #expect(throws: SteamClient.Failure.privateInventory) {
            try await client.inventory(steamID64: "76561197960287930", context: Self.context)
        }
    }

    @Test func rateLimitBacksOff() async {
        MockSteam.routes = [("/market/priceoverview/", 429, "")]
        let client = SteamClient(configuration: MockSteam.configuration(), intervalScale: 0)
        await #expect(throws: SteamClient.Failure.rateLimited(retryAfter: 60)) {
            try await client.priceOverview(appID: 570, marketHashName: "A+B", currency: .usd)
        }
    }

    @Test func encodesMarketHashNameStrictly() async throws {
        MockSteam.requests = []
        MockSteam.routes = [("/market/priceoverview/", 200, #"{"success":true,"lowest_price":"$0.03"}"#)]
        let client = SteamClient(configuration: MockSteam.configuration(), intervalScale: 0)
        let quote = try await client.priceOverview(appID: 570, marketHashName: "A+B & C", currency: .usd)
        #expect(quote.lowestCents == 3)
        #expect(MockSteam.requests.last?.url?.absoluteString.hasSuffix("market_hash_name=A%2BB%20%26%20C") == true)
    }

    @Test func sellPostsTheSellerPrice() async throws {
        MockSteam.requests = []
        MockSteam.routes = [("/market/sellitem/", 200, #"{"success":true,"requires_confirmation":1,"needs_mobile_confirmation":true}"#)]
        let client = SteamClient(configuration: MockSteam.configuration(), intervalScale: 0)
        let auth = SteamWebAuth(steamID64: "76561197960287930", sessionID: "abc", steamLoginSecure: "76561197960287930%7C%7Ctoken")
        let result = try await client.sell(SellRequest(appID: 570, contextID: "2", assetID: "99", amount: 1, sellerCents: 319), auth: auth)
        #expect(result.success && result.needsConfirmation)
        let request = try #require(MockSteam.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("sessionid=abc") == true)
    }

    @Test func resolvesVanityProfiles() async throws {
        MockSteam.routes = [("/id/gaben/", 200, "<profile><steamID64>76561197960287930</steamID64><steamID><![CDATA[Rabscuttle]]></steamID><privacyState>public</privacyState></profile>")]
        let client = SteamClient(configuration: MockSteam.configuration(), intervalScale: 0)
        let profile = try await client.profile(.vanity("gaben"))
        #expect(profile.personaName == "Rabscuttle")
    }
}
