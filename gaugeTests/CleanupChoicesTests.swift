//
//  CleanupChoicesTests.swift
//  gaugeTests
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftData
import Testing
@testable import gauge

@MainActor
struct CleanupChoicesTests {
    static let dota = InventoryContext(appID: 570, contextID: "2", name: "Dota 2", iconURL: nil, assetCount: 2)
    let items = [CleanupPlannerTests.item("1", "Crest"), CleanupPlannerTests.item("2", "Dust")]

    func makeModel(_ defaults: UserDefaults) -> AppModel {
        let client = SteamClient(configuration: OfflineSteam.configuration(), intervalScale: 0)
        let model = AppModel(container: GaugeSchema.makeContainer(inMemory: true), defaults: defaults, client: client, networkLog: nil)
        model.updateSettings { $0.profile = DemoModeTests.profile }
        return model
    }

    func load(_ items: [InventoryItem], into model: AppModel) {
        model.contexts = [Self.dota]
        model.itemsByContext = [Self.dota.id: items]
        model.rebuildDerived()
    }

    func withDefaults(_ body: (UserDefaults) async -> Void) async {
        let suite = "GaugeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        await body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func movesAreRememberedUntilTheItemLeaves() async {
        await withDefaults { defaults in
            let model = makeModel(defaults)
            load(items, into: model)
            // Unpriced items stay in Keep by rule, so Sell is a real move.
            model.moveCleanupItems(["570_2_1", "570_2_2"], to: .sell)
            #expect(model.cleanup.overrides.count == 2)

            let relaunched = makeModel(defaults)
            load(Array(items.prefix(1)), into: relaunched)
            relaunched.loadCleanupOverrides()
            // Dust has left the inventory, so its choice is forgotten.
            #expect(relaunched.cleanup.overrides == ["570_2_1": .sell])
        }
    }

    @Test func movesCanBeUndoneAndRedone() async {
        await withDefaults { defaults in
            let model = makeModel(defaults)
            load(items, into: model)
            let undo = UndoManager()
            undo.groupsByEvent = false
            undo.beginUndoGrouping()
            model.moveCleanupItems(["570_2_1"], to: .sell, undoManager: undo)
            undo.endUndoGrouping()
            #expect(undo.undoActionName == "Move to Sell")

            undo.undo()
            #expect(model.cleanup.overrides.isEmpty)
            undo.redo()
            #expect(model.cleanup.overrides == ["570_2_1": .sell])

            // Moving it back to where the rules put it needs no override.
            model.moveCleanupItems(["570_2_1"], to: .keep)
            #expect(model.cleanup.overrides.isEmpty)

            model.moveCleanupItems(["570_2_2"], to: .review)
            model.resetCleanupOverrides()
            #expect(model.cleanup.overrides.isEmpty)
        }
    }

    @Test func demoChoicesAreNeverSaved() async {
        await withDefaults { defaults in
            let model = makeModel(defaults)
            model.enterDemo()
            let kept = model.cleanupPlan(contextKey: nil).entries(in: .keep).first
            model.moveCleanupItems([kept?.item.id ?? ""], to: .sell)
            #expect(model.cleanup.overrides.count == 1)
            #expect(defaults.dictionary(forKey: AppModel.overridesKey) == nil)
        }
    }
}
