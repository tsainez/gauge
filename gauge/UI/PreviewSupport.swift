//
//  PreviewSupport.swift
//  gauge
//
//  Xcode previews for each tab, backed by the demo inventory and an in-memory store.
//

import SwiftUI

#if DEBUG
extension AppModel {
    /// A model showing the demo inventory without touching the real cache or settings.
    static func preview(tab: AppTab = .portfolio, theme: ThemeChoice = .modern) -> AppModel {
        let model = AppModel(container: GaugeSchema.makeContainer(inMemory: true), networkLog: nil)
        model.settings = AppSettings()
        model.settings.demoMode = true
        model.settings.theme = theme
        model.loadDemo()
        model.tab = tab
        if tab == .inventory {
            model.browser.contextKey = model.contexts.first?.id
            model.browser.focusedID = model.allItems.first { $0.name == "Song of the Solstice Neck" }?.id
        }
        if tab == .settings {
            // Demo mode sends nothing, so show what a few real requests look like.
            let now = Date()
            let base = "https://steamcommunity.com"
            for event in [
                NetworkEvent(kind: .profile, startedAt: now.addingTimeInterval(-600), url: base + "/profiles/76561190000000000/inventory/", signedIn: true, duration: 0.62, status: 200, bytes: 48_000),
                NetworkEvent(kind: .inventory, startedAt: now.addingTimeInterval(-590), url: base + "/inventory/76561190000000000/570/2?l=english&count=2000", signedIn: true, waited: 1.4, duration: 1.9, status: 200, bytes: 2_400_000),
                NetworkEvent(kind: .market, startedAt: now.addingTimeInterval(-120), url: base + "/market/priceoverview/?appid=570&currency=1&market_hash_name=Crest", waited: 3.1, duration: 0.41, status: 200, bytes: 88),
                NetworkEvent(kind: .market, startedAt: now.addingTimeInterval(-30), url: base + "/market/priceoverview/?appid=570&currency=1&market_hash_name=Dust", waited: 3.2, duration: 0.2, status: 429, outcome: .rateLimited(retryAfter: 60)),
            ] {
                model.network.record(event)
            }
        }
        return model
    }
}

#Preview("Portfolio") {
    RootView()
        .environment(AppModel.preview(tab: .portfolio))
        .frame(width: 1_280, height: 800)
}

#Preview("Inventory") {
    RootView()
        .environment(AppModel.preview(tab: .inventory))
        .frame(width: 1_280, height: 800)
}

#Preview("Clean up") {
    RootView()
        .environment(AppModel.preview(tab: .cleanup))
        .frame(width: 1_280, height: 800)
}

#Preview("Settings") {
    RootView()
        .environment(AppModel.preview(tab: .settings))
        .frame(width: 1_280, height: 800)
}

#Preview("Clean up, Classic") {
    RootView()
        .environment(AppModel.preview(tab: .cleanup, theme: .classic))
        .frame(width: 1_280, height: 800)
}
#endif
