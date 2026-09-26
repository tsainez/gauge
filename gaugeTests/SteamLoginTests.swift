//
//  SteamLoginTests.swift
//  gaugeTests
//

import Foundation
import Testing
@testable import gauge

struct SteamLoginTests {
    static let steamID = "76561197960287930"

    /// A token shaped like Steam's: header.payload.signature, base64url without padding.
    static func jwt(_ payload: String) -> String {
        func encode(_ text: String) -> String {
            Data(text.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return encode(#"{"typ":"JWT","alg":"EdDSA"}"#) + "." + encode(payload) + ".c2lnbmF0dXJl"
    }

    static func cookie(sub: String = steamID, exp: Int) -> String {
        let token = jwt(#"{"iss":"r:0F2B","sub":"\#(sub)","aud":["web:community"],"exp":\#(exp),"nbf":1700000000}"#)
        return "\(steamID)%7C%7C\(token)"
    }

    @Test func readsTheAccountAndExpiry() throws {
        let token = try #require(SteamLoginToken(cookieValue: Self.cookie(exp: 1_800_000_000)))
        #expect(token.steamID64 == Self.steamID)
        #expect(token.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func knowsWhenToRenew() throws {
        let token = try #require(SteamLoginToken(cookieValue: Self.cookie(exp: 1_800_000_000)))
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(!token.needsRenewal(at: expiry.addingTimeInterval(-3_600)))
        #expect(token.needsRenewal(at: expiry.addingTimeInterval(-60)))
        #expect(!token.isExpired(at: expiry.addingTimeInterval(-60)))
        #expect(token.isExpired(at: expiry))
    }

    @Test func acceptsAnUnencodedSeparator() throws {
        let value = Self.cookie(exp: 1_800_000_000).replacingOccurrences(of: "%7C%7C", with: "||")
        #expect(SteamLoginToken(cookieValue: value)?.steamID64 == Self.steamID)
    }

    @Test func rejectsATokenForAnotherAccount() {
        #expect(SteamLoginToken(cookieValue: Self.cookie(sub: "76561198000000000", exp: 1_800_000_000)) == nil)
    }

    @Test func keepsTokensItCantDecode() throws {
        // Older sessions used an opaque token. The account is still known; the expiry isn't.
        let token = try #require(SteamLoginToken(cookieValue: "\(Self.steamID)%7C%7C0123456789ABCDEF"))
        #expect(token.expiresAt == nil)
        #expect(!token.isExpired())
        #expect(!token.needsRenewal())
    }

    @Test func rejectsOtherCookies() {
        #expect(SteamLoginToken(cookieValue: "") == nil)
        #expect(SteamLoginToken(cookieValue: "deleted") == nil)
        #expect(SteamLoginToken(cookieValue: "gaben%7C%7Ctoken") == nil)
    }

    @Test func statusFollowsTheToken() {
        let token = SteamLoginToken(steamID64: Self.steamID, expiresAt: Date(timeIntervalSince1970: 1_800_000_000))
        let before = SteamSignInStatus(token: token, now: Date(timeIntervalSince1970: 1_799_000_000))
        #expect(before.signedInSteamID == Self.steamID)
        #expect(!before.hasExpired)

        let after = SteamSignInStatus(token: token, now: Date(timeIntervalSince1970: 1_800_000_001))
        #expect(after.signedInSteamID == nil)
        #expect(after.steamID64 == Self.steamID)
        #expect(after.hasExpired)

        #expect(SteamSignInStatus(token: nil) == .signedOut)
        #expect(SteamSignInStatus.unknown.steamID64 == nil)
    }

    @Test func privateProfilesNeedTheirOwnersSignIn() {
        let open = ProfileSummary(steamID64: Self.steamID, personaName: "Tony", avatarURL: nil, isPublic: true)
        let closed = ProfileSummary(steamID64: Self.steamID, personaName: "Tony", avatarURL: nil, isPublic: false)
        #expect(open.accessProblem(signedInSteamID: nil) == nil)
        #expect(closed.accessProblem(signedInSteamID: Self.steamID) == nil)
        #expect(closed.accessProblem(signedInSteamID: nil)?.contains("private") == true)
        #expect(closed.accessProblem(signedInSteamID: "76561198000000000") != nil)
    }

    @Test func signInSheetStaysOnSteam() {
        let kept = [
            "https://steamcommunity.com/login/home/?goto=",
            "https://login.steampowered.com/jwt/refresh?redir=x",
            "https://store.steampowered.com/login/",
            "about:blank",
        ]
        let opened = [
            "https://help.steampowered.com/en/wizard/HelpWithLogin",
            "http://steamcommunity.com/login/home/",
            "https://steamcommunity.com.example.net/login",
            "https://notsteampowered.com/",
            "steam://openurl/https://store.steampowered.com",
        ]
        for url in kept { #expect(SteamSignInPage.keepsInSheet(URL(string: url)!), "\(url)") }
        for url in opened { #expect(!SteamSignInPage.keepsInSheet(URL(string: url)!), "\(url)") }
    }
}
