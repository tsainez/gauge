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
    /// Every request to Steam this session, and the log file behind "Export log".
    let network: NetworkActivity

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

    let client: SteamClient
    let container: ModelContainer
    /// Where settings and the last inventory check are saved. Tests pass their own suite.
    let defaults: UserDefaults
    @ObservationIgnored var priceHistory: [String: [PricePoint]] = [:]
    @ObservationIgnored var inventoryRecords: [String: CachedInventory] = [:]
    @ObservationIgnored var priceRecords: [String: PriceRecord] = [:]
    @ObservationIgnored var failedPriceKeys: [String: Date] = [:]
    /// Keys the user is looking at right now; priced before anything else.
    @ObservationIgnored var priorityPriceKeys: [String] = []
    /// When each game was last swept for bulk prices, so a sweep that found little isn't repeated every run.
    @ObservationIgnored var marketSweptAt: [Int: Date] = [:]
    /// Set when Steam's Market search answered in another currency; bulk pricing then waits for a currency change.
    @ObservationIgnored var marketSweepUnavailable = false
    @ObservationIgnored var pricingTask: Task<Void, Never>?
    @ObservationIgnored var schedulerTask: Task<Void, Never>?
    /// Whether this launch already checked inventories cached by an older version.
    @ObservationIgnored var checkedOutdatedInventories = false
    @ObservationIgnored private var started = false

    static let settingsKey = "GaugeSettings"
    static let lastCheckKey = "GaugeLastInventoryCheck"

    /// - Parameter networkLog: where requests are logged; tests pass nil to keep the app's log clean.
    init(
        container: ModelContainer,
        defaults: UserDefaults = .standard,
        client: SteamClient = SteamClient(),
        networkLog: NetworkLogFile? = NetworkLogFile.standard()
    ) {
        self.container = container
        self.defaults = defaults
        self.client = client
        network = NetworkActivity(file: networkLog)
        if let data = defaults.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = AppSettings()
        }
        lastInventoryCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
        web.onActivity = { [network] event in network.record(event) }
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
        await connectNetworkLog()
        guard !started else { return }
        started = true
        if settings.demoMode {
            loadDemo()
            return
        }
        await loadCache()
        // A quick look at the cookies; the first sync renews the session if it needs it.
        await web.refresh(renewIfNeeded: false)
        startScheduler()
    }

    /// Sends every request the client makes to the network log.
    func connectNetworkLog() async {
        let network = network
        await client.setMonitor { event in
            Task { @MainActor in network.record(event) }
        }
    }

    func loadCache() async {
        lastInventoryCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
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
        loadCleanupOverrides()
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
            defaults.set(data, forKey: Self.settingsKey)
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
        guard !settings.demoMode else {
            // Demo stars live in memory so they never mix with the real profile's.
            if starred.contains(item.id) { starred.remove(item.id) } else { starred.insert(item.id) }
            return
        }
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

    /// Stars or unstars several items at once, saving once.
    func setStarred(_ items: [InventoryItem], _ isStarred: Bool) {
        let changing = items.filter { starred.contains($0.id) != isStarred }
        guard !changing.isEmpty else { return }
        guard !settings.demoMode else {
            for item in changing {
                if isStarred { starred.insert(item.id) } else { starred.remove(item.id) }
            }
            return
        }
        let context = modelContext
        if isStarred {
            for item in changing {
                starred.insert(item.id)
                context.insert(StarredItem(key: item.id))
            }
        } else {
            let removingKeys = changing.map(\.id)
            for key in removingKeys {
                starred.remove(key)
            }
            let descriptor = FetchDescriptor<StarredItem>(predicate: #Predicate<StarredItem> { removingKeys.contains($0.key) })
            for record in (try? context.fetch(descriptor)) ?? [] {
                context.delete(record)
            }
        }
        try? context.save()
    }

    // MARK: - Profile

    /// Shows the account the user just signed in to Steam with.
    /// Returns an error message to show, or nil on success.
    func connectSignedInAccount() async -> String? {
        await web.refresh(renewIfNeeded: false)
        guard let steamID = web.signedInSteamID else {
            return "Steam didn't finish signing you in. Try again."
        }
        return await connect(to: steamID)
    }

    /// Resolves what the user typed and loads that profile's inventories.
    /// Returns an error message to show, or nil on success.
    func connect(to input: String) async -> String? {
        guard let reference = ProfileReference.parse(input) else {
            return "That doesn't look like a Steam profile link, custom URL, or SteamID64."
        }
        syncPhase = .resolving
        await web.refresh(renewIfNeeded: false)
        do {
            let profile = try await client.profile(reference)
            syncPhase = .idle
            if let problem = profile.accessProblem(signedInSteamID: web.signedInSteamID) {
                return problem
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
            startScheduler()
            return nil
        } catch {
            syncPhase = .idle
            return error.localizedDescription
        }
    }

    /// Shows the demo inventory. The real profile's cache stays on disk untouched,
    /// so leaving demo mode picks up exactly where it left off.
    func enterDemo() {
        resetInMemoryState()
        updateSettings { $0.demoMode = true }
        started = true
        tab = .portfolio
        loadDemo()
    }

    /// Leaves demo mode: back to the saved profile if there is one, otherwise to onboarding.
    func exitDemo() async {
        guard settings.demoMode else { return }
        resetInMemoryState()
        updateSettings { $0.demoMode = false }
        tab = .portfolio
        started = false
        guard settings.profile != nil else { return }
        await start()
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
        let context = modelContext
        try? context.delete(model: CachedInventory.self)
        try? context.delete(model: PriceRecord.self)
        try? context.delete(model: NetWorthSnapshot.self)
        try? context.delete(model: StarredItem.self)
        try? context.delete(model: ListingRecord.self)
        try? context.save()
        defaults.removeObject(forKey: Self.lastCheckKey)
        defaults.removeObject(forKey: Self.overridesKey)
        network.clear()
        resetInMemoryState()
        if !keepSettings {
            settings = AppSettings()
            defaults.removeObject(forKey: Self.settingsKey)
        }
    }

    /// Stops background work and forgets everything loaded in memory, leaving the cache on disk alone.
    func resetInMemoryState() {
        pricingTask?.cancel()
        pricingTask = nil
        pricingActive = false
        schedulerTask?.cancel()
        schedulerTask = nil
        syncPhase = .idle
        notice = nil
        inventoryRecords = [:]
        priceRecords = [:]
        priceHistory = [:]
        failedPriceKeys = [:]
        priorityPriceKeys = []
        marketSweptAt = [:]
        marketSweepUnavailable = false
        contexts = []
        itemsByContext = [:]
        contextStatus = [:]
        prices = [:]
        starred = []
        snapshots = []
        pricingQueue = []
        pricingPausedUntil = nil
        lastInventoryCheck = nil
        browser.reset()
        cleanup.reset()
        rebuildDerived()
        recomputeTrends()
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
        starred = Set(demo.starred)
        snapshots = demo.snapshots.map { NetWorthPoint(day: $0.day, buyerCents: $0.buyerCents, sellerCents: $0.sellerCents) }
        lastInventoryCheck = now.addingTimeInterval(-3_600)
        pricingQueue = []
        rebuildDerived()
        recomputeTrends()
    }
}
