//
//  Models.swift
//  gauge
//
//  The on-disk cache. Everything here lives in the app's sandbox on this Mac.
//  Inventories are stored whole (Steam always returns them whole), while
//  prices are rows because the pricing queue updates them one at a time.
//

import Foundation
import SwiftData

/// One inventory (app + context) as last downloaded.
@Model
final class CachedInventory {
    @Attribute(.unique) var key: String
    var appID: Int
    var contextID: String
    var name: String
    var iconURL: String?
    var assetCount: Int
    var syncedAt: Date?
    var newSinceLastSync: Int
    var lastError: String?
    /// JSON-encoded `[InventoryItem]`.
    @Attribute(.externalStorage) var payload: Data

    init(context: InventoryContext) {
        key = context.id
        appID = context.appID
        contextID = context.contextID
        name = context.name
        iconURL = context.iconURL
        assetCount = context.assetCount
        syncedAt = nil
        newSinceLastSync = 0
        lastError = nil
        payload = Data()
    }

    var inventoryContext: InventoryContext {
        InventoryContext(appID: appID, contextID: contextID, name: name, iconURL: iconURL, assetCount: assetCount)
    }
}

/// The latest Market quote for one market hash name, plus a short daily history.
@Model
final class PriceRecord {
    @Attribute(.unique) var key: String
    var currencyCode: Int
    var lowestCents: Int?
    var medianCents: Int?
    var volume: Int?
    var checkedAt: Date
    /// JSON-encoded `[PricePoint]`, one per day, capped by `PriceTrend.appending`.
    var historyData: Data

    init(key: String, quote: PriceQuote, history: [PricePoint]) {
        self.key = key
        currencyCode = quote.currency.rawValue
        lowestCents = quote.lowestCents
        medianCents = quote.medianCents
        volume = quote.volume
        checkedAt = quote.checkedAt
        historyData = (try? JSONEncoder().encode(history)) ?? Data()
    }

    func update(quote: PriceQuote, history: [PricePoint]) {
        currencyCode = quote.currency.rawValue
        lowestCents = quote.lowestCents
        medianCents = quote.medianCents
        volume = quote.volume
        checkedAt = quote.checkedAt
        historyData = (try? JSONEncoder().encode(history)) ?? Data()
    }

    var quote: PriceQuote {
        PriceQuote(
            lowestCents: lowestCents,
            medianCents: medianCents,
            volume: volume,
            checkedAt: checkedAt,
            currency: SteamCurrency(rawValue: currencyCode) ?? .usd
        )
    }

    var history: [PricePoint] {
        (try? JSONDecoder().decode([PricePoint].self, from: historyData)) ?? []
    }
}

/// Marketable net worth on one day. The Portfolio chart is drawn from these.
@Model
final class NetWorthSnapshot {
    @Attribute(.unique) var day: Date
    var buyerCents: Int
    var sellerCents: Int
    var currencyCode: Int
    var itemCount: Int

    init(day: Date, buyerCents: Int, sellerCents: Int, currencyCode: Int, itemCount: Int) {
        self.day = day
        self.buyerCents = buyerCents
        self.sellerCents = sellerCents
        self.currencyCode = currencyCode
        self.itemCount = itemCount
    }
}

@Model
final class StarredItem {
    /// `InventoryItem.id`: app, context, and asset id.
    @Attribute(.unique) var key: String
    var starredAt: Date

    init(key: String, starredAt: Date = Date()) {
        self.key = key
        self.starredAt = starredAt
    }
}

/// A record of every listing Gauge submitted, kept for the user's own reference.
@Model
final class ListingRecord {
    var itemKey: String
    var name: String
    var appID: Int
    var buyerCents: Int
    var sellerCents: Int
    var currencyCode: Int
    var listedAt: Date
    var outcome: String

    init(itemKey: String, name: String, appID: Int, buyerCents: Int, sellerCents: Int, currencyCode: Int, listedAt: Date, outcome: String) {
        self.itemKey = itemKey
        self.name = name
        self.appID = appID
        self.buyerCents = buyerCents
        self.sellerCents = sellerCents
        self.currencyCode = currencyCode
        self.listedAt = listedAt
        self.outcome = outcome
    }
}

enum GaugeSchema {
    static let models: [any PersistentModel.Type] = [
        CachedInventory.self,
        PriceRecord.self,
        NetWorthSnapshot.self,
        StarredItem.self,
        ListingRecord.self,
    ]

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // The cache can always be rebuilt from Steam, so start over rather than crash.
            let path = configuration.url.path
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Could not create the local cache: \(error)")
            }
        }
    }
}
