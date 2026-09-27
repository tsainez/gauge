//
//  AppModel+Cleanup.swift
//  gauge
//
//  The Clean up plan and the choices made on it. Moving an item by hand is
//  remembered between launches (per profile, never in demo mode) and can be
//  undone from the Edit menu.
//

import Foundation

extension AppModel {
    static let overridesKey = "GaugeCleanupOverrides"

    /// Builds the listing plan for Clean up, for one inventory or all of them.
    func cleanupPlan(contextKey: String?, overrides: [String: CleanupBucket]? = nil) -> CleanupPlan {
        var rules = settings.cleanupRules
        if settings.protectStarred { rules.keepStarred = true }
        return CleanupPlanner.plan(
            items: items(in: contextKey),
            prices: prices,
            trends: monthlyChange,
            starred: starred,
            overrides: overrides ?? cleanup.overrides,
            rules: rules,
            currency: settings.currency
        )
    }

    /// Moves items to a bucket by hand, or hands them back to the rules when `bucket` is nil.
    /// Moving an item to where the rules would put it anyway just clears its override.
    /// With the window's undo manager, the move can be undone.
    func moveCleanupItems(_ ids: [String], to bucket: CleanupBucket?, undoManager: UndoManager? = nil) {
        guard !ids.isEmpty else { return }
        var ruled = cleanup.overrides
        for id in ids { ruled[id] = nil }
        let natural = bucket == nil ? [:] : cleanupPlan(contextKey: cleanup.contextKey, overrides: ruled).bucketsByItem
        let changes = Dictionary(ids.map { id in (id, natural[id] == bucket ? nil : bucket) }, uniquingKeysWith: { first, _ in first })
        applyCleanupOverrides(changes, undoManager: undoManager, actionName: bucket.map { "Move to \($0.title)" } ?? "Use Rules")
    }

    /// Hands every item moved by hand back to the rules.
    func resetCleanupOverrides(undoManager: UndoManager? = nil) {
        let changes = Dictionary(cleanup.overrides.keys.map { ($0, CleanupBucket?.none) }, uniquingKeysWith: { first, _ in first })
        applyCleanupOverrides(changes, undoManager: undoManager, actionName: "Reset Clean Up")
    }

    /// Sets each item's bucket (nil removes the override) and registers the reverse change.
    private func applyCleanupOverrides(_ changes: [String: CleanupBucket?], undoManager: UndoManager?, actionName: String) {
        guard !changes.isEmpty else { return }
        var reverse: [String: CleanupBucket?] = [:]
        for (id, bucket) in changes {
            reverse.updateValue(cleanup.overrides[id], forKey: id)
            cleanup.overrides[id] = bucket
        }
        saveCleanupOverrides()
        guard let undoManager else { return }
        // The manager is the target so the handler doesn't capture it; undoing registers the redo.
        undoManager.registerUndo(withTarget: undoManager) { [self] manager in
            MainActor.assumeIsolated {
                self.applyCleanupOverrides(reverse, undoManager: manager, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
    }

    func saveCleanupOverrides() {
        guard !settings.demoMode else { return }
        defaults.set(cleanup.overrides.mapValues(\.rawValue), forKey: Self.overridesKey)
    }

    /// Restores the saved choices for items still in the inventory.
    func loadCleanupOverrides() {
        guard !settings.demoMode else { return }
        let saved = defaults.dictionary(forKey: Self.overridesKey) as? [String: String] ?? [:]
        cleanup.overrides = saved.compactMapValues(CleanupBucket.init(rawValue:))
        pruneCleanupOverrides()
    }

    /// Forgets choices for items that have left the inventory, for example after being listed.
    func pruneCleanupOverrides() {
        let known = Set(allItems.map(\.id))
        let kept = cleanup.overrides.filter { known.contains($0.key) }
        guard kept.count != cleanup.overrides.count else { return }
        cleanup.overrides = kept
        saveCleanupOverrides()
    }
}
