//
//  DemoData.swift
//  gauge
//
//  A deterministic, offline stand-in for a large Steam inventory. It powers
//  Demo mode (no network, no Steam account) for development, SwiftUI
//  previews, and App Store screenshots. Names are invented in the style of
//  real items, except the few drawn in the original storyboards.
//

import Foundation

nonisolated struct DemoDataset: Sendable {
    var profile: ProfileSummary
    var contexts: [InventoryContext]
    var itemsByContext: [String: [InventoryItem]]
    var prices: [String: PriceQuote]
    var history: [String: [PricePoint]]
    var snapshots: [DemoSnapshot]
    var starred: [String]
}

nonisolated struct DemoSnapshot: Sendable {
    var day: Date
    var buyerCents: Int
    var sellerCents: Int
}

nonisolated enum DemoData {
    static let steamID = "76561190000000000"
    /// Shown in the header in demo mode, which App Review and screenshots use.
    static let personaName = "Demo profile"

    static func make(now: Date = Date(), seed: UInt64 = 0x6A_0E6E) -> DemoDataset {
        var rng = SplitMix64(seed: seed)
        var builder = Builder(now: now)

        builder.dota(rng: &rng)
        builder.steamCommunity(rng: &rng)
        builder.simpleApp(appID: 440, name: "Team Fortress 2", count: 191, marketableShare: 0.55, pool: tf2Names, rng: &rng)
        builder.simpleApp(appID: 730, name: "Counter-Strike 2", count: 44, marketableShare: 0.8, pool: cs2Names, rng: &rng)
        builder.simpleApp(appID: 232090, name: "Killing Floor 2", count: 41, marketableShare: 0.7, pool: kf2Names, rng: &rng)
        for (index, other) in otherApps.enumerated() {
            builder.simpleApp(appID: other.appID, name: other.name, count: [4, 3, 2, 2, 2, 1][index], marketableShare: 0.7, pool: other.pool, rng: &rng)
        }
        // Skins draw from their own generator, so every other game's items stay as they were.
        var skinRNG = SplitMix64(seed: seed ^ 0xC5_2A_11)
        builder.cs2Skins(rng: &skinRNG)

        let starred = builder.itemsByContext["570_2"]?
            .filter { $0.name == "Songs of the Caravan Music Pack" || $0.name == "Song of the Solstice Arms" }
            .map(\.id) ?? []

        return DemoDataset(
            profile: ProfileSummary(steamID64: steamID, personaName: personaName, avatarURL: nil, isPublic: true),
            contexts: builder.contexts,
            itemsByContext: builder.itemsByContext,
            prices: builder.prices,
            history: builder.history,
            snapshots: builder.snapshots(rng: &rng),
            starred: starred
        )
    }

    /// FNV-1a, because `hashValue` changes on every launch.
    static func stableHash(_ text: String) -> Int {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Int(hash >> 1)
    }

    // MARK: - Catalog

    struct Rarity {
        var name: String
        var color: String
        var cents: ClosedRange<Int>
    }

    static let rarities: [Rarity] = [
        Rarity(name: "Common", color: "b0c3d9", cents: 3...3),
        Rarity(name: "Uncommon", color: "5e98d9", cents: 3...6),
        Rarity(name: "Rare", color: "4b69ff", cents: 3...14),
        Rarity(name: "Mythical", color: "8847ff", cents: 3...60),
        Rarity(name: "Legendary", color: "d32ce6", cents: 8...400),
        Rarity(name: "Immortal", color: "e4ae39", cents: 25...2_600),
        Rarity(name: "Arcana", color: "ade55c", cents: 1_400...4_200),
    ]

    static let dotaSets: [(name: String, hero: String, slots: [String])] = [
        ("Song of the Solstice", "Enchantress", ["Head", "Neck", "Arms", "Belt", "Weapon"]),
        ("Regalia of the Amber Tide", "Tidehunter", ["Head", "Back", "Arms", "Belt", "Weapon"]),
        ("Vestments of the Hollow Crown", "Lich", ["Head", "Shoulder", "Arms", "Belt"]),
        ("Garb of the Wandering Blade", "Juggernaut", ["Head", "Weapon", "Arms", "Legs", "Back"]),
        ("Mantle of the Ember Warden", "Ember Spirit", ["Head", "Shoulder", "Arms", "Weapon", "Belt"]),
        ("Armor of the Frostbound Oath", "Crystal Maiden", ["Head", "Back", "Arms", "Weapon", "Shoulder"]),
        ("Trappings of the Iron Grove", "Treant Protector", ["Head", "Arms", "Legs", "Back"]),
        ("Raiment of the Silent Moon", "Luna", ["Head", "Weapon", "Shoulder", "Belt", "Mount"]),
        ("Harness of the Storm Herald", "Storm Spirit", ["Head", "Arms", "Belt", "Back"]),
        ("Relics of the Sunken Reef", "Slardar", ["Head", "Weapon", "Back", "Arms", "Tail"]),
        ("Guise of the Twilight Hunter", "Drow Ranger", ["Head", "Weapon", "Back", "Arms", "Legs"]),
        ("Accoutrements of the Gilded Fang", "Lycan", ["Head", "Weapon", "Shoulder", "Belt", "Arms"]),
        ("Plumage of the Scarlet Talon", "Phoenix", ["Head", "Neck", "Wings", "Tail"]),
        ("Wraps of the Dune Strider", "Sand King", ["Head", "Arms", "Legs", "Tail", "Back"]),
    ]

    static let dotaSingles: [(name: String, type: String, rarity: Int, slot: String?, hero: String?)] = [
        ("Crest of the Honored Servant of the Empire", "Wearable", 3, "Head", "Legion Commander"),
        ("Songs of the Caravan Music Pack", "Music", 4, nil, nil),
        ("Visage of the Gloom Tyrant", "Wearable", 5, "Head", "Shadow Fiend"),
        ("Blade of the Northern Vigil", "Wearable", 5, "Weapon", "Sven"),
        ("Staff of the Verdant Hymn", "Wearable", 6, "Weapon", "Nature's Prophet"),
        ("Crown of the Dreaming Sands", "Wearable", 4, "Head", "Sand King"),
        ("Lantern of the Marsh Keeper", "Wearable", 3, "Offhand", "Venomancer"),
        ("Pauldrons of the Ashen Legion", "Wearable", 2, "Shoulder", "Legion Commander"),
        ("Cowl of the Quiet Stream", "Wearable", 1, "Head", "Naga Siren"),
        ("Whisper of the Frozen Pines", "Ward", 3, nil, nil),
        ("Little Lantern Courier", "Courier", 4, nil, nil),
        ("Brass Kinetic Courier", "Courier", 3, nil, nil),
        ("Dawnbreaker Loading Screen", "Loading Screen", 2, nil, nil),
        ("Tide of the Sunken Isles Loading Screen", "Loading Screen", 1, nil, nil),
        ("Emblem of the Ancient Rite", "Wearable", 2, "Misc", "Oracle"),
        ("Gauntlets of the Crimson Siege", "Wearable", 1, "Arms", "Axe"),
        ("Belt of the Wandering Tinker", "Wearable", 0, "Belt", "Tinker"),
        ("Hood of the Lost Pilgrim", "Wearable", 0, "Head", "Omniknight"),
        ("Quiver of the Hunting Moon", "Wearable", 1, "Back", "Windranger"),
        ("Sigil of the Burning Pact", "Wearable", 2, "Misc", "Warlock"),
        ("Taunt: Victory Waltz", "Taunt", 3, nil, "Enchantress"),
        ("Taunt: Hammer Toss", "Taunt", 2, nil, "Earthshaker"),
        ("Shoulders of the Glacial Rook", "Wearable", 1, "Shoulder", "Tusk"),
        ("Mask of the Painted Serpent", "Wearable", 2, "Head", "Medusa"),
        ("Daggers of the Hidden Veil", "Wearable", 3, "Weapon", "Phantom Assassin"),
        ("Tome of the Endless Night", "Wearable", 2, "Offhand", "Invoker"),
        ("Bracers of the Salt Wind", "Wearable", 0, "Arms", "Kunkka"),
        ("Hat of the Travelling Merchant", "Wearable", 0, "Head", "Alchemist"),
        ("Cape of the Gloaming Court", "Wearable", 1, "Back", "Night Stalker"),
        ("Horn of the Stone Colossus", "Wearable", 2, "Head", "Tiny"),
    ]

    static let dotaLocked = [
        "Collector's Cache", "Immortal Treasure I", "Immortal Treasure II", "Battle Pass Emoticon",
        "Summer Chest", "Player Card Pack", "Seasonal Terrain", "Frozen Treasure",
        "Diretide Chest", "Crownfall Sticker", "Tipping Token", "Guild Banner",
    ]

    static let tf2Names = [
        ("Mann Co. Supply Crate Key", 230), ("Refined Metal", 5), ("Summer Cooler", 8), ("Mann Co. Supply Munition", 4),
        ("Strange Part: Kills", 55), ("Tour of Duty Ticket", 92), ("Festive Shotgun", 11), ("Killstreak Kit", 25),
        ("Name Tag", 12), ("Paint Can: Team Spirit", 60), ("Unusualifier", 400), ("Decal Tool", 9),
    ]
    static let cs2Names = [
        ("Recoil Case", 45), ("Dreams & Nightmares Case", 110), ("Sticker | Glitter Gun", 6), ("Sealed Graffiti | Heart", 3),
        ("Fracture Case", 38), ("Sticker | Bronze Ace", 21), ("Kilowatt Case", 72), ("Revolution Case", 64),
    ]
    /// A CS2 skin and the copies owned, each with its own float and pattern.
    struct DemoSkin {
        var name: String
        var type: String
        var rarity: Int
        var defIndex: Int
        var paintIndex: Int
        var cents: Int
        var copies: [SkinDetails]
        /// Description lines, such as the names of applied stickers.
        var details: [String] = []
    }

    static let cs2Rarities: [(name: String, color: String)] = [
        ("Consumer Grade", "b0c3d9"), ("Industrial Grade", "5e98d9"), ("Mil-Spec Grade", "4b69ff"),
        ("Restricted", "8847ff"), ("Classified", "d32ce6"), ("Covert", "eb4b4b"),
    ]

    /// Drops worth cents with floats spread across their wear, a few low floats, stickers,
    /// StatTrak, a name tag, a blue gem pattern, and Doppler phases that share a name.
    static let cs2Skins: [DemoSkin] = [
        DemoSkin(name: "P250 | Sand Dune (Factory New)", type: "Pistol", rarity: 0, defIndex: 36, paintIndex: 99, cents: 12, copies: [
            SkinDetails(wear: 0.000_812_455_4, pattern: 311, origin: 24),
            SkinDetails(wear: 0.031_428_571, pattern: 87, origin: 24),
            SkinDetails(wear: 0.052_734_375, pattern: 902, origin: 24),
            SkinDetails(wear: 0.066_210_938, pattern: 455, origin: 0),
        ]),
        DemoSkin(name: "MP9 | Sand Dashed (Field-Tested)", type: "SMG", rarity: 0, defIndex: 34, paintIndex: 148, cents: 4, copies: [
            SkinDetails(wear: 0.210_937_5, pattern: 12, origin: 24),
            SkinDetails(wear: 0.334_562_1, pattern: 640, origin: 24),
            SkinDetails(wear: 0.281_25, pattern: 377, origin: 24),
        ]),
        DemoSkin(name: "SG 553 | Waves Perforated (Minimal Wear)", type: "Rifle", rarity: 0, defIndex: 39, paintIndex: 186, cents: 6, copies: [
            SkinDetails(wear: 0.071_184_2, pattern: 229, origin: 24),
            SkinDetails(wear: 0.124_512_7, pattern: 815, origin: 24),
        ]),
        DemoSkin(name: "UMP-45 | Mudder (Battle-Scarred)", type: "SMG", rarity: 0, defIndex: 24, paintIndex: 90, cents: 3, copies: [
            SkinDetails(wear: 0.451_171_9, pattern: 54, origin: 24),
        ]),
        DemoSkin(name: "Nova | Predator (Field-Tested)", type: "Shotgun", rarity: 1, defIndex: 35, paintIndex: 170, cents: 5, copies: [
            SkinDetails(wear: 0.184_326_2, pattern: 703, origin: 24),
            SkinDetails(wear: 0.366_210_9, pattern: 31, origin: 24),
        ]),
        DemoSkin(name: "MP9 | Sand Dashed (Minimal Wear)", type: "SMG", rarity: 0, defIndex: 34, paintIndex: 148, cents: 9, copies: [
            SkinDetails(wear: 0.098_144_5, pattern: 488, origin: 24, stickers: [SkinAccessory(slot: 0, name: "Bronze Ace", wear: 0.42)]),
        ], details: ["Sticker: Bronze Ace"]),
        DemoSkin(name: "Five-SeveN | Case Hardened (Field-Tested)", type: "Pistol", rarity: 2, defIndex: 3, paintIndex: 44, cents: 410, copies: [
            SkinDetails(wear: 0.227_893_4, pattern: 278, origin: 8),
        ]),
        DemoSkin(name: "Glock-18 | Water Elemental (Minimal Wear)", type: "Pistol", rarity: 4, defIndex: 4, paintIndex: 353, cents: 340, copies: [
            SkinDetails(wear: 0.112_304_7, pattern: 610, nameTag: "Splash Zone", origin: 8),
        ]),
        DemoSkin(name: "AK-47 | Redline (Field-Tested)", type: "Rifle", rarity: 4, defIndex: 7, paintIndex: 282, cents: 2_390, copies: [
            SkinDetails(wear: 0.152_893_1, pattern: 118, origin: 4),
            SkinDetails(wear: 0.347_122_8, pattern: 926, origin: 8, stickers: [
                SkinAccessory(slot: 0, name: "Crown (Foil)"),
                SkinAccessory(slot: 2, name: "Titan (Holo) | Katowice 2014", wear: 0.12),
            ]),
        ], details: ["Sticker: Crown (Foil), Titan (Holo) | Katowice 2014"]),
        DemoSkin(name: "StatTrak™ M4A1-S | Decimator (Field-Tested)", type: "Rifle", rarity: 5, defIndex: 60, paintIndex: 644, cents: 1_820, copies: [
            SkinDetails(wear: 0.201_171_9, pattern: 47, statTrak: 1_337, origin: 8),
        ]),
        DemoSkin(name: "AK-47 | Case Hardened (Field-Tested)", type: "Rifle", rarity: 4, defIndex: 7, paintIndex: 44, cents: 15_400, copies: [
            SkinDetails(wear: 0.257_324_2, pattern: 661, origin: 8),
        ]),
        DemoSkin(name: "USP-S | Cortex (Field-Tested)", type: "Pistol", rarity: 4, defIndex: 61, paintIndex: 705, cents: 260, copies: [
            SkinDetails(wear: 0.293_457, pattern: 390, origin: 8, charms: [SkinAccessory(slot: 0, name: "Lil' Squirt", pattern: 12_411)]),
        ], details: ["Charm: Lil' Squirt"]),
        DemoSkin(name: "★ Karambit | Doppler (Factory New)", type: "Knife", rarity: 5, defIndex: 507, paintIndex: 418, cents: 88_000, copies: [
            SkinDetails(wear: 0.010_253_9, pattern: 412, paintIndex: 415, origin: 8),
            SkinDetails(wear: 0.030_151_4, pattern: 77, paintIndex: 419, origin: 8),
        ]),
    ]

    static let kf2Names = [
        ("Vault Crate | Series 3", 4), ("Cosmetic Crate | Hunter", 3), ("Weapon Skin | Chrome Katana", 18),
        ("Vault Ticket", 99), ("Emote | Victory Stomp", 6),
    ]
    static let otherApps: [(appID: Int, name: String, pool: [(String, Int)])] = [
        (252490, "Rust", [("Rustic Hoodie", 140), ("Tempered AK47", 380)]),
        (578080, "PUBG: BATTLEGROUNDS", [("Survivor Crate", 18), ("Biker Vest", 7)]),
        (304930, "Unturned", [("Mystery Box", 5)]),
        (218620, "PAYDAY 2", [("Safe", 3), ("Drill", 45)]),
        (322170, "Geometry Dash", [("Wave Badge", 12)]),
        (1172470, "Apex Legends", [("Holo-Spray", 4)]),
    ]

    static let steamGames = ["Portal 2", "Terraria", "Hades", "Stardew Valley", "Celeste", "Hollow Knight", "Risk of Rain 2", "Slay the Spire", "Dead Cells", "Rocket League", "Factorio", "Deep Rock Galactic"]

    // MARK: - Builder

    struct Builder {
        let now: Date
        let today: Date
        var contexts: [InventoryContext] = []
        var itemsByContext: [String: [InventoryItem]] = [:]
        var prices: [String: PriceQuote] = [:]
        var history: [String: [PricePoint]] = [:]
        var nextAsset = 30_000_000_000

        init(now: Date) {
            self.now = now
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
            today = calendar.startOfDay(for: now)
        }

        mutating func add(_ items: [InventoryItem], appID: Int, name: String) {
            let context = InventoryContext(appID: appID, contextID: appID == 753 ? "6" : "2", name: name, iconURL: nil, assetCount: items.count)
            contexts.append(context)
            itemsByContext[context.id] = items
        }

        mutating func asset() -> String {
            nextAsset += 1
            return String(nextAsset)
        }

        mutating func price(_ key: String, base: Int, rng: inout SplitMix64) {
            guard prices[key] == nil else { return }
            var points: [PricePoint] = []
            var value = Double(base)
            for back in stride(from: 60, through: 0, by: -3) {
                let day = today.addingTimeInterval(-Double(back) * 86_400)
                points.append(PricePoint(day: day, cents: max(3, Int(value.rounded()))))
                value = max(3, value * (1 + rng.double(in: -0.06...0.065)))
            }
            // Pin today's point to the quoted price so trends and quotes agree.
            points[points.count - 1].cents = max(3, base)
            history[key] = points
            prices[key] = PriceQuote(
                lowestCents: max(3, base),
                medianCents: max(3, Int(Double(base) * rng.double(in: 0.9...1.02))),
                volume: rng.int(in: 1...900),
                checkedAt: now.addingTimeInterval(-rng.double(in: 600...70_000)),
                currency: .usd
            )
        }

        mutating func dota(rng: inout SplitMix64) {
            var items: [InventoryItem] = []
            let quality = ItemTag(category: "Quality", categoryName: "Quality", internalName: "unique", name: "Standard", color: "D2D2D2")

            func tags(rarity: Rarity, type: String, slot: String?, hero: String?) -> [ItemTag] {
                var result = [quality, ItemTag(category: "Rarity", categoryName: "Rarity", internalName: "Rarity_\(rarity.name)", name: rarity.name, color: rarity.color)]
                result.append(ItemTag(category: "Type", categoryName: "Type", internalName: type.lowercased(), name: type, color: nil))
                if let slot { result.append(ItemTag(category: "Slot", categoryName: "Slot", internalName: slot.lowercased(), name: slot, color: nil)) }
                if let hero { result.append(ItemTag(category: "Hero", categoryName: "Hero", internalName: "npc_dota_hero_" + hero.lowercased(), name: hero, color: nil)) }
                return result
            }

            func make(_ name: String, rarity: Rarity, type: String, slot: String?, hero: String?, set: ItemSetInfo?, marketable: Bool) -> InventoryItem {
                var details: [String] = []
                if let hero { details.append("Used By: \(hero)") }
                if let set { details.append(set.name); details.append(contentsOf: set.members) }
                return InventoryItem(
                    appID: 570, contextID: "2", assetID: asset(), classID: String(DemoData.stableHash(name) % 9_000_000), instanceID: "0",
                    amount: 1, name: name, baseName: name, marketHashName: name, type: "\(rarity.name) \(slot ?? type)",
                    iconHash: nil, nameColor: rarity.color, marketable: marketable, tradable: marketable, commodity: false,
                    tags: tags(rarity: rarity, type: type, slot: slot, hero: hero), details: details, itemSet: set
                )
            }

            // Set pieces: own a few pieces of every set, all of some.
            for (index, entry) in DemoData.dotaSets.enumerated() {
                let members = entry.slots.map { "\(entry.name) \($0)" }
                let set = ItemSetInfo(name: entry.name, members: members)
                let rarity = DemoData.rarities[index == 0 ? 3 : [2, 3, 3, 4, 5][index % 5]]
                let owned = index == 0 ? members.count : rng.int(in: 1...members.count)
                for member in members.shuffled(using: &rng).prefix(owned) {
                    let slot = String(member.dropFirst(entry.name.count + 1))
                    items.append(make(member, rarity: rarity, type: "Wearable", slot: slot, hero: entry.hero, set: set, marketable: true))
                    let base = index == 0 ? 3 : rng.skewed(in: rarity.cents)
                    price(PriceKey.make(appID: 570, marketHashName: member), base: base, rng: &rng)
                }
            }

            // Singles, with duplicates like a real drop-heavy inventory.
            while items.count < 1_071 {
                let pick = DemoData.dotaSingles[rng.int(in: 0...(DemoData.dotaSingles.count - 1))]
                let rarity = DemoData.rarities[pick.rarity]
                items.append(make(pick.name, rarity: rarity, type: pick.type, slot: pick.slot, hero: pick.hero, set: nil, marketable: true))
                let base = pick.name.hasPrefix("Crest of the Honored") ? 367 : rng.skewed(in: rarity.cents)
                price(PriceKey.make(appID: 570, marketHashName: pick.name), base: base, rng: &rng)
            }

            // Things that can't be sold: treasures, battle pass rewards, and so on.
            while items.count < 3_029 {
                let name = DemoData.dotaLocked[rng.int(in: 0...(DemoData.dotaLocked.count - 1))]
                let rarity = DemoData.rarities[rng.int(in: 0...5)]
                items.append(make(name, rarity: rarity, type: "Treasure", slot: nil, hero: nil, set: nil, marketable: false))
            }
            add(items, appID: 570, name: "Dota 2")
        }

        mutating func steamCommunity(rng: inout SplitMix64) {
            var items: [InventoryItem] = []
            let kinds: [(type: String, cents: ClosedRange<Int>)] = [("Trading Card", 3...14), ("Profile Background", 3...40), ("Emoticon", 3...25), ("Foil Trading Card", 20...180)]
            while items.count < 539 {
                let game = DemoData.steamGames[rng.int(in: 0...(DemoData.steamGames.count - 1))]
                let kind = kinds[rng.int(in: 0...(rng.chance(0.08) ? 3 : 2))]
                let number = rng.int(in: 1...8)
                let name: String
                switch kind.type {
                case "Emoticon": name = ":\(game.replacingOccurrences(of: " ", with: "").lowercased().prefix(8))\(number):"
                case "Profile Background": name = "\(game) Background \(number)"
                default: name = "\(game) Card \(number)"
                }
                let hashName = "\(DemoData.stableHash(game) % 900_000)-\(name)"
                let marketable = rng.chance(0.9)
                let tag = ItemTag(category: "item_class", categoryName: "Item Type", internalName: kind.type, name: kind.type, color: nil)
                let gameTag = ItemTag(category: "Game", categoryName: "Game", internalName: game, name: game, color: nil)
                items.append(InventoryItem(
                    appID: 753, contextID: "6", assetID: asset(), classID: hashName, instanceID: "0",
                    amount: 1, name: name, baseName: name, marketHashName: hashName, type: "\(game) \(kind.type)",
                    iconHash: nil, nameColor: kind.type == "Foil Trading Card" ? "CF6A32" : nil,
                    marketable: marketable, tradable: marketable, commodity: true, tags: [tag, gameTag], details: [], itemSet: nil
                ))
                price(PriceKey.make(appID: 753, marketHashName: hashName), base: rng.skewed(in: kind.cents), rng: &rng)
            }
            let gems = ItemTag(category: "item_class", categoryName: "Item Type", internalName: "Gems", name: "Gems", color: nil)
            items.append(InventoryItem(
                appID: 753, contextID: "6", assetID: asset(), classID: "gems", instanceID: "0",
                amount: 12, name: "Sack of Gems", baseName: "Sack of Gems", marketHashName: "753-Sack of Gems", type: "Steam Gems",
                iconHash: nil, nameColor: nil, marketable: true, tradable: true, commodity: true, tags: [gems], details: ["1000 Gems"], itemSet: nil
            ))
            price(PriceKey.make(appID: 753, marketHashName: "753-Sack of Gems"), base: 42, rng: &rng)
            add(items, appID: 753, name: "Steam")
        }

        mutating func simpleApp(appID: Int, name: String, count: Int, marketableShare: Double, pool: [(String, Int)], rng: inout SplitMix64) {
            var items: [InventoryItem] = []
            for _ in 0..<count {
                let pick = pool[rng.int(in: 0...(pool.count - 1))]
                let marketable = rng.chance(marketableShare)
                let tag = ItemTag(category: "Type", categoryName: "Type", internalName: "item", name: "Item", color: nil)
                items.append(InventoryItem(
                    appID: appID, contextID: "2", assetID: asset(), classID: pick.0, instanceID: "0",
                    amount: 1, name: pick.0, baseName: pick.0, marketHashName: pick.0, type: name,
                    iconHash: nil, nameColor: nil, marketable: marketable, tradable: marketable, commodity: false,
                    tags: [tag], details: [], itemSet: nil
                ))
                let base = max(3, Int(Double(pick.1) * rng.double(in: 0.9...1.1)))
                price(PriceKey.make(appID: appID, marketHashName: pick.0), base: base, rng: &rng)
            }
            add(items, appID: appID, name: name)
        }

        /// Adds the skins to the CS2 inventory, with their exterior, rarity, and weapon type as Steam tags them.
        mutating func cs2Skins(rng: inout SplitMix64) {
            let key = InventoryContext.key(appID: 730, contextID: "2")
            var items = itemsByContext[key] ?? []
            for skin in DemoData.cs2Skins {
                let rarity = DemoData.cs2Rarities[skin.rarity]
                let quality: (name: String, color: String) = skin.name.hasPrefix("★") ? ("★", "8650AC")
                    : skin.name.hasPrefix("StatTrak™") ? ("StatTrak™", "CF6A32") : ("Normal", "D2D2D2")
                let prefix = quality.name == "Normal" ? "" : quality.name + " "
                for copy in skin.copies {
                    var details = copy
                    details.defIndex = skin.defIndex
                    details.paintIndex = details.paintIndex ?? skin.paintIndex
                    let exterior = Exterior.of(details.wear ?? 0)
                    let tags = [
                        ItemTag(category: "Type", categoryName: "Type", internalName: skin.type, name: skin.type, color: nil),
                        ItemTag(category: "Quality", categoryName: "Category", internalName: quality.name, name: quality.name, color: quality.color),
                        ItemTag(category: "Rarity", categoryName: "Quality", internalName: rarity.name, name: rarity.name, color: rarity.color),
                        ItemTag(category: "Exterior", categoryName: "Exterior", internalName: exterior.title, name: exterior.title, color: nil),
                    ]
                    items.append(InventoryItem(
                        appID: 730, contextID: "2", assetID: asset(), classID: String(DemoData.stableHash(skin.name) % 9_000_000), instanceID: "0",
                        amount: 1, name: skin.name, baseName: skin.name, marketHashName: skin.name, type: "\(prefix)\(rarity.name) \(skin.type)",
                        iconHash: nil, nameColor: quality.name == "Normal" ? nil : quality.color, marketable: true, tradable: true, commodity: false,
                        tags: tags, details: ["Exterior: \(exterior.title)"] + skin.details, itemSet: nil, skin: details
                    ))
                }
                price(PriceKey.make(appID: 730, marketHashName: skin.name), base: skin.cents, rng: &rng)
            }
            itemsByContext[key] = items
            if let index = contexts.firstIndex(where: { $0.id == key }) {
                contexts[index].assetCount = items.count
            }
        }

        func snapshots(rng: inout SplitMix64) -> [DemoSnapshot] {
            let all = itemsByContext.values.flatMap { $0 }
            let current = Valuation.of(all, prices: prices)
            var result: [DemoSnapshot] = []
            var value = Double(current.buyerCents)
            for back in 0..<150 {
                let day = today.addingTimeInterval(-Double(back) * 86_400)
                let seller = Int(value * Double(current.sellerCents) / Double(max(current.buyerCents, 1)))
                result.append(DemoSnapshot(day: day, buyerCents: Int(value), sellerCents: seller))
                value = max(1, value * (1 - rng.double(in: -0.022...0.026)))
            }
            return result.reversed()
        }
    }
}

/// Small deterministic generator so demo data is identical on every launch.
nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }
    mutating func double(in range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &self) }
    mutating func chance(_ probability: Double) -> Bool { double(in: 0...1) < probability }

    /// Values bunched toward the low end of the range, like real Market prices.
    mutating func skewed(in range: ClosedRange<Int>) -> Int {
        let t = pow(double(in: 0...1), 3)
        return range.lowerBound + Int(Double(range.upperBound - range.lowerBound) * t)
    }
}
