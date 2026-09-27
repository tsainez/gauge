//
//  Sessions.swift
//  gauge
//
//  UI state that outlives a single view: what the Inventory tab is showing,
//  where the user is in Clean up, and the progress of a listing run.
//

import Foundation
import Observation

@Observable
final class InventoryBrowser {
    var contextKey: String?
    var query = InventoryQuery(quick: [.marketable])
    var selection: Set<String> = []
    var focusedID: String?
    /// Sidebar sections that are open.
    var expanded: Set<String> = ["Quick", "Rarity"]
    /// Sections showing every value instead of the first few.
    var showingAll: Set<String> = []
    var sectionSearch: [String: String] = [:]

    func reset() {
        contextKey = nil
        query = InventoryQuery(quick: [.marketable])
        selection = []
        focusedID = nil
    }

    /// Opens the Inventory tab on one game with a preset filter, used by Portfolio shortcuts.
    func show(contextKey: String?, quick: Set<QuickFilter> = [.marketable], search: String = "") {
        if let contextKey { self.contextKey = contextKey }
        query = InventoryQuery(search: search, quick: quick, tags: [:], sort: query.sort)
        selection = []
    }

    func toggleTag(_ category: String, _ value: String) {
        var values = query.tags[category] ?? []
        if values.contains(value) { values.remove(value) } else { values.insert(value) }
        query.tags[category] = values.isEmpty ? nil : values
    }

    func toggleQuick(_ filter: QuickFilter) {
        if query.quick.contains(filter) { query.quick.remove(filter) } else { query.quick.insert(filter) }
    }

    func clearFilters() {
        query.quick = []
        query.tags = [:]
        query.search = ""
    }
}

@Observable
final class CleanupSession {
    enum Step: Int, CaseIterable, Identifiable {
        case review = 1
        case list

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .review: "Review"
            case .list: "List and confirm"
            }
        }
    }

    var step: Step = .review
    var contextKey: String?
    /// Items the user moved to a different bucket by hand, by item id. Saved between launches.
    var overrides: [String: CleanupBucket] = [:]
    var run: ListingRun?

    /// The bucket the list shows, and how it's narrowed and ordered.
    var bucket: CleanupBucket = .sell
    var search = ""
    var filter: CleanupFilter?
    var sort: CleanupSort = .value
    /// Selected rows, by `CleanupRow.id`.
    var selection: Set<String> = []

    func reset() {
        step = .review
        contextKey = nil
        overrides = [:]
        run = nil
        bucket = .sell
        search = ""
        filter = nil
        selection = []
    }

    /// Call before rows leave the list. If any were selected, the row after them is
    /// selected instead, so ↓ and ⌫ can keep working through a list.
    func selectNext(afterRemoving removed: Set<String>, from rows: [CleanupRow]) {
        if selection.isDisjoint(with: removed) { return }
        selection = CleanupRow.nextID(after: removed, in: rows).map { [$0] } ?? []
    }

    /// Shows another bucket, clearing what only made sense in the last one.
    func show(_ bucket: CleanupBucket) {
        guard bucket != self.bucket else { return }
        self.bucket = bucket
        filter = nil
        selection = []
    }
}

/// One pass of listing items on the Market, shown on step 3 of Clean up and in the Sell sheet.
@Observable
final class ListingRun {
    enum JobState: Equatable {
        case queued
        case checkingPrice
        case listing
        case listed(needsConfirmation: Bool)
        case skipped(String)
        case failed(String)

        var isFinished: Bool {
            switch self {
            case .queued, .checkingPrice, .listing: false
            default: true
            }
        }
    }

    struct Job: Identifiable, Equatable {
        var item: InventoryItem
        var buyerCents: Int
        var sellerCents: Int
        var state: JobState = .queued
        var id: String { item.id }
    }

    var jobs: [Job]
    var isRunning = false
    var stopRequested = false
    /// Why the run stopped early, if it did.
    var haltMessage: String?

    init(entries: [CleanupEntry]) {
        jobs = entries.compactMap { entry in
            guard let buyer = entry.buyerCents, let seller = entry.sellerCents else { return nil }
            return Job(item: entry.item, buyerCents: buyer, sellerCents: seller)
        }
    }

    init(jobs: [Job]) {
        self.jobs = jobs
    }

    var listedCount: Int { jobs.filter { if case .listed = $0.state { true } else { false } }.count }
    var failedCount: Int { jobs.filter { if case .failed = $0.state { true } else { false } }.count }
    var remainingCount: Int { jobs.filter { !$0.state.isFinished }.count }
    var isComplete: Bool { !jobs.isEmpty && remainingCount == 0 }

    var buyerTotal: Int { jobs.reduce(0) { $0 + $1.buyerCents * $1.item.amount } }
    var sellerTotal: Int { jobs.reduce(0) { $0 + $1.sellerCents * $1.item.amount } }
    var listedSellerTotal: Int {
        jobs.reduce(0) { total, job in
            if case .listed = job.state { return total + job.sellerCents * job.item.amount }
            return total
        }
    }
}
