//
//  SteamClient.swift
//  gauge
//
//  Every request Gauge makes to steamcommunity.com goes through this actor.
//  Steam rate limits anonymous traffic hard (roughly 20 market price checks
//  a minute per IP, fewer for inventories), so each endpoint family has its
//  own gate that spaces requests out and backs off after a 429. Callers never
//  wait on the network from the UI; they read cached data and this actor
//  fills the cache in the background.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

nonisolated struct SteamWebAuth: Sendable {
    var steamID64: String
    var sessionID: String
    var steamLoginSecure: String

    var cookieHeader: String { "sessionid=\(sessionID); steamLoginSecure=\(steamLoginSecure)" }
}

nonisolated struct SellRequest: Sendable {
    var appID: Int
    var contextID: String
    var assetID: String
    var amount: Int
    /// What the seller receives per unit, which is what Steam's sell form submits.
    var sellerCents: Int
}

actor SteamClient {
    nonisolated enum Failure: Error, LocalizedError, Equatable {
        case rateLimited(retryAfter: TimeInterval)
        case privateInventory
        case profileNotFound(String)
        case http(Int)
        case unreadable
        case steam(String)

        var errorDescription: String? {
            switch self {
            case .rateLimited(let wait):
                "Steam asked Gauge to slow down. Trying again in \(Int(wait / 60) + 1) min."
            case .privateInventory:
                "This inventory is private. Sign in with Steam as its owner, or set Inventory to Public in Steam's privacy settings."
            case .profileNotFound(let message):
                message
            case .http(let code):
                "Steam returned an error (HTTP \(code)). Try again in a few minutes."
            case .unreadable:
                "Steam sent a response Gauge couldn't read."
            case .steam(let message):
                message
            }
        }
    }

    nonisolated enum Endpoint: Hashable, Sendable {
        case profile
        case inventory
        case market
        case sell

        /// Minimum spacing between requests of this kind.
        var interval: TimeInterval {
            switch self {
            case .profile: 1.5
            case .inventory: 4
            case .market: 3.2
            case .sell: 2.5
            }
        }
    }

    private nonisolated struct Gate {
        var nextAllowed = Date.distantPast
        var backoff: TimeInterval = 0
    }

    private let session: URLSession
    private let intervalScale: Double
    private var gates: [Endpoint: Gate] = [:]

    /// - Parameter intervalScale: multiplies request spacing; tests pass 0.
    init(configuration: URLSessionConfiguration = SteamClient.defaultConfiguration(), intervalScale: Double = 1) {
        session = URLSession(configuration: configuration)
        self.intervalScale = intervalScale
    }

    nonisolated static func defaultConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["Accept-Language": "en-US,en;q=0.9"]
        return configuration
    }

    // MARK: - Public API

    /// Resolves a SteamID64 or custom URL to a profile without an API key.
    func profile(_ reference: ProfileReference) async throws -> ProfileSummary {
        let data = try await send(URLRequest(url: reference.profileXMLURL), endpoint: .profile)
        do {
            return try ProfileSummary.parse(xml: String(decoding: data, as: UTF8.self))
        } catch ProfileSummary.ParseError.steam(let message) {
            throw Failure.profileNotFound(message)
        } catch {
            throw Failure.unreadable
        }
    }

    /// Lists the games the profile has items for, read from its inventory page.
    /// With the owner's `auth`, this works for a private inventory too, as it does in a browser.
    func inventoryDirectory(steamID64: String, auth: SteamWebAuth? = nil) async throws -> [InventoryContext] {
        var request = URLRequest(url: URL(string: "https://steamcommunity.com/profiles/\(steamID64)/inventory/")!)
        Self.signIn(&request, auth)
        let data = try await send(request, endpoint: .profile)
        guard let contexts = InventoryDirectoryParser.contexts(fromInventoryPage: String(decoding: data, as: UTF8.self)) else {
            throw Failure.unreadable
        }
        return contexts
    }

    /// Downloads a whole inventory, page by page. `progress` receives (loaded, total).
    /// With the owner's `auth`, this works for a private inventory too.
    func inventory(
        steamID64: String,
        context: InventoryContext,
        auth: SteamWebAuth? = nil,
        progress: @Sendable (Int, Int?) -> Void = { _, _ in }
    ) async throws -> [InventoryItem] {
        var items: [InventoryItem] = []
        var startAsset: String?
        var pageSize = 2_000
        while true {
            var components = URLComponents(string: "https://steamcommunity.com/inventory/\(steamID64)/\(context.appID)/\(context.contextID)")!
            var query = [URLQueryItem(name: "l", value: "english"), URLQueryItem(name: "count", value: String(pageSize))]
            if let startAsset { query.append(URLQueryItem(name: "start_assetid", value: startAsset)) }
            components.queryItems = query
            var request = URLRequest(url: components.url!)
            request.setValue("https://steamcommunity.com/profiles/\(steamID64)/inventory/", forHTTPHeaderField: "Referer")
            Self.signIn(&request, auth)

            let data: Data
            do {
                data = try await send(request, endpoint: .inventory)
            } catch Failure.http(400) where pageSize > 500 && items.isEmpty {
                // Steam has lowered the maximum page size before; retry smaller.
                pageSize = 500
                continue
            }
            let page: InventoryPage
            do {
                page = try InventoryPageParser.parse(data)
            } catch InventoryPageParser.ParseError.unsuccessful(let message) {
                throw Failure.steam(message ?? "Steam couldn't load this inventory.")
            }
            items.append(contentsOf: page.items)
            progress(items.count, page.totalCount)
            guard page.moreItems, let last = page.lastAssetID else { return items }
            startAsset = last
        }
    }

    /// The lowest listing and median sale for one item. No login needed.
    func priceOverview(appID: Int, marketHashName: String, currency: SteamCurrency) async throws -> PriceQuote {
        let name = PriceKey.percentEncode(marketHashName)
        let url = URL(string: "https://steamcommunity.com/market/priceoverview/?appid=\(appID)&currency=\(currency.rawValue)&market_hash_name=\(name)")!
        let data = try await send(URLRequest(url: url), endpoint: .market)
        do {
            return try PriceOverviewParser.parse(data, currency: currency, checkedAt: Date())
        } catch {
            throw Failure.unreadable
        }
    }

    /// Lists one item on the Community Market. Steam then asks for confirmation in the mobile app.
    func sell(_ sell: SellRequest, auth: SteamWebAuth) async throws -> SellResult {
        var request = URLRequest(url: URL(string: "https://steamcommunity.com/market/sellitem/")!)
        request.httpMethod = "POST"
        Self.signIn(&request, auth)
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://steamcommunity.com", forHTTPHeaderField: "Origin")
        request.setValue("https://steamcommunity.com/profiles/\(auth.steamID64)/inventory/", forHTTPHeaderField: "Referer")
        let form = [
            ("sessionid", auth.sessionID),
            ("appid", String(sell.appID)),
            ("contextid", sell.contextID),
            ("assetid", sell.assetID),
            ("amount", String(sell.amount)),
            ("price", String(sell.sellerCents)),
        ]
        request.httpBody = Data(form.map { "\($0.0)=\(PriceKey.percentEncode($0.1))" }.joined(separator: "&").utf8)
        // Steam reports listing errors as HTTP 502 with a JSON message, so read the body either way.
        let data = try await send(request, endpoint: .sell, acceptErrorBodies: true)
        return SellResponseParser.parse(data)
    }

    /// When the next request of a kind may go out. Used to show "resumes at" in the UI.
    func nextAllowed(_ endpoint: Endpoint) -> Date {
        gates[endpoint]?.nextAllowed ?? .distantPast
    }

    // MARK: - Transport

    /// Sends the web session's cookies with one request. The session itself never stores cookies.
    private static func signIn(_ request: inout URLRequest, _ auth: SteamWebAuth?) {
        guard let auth else { return }
        request.httpShouldHandleCookies = false
        request.setValue(auth.cookieHeader, forHTTPHeaderField: "Cookie")
    }

    private func send(_ request: URLRequest, endpoint: Endpoint, acceptErrorBodies: Bool = false) async throws -> Data {
        let wait = reserveSlot(endpoint)
        if wait > 0 {
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            gates[endpoint, default: Gate()].backoff = 0
            return data
        case 429:
            throw Failure.rateLimited(retryAfter: backOff(endpoint))
        case 403 where endpoint == .inventory:
            throw Failure.privateInventory
        default:
            if acceptErrorBodies && !data.isEmpty { return data }
            if status >= 500 && endpoint == .market {
                // Steam's market answers overload with 5xx as often as 429.
                throw Failure.rateLimited(retryAfter: backOff(endpoint))
            }
            throw Failure.http(status)
        }
    }

    /// Books the next free slot for `endpoint` and returns how long to wait for it.
    /// Booking happens before the caller suspends, so concurrent callers queue up
    /// behind each other instead of all firing when the gate opens.
    private func reserveSlot(_ endpoint: Endpoint) -> TimeInterval {
        let now = Date()
        var gate = gates[endpoint, default: Gate()]
        let start = max(now, gate.nextAllowed)
        gate.nextAllowed = start.addingTimeInterval(endpoint.interval * intervalScale)
        gates[endpoint] = gate
        return start.timeIntervalSince(now)
    }

    private func backOff(_ endpoint: Endpoint) -> TimeInterval {
        var gate = gates[endpoint, default: Gate()]
        gate.backoff = min(max(gate.backoff * 2, 60), 600)
        gate.nextAllowed = Date().addingTimeInterval(gate.backoff * intervalScale)
        gates[endpoint] = gate
        return gate.backoff
    }
}
