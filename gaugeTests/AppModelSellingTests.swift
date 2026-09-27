//
//  AppModelSellingTests.swift
//  gaugeTests
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftData
import Testing
import WebKit
@testable import gauge

@Suite(.serialized)
@MainActor
struct AppModelSellingTests {
    func makeModel(_ defaults: UserDefaults) -> AppModel {
        let configuration = MockSteam.configuration()
        let client = SteamClient(configuration: configuration, intervalScale: 0)
        let model = AppModel(container: GaugeSchema.makeContainer(inMemory: true), defaults: defaults, client: client, networkLog: nil)
        model.updateSettings { $0.profile = DemoModeTests.profile }
        MockSteam.routes = []
        return model
    }

    func withDefaults(_ body: (UserDefaults) async -> Void) async {
        let suite = "GaugeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        await body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    func withDefaultsAndCookie(_ body: (UserDefaults) async -> Void) async {
        await injectSteamLoginCookie()
        await withDefaults(body)
        await clearSteamLoginCookie()
    }

    func injectSteamLoginCookie() async {
        let cookie = HTTPCookie(properties: [
            .domain: "steamcommunity.com",
            .path: "/",
            .name: "steamLoginSecure",
            .value: SteamLoginTests.cookie(exp: Int(Date().timeIntervalSince1970) + 3600),
            .secure: "TRUE"
        ])!
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    func clearSteamLoginCookie() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: Date(timeIntervalSince1970: 0)
            ) {
                continuation.resume()
            }
        }
    }

    @Test func runListingDoesNothingInDemoMode() async {
        await withDefaults { defaults in
            let model = makeModel(defaults)
            model.enterDemo()

            let item = CleanupPlannerTests.item("1", "Crest")
            let run = ListingRun(jobs: [ListingRun.Job(item: item, buyerCents: 10, sellerCents: 8)])

            await model.runListing(run)

            #expect(!run.isRunning)
            #expect(run.haltMessage == "Demo mode doesn't list anything. Connect your own Steam profile to sell.")
            #expect(run.jobs[0].state == .queued)
        }
    }

    @Test func runListingRequiresSignIn() async {
        await withDefaults { defaults in
            await clearSteamLoginCookie()

            let model = makeModel(defaults)
            let item = CleanupPlannerTests.item("1", "Crest")
            let run = ListingRun(jobs: [ListingRun.Job(item: item, buyerCents: 10, sellerCents: 8)])

            await model.runListing(run)

            #expect(!run.isRunning)
            #expect(run.haltMessage == "Sign in with Steam to list items.")
            #expect(run.jobs[0].state == .queued)
        }
    }

    @Test func runListingSkipsStarredItemsWhenProtected() async {
        await withDefaultsAndCookie { defaults in
            let model = makeModel(defaults)
            let item = CleanupPlannerTests.item("1", "Crest")
            model.starred.insert(item.id)
            model.updateSettings { $0.protectStarred = true }

            let run = ListingRun(jobs: [ListingRun.Job(item: item, buyerCents: 10, sellerCents: 8)])

            await model.runListing(run)

            #expect(!run.isRunning)
            #expect(run.jobs[0].state == .skipped("Starred"))
        }
    }

    @Test func runListingRechecksStalePricesAndSkipsIfPriceDrops() async {
        await withDefaultsAndCookie { defaults in
            let model = makeModel(defaults)
            let item = CleanupPlannerTests.item("1", "Crest")

            // Stale price quote:
            let oldQuote = PriceQuote(lowestCents: 50, medianCents: nil, volume: 10, checkedAt: Date().addingTimeInterval(-AppModel.listingPriceMaxAge - 1), currency: .usd)
            model.prices[item.priceKey] = oldQuote

            // New price overview response (price falls to 10 cents):
            MockSteam.routes = [
                ("market/priceoverview", 200, #"{"success":true,"lowest_price":"$0.10","volume":"1"}"#)
            ]

            // The job has buyerCents=50, buyer * 2 = 100 > 50 -> this will fail if 10 * 2 < 50
            let run = ListingRun(jobs: [ListingRun.Job(item: item, buyerCents: 50, sellerCents: 43)])

            await model.runListing(run)

            #expect(!run.isRunning)
            #expect(run.jobs[0].state == .skipped("Price fell to $0.10. Review it again."))

            if case .skipped(let reason) = run.jobs[0].state {
                #expect(reason.contains("Price fell"))
            } else {
                Issue.record("Expected skipped state due to price drop")
            }
        }
    }

    @Test func runListingSkipsItemsBelowSteamMinimumPrice() async {
        await withDefaultsAndCookie { defaults in
            let model = makeModel(defaults)
            let item = CleanupPlannerTests.item("1", "Crest")

            let run = ListingRun(jobs: [ListingRun.Job(item: item, buyerCents: 1, sellerCents: 0)])

            await model.runListing(run)

            #expect(!run.isRunning)
            #expect(run.jobs[0].state == .skipped("Below Steam's minimum price"))
        }
    }

    @Test func runListingListsSuccessfully() async {
        await withDefaultsAndCookie { defaults in
            let model = makeModel(defaults)
            let item = CleanupPlannerTests.item("1", "Crest")

            let context = InventoryContext(appID: 570, contextID: "2", name: "Dota 2", iconURL: nil, assetCount: 1)
            model.contexts = [context]
            model.itemsByContext = [context.id: [item]]
            model.rebuildDerived()

            MockSteam.routes = [
                ("market/sellitem", 200, #"{"success":true,"needs_mobile_confirmation":true}"#)
            ]

            let run = ListingRun(jobs: [ListingRun.Job(item: item, buyerCents: 10, sellerCents: 8)])

            await model.runListing(run)

            #expect(!run.isRunning)
            #expect(run.jobs[0].state == .listed(needsConfirmation: true))
            #expect(model.items(in: context.id).isEmpty, "Listed items should be removed from the inventory")
        }
    }

    @Test func runListingHaltsOnRateLimit() async {
        await withDefaultsAndCookie { defaults in
            let model = makeModel(defaults)
            let item = CleanupPlannerTests.item("1", "Crest")

            MockSteam.routes = [
                ("market/sellitem", 429, #"null"#)
            ]

            let run = ListingRun(jobs: [ListingRun.Job(item: item, buyerCents: 10, sellerCents: 8)])

            await model.runListing(run)

            #expect(!run.isRunning)
            #expect(run.jobs[0].state == .queued)
            #expect(run.haltMessage?.contains("Steam asked Gauge to slow down.") == true)
        }
    }
}
