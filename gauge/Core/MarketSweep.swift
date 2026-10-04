//
//  MarketSweep.swift
//  gauge
//
//  Bulk pricing. `priceoverview` prices one market hash name per request,
//  so a first sync of a big inventory spends most of an hour on items worth
//  a few cents. The Market's search (`/market/search/render/?norender=1`)
//  returns 100 items' lowest listings in one request. Sorted cheapest first,
//  its early pages are exactly where most of an inventory's fluff lives.
//
//  A sweep pages through one game's listings that way and keeps the names
//  the inventory needs. It stops as soon as it stops paying off: when every
//  name is found, the catalog runs out, or recent pages find fewer names
//  than single checks would in the same number of requests. Whatever it
//  didn't find is priced one name at a time, as before.
//

import Foundation

/// One item from a Market search page.
nonisolated struct MarketSearchResult: Equatable, Sendable {
    var hashName: String
    var appID: Int?
    var sellListings: Int
    /// The lowest listing, what a buyer pays. Nil when nobody is selling it.
    var lowestCents: Int?
    var priceText: String?
}

nonisolated struct MarketSearchPage: Equatable, Sendable {
    var start: Int
    var totalCount: Int
    var results: [MarketSearchResult]
    /// Whether every price on the page is in the currency that was asked for.
    /// Steam may answer in another currency; those prices must not be stored.
    var currencyMatches: Bool
}

nonisolated enum MarketSearchParser {
    enum ParseError: Error, Equatable {
        case unsuccessful
    }

    /// Parses `https://steamcommunity.com/market/search/render/?norender=1`.
    static func parse(_ data: Data, currency: SteamCurrency) throws -> MarketSearchPage {
        let dto = try JSONDecoder().decode(MarketSearchDTO.self, from: data)
        guard dto.success else { throw ParseError.unsuccessful }
        var matches = true
        let results = dto.results.compactMap { result -> MarketSearchResult? in
            guard let hashName = result.hashName, !hashName.isEmpty else { return nil }
            let listings = result.sellListings ?? 0
            var cents: Int?
            if listings > 0, let text = result.sellPriceText {
                if currency.matchesPriceText(text) {
                    cents = PriceParser.cents(from: text)
                } else {
                    matches = false
                }
            }
            return MarketSearchResult(
                hashName: hashName,
                appID: result.assetDescription?.appID,
                sellListings: listings,
                lowestCents: cents.flatMap { $0 > 0 ? $0 : nil },
                priceText: result.sellPriceText
            )
        }
        return MarketSearchPage(start: dto.start ?? 0, totalCount: dto.totalCount ?? 0, results: results, currencyMatches: matches)
    }
}

nonisolated extension SteamCurrency {
    /// Whether a Steam price string is written in this currency: "$0.03" is US dollars,
    /// "CDN$ 0.04" isn't. Yen is shared by JPY and CNY, so it never counts as a match.
    func matchesPriceText(_ text: String) -> Bool {
        let marker = String(text.filter { ch in
            !(ch.isASCII && ch.isNumber) && !ch.isWhitespace && !".,'-".contains(ch)
        })
        switch self {
        case .jpy, .cny: return false
        case .rub: return marker == symbol || marker.contains("уб")
        default: return marker == symbol
        }
    }
}

/// Pages through one game's Market listings, cheapest first, collecting prices for `wanted` names.
nonisolated struct MarketSweep: Equatable, Sendable {
    /// The most results Steam's search returns per request.
    static let pageSize = 100
    /// A game needs at least this many names waiting for a price before a sweep is worth trying.
    static let minimumNames = 40
    /// Wanted names found per page, averaged over the last `yieldWindow` pages, below which
    /// single checks are a better use of requests. One page costs what one single check does.
    static let minimumYield = 2.0
    static let yieldWindow = 3
    /// Never spend more than this many requests on one sweep.
    static let maximumPages = 300

    let appID: Int
    private(set) var wanted: Set<String>
    private(set) var nextStart = 0
    private(set) var pagesFetched = 0
    private(set) var recentHits: [Int] = []
    private(set) var isFinished = false

    init(appID: Int, wanted: Set<String>) {
        self.appID = appID
        self.wanted = wanted
        isFinished = wanted.isEmpty
    }

    /// Takes in one page and returns the wanted names it priced. Updates when to stop.
    mutating func absorb(_ page: MarketSearchPage) -> [MarketSearchResult] {
        pagesFetched += 1
        nextStart = page.start + max(page.results.count, 1)
        var hits: [MarketSearchResult] = []
        for result in page.results where result.lowestCents != nil && wanted.contains(result.hashName) {
            if let appID = result.appID, appID != self.appID { continue }
            wanted.remove(result.hashName)
            hits.append(result)
        }
        recentHits.append(hits.count)
        if recentHits.count > Self.yieldWindow { recentHits.removeFirst() }

        if wanted.isEmpty || page.results.isEmpty || nextStart >= page.totalCount || pagesFetched >= Self.maximumPages {
            isFinished = true
        } else if pagesFetched >= 2 {
            // The first page alone can be unlucky (thousands of items share the lowest price),
            // so judge from the second page on.
            let yield = Double(recentHits.reduce(0, +)) / Double(recentHits.count)
            if yield < Self.minimumYield { isFinished = true }
        }
        return hits
    }
}

// MARK: - Wire format

nonisolated struct MarketSearchDTO: Decodable {
    var success: Bool
    var start: Int?
    var totalCount: Int?
    var results: [Result]

    struct Result: Decodable {
        var hashName: String?
        var sellListings: Int?
        var sellPriceText: String?
        var assetDescription: AssetDescription?

        enum CodingKeys: String, CodingKey {
            case hashName = "hash_name"
            case sellListings = "sell_listings"
            case sellPriceText = "sell_price_text"
            case assetDescription = "asset_description"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            hashName = c.flexibleString(.hashName)
            sellListings = c.flexibleInt(.sellListings)
            sellPriceText = c.flexibleString(.sellPriceText)
            assetDescription = try? c.decodeIfPresent(AssetDescription.self, forKey: .assetDescription)
        }
    }

    struct AssetDescription: Decodable {
        var appID: Int?

        enum CodingKeys: String, CodingKey {
            case appID = "appid"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            appID = c.flexibleInt(.appID)
        }
    }

    enum CodingKeys: String, CodingKey {
        case success, start, results
        case totalCount = "total_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = c.flexibleBool(.success) ?? false
        start = c.flexibleInt(.start)
        totalCount = c.flexibleInt(.totalCount)
        results = (try? c.decodeIfPresent([Result].self, forKey: .results)) ?? []
    }
}
