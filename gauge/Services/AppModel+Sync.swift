//
//  AppModel+Sync.swift
//  gauge
//
//  Inventory sync. A check costs one request (the inventory page lists
//  every game with an item count); an inventory is only re-downloaded when
//  its count changed or the user forces a refresh.
//

import Foundation
import SwiftData

extension AppModel {
    /// Runs every 10 minutes while the app is open: checks inventories when due and keeps pricing going.
    func startScheduler() {
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.schedulerTick()
                try? await Task.sleep(nanoseconds: 600 * 1_000_000_000)
            }
        }
    }

    func schedulerTick() async {
        guard settings.profile != nil, !settings.demoMode else { return }
        if inventoryCheckIsDue {
            await syncInventories(force: false)
        } else {
            rebuildPricingQueue()
            ensurePricing()
        }
    }

    var inventoryCheckIsDue: Bool {
        guard let interval = settings.inventoryCheck.seconds else { return contexts.isEmpty }
        guard let lastInventoryCheck else { return true }
        return Date().timeIntervalSince(lastInventoryCheck) >= interval
    }

    /// Refreshes inventories from Steam. With `force`, every inventory is re-downloaded.
    func syncInventories(force: Bool) async {
        guard let profile = settings.profile, !settings.demoMode, !syncPhase.isBusy else { return }
        notice = nil
        syncPhase = .discovering
        let auth = await ownerAuth(for: profile)

        var directory: [InventoryContext]
        var directoryIsComplete = true
        do {
            directory = try await client.inventoryDirectory(steamID64: profile.steamID64, auth: auth)
        } catch SteamClient.Failure.rateLimited(let wait) {
            syncPhase = .idle
            notice = SteamClient.Failure.rateLimited(retryAfter: wait).errorDescription
            return
        } catch {
            // The page layout may change; fall back to what we know and the common games.
            directoryIsComplete = false
            directory = contexts.isEmpty ? InventoryContext.common : contexts
        }

        var refreshed: [InventoryContext] = []
        for context in directory {
            if settings.demoMode { return }
            let cached = itemsByContext[context.id]
            let unchanged = cached != nil && self.context(for: context.id)?.assetCount == context.assetCount
            if !force && directoryIsComplete && unchanged {
                refreshed.append(context)
                continue
            }
            syncPhase = .loading(name: context.name, loaded: 0, total: context.assetCount > 0 ? context.assetCount : nil)
            do {
                let name = context.name
                let items = try await client.inventory(steamID64: profile.steamID64, context: context, auth: auth) { loaded, total in
                    Task { @MainActor [weak self] in
                        guard let self, !self.settings.demoMode else { return }
                        self.syncPhase = .loading(name: name, loaded: loaded, total: total)
                    }
                }
                if settings.demoMode { return }
                guard !items.isEmpty || directoryIsComplete else { continue }
                var updated = context
                updated.assetCount = items.count
                await store(items, for: updated)
                refreshed.append(updated)
            } catch SteamClient.Failure.rateLimited(let wait) {
                notice = SteamClient.Failure.rateLimited(retryAfter: wait).errorDescription
                let refreshedIDs = Set(refreshed.map(\.id))
                refreshed.append(contentsOf: directory.filter { candidate in
                    !refreshedIDs.contains(candidate.id) && itemsByContext[candidate.id] != nil
                })
                break
            } catch {
                contextStatus[context.id, default: ContextStatus()].error = error.localizedDescription
                if cached != nil { refreshed.append(context) }
                // While probing guessed games, a 403 just means there's nothing there.
                if directoryIsComplete, let failure = error as? SteamClient.Failure, failure == .privateInventory {
                    notice = auth == nil
                        ? failure.localizedDescription
                        : "Steam wouldn't show \(context.name) even with your sign-in. Try signing in again from Settings."
                }
            }
        }

        if settings.demoMode { return }
        if directoryIsComplete {
            removeInventories(notIn: Set(refreshed.map(\.id)))
        }
        var merged = refreshed
        var mergedIDs = Set(merged.map(\.id))
        for context in contexts where !mergedIDs.contains(context.id) && itemsByContext[context.id] != nil {
            merged.append(context)
            mergedIDs.insert(context.id)
        }
        contexts = merged.sorted { $0.assetCount > $1.assetCount }

        lastInventoryCheck = Date()
        defaults.set(lastInventoryCheck, forKey: Self.lastCheckKey)
        syncPhase = .idle
        rebuildDerived()
        pruneCleanupOverrides()
        rebuildPricingQueue()
        ensurePricing()
        recordSnapshot()
    }

    /// The Steam session, when it belongs to the profile being shown. Sent with inventory
    /// requests, it lets Gauge read that profile's inventory even when it's private,
    /// the same way Steam's own inventory page does for its owner.
    func ownerAuth(for profile: ProfileSummary) async -> SteamWebAuth? {
        guard web.status.steamID64 == profile.steamID64 else { return nil }
        let auth = await web.auth()
        return auth?.steamID64 == profile.steamID64 ? auth : nil
    }

    /// Replaces one inventory in memory and in the cache.
    func store(_ items: [InventoryItem], for context: InventoryContext) async {
        let previous = Set((itemsByContext[context.id] ?? []).map(\.assetID))
        let newCount = previous.isEmpty ? 0 : items.reduce(0) { $0 + (previous.contains($1.assetID) ? 0 : 1) }
        itemsByContext[context.id] = items
        let now = Date()
        contextStatus[context.id] = ContextStatus(syncedAt: now, newSinceLastSync: newCount, error: nil)

        let payload = await Task.detached(priority: .utility) { () -> Data in
            (try? JSONEncoder().encode(items)) ?? Data()
        }.value
        let record: CachedInventory
        if let existing = inventoryRecords[context.id] {
            record = existing
        } else {
            record = CachedInventory(context: context)
            modelContext.insert(record)
            inventoryRecords[context.id] = record
        }
        record.name = context.name
        record.iconURL = context.iconURL
        record.assetCount = items.count
        record.syncedAt = now
        record.newSinceLastSync = newCount
        record.lastError = nil
        record.payload = payload
        try? modelContext.save()
    }

    /// Drops items that left the inventory (for example, after being listed) without a full sync.
    func removeItems(withIDs ids: Set<String>) async {
        var touched: [InventoryContext] = []
        for context in contexts {
            guard let items = itemsByContext[context.id], items.contains(where: { ids.contains($0.id) }) else { continue }
            var updated = context
            let remaining = items.filter { !ids.contains($0.id) }
            updated.assetCount = remaining.count
            let status = contextStatus[context.id]
            await store(remaining, for: updated)
            contextStatus[context.id]?.newSinceLastSync = status?.newSinceLastSync ?? 0
            touched.append(updated)
        }
        for context in touched {
            if let index = contexts.firstIndex(where: { $0.id == context.id }) { contexts[index] = context }
        }
        browser.selection.subtract(ids)
        rebuildDerived()
    }

    private func removeInventories(notIn keep: Set<String>) {
        for (key, record) in inventoryRecords where !keep.contains(key) {
            modelContext.delete(record)
            inventoryRecords[key] = nil
            itemsByContext[key] = nil
            contextStatus[key] = nil
        }
        contexts.removeAll { !keep.contains($0.id) }
        try? modelContext.save()
    }
}

// MARK: - Pricing queue

extension AppModel {
    static let failedPriceRetry: TimeInterval = 6 * 3_600

    /// Orders every marketable item that needs a price: never-priced first (rarest first,
    /// since those are likely worth the most), then stale valuable items, then stale fluff.
    func rebuildPricingQueue() {
        guard !settings.demoMode else {
            pricingQueue = []
            return
        }
        let now = Date()
        var best: [String: (priority: Int, rank: Int, count: Int)] = [:]
        for item in allItems where item.marketable {
            let key = item.priceKey
            if var entry = best[key] {
                entry.rank = max(entry.rank, RarityOrder.rank(item.rarity?.name))
                entry.count += item.amount
                best[key] = entry
                continue
            }
            if let failed = failedPriceKeys[key], now.timeIntervalSince(failed) < Self.failedPriceRetry { continue }
            let priority: Int
            if let quote = prices[key] {
                guard let lifetime = settings.priceLifetime(forValue: quote.valueCents),
                      now.timeIntervalSince(quote.checkedAt) >= lifetime
                else { continue }
                priority = (quote.valueCents ?? 0) >= settings.fluffThresholdCents ? 1 : 2
            } else {
                priority = 0
            }
            best[key] = (priority, RarityOrder.rank(item.rarity?.name), item.amount)
        }
        let ordered = best.sorted { lhs, rhs in
            if lhs.value.priority != rhs.value.priority { return lhs.value.priority < rhs.value.priority }
            if lhs.value.rank != rhs.value.rank { return lhs.value.rank > rhs.value.rank }
            if lhs.value.count != rhs.value.count { return lhs.value.count > rhs.value.count }
            return lhs.key < rhs.key
        }.map(\.key)
        let urgent = priorityPriceKeys.filter { best[$0] != nil }
        let urgentSet = Set(urgent)
        pricingQueue = urgent + ordered.filter { !urgentSet.contains($0) }
    }

    /// Moves these items to the front of the queue, e.g. when the user selects them.
    func prioritizePricing(for items: [InventoryItem]) {
        let keys = items.filter(\.marketable).map(\.priceKey)
        guard !keys.isEmpty, !settings.demoMode else { return }
        var seen = Set<String>()
        priorityPriceKeys = (keys + priorityPriceKeys).filter { seen.insert($0).inserted }.prefix(200).map { $0 }
        rebuildPricingQueue()
        ensurePricing()
    }

    func ensurePricing() {
        guard pricingTask == nil, !pricingQueue.isEmpty, !settings.demoMode else { return }
        pricingTask = Task { [weak self] in
            await self?.runPricingQueue()
        }
    }

    func stopPricing() {
        pricingTask?.cancel()
        pricingTask = nil
        pricingActive = false
    }

    private func runPricingQueue() async {
        pricingActive = true
        var sinceSnapshot = 0
        while !Task.isCancelled, !pricingQueue.isEmpty {
            let key = pricingQueue.removeFirst()
            priorityPriceKeys.removeAll { $0 == key }
            guard let parts = PriceKey.split(key) else { continue }
            if let quote = prices[key], let lifetime = settings.priceLifetime(forValue: quote.valueCents),
               Date().timeIntervalSince(quote.checkedAt) < lifetime {
                continue
            }
            do {
                let quote = try await client.priceOverview(appID: parts.appID, marketHashName: parts.marketHashName, currency: settings.currency)
                guard !Task.isCancelled, !settings.demoMode else { break }
                store(quote, for: key)
                pricingPausedUntil = nil
                sinceSnapshot += 1
                if sinceSnapshot >= 25 {
                    recordSnapshot()
                    recomputeTrends()
                    sinceSnapshot = 0
                }
            } catch SteamClient.Failure.rateLimited(let wait) {
                // The client holds the next request until the back-off passes.
                pricingQueue.insert(key, at: 0)
                pricingPausedUntil = Date().addingTimeInterval(wait)
            } catch is CancellationError {
                pricingQueue.insert(key, at: 0)
                break
            } catch {
                failedPriceKeys[key] = Date()
            }
        }
        if !Task.isCancelled {
            // A cancelled run was already detached by stopPricing(), and a new one may be running.
            pricingActive = false
            pricingTask = nil
        }
        recomputeTrends()
        recordSnapshot()
    }

    /// Saves a fresh quote in memory, in the day's history, and in the cache.
    func store(_ quote: PriceQuote, for key: String) {
        prices[key] = quote
        var history = priceHistory[key] ?? []
        if let value = quote.valueCents {
            history = PriceTrend.appending(value, on: Calendar.current.startOfDay(for: quote.checkedAt), to: history)
            priceHistory[key] = history
        }
        if let record = priceRecords[key] {
            record.update(quote: quote, history: history)
        } else {
            let record = PriceRecord(key: key, quote: quote, history: history)
            modelContext.insert(record)
            priceRecords[key] = record
        }
        try? modelContext.save()
        recomputeValuation()
    }

    /// Prices are per currency, so switching currency starts pricing over.
    func currencyChanged() {
        stopPricing()
        for record in priceRecords.values { modelContext.delete(record) }
        try? modelContext.save()
        priceRecords = [:]
        priceHistory = [:]
        prices = [:]
        failedPriceKeys = [:]
        loadSnapshots()
        recomputeValuation()
        recomputeTrends()
        rebuildPricingQueue()
        ensurePricing()
    }

    /// When the next price check can go out, if Steam asked Gauge to wait.
    var pricingResumesAt: Date? {
        guard let pricingPausedUntil, pricingPausedUntil > Date() else { return nil }
        return pricingPausedUntil
    }
}

// MARK: - Net worth history

extension AppModel {
    /// Saves today's marketable net worth. Called as prices come in, so the
    /// day's point converges on the full valuation.
    func recordSnapshot() {
        guard !settings.demoMode, valuation.pricedCount > 0 else { return }
        let day = Calendar.current.startOfDay(for: Date())
        let context = modelContext
        let descriptor = FetchDescriptor<NetWorthSnapshot>(predicate: #Predicate<NetWorthSnapshot> { $0.day == day })
        if let existing = try? context.fetch(descriptor).first {
            existing.buyerCents = valuation.buyerCents
            existing.sellerCents = valuation.sellerCents
            existing.currencyCode = settings.currency.rawValue
            existing.itemCount = valuation.pricedCount
        } else {
            context.insert(NetWorthSnapshot(
                day: day,
                buyerCents: valuation.buyerCents,
                sellerCents: valuation.sellerCents,
                currencyCode: settings.currency.rawValue,
                itemCount: valuation.pricedCount
            ))
        }
        try? context.save()
        loadSnapshots()
    }

    func loadSnapshots() {
        guard !settings.demoMode else { return }
        let currency = settings.currency.rawValue
        let descriptor = FetchDescriptor<NetWorthSnapshot>(sortBy: [SortDescriptor(\.day)])
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        snapshots = rows
            .filter { $0.currencyCode == currency }
            .map { NetWorthPoint(day: $0.day, buyerCents: $0.buyerCents, sellerCents: $0.sellerCents) }
    }

    /// Writes the net worth history as CSV.
    func historyCSV() -> String {
        var lines = ["date,currency,marketable_value,after_fees"]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        for point in snapshots {
            lines.append("\(formatter.string(from: point.day)),\(settings.currency.isoCode),\(Decimal(point.buyerCents) / 100),\(Decimal(point.sellerCents) / 100)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
