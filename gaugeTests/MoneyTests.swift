//
//  MoneyTests.swift
//  gaugeTests
//

import Foundation
import Testing
@testable import gauge

struct SteamFeeTests {
    @Test func floorListingPaysOneCent() {
        let fees = SteamFees.forBuyerPaying(3)
        #expect(fees.sellerReceives == 1)
        #expect(fees.steamFee == 1)
        #expect(fees.publisherFee == 1)
    }

    @Test(arguments: [
        (buyer: 3, seller: 1),
        (buyer: 4, seller: 2),
        (buyer: 5, seller: 3),
        (buyer: 10, seller: 8),
        (buyer: 23, seller: 20),
        (buyer: 100, seller: 88),
        (buyer: 367, seller: 319),
        (buyer: 1_000, seller: 870),
        (buyer: 12_345, seller: 10_736),
    ])
    func buyerPriceSplitsLikeSteam(buyer: Int, seller: Int) {
        let fees = SteamFees.forBuyerPaying(buyer)
        #expect(fees.sellerReceives == seller)
        #expect(fees.sellerReceives + fees.totalFees == buyer)
    }

    @Test func roundTripsFromSellerPrice() {
        for seller in 1...2_000 {
            let buyer = SteamFees.forSellerReceiving(seller).buyerPays
            #expect(SteamFees.sellerReceives(buyerPays: buyer) == seller)
        }
    }

    @Test func belowFloorPaysNothing() {
        #expect(SteamFees.sellerReceives(buyerPays: 1) == 0)
        #expect(SteamFees.sellerReceives(buyerPays: 0) == 0)
    }
}

struct PriceParserTests {
    @Test(arguments: [
        ("$0.03", 3),
        ("$3.67", 367),
        ("$1,234.56", 123_456),
        ("0,03€", 3),
        ("12,--€", 1_200),
        ("1.234,56€", 123_456),
        ("1 234,56 pуб.", 123_456),
        ("¥ 1,234", 123_400),
        ("R$ 0,03", 3),
        ("CDN$ 0.04", 4),
        ("£0.5", 50),
        ("12 zł", 1_200),
    ])
    func parsesSteamFormats(text: String, cents: Int) {
        #expect(PriceParser.cents(from: text) == cents)
    }

    @Test func rejectsTextWithoutDigits() {
        #expect(PriceParser.cents(from: "") == nil)
        #expect(PriceParser.cents(from: "--") == nil)
    }

    @Test func parsesVolumes() {
        #expect(PriceParser.integer(from: "1,234") == 1_234)
        #expect(PriceParser.integer(from: "7") == 7)
        #expect(PriceParser.integer(from: "") == nil)
    }
}

struct ProfileReferenceTests {
    @Test func acceptsEveryProfileForm() {
        #expect(ProfileReference.parse("76561197960287930") == .steamID64("76561197960287930"))
        #expect(ProfileReference.parse("https://steamcommunity.com/profiles/76561197960287930/") == .steamID64("76561197960287930"))
        #expect(ProfileReference.parse("steamcommunity.com/id/gabelogannewell") == .vanity("gabelogannewell"))
        #expect(ProfileReference.parse("  https://steamcommunity.com/id/some_name/inventory/  ") == .vanity("some_name"))
        #expect(ProfileReference.parse("tony") == .vanity("tony"))
    }

    @Test func rejectsOtherSites() {
        #expect(ProfileReference.parse("https://example.com/id/tony") == nil)
        #expect(ProfileReference.parse("not a profile") == nil)
        #expect(ProfileReference.parse("") == nil)
    }

    @Test func readsProfileXML() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <profile>
          <steamID64>76561197960287930</steamID64>
          <steamID><![CDATA[Rabscuttle & Co]]></steamID>
          <privacyState>public</privacyState>
          <avatarMedium><![CDATA[https://avatars.example/abc_medium.jpg]]></avatarMedium>
        </profile>
        """
        let profile = try ProfileSummary.parse(xml: xml)
        #expect(profile.steamID64 == "76561197960287930")
        #expect(profile.personaName == "Rabscuttle & Co")
        #expect(profile.isPublic)
        #expect(profile.avatarURL == "https://avatars.example/abc_medium.jpg")
    }

    @Test func surfacesSteamErrors() {
        let xml = "<response><error><![CDATA[The specified profile could not be found.]]></error></response>"
        #expect(throws: ProfileSummary.ParseError.steam("The specified profile could not be found.")) {
            try ProfileSummary.parse(xml: xml)
        }
    }
}
