//
//  RootView.swift
//  gauge
//

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = model.palette
        VStack(spacing: 0) {
            HeaderBar()
            if model.hasProfile {
                TabStrip()
                Group {
                    switch model.tab {
                    case .portfolio: PortfolioView()
                    case .inventory: InventoryView()
                    case .cleanup: CleanupView()
                    case .settings: SettingsView()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                WindowStatusBar()
            } else {
                OnboardingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(p.window)
        .foregroundStyle(p.text)
        .font(p.font(12.5))
        .ignoresSafeArea(edges: .top)
        .task { await model.start() }
        .onAppear { model.systemIsDark = colorScheme == .dark }
        .onChange(of: colorScheme) { _, scheme in
            model.systemIsDark = scheme == .dark
        }
    }
}

/// The custom title bar: app name on the left (after the window buttons), profile on the right.
struct HeaderBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.palette
        HStack(spacing: 12) {
            Text("GAUGE")
                .font(p.font(14, .bold))
                .foregroundStyle(p.accent)
                .padding(.leading, 84)
            if model.settings.demoMode {
                Text("DEMO DATA")
                    .font(p.font(10, .bold))
                    .foregroundStyle(p.onPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(p.primary)
            }
            Spacer()
            if let label = model.syncPhase.label {
                ProgressView().controlSize(.small)
                Text(label).foregroundStyle(p.secondaryText)
            }
            if let name = model.settings.demoMode ? "tony!!!" : model.settings.profile?.personaName {
                Text(name).foregroundStyle(p.text.opacity(0.9))
            }
        }
        .font(p.font(12.5))
        .padding(.trailing, 16)
        .frame(height: 40)
        .background(p.header)
        .overlay(alignment: .bottom) { p.bevelDark.frame(height: 1) }
    }
}

struct TabStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.palette
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button(tab.title) { model.tab = tab }
                    .classicButton(.tab(selected: model.tab == tab), p)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

/// The bottom strip. Each tab shows what matters for it, as in the storyboards.
struct WindowStatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.palette
        let content = texts
        StatusBar(leading: content.0, middle: content.1, trailing: content.2, palette: p)
    }

    private var texts: (String, String?, String?) {
        if let notice = model.notice {
            return (notice, nil, nil)
        }
        switch model.tab {
        case .portfolio:
            return (inventoryLine, pricingLine, "Stored locally")
        case .inventory:
            let status = model.contextStatus[model.browser.contextKey ?? ""]
            let newItems = status?.newSinceLastSync ?? 0
            let lead = newItems > 0 ? "Showing cached inventory · \(newItems) new item\(newItems == 1 ? "" : "s") since last sync" : "Showing cached inventory"
            return (lead, pricingLine, model.settings.protectStarred ? "Starred items are never sold by clean up" : nil)
        case .cleanup:
            let items = model.items(in: model.cleanup.contextKey)
            let hidden = items.reduce(0) { $0 + ($1.marketable ? 0 : 1) }
            let oldest = items.lazy.filter(\.marketable).compactMap { model.prices[$0.priceKey]?.checkedAt }.min()
            return ("Prices checked \(RelativeTime.short(oldest)) at the oldest", pricingLine, "\(hidden.formatted()) non-marketable items hidden")
        case .settings:
            return ("Changes save automatically", nil, nil)
        }
    }

    private var inventoryLine: String {
        if model.settings.demoMode { return "Demo inventory · nothing is sent to Steam" }
        if let label = model.syncPhase.label { return label }
        guard let checked = model.lastInventoryCheck else { return "Inventory not loaded yet" }
        return "Inventory cached · last checked \(checked.formatted(date: .omitted, time: .shortened))"
    }

    private var pricingLine: String? {
        if model.settings.demoMode { return nil }
        if let resume = model.pricingResumesAt {
            return "Pricing paused by Steam · resumes \(resume.formatted(date: .omitted, time: .shortened))"
        }
        let count = model.pricingQueue.count
        if count == 0 { return model.valuation.pricedCount > 0 ? "All prices up to date" : nil }
        return "Pricing queue: \(count.formatted()) item\(count == 1 ? "" : "s") · resumes automatically"
    }
}
