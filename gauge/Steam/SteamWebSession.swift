//
//  SteamWebSession.swift
//  gauge
//
//  Signing in with Steam. Gauge never sees the user's password: they sign
//  in on Steam's own page in a web view (with their password or the Steam
//  Mobile app's QR code), and Gauge reads the session cookie Steam sets from
//  WebKit's cookie store, which keeps it in the app's sandbox. The same
//  session tells Gauge whose profile to show, lets it read that account's
//  inventory even when it's private, and lists items. Signing out deletes it.
//
//  Steam's session cookie lasts about a day. Steam also keeps a long-lived
//  refresh cookie on login.steampowered.com, and its pages trade that for a
//  new session when the old one runs out, so renewing is just loading a
//  steamcommunity.com page in an off-screen web view.
//

import AppKit
import Foundation
import Observation
import WebKit

@Observable
final class SteamWebSession {
    private(set) var status: SteamSignInStatus = .unknown
    private(set) var isRenewing = false

    /// Told about each off-screen renewal, for the network log.
    @ObservationIgnored var onActivity: ((NetworkEvent) -> Void)?
    @ObservationIgnored private var loginCookie: String?
    @ObservationIgnored private var lastRenewalAttempt: Date?
    @ObservationIgnored private var renewal: Task<SteamLoginToken?, Never>?

    static let loginURL = URL(string: "https://steamcommunity.com/login/home/?goto=")!
    static let renewalURL = URL(string: "https://steamcommunity.com/my/")!
    /// Don't retry a failed renewal more often than this.
    static let renewalRetryInterval: TimeInterval = 5 * 60

    /// The account with a working session, if any.
    var signedInSteamID: String? { status.signedInSteamID }
    var isSignedIn: Bool { signedInSteamID != nil }

    /// The web views Gauge shows Steam in. They share WebKit's persistent store,
    /// which is what keeps the refresh cookie between launches.
    static func webViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        return configuration
    }

    /// Re-reads the cookie store. With `renewIfNeeded`, a session that has run out
    /// (or is about to) is renewed first.
    func refresh(renewIfNeeded: Bool = true) async {
        var token = await readToken()
        if renewIfNeeded, let current = token, current.needsRenewal() {
            if let renewal {
                // Someone else is already renewing; wait for theirs.
                token = await renewal.value
            } else if lastRenewalAttempt.map({ Date().timeIntervalSince($0) >= Self.renewalRetryInterval }) ?? true {
                lastRenewalAttempt = Date()
                let task = Task { await self.renew(current) }
                renewal = task
                token = await task.value
                renewal = nil
            }
        }
        // The sign-in sheet checks every second; only tell observers about real changes.
        let updated = SteamSignInStatus(token: token)
        if updated != status { status = updated }
    }

    /// Credentials for signed-in requests, renewing the session first if it needs it.
    /// Nil when signed out or when the session couldn't be renewed.
    func auth() async -> SteamWebAuth? {
        await refresh()
        guard let steamID = status.signedInSteamID, let login = loginCookie else { return nil }
        let sessionID: String
        if let existing = await steamCookies().first(where: { $0.name == "sessionid" })?.value, !existing.isEmpty {
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
        return SteamWebAuth(steamID64: steamID, sessionID: sessionID, steamLoginSecure: login)
    }

    /// Clears the web view's cookies and storage, including Steam's refresh cookie.
    /// Steam is the only site Gauge's web views visit.
    func signOut() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: Date(timeIntervalSince1970: 0)
            ) {
                continuation.resume()
            }
        }
        loginCookie = nil
        lastRenewalAttempt = nil
        status = .signedOut
    }

    // MARK: - Private

    private func readToken() async -> SteamLoginToken? {
        let value = await steamCookies().first { $0.name == "steamLoginSecure" }?.value
        loginCookie = value
        return value.flatMap { SteamLoginToken(cookieValue: $0) }
    }

    /// Loads a steamcommunity.com page off screen and waits for Steam to replace the
    /// session cookie. Returns whatever session cookie is there when it's done.
    private func renew(_ current: SteamLoginToken, timeout: TimeInterval = 20) async -> SteamLoginToken? {
        isRenewing = true
        defer { isRenewing = false }

        let started = Date()
        let webView = WKWebView(frame: .zero, configuration: Self.webViewConfiguration())
        webView.load(URLRequest(url: Self.renewalURL))
        defer { webView.stopLoading() }
        let deadline = Date().addingTimeInterval(timeout)
        var renewed: SteamLoginToken?
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
            // The cookie can briefly disappear while Steam redirects, so keep waiting on nil.
            if let token = await readToken(),
               token.steamID64 != current.steamID64 || (token.expiresAt ?? .distantPast) > (current.expiresAt ?? .distantPast) {
                renewed = token
                break
            }
        }
        onActivity?(NetworkEvent(
            kind: .session,
            startedAt: started,
            url: Self.renewalURL.absoluteString,
            signedIn: true,
            duration: Date().timeIntervalSince(started),
            outcome: renewed == nil ? .failed("Steam didn't renew the session") : .ok,
            note: "loaded off screen to renew the sign-in"
        ))
        if let renewed { return renewed }
        return await readToken()
    }

    private func steamCookies() async -> [HTTPCookie] {
        let all = await withCheckedContinuation { (continuation: CheckedContinuation<[HTTPCookie], Never>) in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        return all.filter { $0.domain.hasSuffix("steamcommunity.com") }
    }

    nonisolated static func randomSessionID() -> String {
        (0..<12).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}
