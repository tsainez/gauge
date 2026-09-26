//
//  GaugeApp.swift
//  gauge
//
//  Created by Tony Sainez on 9/25/26.
//

import AppKit
import SwiftData
import SwiftUI

@main
struct GaugeApp: App {
    @State private var model: AppModel

    init() {
        // Item artwork is fetched with AsyncImage, which goes through the shared cache.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1_024 * 1_024, diskCapacity: 512 * 1_024 * 1_024, directory: nil)
        _model = State(initialValue: AppModel(container: GaugeSchema.makeContainer()))
    }

    var body: some Scene {
        Window("Gauge", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1_100, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_280, height: 800)
        .modelContainer(model.container)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Inventory") {
                Button("Refresh Inventories") {
                    Task { await model.syncInventories(force: true) }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.settings.demoMode || model.settings.profile == nil)

                Button("Price Everything Now") {
                    model.rebuildPricingQueue()
                    model.ensurePricing()
                }
                .disabled(model.settings.demoMode || model.settings.profile == nil)

                Divider()

                Button("Exit Demo Mode") {
                    Task { await model.exitDemo() }
                }
                .disabled(!model.settings.demoMode)
            }
        }

        MenuBarExtra(isInserted: model.binding(\.showMenuBarNetWorth)) {
            MenuBarContent()
                .environment(model)
        } label: {
            Text(model.valuation.buyerCents > 0 ? Money.compact(model.valuation.buyerCents, model.currency) : "Gauge")
        }
    }
}

/// The menu shown from the menu bar net worth.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Marketable net worth: \(Money.format(model.valuation.buyerCents, model.currency))")
        Text("After fees: \(Money.format(model.valuation.sellerCents, model.currency))")
        if model.valuation.unpricedCount > 0 {
            Text("\(model.valuation.unpricedCount.formatted()) items waiting for prices")
        }
        Divider()
        Button("Open Gauge") {
            openWindow(id: "main")
            NSApplication.shared.activate()
        }
        Button("Quit Gauge") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
