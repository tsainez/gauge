//
//  ListingViews.swift
//  gauge
//
//  The Sell sheet (from Inventory) and the listing rows and progress list
//  shared with Clean up.
//

import SwiftUI

struct SellSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let items: [InventoryItem]
    @State private var strategy: ListingPriceStrategy = .lowestListing
    @State private var customPrice = ""
    @State private var run: ListingRun?
    @State private var showingSignIn = false

    var body: some View {
        let p = model.palette
        let plan = jobs()
        VStack(alignment: .leading, spacing: 12) {
            Text(items.count == 1 ? "Sell \(items[0].name)" : "Sell \(items.count.formatted()) items")
                .font(p.font(15, .bold))

            if let run {
                ListingProgressList(run: run)
                    .frame(minHeight: 220)
            } else {
                pricingControls(p)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(plan.jobs) { job in
                            ListingRow(item: job.item, buyerCents: job.buyerCents, sellerCents: job.sellerCents, status: nil, palette: p, currency: model.currency)
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 320)
                .classicInset(p)
                if !plan.notes.isEmpty {
                    Text(plan.notes.joined(separator: " "))
                        .font(p.font(11.5))
                        .foregroundStyle(p.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            summary(run?.jobs ?? plan.jobs, p)
            SignInStatus(showingSignIn: $showingSignIn)

            if let message = run?.haltMessage {
                Text(message)
                    .foregroundStyle(p.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(run?.isComplete == true ? "Done" : "Close") { dismiss() }
                    .classicButton(.secondary, p)
                    .disabled(run?.isRunning == true)
                Spacer()
                if let run {
                    if run.isRunning {
                        Button("Stop after this one") { run.stopRequested = true }
                            .classicButton(.secondary, p)
                    } else if !run.isComplete {
                        Button("Resume listing") { Task { await model.runListing(run) } }
                            .classicButton(.primary, p)
                    }
                } else {
                    Button("List \(plan.jobs.count.formatted()) item\(plan.jobs.count == 1 ? "" : "s")") {
                        let newRun = ListingRun(jobs: plan.jobs)
                        run = newRun
                        Task { await model.runListing(newRun) }
                    }
                    .classicButton(.primary, p)
                    .disabled(plan.jobs.isEmpty)
                }
            }
        }
        .padding(18)
        .frame(width: 560)
        .background(p.window)
        .foregroundStyle(p.text)
        .font(p.font(12.5))
        .sheet(isPresented: $showingSignIn) {
            SteamSignInSheet(purpose: .listing).environment(model)
        }
        .onAppear {
            strategy = model.settings.cleanupRules.pricing
            model.prioritizePricing(for: items)
        }
    }

    @ViewBuilder
    private func pricingControls(_ p: Palette) -> some View {
        if items.count == 1, let item = items.first {
            HStack(spacing: 8) {
                Text("Buyer pays")
                TextField(Money.format(defaultBuyer(item) ?? 3, model.currency), text: $customPrice)
                    .classicField(p)
                    .frame(width: 110)
                Text("Leave empty to use the \(strategy.label).")
                    .font(p.font(11.5))
                    .foregroundStyle(p.secondaryText)
            }
        } else {
            HStack(spacing: 8) {
                Text("Price at")
                PopoverPicker(
                    title: strategy.label,
                    options: ListingPriceStrategy.allCases.map { PickerOption(value: $0, label: $0.label) },
                    selection: strategy,
                    palette: p
                ) { strategy = $0 }
                Text("never below \(Money.format(model.settings.cleanupRules.floorCents, model.currency))")
                    .foregroundStyle(p.secondaryText)
            }
        }
    }

    private func summary(_ jobs: [ListingRun.Job], _ p: Palette) -> some View {
        let buyer = jobs.reduce(0) { $0 + $1.buyerCents * $1.item.amount }
        let seller = jobs.reduce(0) { $0 + $1.sellerCents * $1.item.amount }
        return HStack {
            Text("Buyers pay \(Money.format(buyer, model.currency))")
            Spacer()
            Text("You receive \(Money.format(seller, model.currency)) after fees")
                .foregroundStyle(p.accent)
        }
        .font(p.font(12.5, .bold))
    }

    private func defaultBuyer(_ item: InventoryItem) -> Int? {
        var rules = model.settings.cleanupRules
        rules.pricing = strategy
        return model.quote(for: item).flatMap { CleanupPlanner.listingPrice(for: $0, rules: rules) }
    }

    private func jobs() -> (jobs: [ListingRun.Job], notes: [String]) {
        var result: [ListingRun.Job] = []
        var unpriced = 0
        var starred = 0
        let custom = items.count == 1 ? PriceParser.cents(from: customPrice) : nil
        for item in items where item.marketable {
            if model.settings.protectStarred && model.isStarred(item) {
                starred += 1
                continue
            }
            guard let buyer = custom.map({ max($0, SteamFees.floorBuyerCents) }) ?? defaultBuyer(item) else {
                unpriced += 1
                continue
            }
            result.append(ListingRun.Job(item: item, buyerCents: buyer, sellerCents: SteamFees.sellerReceives(buyerPays: buyer)))
        }
        var notes: [String] = []
        if unpriced > 0 { notes.append("\(unpriced) item\(unpriced == 1 ? " has" : "s have") no price yet and will be skipped; Gauge is checking now.") }
        if starred > 0 { notes.append("\(starred) starred item\(starred == 1 ? " is" : "s are") protected and won't be listed.") }
        notes.append("Every listing still needs your confirmation in the Steam Mobile app.")
        return (result, notes)
    }
}

/// Signed-in state for selling, with a button to sign in.
struct SignInStatus: View {
    @Environment(AppModel.self) private var model
    @Binding var showingSignIn: Bool

    var body: some View {
        let p = model.palette
        HStack(spacing: 8) {
            Image(systemName: model.web.isSignedIn ? "checkmark.seal.fill" : "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(model.web.isSignedIn ? p.positive : p.accent)
            if model.settings.demoMode {
                Text("Demo mode: listings are simulated only up to this point.")
                    .foregroundStyle(p.secondaryText)
            } else if model.web.isSignedIn {
                Text("Signed in with Steam")
                    .foregroundStyle(p.secondaryText)
            } else if model.web.status.hasExpired {
                Text("Your Steam sign-in ran out. Sign in again to list items.")
                    .foregroundStyle(p.negative)
            } else {
                Text("Sign in with Steam to list items. Browsing and prices don't need it.")
                    .foregroundStyle(p.secondaryText)
            }
            Spacer()
            if !model.settings.demoMode {
                Button(model.web.isSignedIn ? "Switch account…" : "Sign in…") {
                    Task {
                        // Steam's page skips the form while a session exists, so end it first.
                        if model.web.isSignedIn { await model.web.signOut() }
                        showingSignIn = true
                    }
                }
                .classicButton(.secondary, p)
            }
        }
        .font(p.font(12))
        .padding(10)
        .classicInset(p)
    }
}

struct ListingProgressList: View {
    @Environment(AppModel.self) private var model
    let run: ListingRun

    var body: some View {
        let p = model.palette
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(run.listedCount.formatted()) listed · \(run.remainingCount.formatted()) to go\(run.failedCount > 0 ? " · \(run.failedCount) failed" : "")")
                Spacer()
                if run.isRunning { ProgressView().controlSize(.small) }
            }
            .font(p.font(12, .bold))
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(run.jobs) { job in
                        ListingRow(
                            item: job.item,
                            buyerCents: job.buyerCents,
                            sellerCents: job.sellerCents,
                            status: job.state,
                            palette: p,
                            currency: model.currency
                        )
                    }
                }
            }
            .classicInset(p)
        }
    }
}

struct ListingRow: View {
    let item: InventoryItem
    /// Copies listed at this price, shown as "×2".
    var count = 1
    let buyerCents: Int
    /// What the seller receives for one.
    let sellerCents: Int
    let status: ListingRun.JobState?
    let palette: Palette
    let currency: SteamCurrency

    var body: some View {
        let p = palette
        HStack(spacing: 8) {
            if let status {
                Image(systemName: symbol(status))
                    .foregroundStyle(color(status))
                    .frame(width: 14)
            }
            ItemArtwork(item: item, size: 96, palette: p)
                .frame(width: 40, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: p.bevels ? 0 : 4))
                .overlay(alignment: .bottom) { p.rarity(item).frame(height: 2) }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.name).lineLimit(1)
                    if count > 1 {
                        Text("×\(count)")
                            .font(p.font(11, .bold))
                            .foregroundStyle(p.accent)
                    }
                    if let summary = item.skin?.summary {
                        Text(summary)
                            .font(p.font(11))
                            .foregroundStyle(p.secondaryText)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                if let status, let detail = detail(status) {
                    Text(detail)
                        .font(p.font(11))
                        .foregroundStyle(color(status))
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(Money.format(buyerCents, currency)).foregroundStyle(p.accent)
            Text("→ \(Money.format(sellerCents * count, currency))")
                .foregroundStyle(p.secondaryText)
                .frame(width: 72, alignment: .trailing)
        }
        .font(p.font(12))
        .foregroundStyle(p.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { p.gridLine.frame(height: 1) }
    }

    private func symbol(_ state: ListingRun.JobState) -> String {
        switch state {
        case .queued: "circle"
        case .checkingPrice, .listing: "arrow.triangle.2.circlepath"
        case .listed(let needsConfirmation): needsConfirmation ? "iphone" : "checkmark.circle.fill"
        case .skipped: "minus.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func color(_ state: ListingRun.JobState) -> Color {
        switch state {
        case .listed: palette.positive
        case .failed: palette.negative
        case .skipped: palette.mutedText
        default: palette.secondaryText
        }
    }

    private func detail(_ state: ListingRun.JobState) -> String? {
        switch state {
        case .queued: nil
        case .checkingPrice: "Re-checking the price…"
        case .listing: "Listing…"
        case .listed(let needsConfirmation): needsConfirmation ? "Listed · confirm in the Steam Mobile app" : "Listed"
        case .skipped(let reason): reason
        case .failed(let message): message
        }
    }
}
