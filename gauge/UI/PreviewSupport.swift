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
    static func preview(tab: AppTab = .portfolio, theme: ThemeChoice = .classic) -> AppModel {
        let model = AppModel(container: GaugeSchema.makeContainer(inMemory: true))
        model.settings = AppSettings()
        model.settings.demoMode = true
        model.settings.theme = theme
        model.loadDemo()
        model.tab = tab
        if tab == .inventory {
            model.browser.contextKey = model.contexts.first?.id
            model.browser.focusedID = model.allItems.first { $0.name == "Song of the Solstice Neck" }?.id
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

#Preview("Settings, Modern") {
    RootView()
        .environment(AppModel.preview(tab: .settings, theme: .modern))
        .frame(width: 1_280, height: 800)
}
#endif
