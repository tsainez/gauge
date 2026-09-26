//
//  AppSettings.swift
//  gauge
//

import Foundation

nonisolated enum ThemeChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic
    case classicDark
    case modern

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .classicDark: "Classic Dark"
        case .modern: "Modern"
        }
    }
}

nonisolated enum RefreshInterval: Int, Codable, CaseIterable, Identifiable, Sendable {
    case hourly = 3_600
    case sixHours = 21_600
    case daily = 86_400
    case weekly = 604_800
    case manually = 0

    var id: Int { rawValue }
    var seconds: TimeInterval? { rawValue == 0 ? nil : TimeInterval(rawValue) }

    var title: String {
        switch self {
        case .hourly: "Every hour"
        case .sixHours: "Every 6 hours"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .manually: "Manually"
        }
    }
}

/// Everything on the Settings tab plus the saved profile. Stored as JSON in
/// UserDefaults. Every field decodes with a default so adding a setting never
/// resets the others.
nonisolated struct AppSettings: Codable, Equatable, Sendable {
    var theme: ThemeChoice = .classic
    var matchSystemAppearance = false
    var currency: SteamCurrency = .usd
    var fluffThresholdCents = 5
    var refreshValuable: RefreshInterval = .daily
    var refreshFluff: RefreshInterval = .weekly
    var showAfterFees = true
    var hideUnmarketable = true
    var protectStarred = true
    var showMenuBarNetWorth = false
    var inventoryCheck: RefreshInterval = .sixHours
    var cleanupRules = CleanupRules()
    var demoMode = false
    var profile: ProfileSummary?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        theme = (try? c.decodeIfPresent(ThemeChoice.self, forKey: .theme)) ?? d.theme
        matchSystemAppearance = (try? c.decodeIfPresent(Bool.self, forKey: .matchSystemAppearance)) ?? d.matchSystemAppearance
        currency = (try? c.decodeIfPresent(SteamCurrency.self, forKey: .currency)) ?? d.currency
        fluffThresholdCents = (try? c.decodeIfPresent(Int.self, forKey: .fluffThresholdCents)) ?? d.fluffThresholdCents
        refreshValuable = (try? c.decodeIfPresent(RefreshInterval.self, forKey: .refreshValuable)) ?? d.refreshValuable
        refreshFluff = (try? c.decodeIfPresent(RefreshInterval.self, forKey: .refreshFluff)) ?? d.refreshFluff
        showAfterFees = (try? c.decodeIfPresent(Bool.self, forKey: .showAfterFees)) ?? d.showAfterFees
        hideUnmarketable = (try? c.decodeIfPresent(Bool.self, forKey: .hideUnmarketable)) ?? d.hideUnmarketable
        protectStarred = (try? c.decodeIfPresent(Bool.self, forKey: .protectStarred)) ?? d.protectStarred
        showMenuBarNetWorth = (try? c.decodeIfPresent(Bool.self, forKey: .showMenuBarNetWorth)) ?? d.showMenuBarNetWorth
        inventoryCheck = (try? c.decodeIfPresent(RefreshInterval.self, forKey: .inventoryCheck)) ?? d.inventoryCheck
        cleanupRules = (try? c.decodeIfPresent(CleanupRules.self, forKey: .cleanupRules)) ?? d.cleanupRules
        demoMode = (try? c.decodeIfPresent(Bool.self, forKey: .demoMode)) ?? d.demoMode
        profile = try? c.decodeIfPresent(ProfileSummary.self, forKey: .profile)
    }

    /// How long a price stays fresh. Cheap items change little and there are many of them.
    func priceLifetime(forValue cents: Int?) -> TimeInterval? {
        guard let cents else { return refreshValuable.seconds }
        return cents < fluffThresholdCents ? refreshFluff.seconds : refreshValuable.seconds
    }
}
