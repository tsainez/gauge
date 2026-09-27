//
//  CleanupRows.swift
//  gauge
//
//  What the Clean up list shows: every copy of an item that landed in the
//  same bucket collapses into one row, which can be searched, filtered by
//  why it's there, and sorted.
//

import Foundation

nonisolated enum CleanupSort: String, CaseIterable, Identifiable, Sendable {
    case value
    case name
    case copies
    case newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .value: "Value"
        case .name: "Name"
        case .copies: "Most copies"
        case .newest: "Newest"
        }
    }
}

/// Narrows a bucket to one reason, or to the items that only pay a cent.
nonisolated enum CleanupFilter: Hashable, Sendable {
    case reason(CleanupReason.Kind)
    case paysFloor

    func matches(_ entry: CleanupEntry) -> Bool {
        switch self {
        case .reason(let kind): entry.reason.kind == kind
        case .paysFloor: entry.paysFloor
        }
    }

    func title(rules: CleanupRules, currency: SteamCurrency) -> String {
        switch self {
        case .paysFloor: return "Pays \(Money.format(1, currency))"
        case .reason(let kind):
            switch kind {
            case .extraCopy: return "Extra copies"
            case .cheap: return "Under \(Money.format(rules.cheapBelowCents, currency))"
            case .everythingElse: return "Everything else"
            case .expensive: return "\(Money.format(rules.reviewAboveCents, currency)) or more"
            case .starred: return "Starred"
            case .setPiece: return "Set pieces"
            case .notPriced: return "Not priced yet"
            case .rising: return "Rising"
            case .floorPrice: return "Pays \(Money.format(1, currency))"
            case .keptCopy: return "Copies you keep"
            case .noRule: return "Only copies"
            case .movedByYou: return "Moved by you"
            }
        }
    }
}

/// Every copy of one item in one bucket.
nonisolated struct CleanupRow: Identifiable, Hashable, Sendable {
    var entries: [CleanupEntry]

    var id: String { Self.id(bucket: bucket, priceKey: item.priceKey) }
    var first: CleanupEntry { entries[0] }
    var item: InventoryItem { first.item }
    var bucket: CleanupBucket { first.bucket }
    var itemIDs: [String] { entries.map(\.item.id) }
    /// Units in this row, counting every unit of a stack.
    var count: Int { entries.reduce(0) { $0 + $1.item.amount } }
    /// Copies owned in the inventories being cleaned up, in any bucket.
    var copies: Int { first.copies }
    /// Every copy of an item has the same market price.
    var buyerCents: Int? { first.buyerCents }
    var sellerCents: Int? { first.sellerCents }
    var totalSellerCents: Int { entries.reduce(0) { $0 + $1.totalSellerCents } }
    var totalBuyerCents: Int { entries.reduce(0) { $0 + $1.totalBuyerCents } }
    var paysFloor: Bool { first.paysFloor }
    /// The most recently acquired copy.
    var newest: InventoryItem { entries.map(\.item).max(by: CopyIndex.isOlder) ?? item }

    /// Each distinct reason, most telling first.
    var reasons: [CleanupReason] {
        var seen = Set<CleanupReason>()
        return entries.map(\.reason).filter { seen.insert($0).inserted }.sorted { $0.kind.rank < $1.kind.rank }
    }

    static func id(bucket: CleanupBucket, priceKey: String) -> String { "\(bucket.rawValue)|\(priceKey)" }

    func matches(search needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        let item = item
        return item.name.lowercased().contains(needle)
            || item.type.lowercased().contains(needle)
            || (item.usedBy?.lowercased().contains(needle) ?? false)
    }

    /// Collapses copies into rows, then applies search, filter, and sort.
    static func rows(
        from entries: [CleanupEntry],
        search: String = "",
        filter: CleanupFilter? = nil,
        sort: CleanupSort = .value
    ) -> [CleanupRow] {
        var order: [String] = []
        var grouped: [String: [CleanupEntry]] = [:]
        for entry in entries {
            let key = id(bucket: entry.bucket, priceKey: entry.item.priceKey)
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(entry)
        }
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        let rows = order.compactMap { grouped[$0].map(CleanupRow.init(entries:)) }.filter { row in
            row.matches(search: needle) && (filter.map { filter in row.entries.contains(where: filter.matches) } ?? true)
        }
        return sorted(rows, by: sort)
    }

    static func sorted(_ rows: [CleanupRow], by sort: CleanupSort) -> [CleanupRow] {
        rows.sorted { lhs, rhs in
            switch sort {
            case .value:
                let l = lhs.buyerCents ?? -1, r = rhs.buyerCents ?? -1
                if l != r { return l > r }
            case .name:
                break
            case .copies:
                if lhs.count != rhs.count { return lhs.count > rhs.count }
            case .newest:
                let l = lhs.newest, r = rhs.newest
                if l.id != r.id { return CopyIndex.isOlder(r, l) }
            }
            let order = lhs.item.name.localizedStandardCompare(rhs.item.name)
            return order != .orderedSame ? order == .orderedAscending : lhs.id < rhs.id
        }
    }

    /// The row to select once `removed` leave the list, so the keyboard can carry on:
    /// the first row after them, or failing that the last one before.
    static func nextID(after removed: Set<String>, in rows: [CleanupRow]) -> String? {
        guard let last = rows.lastIndex(where: { removed.contains($0.id) }) else { return nil }
        if let after = rows[(last + 1)...].first(where: { !removed.contains($0.id) }) { return after.id }
        return rows[..<last].last(where: { !removed.contains($0.id) })?.id
    }

    /// The filters worth offering for a bucket: each reason present, plus
    /// "pays a cent" when some rows only pay that. Counts are rows, not items.
    static func filters(for entries: [CleanupEntry]) -> [(filter: CleanupFilter, count: Int)] {
        let rows = rows(from: entries)
        var result: [(filter: CleanupFilter, count: Int)] = []
        for kind in CleanupReason.Kind.allCases {
            let count = rows.filter { $0.entries.contains { $0.reason.kind == kind } }.count
            if count > 0 { result.append((.reason(kind), count)) }
        }
        let floor = rows.filter(\.paysFloor).count
        if floor > 0 && floor < rows.count && !result.contains(where: { $0.filter == .reason(.floorPrice) }) {
            result.append((.paysFloor, floor))
        }
        return result
    }
}

extension CleanupPlan {
    /// The items in a row of this plan, found by `CleanupRow.id`.
    func itemIDs(inRow rowID: String) -> [String] {
        let parts = rowID.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let bucket = CleanupBucket(rawValue: parts[0]) else { return [] }
        return entries(in: bucket).filter { $0.item.priceKey == parts[1] }.map(\.item.id)
    }

    /// Which bucket each item is in.
    var bucketsByItem: [String: CleanupBucket] {
        var result: [String: CleanupBucket] = [:]
        for (bucket, entries) in entries {
            for entry in entries { result[entry.item.id] = bucket }
        }
        return result
    }
}

/// Rows dragged onto a bucket travel as one string, so a whole selection can move at once.
nonisolated enum CleanupDrag {
    static let prefix = "gauge-cleanup-rows:"

    static func payload(rowIDs: [String]) -> String {
        prefix + rowIDs.joined(separator: "\n")
    }

    /// Row ids from dropped strings, ignoring anything that didn't come from a Clean up row.
    static func rowIDs(from payloads: [String]) -> [String] {
        payloads.filter { $0.hasPrefix(prefix) }.flatMap { $0.dropFirst(prefix.count).split(separator: "\n").map(String.init) }
    }
}
