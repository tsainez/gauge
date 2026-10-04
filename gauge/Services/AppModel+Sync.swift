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
        // After an update, inventories cached by the older version are checked at launch,
        // not hours later when the next check is due. Once a launch, so a failure waits.
        let upgrade = inventoriesAreOutdated && !checkedOutdatedInventories && settings.inventoryCheck.seconds != nil
        if inventoryCheckIsDue || upgrade {
            checkedOutdatedInventories = true
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

    /// Whether a cached inventory is missing what this version reads out of it (CS2 floats and patterns).
    var inventoriesAreOutdated: Bool {
        defaults.integer(forKey: Self.inventoryFormatKey) < Self.inventoryFormat
            && contexts.contains { $0.appID == SkinDetailsReader.appID }
    }

    /// Bumped when Gauge reads more out of an inventory than before, so inventories
    /// cached by an older version are downloaded once more. 2: CS2 floats and patterns.
    static let inventoryFormat = 2
    static let inventoryFormatKey = "GaugeInventoryFormat"

    /// Refreshes inventories from Steam. With `force`, every inventory is re-downloaded.
    func syncInventories(force: Bool) async {
        guard let profile = settings.profile, !settings.demoMode, !syncPhase.isBusy else { return }
        notice = nil
        syncPhase = .discovering
        let auth = await ownerAuth(for: profile)
        let outdated = defaults.integer(forKey: Self.inventoryFormatKey) < Self.inventoryFormat
        var upgraded = true

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
            // Only CS2 inventories gained anything from the last format change.
            let upgrading = outdated && cached != nil && context.appID == SkinDetailsReader.appID
            if !force && directoryIsComplete && unchanged && !upgrading {
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
                upgraded = false
                break
            } catch {
                contextStatus[context.id, default: ContextStatus()].error = error.localizedDescription
                if cached != nil { refreshed.append(context) }
                if upgrading { upgraded = false }
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
        if outdated && upgraded {
            defaults.set(Self.inventoryFormat, forKey: Self.inventoryFormatKey)
        }
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

// MARK: - Refreshing one item

extension AppModel {
    /// Whether Refresh Item can run: a real profile, and no inventory download already going.
    var canRefreshItems: Bool {
        settings.profile != nil && !settings.demoMode && !syncPhase.isBusy
    }

    /// Refresh Item: downloads the item's inventory again and re-checks its price. Steam
    /// can't send one item on its own, so the whole inventory for its game comes down,
    /// which also brings every CS2 skin's float and pattern up to date.
    func refresh(_ item: InventoryItem) async {
        guard await refreshInventory(contextKey: item.contextKey) else { return }
        // Price the item as it is now; it may have left the inventory.
        if let current = self.item(withID: item.id), current.marketable {
            await refreshPrice(for: current)
        }
    }

    /// Downloads one inventory again right away, whether or not its item count changed,
    /// and says in the status bar what came back. Returns whether it worked.
    @discardableResult
    func refreshInventory(contextKey: String) async -> Bool {
        guard canRefreshItems, let profile = settings.profile, let context = context(for: contextKey) else { return false }
        notice = nil
        syncPhase = .loading(name: context.name, loaded: 0, total: context.assetCount > 0 ? context.assetCount : nil)
        let auth = await ownerAuth(for: profile)
        do {
            let name = context.name
            let items = try await client.inventory(steamID64: profile.steamID64, context: context, auth: auth) { loaded, total in
                Task { @MainActor [weak self] in
                    guard let self, self.syncPhase.isBusy, !self.settings.demoMode else { return }
                    self.syncPhase = .loading(name: name, loaded: loaded, total: total)
                }
            }
            guard !settings.demoMode else { return false }
            var updated = context
            updated.assetCount = items.count
            await store(items, for: updated)
            if let index = contexts.firstIndex(where: { $0.id == contextKey }) {
                contexts[index] = updated
            }
            syncPhase = .idle
            rebuildDerived()
            pruneCleanupOverrides()
            rebuildPricingQueue()
            ensurePricing()
            showNotice(Self.refreshSummary(name: context.name, appID: context.appID, items: items))
            return true
        } catch {
            syncPhase = .idle
            contextStatus[contextKey, default: ContextStatus()].error = error.localizedDescription
            notice = error.localizedDescription
            return false
        }
    }

    /// Checks one item's price now, even if the last check was recent.
    func refreshPrice(for item: InventoryItem) async {
        guard item.marketable, !settings.demoMode else { return }
        do {
            let quote = try await client.priceOverview(appID: item.appID, marketHashName: item.marketHashName, currency: settings.currency)
            guard !settings.demoMode else { return }
            failedPriceKeys[item.priceKey] = nil
            store(quote, for: item.priceKey)
            recomputeTrends()
            recordSnapshot()
        } catch SteamClient.Failure.rateLimited(let wait) {
            pricingPausedUntil = Date().addingTimeInterval(wait)
        } catch {
            // The old price stays; the pricing queue tries again later.
        }
    }

    /// "Counter-Strike 2 refreshed: 245 items, 180 with a float"
    static func refreshSummary(name: String, appID: Int, items: [InventoryItem]) -> String {
        let count = "\(items.count.formatted()) item\(items.count == 1 ? "" : "s")"
        guard appID == SkinDetailsReader.appID else { return "\(name) refreshed: \(count)" }
        let floats = items.filter { $0.wear != nil }.count
        return "\(name) refreshed: \(count), \(floats == 0 ? "none" : floats.formatted()) with a float"
    }

    /// Shows a message in the status bar for a few seconds.
    func showNotice(_ message: String, seconds: Double = 8) {
        notice = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if self?.notice == message { self?.notice = nil }
        }
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
        var sweeps = planMarketSweeps()
        pricing: while !Task.isCancelled {
            // Items the user is looking at go first; then bulk sweeps; then one name at a time.
            let urgent = pricingQueue.first.map { priorityPriceKeys.contains($0) } ?? false
            if !urgent, !sweeps.isEmpty {
                switch await sweepNextPage(&sweeps[0]) {
                case .priced(let count):
                    sinceSnapshot += count
                    if sweeps[0].isFinished { sweeps.removeFirst() }
                case .skipGame:
                    sweeps.removeFirst()
                case .stopSweeping:
                    sweeps.removeAll()
                case .cancelled:
                    break pricing
                }
                if sinceSnapshot >= 25 {
                    recordSnapshot()
                    recomputeTrends()
                    sinceSnapshot = 0
                }
                continue
            }
            guard !pricingQueue.isEmpty else { break }
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
        store([key: quote])
    }

    /// Saves many quotes at once, with one save and one revaluation.
    func store(_ quotes: [String: PriceQuote]) {
        guard !quotes.isEmpty else { return }
        for (key, quote) in quotes {
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
        }
        try? modelContext.save()
        recomputeValuation()
    }

    /// Prices are per currency, so switching currency starts pricing over.
    func currencyChanged() {
        stopPricing()
        try? modelContext.delete(model: PriceRecord.self)
        try? modelContext.save()
        priceRecords = [:]
        priceHistory = [:]
        prices = [:]
        failedPriceKeys = [:]
        marketSweptAt = [:]
        marketSweepUnavailable = false
        loadSnapshots()
        recomputeValuation()
        recomputeTrends()
        rebuildPricingQueue()
        ensurePricing()
    }

    /// How long before a game is swept again. Names a sweep missed are priced one at a time meanwhile.
    static let marketSweepCooldown: TimeInterval = 6 * 3_600

    /// What one page of a sweep came to.
    enum MarketSweepStep {
        case priced(Int)
        case skipGame
        case stopSweeping
        case cancelled
    }

    /// The games worth sweeping, most names first: each needs a price for at least
    /// `MarketSweep.minimumNames` names that are new or cheap. Stale valuable items are
    /// left to single checks, which also bring back the median sale and volume.
    func planMarketSweeps() -> [MarketSweep] {
        guard !marketSweepUnavailable, !settings.demoMode else { return [] }
        let now = Date()
        let urgent = Set(priorityPriceKeys)
        var wanted: [Int: Set<String>] = [:]
        for key in pricingQueue where !urgent.contains(key) {
            if let quote = prices[key], (quote.valueCents ?? Int.max) >= settings.fluffThresholdCents { continue }
            guard let parts = PriceKey.split(key) else { continue }
            wanted[parts.appID, default: []].insert(parts.marketHashName)
        }
        return wanted
            .filter { entry in
                guard entry.value.count >= MarketSweep.minimumNames else { return false }
                guard let swept = marketSweptAt[entry.key] else { return true }
                return now.timeIntervalSince(swept) >= Self.marketSweepCooldown
            }
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .map { MarketSweep(appID: $0.key, wanted: $0.value) }
    }

    /// Fetches the sweep's next page and stores the prices it found for wanted names.
    func sweepNextPage(_ sweep: inout MarketSweep) async -> MarketSweepStep {
        let currency = settings.currency
        let page: MarketSearchPage
        do {
            page = try await client.marketSearch(appID: sweep.appID, start: sweep.nextStart, currency: currency)
        } catch SteamClient.Failure.rateLimited(let wait) {
            // The client holds the next request until the back-off passes; the same page is asked for again.
            pricingPausedUntil = Date().addingTimeInterval(wait)
            return .priced(0)
        } catch {
            if Task.isCancelled || error is CancellationError { return .cancelled }
            // Search may be unavailable for this game; single checks still work.
            marketSweptAt[sweep.appID] = Date()
            return .skipGame
        }
        guard !Task.isCancelled, !settings.demoMode, settings.currency == currency else { return .cancelled }
        guard page.currencyMatches else {
            // Steam answered in another currency. Storing those prices would be wrong.
            marketSweepUnavailable = true
            return .stopSweeping
        }
        pricingPausedUntil = nil
        let hits = sweep.absorb(page)
        if sweep.isFinished { marketSweptAt[sweep.appID] = Date() }
        let now = Date()
        var quotes: [String: PriceQuote] = [:]
        for hit in hits {
            let key = PriceKey.make(appID: sweep.appID, marketHashName: hit.hashName)
            quotes[key] = PriceQuote(lowestCents: hit.lowestCents, medianCents: nil, volume: nil, checkedAt: now, currency: currency)
            failedPriceKeys[key] = nil
        }
        store(quotes)
        let priced = Set(quotes.keys)
        pricingQueue.removeAll { priced.contains($0) }
        return .priced(quotes.count)
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
