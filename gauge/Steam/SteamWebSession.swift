//
//  SteamWebSession.swift
//  gauge
//
//  Selling needs a signed-in steamcommunity.com session. Gauge never sees
//  the user's password: they sign in on Steam's own page in a web view, and
//  Gauge reads the resulting session cookies from WebKit's cookie store,
//  which keeps them in the app's sandbox. Signing out deletes them.
//

import Foundation
import Observation
import WebKit

@Observable
final class SteamWebSession {
    /// The SteamID64 the web session belongs to, if signed in.
    private(set) var signedInSteamID: String?
    private(set) var lastChecked: Date?

    static let loginURL = URL(string: "https://steamcommunity.com/login/home/?goto=")!

    var isSignedIn: Bool { signedInSteamID != nil }

    /// Re-reads the cookie store.
    func refresh() async {
        let cookies = await steamCookies()
        signedInSteamID = cookies.first { $0.name == "steamLoginSecure" }.flatMap { Self.steamID(fromLoginCookie: $0.value) }
        lastChecked = Date()
    }

    /// Credentials for one selling session, or nil when signed out.
    func auth() async -> SteamWebAuth? {
        let cookies = await steamCookies()
        guard let login = cookies.first(where: { $0.name == "steamLoginSecure" }),
              let steamID = Self.steamID(fromLoginCookie: login.value)
        else {
            signedInSteamID = nil
            return nil
        }
        signedInSteamID = steamID
        let sessionID: String
        if let existing = cookies.first(where: { $0.name == "sessionid" })?.value, !existing.isEmpty {
            sessionID = existing
        } else {
            // Steam's CSRF check only needs the cookie and the form field to match.
            sessionID = Self.randomSessionID()
            if let cookie = HTTPCookie(properties: [
                .domain: "steamcommunity.com",
                .path: "/",
                .name: "sessionid",
                .value: sessionID,
                .secure: "TRUE",
            ]) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie) {
                        continuation.resume()
                    }
                }
            }
        }
        return SteamWebAuth(steamID64: steamID, sessionID: sessionID, steamLoginSecure: login.value)
    }

    /// Clears the web view's cookies and storage. Steam is the only site Gauge's web view visits.
    func signOut() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: Date(timeIntervalSince1970: 0)
            ) {
                continuation.resume()
            }
        }
        signedInSteamID = nil
    }

    private func steamCookies() async -> [HTTPCookie] {
        let all = await withCheckedContinuation { (continuation: CheckedContinuation<[HTTPCookie], Never>) in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        return all.filter { $0.domain.hasSuffix("steamcommunity.com") }
    }

    /// `steamLoginSecure` is "<steamid64>||<token>", URL-encoded.
    nonisolated static func steamID(fromLoginCookie value: String) -> String? {
        let decoded = value.removingPercentEncoding ?? value
        guard let separator = decoded.range(of: "||") else { return nil }
        let id = String(decoded[..<separator.lowerBound])
        return ProfileReference.isSteamID64(id) ? id : nil
    }

    nonisolated static func randomSessionID() -> String {
        (0..<12).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}
