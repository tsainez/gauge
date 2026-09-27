//
//  InventoryQueryTests.swift
//  gaugeTests
//

import Foundation
import Testing
@testable import gauge

struct InventoryQueryTests {
    static func item(_ asset: String, _ name: String, rarity: String, slot: String, marketable: Bool = true) -> InventoryItem {
        var item = CleanupPlannerTests.item(asset, name, marketable: marketable)
        item.tags = [
            ItemTag(category: "Rarity", categoryName: "Rarity", internalName: rarity, name: rarity, color: nil),
            ItemTag(category: "Slot", categoryName: "Slot", internalName: slot, name: slot, color: nil),
        ]
        return item
    }

    let items = [
        item("1", "Neck of Dawn", rarity: "Mythical", slot: "Neck"),
        item("2", "Belt of Dawn", rarity: "Mythical", slot: "Belt"),
        item("3", "Crown of Dusk", rarity: "Legendary", slot: "Head"),
        item("4", "Old Treasure", rarity: "Common", slot: "Misc", marketable: false),
    ]

    var facts: InventoryFacts {
        var facts = InventoryFacts()
        facts.prices = [
            "570|Neck of Dawn": CleanupPlannerTests.quote(3),
            "570|Belt of Dawn": CleanupPlannerTests.quote(40),
            "570|Crown of Dusk": CleanupPlannerTests.quote(900),
        ]
        facts.starred = ["570_2_2"]
        return facts
    }

    @Test func combinesCategoriesWithAnd() {
        var query = InventoryQuery()
        query.tags = ["Rarity": ["Mythical", "Legendary"], "Slot": ["Neck", "Head"]]
        #expect(query.apply(to: items, facts: facts).map(\.name) == ["Crown of Dusk", "Neck of Dawn"])
    }

    @Test func quickFilters() {
        var query = InventoryQuery()
        query.quick = [.marketable]
        #expect(query.apply(to: items, facts: facts).count == 3)
        query.quick = [.fluff]
        #expect(query.apply(to: items, facts: facts).map(\.name) == ["Neck of Dawn"])
        query.quick = [.starred]
        #expect(query.apply(to: items, facts: facts).map(\.name) == ["Belt of Dawn"])
    }

    @Test func searchMatchesNames() {
        var query = InventoryQuery()
        query.search = "dawn"
        query.sort = .name
        #expect(query.apply(to: items, facts: facts).map(\.name) == ["Belt of Dawn", "Neck of Dawn"])
    }

    @Test func sortsByRarity() {
        var query = InventoryQuery()
        query.sort = .rarity
        #expect(query.apply(to: items, facts: facts).first?.name == "Crown of Dusk")
    }

    @Test func buildsFacetsInSidebarOrder() {
        let facets = TagCategoryFacet.facets(for: items)
        #expect(facets.map(\.category) == ["Rarity", "Slot"])
        #expect(facets.first?.values.first?.name == "Legendary")
        #expect(facets.first?.values.first(where: { $0.name == "Mythical" })?.count == 2)
    }
}

struct AppSettingsTests {
    @Test func decodesOlderSettingsWithDefaults() throws {
        let json = Data(#"{"theme":"classicDark","cleanupRules":{"setThreshold":4}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        #expect(settings.theme == .classicDark)
        #expect(AppSettings().theme == .modern)
        #expect(settings.currency == .usd)
        #expect(settings.cleanupRules.setThreshold == 4)
        #expect(settings.cleanupRules.keepStarred)
    }

    @Test func roundTrips() throws {
        var settings = AppSettings()
        settings.profile = ProfileSummary(steamID64: "76561197960287930", personaName: "Gabe", avatarURL: nil, isPublic: true)
        settings.cleanupRules.sellEverythingElse = true
        settings.cleanupRules.cheapBelowCents = 25
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test func cheapItemsRefreshLessOften() {
        let settings = AppSettings()
        #expect(settings.priceLifetime(forValue: 3) == RefreshInterval.weekly.seconds)
        #expect(settings.priceLifetime(forValue: 300) == RefreshInterval.daily.seconds)
    }
}
