//
//  SteamParsingTests.swift
//  gaugeTests
//

import Foundation
import Testing
@testable import gauge

struct InventoryParsingTests {
    static let page = Data("""
    {
      "assets": [
        {"appid": 570, "contextid": "2", "assetid": "1001", "classid": "11", "instanceid": "0", "amount": "1"},
        {"appid": 570, "contextid": "2", "assetid": "1002", "classid": "12", "instanceid": "0", "amount": "1"},
        {"appid": 570, "contextid": "2", "assetid": "1003", "classid": "13", "instanceid": "57", "amount": "1"}
      ],
      "descriptions": [
        {
          "appid": 570, "classid": "11", "instanceid": "0",
          "icon_url": "abc", "icon_url_large": "",
          "name": "Song of the Solstice Neck", "market_hash_name": "Song of the Solstice Neck",
          "type": "Mythical Neck", "tradable": 1, "marketable": 1, "commodity": 0,
          "descriptions": [
            {"type": "html", "value": "Used By: Enchantress"},
            {"type": "html", "value": " "},
            {"type": "html", "value": "Song of the Solstice", "color": "9da1a9"},
            {"type": "html", "value": "Song of the Solstice Arms", "color": "6c7075"},
            {"type": "html", "value": "Song of the Solstice Belt", "color": "6c7075"},
            {"type": "html", "value": "Song of the Solstice Head", "color": "6c7075"},
            {"type": "html", "value": "Song of the Solstice Neck", "color": "6c7075"},
            {"type": "html", "value": "Song of the Solstice Weapon", "color": "6c7075"}
          ],
          "tags": [
            {"category": "Quality", "internal_name": "unique", "localized_category_name": "Quality", "localized_tag_name": "Standard", "color": "D2D2D2"},
            {"category": "Rarity", "internal_name": "Rarity_Mythical", "localized_category_name": "Rarity", "localized_tag_name": "Mythical", "color": "8847ff"},
            {"category": "Slot", "internal_name": "neck", "localized_category_name": "Slot", "localized_tag_name": "Neck"},
            {"category": "Hero", "internal_name": "npc_dota_hero_enchantress", "localized_category_name": "Hero", "localized_tag_name": "Enchantress"}
          ]
        },
        {
          "appid": 570, "classid": "12", "instanceid": "0",
          "icon_url": "def", "name": "Inscribed Song of the Solstice Belt",
          "market_hash_name": "Inscribed Song of the Solstice Belt",
          "type": "Inscribed Mythical Belt", "tradable": 1, "marketable": 1, "commodity": 0,
          "descriptions": [
            {"type": "html", "value": "Song of the Solstice", "color": "9da1a9"},
            {"type": "html", "value": "Song of the Solstice Arms", "color": "6c7075"},
            {"type": "html", "value": "Song of the Solstice Belt", "color": "6c7075"},
            {"type": "html", "value": "Song of the Solstice Neck", "color": "6c7075"}
          ],
          "tags": [
            {"category": "Quality", "internal_name": "strange", "localized_category_name": "Quality", "localized_tag_name": "Inscribed", "color": "CF6A32"}
          ]
        },
        {
          "appid": 570, "classid": "13", "instanceid": "57",
          "icon_url": "ghi", "name": "Treasure Key",
          "type": "Key", "tradable": 0, "marketable": 0, "commodity": 0
        }
      ],
      "more_items": 1,
      "last_assetid": "1003",
      "total_inventory_count": 3029,
      "success": 1,
      "rwgrsn": -2
    }
    """.utf8)

    @Test func mergesAssetsWithDescriptions() throws {
        let page = try InventoryPageParser.parse(Self.page)
        #expect(page.items.count == 3)
        #expect(page.moreItems)
        #expect(page.lastAssetID == "1003")
        #expect(page.totalCount == 3029)

        let neck = try #require(page.items.first)
        #expect(neck.id == "570_2_1001")
        #expect(neck.marketable && neck.tradable)
        #expect(neck.rarity?.name == "Mythical")
        #expect(neck.accentHex == "8847ff")
        #expect(neck.usedBy == "Enchantress")
        #expect(neck.subtitle == "Mythical Neck")
        #expect(neck.iconHash == "abc")
        #expect(neck.priceKey == "570|Song of the Solstice Neck")
    }

    @Test func readsSetsFromDescriptions() throws {
        let page = try InventoryPageParser.parse(Self.page)
        let neck = page.items[0]
        #expect(neck.itemSet?.name == "Song of the Solstice")
        #expect(neck.itemSet?.members.count == 5)

        let belt = page.items[1]
        #expect(belt.baseName == "Song of the Solstice Belt")
        #expect(belt.itemSet?.name == "Song of the Solstice")
        #expect(belt.itemSet?.members.count == 3)
    }

    @Test func keepsNonMarketableItemsButFlagsThem() throws {
        let page = try InventoryPageParser.parse(Self.page)
        let key = page.items[2]
        #expect(!key.marketable)
        #expect(key.marketHashName == "Treasure Key")
        #expect(key.itemSet == nil)
    }

    @Test func emptyInventoryHasNoAssets() throws {
        let page = try InventoryPageParser.parse(Data(#"{"total_inventory_count":0,"success":1,"rwgrsn":-2}"#.utf8))
        #expect(page.items.isEmpty)
        #expect(!page.moreItems)
    }

    @Test func failedResponseThrows() {
        #expect(throws: InventoryPageParser.ParseError.self) {
            try InventoryPageParser.parse(Data(#"{"success":false,"Error":"This profile is private."}"#.utf8))
        }
    }

    @Test func setDetectionWithoutColors() {
        let lines = ["Used By: Juggernaut", "", "Bladeform Legacy", "Bladeform Legacy Mask", "Bladeform Legacy Sword", "Bladeform Legacy Cape"]
            .map { DescriptionLine(text: $0, color: nil) }
        let set = ItemSetDetector.detect(itemName: "Bladeform Legacy Sword", lines: lines)
        #expect(set == ItemSetInfo(name: "Bladeform Legacy", members: ["Bladeform Legacy Mask", "Bladeform Legacy Sword", "Bladeform Legacy Cape"]))
    }
}

struct DirectoryParsingTests {
    @Test func readsAppContextsFromInventoryPage() throws {
        let html = """
        <script>
        var g_rgAppContextData = {"570":{"appid":570,"name":"Dota 2","icon":"https://cdn/570.jpg","link":"https://steamcommunity.com/app/570","asset_count":3029,"rgContexts":{"2":{"asset_count":3029,"id":"2","name":"Backpack"}}},"753":{"appid":753,"name":"Steam","icon":"https://cdn/753.jpg","asset_count":540,"rgContexts":{"1":{"asset_count":0,"id":"1","name":"Gifts"},"6":{"asset_count":540,"id":"6","name":"Community"}}},"999":{"appid":999,"name":"Odd {Braces} \\"Game\\"","asset_count":0,"rgContexts":[]}};
        var g_rgCurrency = [];
        </script>
        """
        let contexts = try #require(InventoryDirectoryParser.contexts(fromInventoryPage: html))
        #expect(contexts.map(\.id) == ["570_2", "753_6"])
        #expect(contexts.first?.name == "Dota 2")
        #expect(contexts.first?.assetCount == 3029)
    }

    @Test func missingDirectoryReturnsNil() {
        #expect(InventoryDirectoryParser.contexts(fromInventoryPage: "<html>private</html>") == nil)
    }
}

struct MarketParsingTests {
    @Test func parsesPriceOverview() throws {
        let data = Data(#"{"success":true,"lowest_price":"$3.67","volume":"1,204","median_price":"$3.52"}"#.utf8)
        let quote = try PriceOverviewParser.parse(data, currency: .usd, checkedAt: Date(timeIntervalSince1970: 0))
        #expect(quote.lowestCents == 367)
        #expect(quote.medianCents == 352)
        #expect(quote.volume == 1_204)
        #expect(quote.valueCents == 367)
    }

    @Test func itemWithoutListingsHasNoPrice() throws {
        let quote = try PriceOverviewParser.parse(Data(#"{"success":true}"#.utf8), currency: .usd, checkedAt: Date())
        #expect(quote.valueCents == nil)
    }

    @Test func parsesSellResponses() {
        let ok = SellResponseParser.parse(Data(#"{"success":true,"requires_confirmation":1,"needs_mobile_confirmation":true,"needs_email_confirmation":false}"#.utf8))
        #expect(ok.success && ok.needsConfirmation)

        let failed = SellResponseParser.parse(Data(#"{"success":false,"message":"You already have a listing for this item pending confirmation."}"#.utf8))
        #expect(!failed.success)
        #expect(failed.message?.contains("pending confirmation") == true)
    }

    @Test func encodesMarketHashNames() {
        #expect(PriceKey.percentEncode("A+B & C/D") == "A%2BB%20%26%20C%2FD")
        #expect(PriceKey.split("570|Name|With|Bars")?.marketHashName == "Name|With|Bars")
    }
}
