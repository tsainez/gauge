//
//  SteamLogin.swift
//  gauge
//
//  Reading Steam's web sign-in cookie. `steamLoginSecure` is
//  "<steamid64>||<access token>", URL-encoded, and the access token is a
//  JWT whose payload says which account it belongs to and when it expires.
//  Gauge only reads the payload to know when to renew; Steam checks the
//  signature.
//

import Foundation

nonisolated struct SteamLoginToken: Equatable, Sendable {
    var steamID64: String
    /// When Steam stops accepting the token. Nil when the token doesn't say.
    var expiresAt: Date?

    /// Renew this long before expiry, so a listing run doesn't fail partway through.
    static let renewalMargin: TimeInterval = 10 * 60

    init(steamID64: String, expiresAt: Date?) {
        self.steamID64 = steamID64
        self.expiresAt = expiresAt
    }

    /// Reads a `steamLoginSecure` cookie value. Nil when it isn't one.
    init?(cookieValue: String) {
        let decoded = cookieValue.removingPercentEncoding ?? cookieValue
        guard let separator = decoded.range(of: "||") else { return nil }
        let id = String(decoded[..<separator.lowerBound])
        guard ProfileReference.isSteamID64(id) else { return nil }
        let claims = Self.claims(fromJWT: String(decoded[separator.upperBound...]))
        // A token issued to a different account than the cookie names isn't one to trust.
        if let subject = claims?.sub, subject != id { return nil }
        steamID64 = id
        expiresAt = claims?.exp.map { Date(timeIntervalSince1970: $0) }
    }

    func isExpired(at now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }

    func needsRenewal(at now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) < Self.renewalMargin
    }

    private struct Claims: Decodable {
        var sub: String?
        var exp: Double?
    }

    /// Decodes the middle, base64url-encoded part of a JWT.
    private static func claims(fromJWT token: String) -> Claims? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(Claims.self, from: data)
    }
}

/// Where a Steam web session stands, as far as Gauge can tell from its cookies.
nonisolated enum SteamSignInStatus: Equatable, Sendable {
    /// Before the cookie store has been read.
    case unknown
    case signedOut
    case signedIn(steamID64: String, expiresAt: Date?)
    /// Steam's sign-in lapsed and couldn't be renewed. The user has to sign in again.
    case expired(steamID64: String)

    init(token: SteamLoginToken?, now: Date = Date()) {
        guard let token else {
            self = .signedOut
            return
        }
        self = token.isExpired(at: now) ? .expired(steamID64: token.steamID64) : .signedIn(steamID64: token.steamID64, expiresAt: token.expiresAt)
    }

    /// The account with a working session.
    var signedInSteamID: String? {
        if case .signedIn(let id, _) = self { return id }
        return nil
    }

    var hasExpired: Bool {
        if case .expired = self { return true }
        return false
    }

    /// The account the cookies belong to, working or not.
    var steamID64: String? {
        switch self {
        case .signedIn(let id, _), .expired(let id): id
        case .unknown, .signedOut: nil
        }
    }
}

/// Which pages the sign-in sheet shows itself. Everything else opens in the
/// browser, so the sheet never turns into a general-purpose web browser.
nonisolated enum SteamSignInPage {
    static func keepsInSheet(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "about" || scheme == "blob" || scheme == "data" { return true }
        guard scheme == "https", let host = url.host?.lowercased() else { return false }
        // Support articles are easier to read in a real browser.
        if host == "help.steampowered.com" { return false }
        return ["steamcommunity.com", "steampowered.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

nonisolated extension ProfileSummary {
    /// Why Gauge can't read this profile's inventory, or nil if it can. A private
    /// profile is readable only while signed in to Steam as its owner.
    func accessProblem(signedInSteamID: String?) -> String? {
        if isPublic || signedInSteamID == steamID64 { return nil }
        return "\(personaName)'s profile is private. Sign in with Steam as \(personaName) to load it, or make the inventory public in Steam's privacy settings."
    }
}
