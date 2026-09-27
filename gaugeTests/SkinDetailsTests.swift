//
//  SkinDetailsTests.swift
//  gaugeTests
//

import Foundation
import Testing
@testable import gauge

struct ItemCertificateTests {
    /// CSFloat's serializer test vectors: generated links (mask 0, checksum included) and real,
    /// masked ones copied from Steam.
    @Test func decodesAGeneratedCertificate() throws {
        let block = try #require(ItemCertificate.decode("00180720DA03280638FBEE88F90340B2026BC03C96"))
        #expect(block.defIndex == 7)
        #expect(block.paintIndex == 474)
        #expect(block.rarity == 6)
        #expect(block.paintSeed == 306)
        #expect(block.paintWear == Float(0.6336590647697449))
        #expect(block.stickers.isEmpty)
    }

    @Test func decodesStickers() throws {
        let block = try #require(ItemCertificate.decode("00180720C80A280638A4E1F5FB03409A0562040800104C62040801104C62040802104C62040803104C6D4F5E30"))
        #expect(block.paintSeed == 666)
        #expect(block.stickers.map(\.slot) == [0, 1, 2, 3])
        #expect(block.stickers.allSatisfy { $0.kitID == 76 })
    }

    @Test func unmasksRealInspectLinks() throws {
        let link = "steam://rungame/730/76561202255233023/+csgo_econ_action_preview%20CBDB3F0B6C6170CAD3F4EB60C2E3C9FBC7F3607D7A3DC88B29C8A9CEC3CADB5F80A9CEC3CBDB2289A9CEC3C8DB7381A9CEC3CFDB5F81A3484B4B4BC7BBC369CADDC3CBDB98F67323398B8E554C76F5869D456F8B9352CE341D4900"
        let block = try #require(ItemCertificate.decode(link))
        #expect(block.itemID == 50_286_157_940)
        #expect(block.defIndex == 63)
        #expect(block.paintIndex == 1195)
        #expect(block.paintSeed == 482)
        #expect(abs(Double(block.paintWear ?? 0) - 0.3991330564) < 1e-9)
        #expect(block.origin == 8)
        #expect(block.stickers.count == 4)
        #expect(block.keychains.map(\.kitID) == [83])

        // The same item under another mask.
        let other = try #require(ItemCertificate.decode("E5F51125424F5EE4FDDAC54EECCDE7D5E9DD4E535413E6A507E687E0EDE4F571AE87E0EDE5F50CA787E0EDE6F55DAF87E0EDE1F571AF8D66656565E995ED47E4F3EDE5F5B6D85D0D17A5A07B6258DBA8B36B41A5BD7CE028CEE12E"))
        #expect(other == block)
    }

    @Test func readsCharmsAndHighlights() throws {
        let block = try #require(ItemCertificate.decode("steam://run/730//+csgo_econ_action_preview%20A2B2A2BA69A882A28AA192AECAA2D2B700A3A5AAA2B286FA7BA0D684BE72"))
        #expect(block.defIndex == 1355)
        #expect(block.keychains.first?.kitID == 36)
        #expect(block.keychains.first?.highlightReel == 345)
    }

    @Test func rejectsWhatIsntACertificate() {
        #expect(ItemCertificate.decode("") == nil)
        #expect(ItemCertificate.decode("not hex at all") == nil)
        #expect(ItemCertificate.decode("00FF") == nil)
        // Truncated: the length says more bytes follow than there are.
        #expect(ItemCertificate.decode("005A10FFFFFFFF00000000") == nil)
    }
}

struct SkinDetailsParsingTests {
    /// A CS2 page: an AK-47 with stickers, a charm, a name tag, and StatTrak, and a case with nothing extra.
    /// The certificate is masked, as Steam's are.
    static let page = Data("""
    {
      "assets": [
        {"appid": 730, "contextid": "2", "assetid": "41300000001", "classid": "501", "instanceid": "9", "amount": "1"},
        {"appid": 730, "contextid": "2", "assetid": "41300000002", "classid": "502", "instanceid": "0", "amount": "1"}
      ],
      "descriptions": [
        {
          "appid": 730, "classid": "501", "instanceid": "9",
          "name": "StatTrak™ AK-47 | Case Hardened (Minimal Wear)",
          "market_hash_name": "StatTrak™ AK-47 | Case Hardened (Minimal Wear)",
          "type": "StatTrak™ Classified Rifle", "tradable": 1, "marketable": 1, "commodity": 0,
          "descriptions": [
            {"type": "html", "value": "Exterior: Minimal Wear", "name": "exterior_wear"},
            {"type": "html", "value": "<br><div id=\\"sticker_info\\" name=\\"sticker_info\\"><center><img src=\\"a.png\\"><img src=\\"b.png\\"><br>Sticker: Crown (Foil), Titan (Holo) | Katowice 2014</center></div>", "name": "sticker_info"},
            {"type": "html", "value": "<br><div id=\\"keychain_info\\"><center><img src=\\"c.png\\"><br>Charm: Lil' Squirt</center></div>", "name": "keychain_info"}
          ],
          "tags": [
            {"category": "Exterior", "internal_name": "WearCategory1", "localized_category_name": "Exterior", "localized_tag_name": "Minimal Wear"},
            {"category": "Rarity", "internal_name": "Rarity_Legendary_Weapon", "localized_category_name": "Quality", "localized_tag_name": "Classified", "color": "d32ce6"}
          ]
        },
        {
          "appid": 730, "classid": "502", "instanceid": "0",
          "name": "Recoil Case", "market_hash_name": "Recoil Case", "type": "Base Grade Container",
          "tradable": 1, "marketable": 1, "commodity": 1
        }
      ],
      "asset_properties": [
        {
          "appid": 730, "contextid": "2", "assetid": "41300000001",
          "asset_properties": [
            {"propertyid": 1, "int_value": "661", "name": "Pattern Template"},
            {"propertyid": 2, "float_value": "0.07123450189828873", "name": "Wear Rating"},
            {"propertyid": 6, "string_value": "A7B7265D084A3EA6BFA0878B8FA197AE9F4261604BA4E732A2EFA7F71EADFDAFE5CBD2C287E0C2CAC5A3AFA7B7EBC5ADAFA5B74781BAA7A72799D7AF05A6A0AFA7B783F71EC7C3FC6A87", "name": "Item Certificate"}
          ]
        }
      ],
      "total_inventory_count": 2,
      "success": 1,
      "rwgrsn": -2
    }
    """.utf8)

    @Test func readsFloatPatternAndCertificate() throws {
        let items = try InventoryPageParser.parse(Self.page).items
        let ak = try #require(items.first)
        let skin = try #require(ak.skin)
        #expect(skin.wear == 0.07123450189828873)
        #expect(skin.exterior == .minimalWear)
        #expect(skin.pattern == 661)
        #expect(skin.paintIndex == 44)
        #expect(skin.defIndex == 7)
        #expect(skin.statTrak == 1_337)
        #expect(skin.nameTag == "Blue Gem")
        #expect(skin.originName == "Unboxed")
        #expect(skin.inspectLink?.hasPrefix("steam://run/730//+csgo_econ_action_preview%20A7B7") == true)
        #expect(ak.wear == skin.wear)
    }

    @Test func matchesStickerAndCharmNamesToTheirSlots() throws {
        let skin = try #require(InventoryPageParser.parse(Self.page).items.first?.skin)
        #expect(skin.stickers.map(\.slot) == [0, 2])
        #expect(skin.stickers.map(\.name) == ["Crown (Foil)", "Titan (Holo) | Katowice 2014"])
        #expect(skin.stickers.map(\.wear) == [nil, 0.25])
        #expect(skin.charms.map(\.name) == ["Lil' Squirt"])
        #expect(skin.charms.first?.pattern == 12_345)
        #expect(skin.appliedSummary == "2 stickers and a charm")
    }

    @Test func itemsWithoutPropertiesHaveNoSkinDetails() throws {
        let items = try InventoryPageParser.parse(Self.page).items
        #expect(items[1].name == "Recoil Case")
        #expect(items[1].skin == nil)
        #expect(items[1].copyKey == items[1].priceKey)
    }

    @Test func readsPropertiesByNumberWhenUnnamed() {
        let skin = SkinDetailsReader.read([
            AssetPropertyDTO(id: 2, floatValue: 0.451),
            AssetPropertyDTO(id: 1, intValue: 12),
            AssetPropertyDTO(id: 99, intValue: 5),
        ], lines: [])
        #expect(skin?.wear == 0.451)
        #expect(skin?.exterior == .battleScarred)
        #expect(skin?.pattern == 12)
        #expect(skin?.certificate == nil)
    }

    @Test func aNameTellsWhichPropertyItIs() {
        let skin = SkinDetailsReader.read([AssetPropertyDTO(id: 7, name: "Wear Rating", floatValue: 0.2)], lines: [])
        #expect(skin?.wear == 0.2)
    }

    @Test func fallsBackToTheCertificatesFloatAndPattern() throws {
        // A Ruby Karambit whose only property is its certificate.
        let skin = try #require(SkinDetailsReader.read([AssetPropertyDTO(id: 6, stringValue: "0018FB03209F032806300338F08BA6E203409C03700807E37A70")], lines: []))
        #expect(skin.wear == Double(Float(0.0123)))
        #expect(skin.pattern == 412)
        #expect(skin.phase == "Ruby")
        #expect(skin.statTrak == nil)
        #expect(skin.stickers.isEmpty)
    }

    @Test func aCharmsTemplateIsItsPattern() throws {
        let fromCertificate = try #require(SkinDetailsReader.read([AssetPropertyDTO(id: 6, stringValue: "3C24F73614380C384C349E3D3B343C2C186CDD00128B2508")], lines: []))
        #expect(fromCertificate.pattern == 7_777)
        #expect(fromCertificate.charms.isEmpty)

        let fromProperty = SkinDetailsReader.read([AssetPropertyDTO(id: 3, name: "Charm Template", intValue: 42)], lines: [])
        #expect(fromProperty?.pattern == 42)

        // A charm's paint seed, if it has one, isn't its pattern.
        let withSeed = try #require(SkinDetailsReader.read([AssetPropertyDTO(id: 6, stringValue: "51499A5B7955615511512159F350565951417501B06DED253FC5")], lines: []))
        #expect(withSeed.pattern == 7_777)
        #expect(withSeed.charms.isEmpty)
    }

    @Test func stickersOnTheirOwnHaveNothingToShow() {
        #expect(SkinDetailsReader.read([AssetPropertyDTO(id: 6, stringValue: "0018B909280330046205080010E0267008B9CB7E8A")], lines: []) == nil)
        #expect(SkinDetailsReader.read([], lines: []) == nil)
    }

    @Test func namesStayOffWhenTheyDontLineUp() {
        var stickers = [SkinAccessory(slot: 0), SkinAccessory(slot: 1)]
        SkinDetailsReader.attach(["Only one"], to: &stickers)
        #expect(stickers.allSatisfy { $0.name == nil })
        let lines = [DescriptionLine(text: "Exterior: Factory New"), DescriptionLine(text: "Sticker: A, B")]
        #expect(SkinDetailsReader.names(in: lines, prefixes: ["Sticker: "]) == ["A", "B"])
    }

    @Test func otherGamesIgnoreProperties() throws {
        let json = #"{"assets":[{"appid":570,"contextid":"2","assetid":"1","classid":"1","instanceid":"0"}],"descriptions":[{"classid":"1","instanceid":"0","name":"Crest","marketable":1}],"asset_properties":[{"assetid":"1","asset_properties":[{"propertyid":2,"float_value":"0.5"}]}],"success":1}"#
        let item = try #require(InventoryPageParser.parse(Data(json.utf8)).items.first)
        #expect(item.skin == nil)
    }

    @Test func malformedPropertiesDontStopTheInventory() throws {
        let json = #"{"assets":[{"appid":730,"contextid":"2","assetid":"1","classid":"1","instanceid":"0"}],"descriptions":[{"classid":"1","instanceid":"0","name":"Case","marketable":1}],"asset_properties":{"unexpected":true},"success":1}"#
        let items = try InventoryPageParser.parse(Data(json.utf8)).items
        #expect(items.count == 1)
        #expect(items.first?.skin == nil)
    }

    @Test func oldCachesStillDecode() throws {
        // Inventories cached before skin details existed have no "skin" key.
        var item = CleanupPlannerTests.item("1", "Crest")
        item.skin = SkinDetails(wear: 0.1)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode([item])) as? [[String: Any]] ?? []
        json[0]["skin"] = nil
        let decoded = try JSONDecoder().decode([InventoryItem].self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.first?.skin == nil)
        #expect(try JSONDecoder().decode([InventoryItem].self, from: JSONEncoder().encode([item])).first?.skin?.wear == 0.1)
    }
}

struct SkinFormattingTests {
    @Test func exteriorsFollowSteamsRanges() {
        #expect(Exterior.of(0) == .factoryNew)
        #expect(Exterior.of(0.0699) == .factoryNew)
        #expect(Exterior.of(0.07) == .minimalWear)
        #expect(Exterior.of(0.15) == .fieldTested)
        #expect(Exterior.of(0.3799) == .fieldTested)
        #expect(Exterior.of(0.38) == .wellWorn)
        #expect(Exterior.of(0.45) == .battleScarred)
        #expect(Exterior.of(1) == .battleScarred)
    }

    @Test func positionWithinTheExterior() {
        #expect(abs(Exterior.position(of: 0.0035) - 0.05) < 1e-12)
        #expect(abs(Exterior.position(of: 0.265) - 0.5) < 1e-12)
        #expect(Exterior.position(of: 1) == 1)
    }

    @Test func floatsPrintEveryDigitWithoutExponents() {
        #expect(FloatText.full(0.07123450189828873) == "0.07123450189828873")
        #expect(FloatText.full(0.5) == "0.5")
        #expect(FloatText.full(1.9394794104066193e-10) == "0.00000000019394794104066193")
        #expect(FloatText.full(0.00001) == "0.00001")
        #expect(FloatText.full(0) == "0.0")
    }

    @Test func shortFloatsKeepThreeSignificantDigits() {
        #expect(FloatText.short(0.07123450189828873) == "0.0712")
        #expect(FloatText.short(0.9) == "0.9000")
        #expect(FloatText.short(0.00331) == "0.00331")
        #expect(FloatText.short(0.0000331) == "0.0000331")
        #expect(FloatText.short(0) == "0.0000")
    }

    @Test func dopplerPhases() {
        #expect(DopplerPhase.name(paintIndex: 415) == "Ruby")
        #expect(DopplerPhase.name(paintIndex: 419) == "Phase 2")
        #expect(DopplerPhase.name(paintIndex: 568) == "Emerald")
        #expect(DopplerPhase.name(paintIndex: 44) == nil)
        #expect(DopplerPhase.shortName("Phase 2") == "P2")
        #expect(DopplerPhase.shortName("Black Pearl") == "Black Pearl")
    }

    @Test func dopplerPhasesAreDifferentItems() {
        var ruby = CleanupPlannerTests.item("1", "★ Karambit | Doppler (Factory New)")
        ruby.skin = SkinDetails(wear: 0.01, paintIndex: 415)
        var phase = ruby
        phase.skin?.paintIndex = 418
        #expect(ruby.priceKey == phase.priceKey)
        #expect(ruby.copyKey != phase.copyKey)
    }

    @Test func searchFindsPatternsAndFloats() {
        var ak = CleanupPlannerTests.item("1", "AK-47 | Case Hardened (Field-Tested)")
        ak.skin = SkinDetails(wear: 0.1523, pattern: 661)
        #expect(ak.matches(search: "#661"))
        #expect(!ak.matches(search: "#662"))
        #expect(ak.matches(search: "0.15"))
        #expect(!ak.matches(search: "0.16"))
        #expect(ak.matches(search: "case hardened"))
        #expect(!CleanupPlannerTests.item("2", "Crest").matches(search: "#661"))
    }
}

struct SkinCleanupTests {
    static func skin(_ asset: String, _ name: String, wear: Double?, pattern: Int? = nil, marketable: Bool = true, stickers: Int = 0) -> InventoryItem {
        var item = CleanupPlannerTests.item(asset, name, marketable: marketable)
        item.appID = 730
        item.skin = SkinDetails(wear: wear, pattern: pattern, stickers: (0..<stickers).map { SkinAccessory(slot: $0) })
        return item
    }

    func plan(_ items: [InventoryItem], _ prices: [String: Int], starred: Set<String> = [], rules: CleanupRules = CleanupRules()) -> CleanupPlan {
        var quotes: [String: PriceQuote] = [:]
        for (name, cents) in prices { quotes["730|\(name)"] = CleanupPlannerTests.quote(cents) }
        return CleanupPlanner.plan(items: items, prices: quotes, trends: [:], starred: starred, overrides: [:], rules: rules, currency: .usd)
    }

    static let redline = "AK-47 | Redline (Field-Tested)"

    @Test func extraCopiesKeepTheLowestFloat() {
        let items = [
            Self.skin("1", Self.redline, wear: 0.30),
            Self.skin("2", Self.redline, wear: 0.17),
            Self.skin("3", Self.redline, wear: 0.25),
        ]
        let result = plan(items, [Self.redline: 300])
        #expect(Set(result.entries(in: .sell).map(\.item.assetID)) == ["1", "3"])
        #expect(result.entries(in: .keep).map(\.item.assetID) == ["2"])
        #expect(result.entries(in: .keep).first?.reason.text == "Lowest float of 3")
    }

    @Test func theLowestFloatStaysEvenWhenItCantBeSold() {
        let items = [
            Self.skin("1", Self.redline, wear: 0.30),
            Self.skin("2", Self.redline, wear: 0.17, marketable: false),
            Self.skin("3", Self.redline, wear: 0.25),
        ]
        #expect(Set(plan(items, [Self.redline: 300]).entries(in: .sell).map(\.item.assetID)) == ["1", "3"])

        // A starred copy is the one kept, whatever its float.
        let starred = plan(items.map { var item = $0; item.marketable = true; return item }, [Self.redline: 300], starred: ["730_2_1"])
        #expect(Set(starred.entries(in: .sell).map(\.item.assetID)) == ["2", "3"])
    }

    @Test func lowFloatsWaitForALook() {
        let name = "P250 | Sand Dune (Factory New)"
        let items = [
            Self.skin("1", name, wear: 0.001),
            Self.skin("2", name, wear: 0.002),
            Self.skin("3", name, wear: 0.05),
        ]
        let result = plan(items, [name: 50])
        #expect(result.entries(in: .keep).map(\.item.assetID) == ["1"])
        #expect(result.entries(in: .review).map(\.item.assetID) == ["2"])
        #expect(result.entries(in: .review).first?.reason == CleanupReason(kind: .lowFloat, text: "Float 0.00200 · cleanest 3% of Factory New · extra copy"))
        #expect(result.entries(in: .sell).map(\.item.assetID) == ["3"])

        var rules = CleanupRules()
        rules.lowFloatShare = 0.01
        #expect(plan(items, [name: 50], rules: rules).entries(in: .review).isEmpty)
        rules.reviewLowFloats = false
        rules.lowFloatShare = 0.05
        #expect(plan(items, [name: 50], rules: rules).entries(in: .sell).count == 2)
    }

    @Test func stickersAndCharmsWaitForALook() {
        let name = "MP9 | Sand Dashed (Field-Tested)"
        let result = plan([Self.skin("1", name, wear: 0.3, stickers: 2)], [name: 4])
        #expect(result.entries(in: .review).first?.reason == CleanupReason(kind: .applied, text: "With 2 stickers"))

        var rules = CleanupRules()
        rules.reviewApplied = false
        #expect(plan([Self.skin("1", name, wear: 0.3, stickers: 2)], [name: 4], rules: rules).entries(in: .sell).count == 1)
    }

    @Test func dopplerPhasesArentCopiesOfEachOther() {
        let name = "★ Karambit | Doppler (Factory New)"
        var ruby = Self.skin("1", name, wear: 0.01)
        ruby.skin?.paintIndex = 415
        var phase = Self.skin("2", name, wear: 0.02)
        phase.skin?.paintIndex = 418
        let result = plan([ruby, phase], [name: 90_000])
        #expect(result.entries(in: .keep).map(\.reason.kind) == [.noRule, .noRule])
        #expect(result.entries(in: .keep).allSatisfy { $0.copies == 1 })
    }

    @Test func everySkinGetsItsOwnRow() {
        let items = [
            Self.skin("1", Self.redline, wear: 0.30, pattern: 661),
            Self.skin("3", Self.redline, wear: 0.25, pattern: 12),
            Self.skin("2", Self.redline, wear: 0.17),
        ]
        let result = plan(items, [Self.redline: 300])
        let rows = CleanupRow.rows(from: result.entries(in: .sell))
        #expect(rows.map(\.item.assetID) == ["3", "1"])
        #expect(rows.first?.id == "sell|730_2_3")
        #expect(result.itemIDs(inRow: "sell|730_2_3") == ["730_2_3"])
        #expect(CleanupRow.rows(from: result.entries(in: .sell), search: "#661").map(\.item.assetID) == ["1"])
        #expect(CleanupRow.filters(for: result.entries(in: .sell)).map(\.filter) == [.reason(.extraCopy)])
    }

    @Test func olderRulesTurnTheSkinChecksOn() throws {
        let rules = try JSONDecoder().decode(CleanupRules.self, from: Data(#"{"sellCheap":false}"#.utf8))
        #expect(rules.reviewLowFloats && rules.reviewApplied)
        #expect(rules.lowFloatShare == 0.05)
        #expect(!rules.sellCheap)
    }

    @Test func sortsByFloat() {
        let items = [
            Self.skin("1", "B", wear: 0.30),
            CleanupPlannerTests.item("2", "A"),
            Self.skin("3", "C", wear: 0.01),
        ]
        var query = InventoryQuery()
        query.sort = .float
        #expect(query.apply(to: items, facts: InventoryFacts()).map(\.assetID) == ["3", "1", "2"])
    }
}

struct SkinSummaryTests {
    @Test func summarizesWhatTellsCopiesApart() {
        #expect(SkinDetails(wear: 0.0123, pattern: 412, paintIndex: 419).summary == "P2 · 0.0123 · #412")
        #expect(SkinDetails(pattern: 7_777).summary == "#7777")
        #expect(SkinDetails(nameTag: "Hi").summary == nil)
    }

    @Test func linksToTheFinishAndPatternInCSFloatsDatabase() {
        let skin = SkinDetails(pattern: 661, paintIndex: 44, defIndex: 7)
        #expect(skin.databaseURL?.absoluteString == "https://csfloat.com/db?defIndex=7&paintIndex=44&paintSeed=661")
        #expect(SkinDetails(pattern: 661).databaseURL == nil)
    }

    @Test func explainsWorthALook() {
        var rules = CleanupRules()
        #expect(rules.reviewSummary(currency: .usd, skins: false) == "worth \(Money.format(500, .usd)) or more")
        #expect(rules.reviewSummary(currency: .usd, skins: true) == "worth \(Money.format(500, .usd)) or more, a skin with a low float, or a skin with stickers or a charm")
        rules.reviewExpensive = false
        rules.reviewApplied = false
        #expect(rules.reviewSummary(currency: .usd, skins: true) == "a skin with a low float")
        rules.reviewLowFloats = false
        #expect(rules.reviewSummary(currency: .usd, skins: true) == nil)
    }

    @Test func listsEveryCopyBestFloatFirst() {
        let name = SkinCleanupTests.redline
        let items = [
            SkinCleanupTests.skin("1", name, wear: 0.30),
            SkinCleanupTests.skin("2", name, wear: 0.17),
            SkinCleanupTests.skin("3", "Other", wear: 0.2),
        ]
        var quotes: [String: PriceQuote] = [:]
        for key in ["730|\(name)", "730|Other"] { quotes[key] = CleanupPlannerTests.quote(300) }
        let plan = CleanupPlanner.plan(items: items, prices: quotes, trends: [:], starred: [], overrides: [:], rules: CleanupRules(), currency: .usd)
        #expect(plan.copies(of: items[0]).map(\.item.assetID) == ["2", "1"])
        #expect(plan.copies(of: items[0]).map(\.bucket) == [.keep, .sell])
        #expect(plan.hasSkins)

        let dota = CleanupPlanner.plan(items: [CleanupPlannerTests.item("1", "Crest")], prices: [:], trends: [:], starred: [], overrides: [:], rules: CleanupRules(), currency: .usd)
        #expect(!dota.hasSkins)
    }
}

struct DemoSkinTests {
    @Test func theDemoHasSkinsWorthALook() {
        let demo = DemoData.make(now: Date(timeIntervalSince1970: 1_790_000_000))
        let cs2 = demo.itemsByContext["730_2"] ?? []
        #expect(cs2.filter { $0.skin?.wear != nil }.count == 22)
        #expect(demo.contexts.first { $0.id == "730_2" }?.assetCount == cs2.count)

        let plan = CleanupPlanner.plan(items: cs2, prices: demo.prices, trends: [:], starred: [], overrides: [:], rules: CleanupRules(), currency: .usd)
        #expect(plan.entries(in: .review).contains { $0.reason.kind == .lowFloat && $0.item.name.hasPrefix("UMP-45") })
        #expect(plan.entries(in: .review).contains { $0.reason.kind == .applied })
        // The P250 kept is the 0.0008, not the oldest.
        #expect(plan.entries(in: .keep).first { $0.item.name.hasPrefix("P250") }?.item.wear == 0.000_812_455_4)
        let karambits = cs2.filter { $0.name.hasPrefix("★ Karambit") }
        #expect(Set(karambits.compactMap(\.skin?.phase)) == ["Ruby", "Phase 2"])
    }
}
