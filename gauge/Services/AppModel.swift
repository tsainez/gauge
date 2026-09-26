//
//  AppModel.swift
//  gauge
//
//  The single source of truth for the UI. Views read plain in-memory values
//  from here and never wait on Steam: on launch the model loads the local
//  cache, then background work (inventory sync, the pricing queue) refreshes
//  it and the UI updates as results land.
//

import Foundation
import Observation
import SwiftData
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case portfolio
    case inventory
    case cleanup
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portfolio: "Portfolio"
        case .inventory: "Inventory"
        case .cleanup: "Clean up"
        case .settings: "Settings"
        }
    }
}

enum SyncPhase: Equatable {
    case idle
    case resolving
    case discovering
    case loading(name: String, loaded: Int, total: Int?)

    var isBusy: Bool { self != .idle }

    var label: String? {
        switch self {
        case .idle: nil
        case .resolving: "Finding your profile…"
        case .discovering: "Checking for inventory changes…"
        case .loading(let name, let loaded, let total):
            if let total, total > 0 { "Loading \(name): \(loaded.formatted()) of \(total.formatted())" } else { "Loading \(name)…" }
        }
    }
}

struct ContextStatus: Equatable {
    var syncedAt: Date?
    var newSinceLastSync = 0
    var error: String?
}

struct NetWorthPoint: Identifiable, Equatable {
    var day: Date
    var buyerCents: Int
    var sellerCents: Int
    var id: Date { day }
}

@Observable
final class AppModel {
    // MARK: Settings and navigation

    var settings: AppSettings
    /// Set by the root view from the window's color scheme.
    var systemIsDark = false
    var tab: AppTab = .portfolio
    /// A short message shown in the status bar, such as a sync error.
    var notice: String?

    let browser = InventoryBrowser()
    let cleanup = CleanupSession()
    let web = SteamWebSession()

    // MARK: Inventory

    var contexts: [InventoryContext] = []
    var itemsByContext: [String: [InventoryItem]] = [:]
    var contextStatus: [String: ContextStatus] = [:]
    /// Every item across inventories, in `contexts` order.
    var allItems: [InventoryItem] = []
    var ownership = SetOwnership(items: [])
    var syncPhase: SyncPhase = .idle
    var lastInventoryCheck: Date?

    // MARK: Prices

    var prices: [String: PriceQuote] = [:]
    var monthlyChange: [String: Double] = [:]
    var weeklyChange: [String: Double] = [:]
    var valuation = Valuation()
    var pricingQueue: [String] = []
    var pricingActive = false
    var pricingPausedUntil: Date?

    // MARK: Stars and history

    var starred: Set<String> = []
    var snapshots: [NetWorthPoint] = []

    // MARK: Plumbing

    let client = SteamClient()
    let container: ModelContainer
    @ObservationIgnored var priceHistory: [String: [PricePoint]] = [:]
    @ObservationIgnored var inventoryRecords: [String: CachedInventory] = [:]
    @ObservationIgnored var priceRecords: [String: PriceRecord] = [:]
    @ObservationIgnored var failedPriceKeys: [String: Date] = [:]
    /// Keys the user is looking at right now; priced before anything else.
    @ObservationIgnored var priorityPriceKeys: [String] = []
    @ObservationIgnored var pricingTask: Task<Void, Never>?
    @ObservationIgnored var schedulerTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    static let settingsKey = "GaugeSettings"
    static let lastCheckKey = "GaugeLastInventoryCheck"

    init(container: ModelContainer) {
        self.container = container
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = AppSettings()
        }
        lastInventoryCheck = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
    }

    var modelContext: ModelContext { container.mainContext }

    var hasProfile: Bool { settings.profile != nil || settings.demoMode }
    var currency: SteamCurrency { settings.currency }

    var palette: Palette {
        if settings.matchSystemAppearance {
            return systemIsDark ? .classicDark : .classic
        }
        return Palette.named(settings.theme)
    }

    // MARK: - Lifecycle

    /// Loads the cache and starts background refresh. Safe to call more than once.
    func start() async {
        guard !started else { return }
        started = true
        if settings.demoMode {
            loadDemo()
            return
        }
        await loadCache()
        await web.refresh()
        startScheduler()
    }

    func loadCache() async {
        let context = modelContext
        let inventories = (try? context.fetch(FetchDescriptor<CachedInventory>())) ?? []
        var loadedContexts: [InventoryContext] = []
        var loadedItems: [String: [InventoryItem]] = [:]
        var statuses: [String: ContextStatus] = [:]
        for record in inventories {
            inventoryRecords[record.key] = record
            let payload = record.payload
            let items = await Task.detached(priority: .userInitiated) { () -> [InventoryItem] in
                (try? JSONDecoder().decode([InventoryItem].self, from: payload)) ?? []
            }.value
            loadedContexts.append(record.inventoryContext)
            loadedItems[record.key] = items
            statuses[record.key] = ContextStatus(syncedAt: record.syncedAt, newSinceLastSync: record.newSinceLastSync, error: record.lastError)
        }
        contexts = loadedContexts.sorted { $0.assetCount > $1.assetCount }
        itemsByContext = loadedItems
        contextStatus = statuses

        var loadedPrices: [String: PriceQuote] = [:]
        for record in (try? context.fetch(FetchDescriptor<PriceRecord>())) ?? [] {
            priceRecords[record.key] = record
            guard record.currencyCode == settings.currency.rawValue else { continue }
            loadedPrices[record.key] = record.quote
            priceHistory[record.key] = record.history
        }
        prices = loadedPrices

        let stars = (try? context.fetch(FetchDescriptor<StarredItem>())) ?? []
        starred = Set(stars.map(\.key))

        loadSnapshots()
        rebuildDerived()
        recomputeTrends()
    }

    /// Recomputes everything derived from the item lists.
    func rebuildDerived() {
        allItems = contexts.flatMap { itemsByContext[$0.id] ?? [] }
        ownership = SetOwnership(items: allItems)
        recomputeValuation()
    }

    func recomputeValuation() {
        valuation = Valuation.of(allItems, prices: prices)
    }

    func recomputeTrends() {
        var month: [String: Double] = [:]
        var week: [String: Double] = [:]
        let now = Date()
        for (key, history) in priceHistory {
            if let change = PriceTrend.change(history, days: 30, now: now) { month[key] = change }
            if let change = PriceTrend.change(history, days: 7, now: now) { week[key] = change }
        }
        monthlyChange = month
        weeklyChange = week
    }

    // MARK: - Settings

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        let previous = settings
        settings = updated
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
        if previous.currency != updated.currency {
            currencyChanged()
        } else if previous.refreshValuable != updated.refreshValuable
                    || previous.refreshFluff != updated.refreshFluff
                    || previous.fluffThresholdCents != updated.fluffThresholdCents {
            rebuildPricingQueue()
            ensurePricing()
        }
    }

    /// A two-way binding into one setting, saving on every change.
    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in self.updateSettings { $0[keyPath: keyPath] = newValue } }
        )
    }

    // MARK: - Lookups

    func items(in contextKey: String?) -> [InventoryItem] {
        guard let contextKey else { return allItems }
        return itemsByContext[contextKey] ?? []
    }

    func context(for key: String?) -> InventoryContext? {
        contexts.first { $0.id == key }
    }

    func item(withID id: String?) -> InventoryItem? {
        guard let id else { return nil }
        for items in itemsByContext.values {
            if let match = items.first(where: { $0.id == id }) { return match }
        }
        return nil
    }

    func quote(for item: InventoryItem) -> PriceQuote? { prices[item.priceKey] }

    func facts() -> InventoryFacts {
        InventoryFacts(
            prices: prices,
            starred: starred,
            fluffThresholdCents: settings.fluffThresholdCents,
            weeklyChange: weeklyChange,
            ownership: ownership
        )
    }

    func contextValuation(_ contextKey: String) -> Valuation {
        Valuation.of(itemsByContext[contextKey] ?? [], prices: prices)
    }

    /// The oldest price check among an inventory's priced items.
    func oldestPriceCheck(in contextKey: String) -> Date? {
        (itemsByContext[contextKey] ?? []).lazy
            .filter(\.marketable)
            .compactMap { self.prices[$0.priceKey]?.checkedAt }
            .min()
    }

    // MARK: - Stars

    func isStarred(_ item: InventoryItem) -> Bool { starred.contains(item.id) }

    func toggleStar(_ item: InventoryItem) {
        let context = modelContext
        if starred.contains(item.id) {
            starred.remove(item.id)
            let key = item.id
            let descriptor = FetchDescriptor<StarredItem>(predicate: #Predicate<StarredItem> { $0.key == key })
            for record in (try? context.fetch(descriptor)) ?? [] { context.delete(record) }
        } else {
            starred.insert(item.id)
            context.insert(StarredItem(key: item.id))
        }
        try? context.save()
    }

    // MARK: - Profile

    /// Resolves what the user typed and loads that profile's inventories.
    /// Returns an error message to show, or nil on success.
    func connect(to input: String) async -> String? {
        guard let reference = ProfileReference.parse(input) else {
            return "That doesn't look like a Steam profile link, custom URL, or SteamID64."
        }
        syncPhase = .resolving
        do {
            let profile = try await client.profile(reference)
            syncPhase = .idle
            guard profile.isPublic else {
                return "\(profile.personaName)'s profile is private. Gauge can only read public inventories."
            }
            if settings.profile?.steamID64 != profile.steamID64 {
                clearLocalData(keepSettings: true)
            }
            updateSettings {
                $0.profile = profile
                $0.demoMode = false
            }
            started = true
            await syncInventories(force: true)
            await web.refresh()
            startScheduler()
            return nil
        } catch {
            syncPhase = .idle
            return error.localizedDescription
        }
    }

    func enterDemo() {
        clearLocalData(keepSettings: true)
        updateSettings { $0.demoMode = true }
        started = true
        loadDemo()
    }

    /// Forgets the profile and everything cached for it.
    func signOutOfProfile() {
        clearLocalData(keepSettings: true)
        updateSettings {
            $0.profile = nil
            $0.demoMode = false
        }
        started = false
        tab = .portfolio
    }

    /// Deletes the inventory cache, prices, stars, snapshots and listing log.
    func clearLocalData(keepSettings: Bool) {
        pricingTask?.cancel()
        pricingTask = nil
        schedulerTask?.cancel()
        schedulerTask = nil
        let context = modelContext
        try? context.delete(model: CachedInventory.self)
        try? context.delete(model: PriceRecord.self)
        try? context.delete(model: NetWorthSnapshot.self)
        try? context.delete(model: StarredItem.self)
        try? context.delete(model: ListingRecord.self)
        try? context.save()
        inventoryRecords = [:]
        priceRecords = [:]
        priceHistory = [:]
        failedPriceKeys = [:]
        priorityPriceKeys = []
        contexts = []
        itemsByContext = [:]
        contextStatus = [:]
        prices = [:]
        starred = []
        snapshots = []
        pricingQueue = []
        pricingPausedUntil = nil
        lastInventoryCheck = nil
        UserDefaults.standard.removeObject(forKey: Self.lastCheckKey)
        browser.reset()
        cleanup.reset()
        rebuildDerived()
        recomputeTrends()
        if !keepSettings {
            settings = AppSettings()
            UserDefaults.standard.removeObject(forKey: Self.settingsKey)
        }
    }

    // MARK: - Demo

    func loadDemo() {
        let demo = DemoData.make()
        contexts = demo.contexts.sorted { $0.assetCount > $1.assetCount }
        itemsByContext = demo.itemsByContext
        let now = Date()
        contextStatus = Dictionary(uniqueKeysWithValues: demo.contexts.map {
            ($0.id, ContextStatus(syncedAt: now.addingTimeInterval(-3_600), newSinceLastSync: $0.appID == 570 ? 2 : 0, error: nil))
        })
        prices = demo.prices
        priceHistory = demo.history
        let stars = (try? modelContext.fetch(FetchDescriptor<StarredItem>())) ?? []
        starred = stars.isEmpty ? Set(demo.starred) : Set(stars.map(\.key))
        snapshots = demo.snapshots.map { NetWorthPoint(day: $0.day, buyerCents: $0.buyerCents, sellerCents: $0.sellerCents) }
        lastInventoryCheck = now.addingTimeInterval(-3_600)
        pricingQueue = []
        rebuildDerived()
        recomputeTrends()
    }
}
