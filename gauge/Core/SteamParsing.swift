//
//  SteamParsing.swift
//  gauge
//
//  Turns steamcommunity.com responses into app values. Steam is loose with
//  types (ids arrive as strings or numbers, flags as 0/1), so the decoding
//  here accepts either.
//

import Foundation

// MARK: - Inventory pages

/// One page of `https://steamcommunity.com/inventory/<steamid>/<appid>/<contextid>`.
nonisolated struct InventoryPage: Sendable {
    var items: [InventoryItem]
    var moreItems: Bool
    var lastAssetID: String?
    var totalCount: Int?
}

nonisolated enum InventoryPageParser {
    enum ParseError: Error, Equatable {
        case unsuccessful(String?)
    }

    static func parse(_ data: Data) throws -> InventoryPage {
        let response = try JSONDecoder().decode(InventoryResponseDTO.self, from: data)
        guard response.success else { throw ParseError.unsuccessful(response.error) }

        var descriptions: [String: DescriptionDTO] = [:]
        for description in response.descriptions {
            descriptions[description.lookupKey] = description
        }

        var items: [InventoryItem] = []
        items.reserveCapacity(response.assets.count)
        for asset in response.assets {
            guard let description = descriptions[asset.lookupKey] else { continue }
            items.append(makeItem(asset: asset, description: description))
        }
        return InventoryPage(
            items: items,
            moreItems: response.moreItems,
            lastAssetID: response.lastAssetID,
            totalCount: response.totalInventoryCount
        )
    }

    static func makeItem(asset: AssetDTO, description: DescriptionDTO) -> InventoryItem {
        let tags = description.tags.map {
            ItemTag(category: $0.category, categoryName: $0.categoryName, internalName: $0.internalName, name: $0.name, color: $0.color)
        }
        let lines = description.descriptions.flatMap { line in
            HTMLText.lines(from: line.value).map { DescriptionLine(text: $0, color: line.color) }
        }
        let name = description.name
        let baseName = stripQualityPrefix(name, tags: tags)
        return InventoryItem(
            appID: asset.appID,
            contextID: asset.contextID,
            assetID: asset.assetID,
            classID: asset.classID,
            instanceID: asset.instanceID,
            amount: max(asset.amount, 1),
            name: name,
            baseName: baseName,
            marketHashName: description.marketHashName ?? name,
            type: description.type ?? "",
            iconHash: description.iconURLLarge ?? description.iconURL,
            nameColor: description.nameColor,
            marketable: description.marketable,
            tradable: description.tradable,
            commodity: description.commodity,
            tags: tags,
            details: lines.map(\.text).filter { !$0.isEmpty },
            itemSet: ItemSetDetector.detect(itemName: baseName, lines: lines)
        )
    }

    /// "Inscribed Crest of the Wyrm" → "Crest of the Wyrm", so set pieces match regardless of quality.
    static func stripQualityPrefix(_ name: String, tags: [ItemTag]) -> String {
        guard let quality = tags.first(where: { $0.category == "Quality" })?.name,
              !["Standard", "Unique", "Normal"].contains(quality),
              name.hasPrefix(quality + " ")
        else { return name }
        return String(name.dropFirst(quality.count + 1))
    }
}

nonisolated struct DescriptionLine: Equatable, Sendable {
    var text: String
    var color: String?
}

// MARK: - Sets

/// Finds the cosmetic set listed in an item's description. Dota 2 and TF2
/// print the set name followed by every piece, one per line, with the pieces
/// sharing a color that differs from the set name:
///
///     Used By: Enchantress
///
///     Song of the Solstice            (set name)
///     Song of the Solstice Arms       (pieces…)
///     Song of the Solstice Belt
///
nonisolated enum ItemSetDetector {
    static func detect(itemName: String, lines: [DescriptionLine]) -> ItemSetInfo? {
        let target = itemName.lowercased()
        guard let hit = lines.firstIndex(where: { $0.text.lowercased() == target }) else { return nil }

        func isCandidate(_ index: Int) -> Bool {
            let line = lines[index]
            return !line.text.isEmpty && !line.text.contains(":") && line.color == lines[hit].color
        }

        var start = hit
        while start > 0 && isCandidate(start - 1) { start -= 1 }
        var end = hit
        while end + 1 < lines.count && isCandidate(end + 1) { end += 1 }

        var header: String?
        var members = Array(lines[start...end].map(\.text))
        if start > 0 {
            let previous = lines[start - 1]
            if !previous.text.isEmpty && !previous.text.contains(":") && previous.color != lines[hit].color {
                header = previous.text
            }
        }
        if header == nil, members.count >= 3, members[0].lowercased() != target {
            header = members.removeFirst()
        }
        guard let header, members.count >= 2 else { return nil }
        return ItemSetInfo(name: header, members: members)
    }
}

// MARK: - Inventory directory

/// Reads `g_rgAppContextData` out of a profile's public inventory page, which
/// lists every game the profile has items for, with counts, and needs no API key.
nonisolated enum InventoryDirectoryParser {
    static func contexts(fromInventoryPage html: String) -> [InventoryContext]? {
        guard let marker = html.range(of: "g_rgAppContextData"),
              let json = balancedObject(in: html, from: marker.upperBound),
              let data = json.data(using: .utf8),
              let apps = try? JSONDecoder().decode([String: AppContextDTO].self, from: data)
        else { return nil }

        var result: [InventoryContext] = []
        for app in apps.values {
            for context in app.contexts where context.assetCount > 0 {
                result.append(InventoryContext(
                    appID: app.appID,
                    contextID: context.id,
                    name: app.name,
                    iconURL: app.icon,
                    assetCount: context.assetCount
                ))
            }
        }
        return result.sorted { $0.assetCount > $1.assetCount }
    }

    /// Returns the `{...}` literal that starts at or after `index`, respecting JSON strings.
    static func balancedObject(in text: String, from index: String.Index) -> String? {
        guard let open = text[index...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var cursor = open
        while cursor < text.endIndex {
            let ch = text[cursor]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else if ch == "\"" {
                inString = true
            } else if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 { return String(text[open...cursor]) }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }
}

// MARK: - Prices

/// A cached Community Market quote for one market hash name.
nonisolated struct PriceQuote: Codable, Hashable, Sendable {
    /// Cheapest current listing, what a buyer pays right now.
    var lowestCents: Int?
    /// Median sale price over the last day.
    var medianCents: Int?
    var volume: Int?
    var checkedAt: Date
    var currency: SteamCurrency

    /// The price Gauge values an item at: the lowest listing, else the recent median.
    var valueCents: Int? { lowestCents ?? medianCents }
}

nonisolated enum PriceOverviewParser {
    enum ParseError: Error, Equatable {
        case unsuccessful
    }

    /// Parses `https://steamcommunity.com/market/priceoverview/`.
    /// An item nobody is selling comes back as `{"success":true}` with no prices.
    static func parse(_ data: Data, currency: SteamCurrency, checkedAt: Date) throws -> PriceQuote {
        let dto = try JSONDecoder().decode(PriceOverviewDTO.self, from: data)
        guard dto.success else { throw ParseError.unsuccessful }
        return PriceQuote(
            lowestCents: dto.lowestPrice.flatMap(PriceParser.cents(from:)),
            medianCents: dto.medianPrice.flatMap(PriceParser.cents(from:)),
            volume: dto.volume.flatMap(PriceParser.integer(from:)),
            checkedAt: checkedAt,
            currency: currency
        )
    }
}

// MARK: - Selling

nonisolated struct SellResult: Equatable, Sendable {
    var success: Bool
    var needsConfirmation: Bool
    var message: String?
}

nonisolated enum SellResponseParser {
    /// Parses `https://steamcommunity.com/market/sellitem/`. Steam answers errors with
    /// HTTP 502 and a JSON message, so the body is read regardless of status.
    static func parse(_ data: Data) -> SellResult {
        guard let dto = try? JSONDecoder().decode(SellItemDTO.self, from: data) else {
            // An HTML page instead of JSON usually means the session expired.
            return SellResult(success: false, needsConfirmation: false, message: "Steam sent back a web page instead of a result. Your sign-in may have expired; sign in again.")
        }
        return SellResult(
            success: dto.success,
            needsConfirmation: dto.requiresConfirmation || dto.needsMobileConfirmation || dto.needsEmailConfirmation,
            message: dto.message
        )
    }
}

// MARK: - Wire formats

nonisolated struct InventoryResponseDTO: Decodable {
    var assets: [AssetDTO]
    var descriptions: [DescriptionDTO]
    var moreItems: Bool
    var lastAssetID: String?
    var totalInventoryCount: Int?
    var success: Bool
    var error: String?

    enum CodingKeys: String, CodingKey {
        case assets, descriptions, success, error, Error
        case moreItems = "more_items"
        case lastAssetID = "last_assetid"
        case totalInventoryCount = "total_inventory_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assets = try c.decodeIfPresent([AssetDTO].self, forKey: .assets) ?? []
        descriptions = try c.decodeIfPresent([DescriptionDTO].self, forKey: .descriptions) ?? []
        moreItems = (c.flexibleInt(.moreItems) ?? 0) != 0
        lastAssetID = c.flexibleString(.lastAssetID)
        totalInventoryCount = c.flexibleInt(.totalInventoryCount)
        success = (c.flexibleInt(.success) ?? 0) != 0
        error = c.flexibleString(.error) ?? c.flexibleString(.Error)
    }
}

nonisolated struct AssetDTO: Decodable {
    var appID: Int
    var contextID: String
    var assetID: String
    var classID: String
    var instanceID: String
    var amount: Int

    var lookupKey: String { "\(classID)_\(instanceID)" }

    enum CodingKeys: String, CodingKey {
        case appid, contextid, assetid, classid, instanceid, amount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appID = c.flexibleInt(.appid) ?? 0
        contextID = c.flexibleString(.contextid) ?? "2"
        guard let asset = c.flexibleString(.assetid), let classID = c.flexibleString(.classid) else {
            throw DecodingError.dataCorruptedError(forKey: .assetid, in: c, debugDescription: "asset without ids")
        }
        assetID = asset
        self.classID = classID
        instanceID = c.flexibleString(.instanceid) ?? "0"
        amount = c.flexibleInt(.amount) ?? 1
    }
}

nonisolated struct DescriptionDTO: Decodable {
    var classID: String
    var instanceID: String
    var name: String
    var marketHashName: String?
    var type: String?
    var iconURL: String?
    var iconURLLarge: String?
    var nameColor: String?
    var tradable: Bool
    var marketable: Bool
    var commodity: Bool
    var descriptions: [DescriptionLineDTO]
    var tags: [TagDTO]

    var lookupKey: String { "\(classID)_\(instanceID)" }

    enum CodingKeys: String, CodingKey {
        case classid, instanceid, name, type, tradable, marketable, commodity, descriptions, tags
        case marketHashName = "market_hash_name"
        case iconURL = "icon_url"
        case iconURLLarge = "icon_url_large"
        case nameColor = "name_color"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        classID = c.flexibleString(.classid) ?? ""
        instanceID = c.flexibleString(.instanceid) ?? "0"
        name = c.flexibleString(.name) ?? "Unknown item"
        marketHashName = c.flexibleString(.marketHashName)
        type = c.flexibleString(.type)
        iconURL = c.flexibleString(.iconURL)
        let large = c.flexibleString(.iconURLLarge)
        iconURLLarge = (large?.isEmpty ?? true) ? nil : large
        nameColor = c.flexibleString(.nameColor)
        tradable = (c.flexibleInt(.tradable) ?? 0) != 0
        marketable = (c.flexibleInt(.marketable) ?? 0) != 0
        commodity = (c.flexibleInt(.commodity) ?? 0) != 0
        descriptions = (try? c.decodeIfPresent([DescriptionLineDTO].self, forKey: .descriptions)) ?? []
        tags = (try? c.decodeIfPresent([TagDTO].self, forKey: .tags)) ?? []
    }
}

nonisolated struct DescriptionLineDTO: Decodable {
    var value: String
    var color: String?

    enum CodingKeys: String, CodingKey { case value, color }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = c.flexibleString(.value) ?? ""
        let color = c.flexibleString(.color)
        self.color = (color?.isEmpty ?? true) ? nil : color
    }
}

nonisolated struct TagDTO: Decodable {
    var category: String
    var categoryName: String
    var internalName: String
    var name: String
    var color: String?

    enum CodingKeys: String, CodingKey {
        case category, color, name
        case internalName = "internal_name"
        case localizedCategoryName = "localized_category_name"
        case localizedTagName = "localized_tag_name"
        case categoryName = "category_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        category = c.flexibleString(.category) ?? ""
        categoryName = c.flexibleString(.localizedCategoryName) ?? c.flexibleString(.categoryName) ?? category
        internalName = c.flexibleString(.internalName) ?? ""
        name = c.flexibleString(.localizedTagName) ?? c.flexibleString(.name) ?? internalName
        let color = c.flexibleString(.color)
        self.color = (color?.isEmpty ?? true) ? nil : color
    }
}

nonisolated struct AppContextDTO: Decodable {
    var appID: Int
    var name: String
    var icon: String?
    var contexts: [ContextDTO]

    enum CodingKeys: String, CodingKey {
        case appid, name, icon, rgContexts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appID = c.flexibleInt(.appid) ?? 0
        name = c.flexibleString(.name) ?? "App \(appID)"
        icon = c.flexibleString(.icon)
        // An app with no visible contexts sends `[]` instead of an object.
        let keyed = (try? c.decodeIfPresent([String: ContextDTO].self, forKey: .rgContexts)) ?? nil
        contexts = keyed.map { Array($0.values) } ?? []
    }
}

nonisolated struct ContextDTO: Decodable {
    var id: String
    var assetCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case assetCount = "asset_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexibleString(.id) ?? "2"
        assetCount = c.flexibleInt(.assetCount) ?? 0
    }
}

nonisolated struct PriceOverviewDTO: Decodable {
    var success: Bool
    var lowestPrice: String?
    var medianPrice: String?
    var volume: String?

    enum CodingKeys: String, CodingKey {
        case success, volume
        case lowestPrice = "lowest_price"
        case medianPrice = "median_price"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = c.flexibleBool(.success) ?? false
        lowestPrice = c.flexibleString(.lowestPrice)
        medianPrice = c.flexibleString(.medianPrice)
        volume = c.flexibleString(.volume)
    }
}

nonisolated struct SellItemDTO: Decodable {
    var success: Bool
    var requiresConfirmation: Bool
    var needsMobileConfirmation: Bool
    var needsEmailConfirmation: Bool
    var message: String?

    enum CodingKeys: String, CodingKey {
        case success, message
        case requiresConfirmation = "requires_confirmation"
        case needsMobileConfirmation = "needs_mobile_confirmation"
        case needsEmailConfirmation = "needs_email_confirmation"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = c.flexibleBool(.success) ?? false
        requiresConfirmation = c.flexibleBool(.requiresConfirmation) ?? false
        needsMobileConfirmation = c.flexibleBool(.needsMobileConfirmation) ?? false
        needsEmailConfirmation = c.flexibleBool(.needsEmailConfirmation) ?? false
        message = c.flexibleString(.message)
    }
}

nonisolated extension KeyedDecodingContainer {
    func flexibleString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }

    func flexibleInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value ? 1 : 0 }
        return nil
    }

    func flexibleBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        return flexibleInt(key).map { $0 != 0 }
    }
}
