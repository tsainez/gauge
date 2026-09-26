//
//  CleanupView.swift
//  gauge
//
//  Sorts marketable items into Sell / Floor / Worth a look / Keep by rule,
//  lets the user move anything between buckets, then lists the Sell bucket
//  (and the floor items, if chosen) a few at a time.
//

import SwiftUI

struct CleanupView: View {
    @Environment(AppModel.self) private var model
    @State private var showingSignIn = false

    var body: some View {
        let p = model.palette
        let session = model.cleanup
        let plan = model.cleanupPlan(contextKey: session.contextKey)
        let rules = model.settings.cleanupRules
        let listings = plan.listings(sellFloorItems: rules.sellFloorItems)

        HStack(alignment: .top, spacing: 12) {
            sidebar(p)
                .frame(width: 236)
                .frame(maxHeight: .infinity, alignment: .top)
                .classicPanel(p)
            VStack(spacing: 12) {
                switch session.step {
                case .rules, .review:
                    if session.step == .rules {
                        RulesPanel()
                            .classicPanel(p)
                    }
                    if plan.unpricedCount > 0 && !model.settings.demoMode {
                        Text("\(plan.unpricedCount.formatted()) items are still waiting for a price and stay in Keep until they have one.")
                            .font(p.font(11.5))
                            .foregroundStyle(p.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(CleanupBucket.allCases) { bucket in
                            BucketColumn(bucket: bucket, entries: plan.entries(in: bucket), receive: plan.receive(in: bucket), editable: true)
                                .classicPanel(p)
                        }
                    }
                    .frame(maxHeight: .infinity)
                case .list:
                    ListStep(listings: listings, showingSignIn: $showingSignIn)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .classicPanel(p)
                }
                footer(listings: listings, p)
                    .classicPanel(p)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showingSignIn) {
            SteamSignInSheet().environment(model)
        }
    }

    private func sidebar(_ p: Palette) -> some View {
        let session = model.cleanup
        return VStack(alignment: .leading, spacing: 4) {
            PopoverPicker(
                title: "Clean up \(model.context(for: session.contextKey)?.name ?? "everything")",
                options: [PickerOption(value: "", label: "Every inventory")] + model.contexts.map { PickerOption(value: $0.id, label: $0.name) },
                selection: session.contextKey ?? "",
                palette: p
            ) { key in
                session.contextKey = key.isEmpty ? nil : key
                session.run = nil
            }
            .padding(.bottom, 8)
            ForEach(CleanupSession.Step.allCases) { step in
                SidebarRow(title: "\(step.rawValue). \(step.title)", isSelected: session.step == step, palette: p) {
                    session.step = step
                }
            }
            Spacer()
            Text("Steam's floor is \(Money.format(SteamFees.floorBuyerCents, model.currency)) buyer price, which pays you \(Money.format(1, model.currency)). Anything priced at the floor loses two thirds to fees.")
                .font(p.font(11.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .classicInset(p)
        }
        .padding(12)
    }

    private func footer(listings: [CleanupEntry], _ p: Palette) -> some View {
        let session = model.cleanup
        return HStack(spacing: 10) {
            Text("Listings go out a few at a time to stay under Steam's limits. Confirm them all at once in the Steam Mobile app.")
                .font(p.font(12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Back") {
                if let previous = CleanupSession.Step(rawValue: session.step.rawValue - 1) { session.step = previous }
            }
            .classicButton(.secondary, p)
            .disabled(session.step == .rules)
            switch session.step {
            case .rules:
                Button("Review buckets…") { session.step = .review }
                    .classicButton(.primary, p)
            case .review:
                Button("Review \(listings.count.formatted()) listings…") {
                    session.run = nil
                    session.step = .list
                }
                .classicButton(.primary, p)
                .disabled(listings.isEmpty)
            case .list:
                EmptyView()
            }
        }
        .padding(12)
    }
}

// MARK: - Rules

struct RulesPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.palette
        let rules = model.binding(\.cleanupRules)
        let currency = model.currency
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Rules", p)
            HStack(spacing: 6) {
                Toggle("Keep every piece of a set I own at least", isOn: rules.keepSets)
                    .toggleStyle(ClassicCheckboxStyle(palette: p))
                PopoverPicker(
                    title: "\(model.settings.cleanupRules.setThreshold)",
                    options: (2...6).map { PickerOption(value: $0, label: "\($0) pieces") },
                    selection: model.settings.cleanupRules.setThreshold,
                    palette: p
                ) { rules.wrappedValue.setThreshold = $0 }
                Text("pieces of")
            }
            Toggle(model.settings.protectStarred ? "Keep anything I've starred (always on in Settings)" : "Keep anything I've starred", isOn: rules.keepStarred)
                .toggleStyle(ClassicCheckboxStyle(palette: p))
                .disabled(model.settings.protectStarred)
            HStack(spacing: 6) {
                Text("Price at").padding(.leading, 21)
                PopoverPicker(
                    title: model.settings.cleanupRules.pricing.label,
                    options: ListingPriceStrategy.allCases.map { PickerOption(value: $0, label: $0.label) },
                    selection: model.settings.cleanupRules.pricing,
                    palette: p
                ) { rules.wrappedValue.pricing = $0 }
                Text("never below \(Money.format(model.settings.cleanupRules.floorCents, currency))")
            }
            HStack(spacing: 6) {
                Toggle("Ask me about items worth", isOn: rules.reviewExpensive)
                    .toggleStyle(ClassicCheckboxStyle(palette: p))
                PopoverPicker(
                    title: Money.format(model.settings.cleanupRules.reviewAboveCents, currency),
                    options: [100, 200, 500, 1_000, 2_500, 5_000, 10_000].map { PickerOption(value: $0, label: Money.format($0, currency)) },
                    selection: model.settings.cleanupRules.reviewAboveCents,
                    palette: p
                ) { rules.wrappedValue.reviewAboveCents = $0 }
                Text("or more before selling them")
            }
            Toggle("Hold items whose price rose more than \(Int(model.settings.cleanupRules.risingThreshold * 100))% this month", isOn: rules.holdRising)
                .toggleStyle(ClassicCheckboxStyle(palette: p))
        }
        .font(p.font(12.5))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Buckets

struct BucketColumn: View {
    @Environment(AppModel.self) private var model
    let bucket: CleanupBucket
    let entries: [CleanupEntry]
    let receive: Int
    let editable: Bool

    var body: some View {
        let p = model.palette
        let groups = Self.group(entries)
        let sellFloor = model.settings.cleanupRules.sellFloorItems
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(bucket.title).font(p.font(14, .bold))
                Spacer()
                Text("\(entries.reduce(0) { $0 + $1.item.amount }.formatted()) items").foregroundStyle(p.accent)
            }
            Text(description)
                .font(p.font(11.5))
                .foregroundStyle(p.text.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 30, alignment: .top)
            if bucket == .floor {
                HStack(spacing: 0) {
                    Button("Sell in bulk") { model.updateSettings { $0.cleanupRules.sellFloorItems = true } }
                        .classicButton(sellFloor ? .primary : .secondary, p)
                    Button("Keep") { model.updateSettings { $0.cleanupRules.sellFloorItems = false } }
                        .classicButton(sellFloor ? .secondary : .primary, p)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        BucketRow(group: group, bucket: bucket, editable: editable)
                    }
                    if entries.isEmpty {
                        Text("Nothing here")
                            .foregroundStyle(p.mutedText)
                            .padding(10)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .classicInset(p)
            HStack {
                Text(bucket == .keep || (bucket == .floor && !sellFloor) || bucket == .review ? "Worth" : "You receive")
                    .foregroundStyle(p.secondaryText)
                Spacer()
                Text(Money.format(receive, model.currency)).foregroundStyle(p.accent)
            }
            .font(p.font(12))
        }
        .padding(12)
        .overlay(alignment: .top) { stripe(p).frame(height: 3) }
    }

    private var description: String {
        let currency = model.currency
        switch bucket {
        case .sell:
            return "Pays you at least \(Money.format(2, currency)) after fees."
        case .floor:
            return "Only sell at \(Money.format(SteamFees.floorBuyerCents, currency)) and pay you \(Money.format(1, currency)). Sell in bulk, or keep."
        case .review:
            return "Worth \(Money.format(model.settings.cleanupRules.reviewAboveCents, currency)) or more. Move to Sell if you'll part with them."
        case .keep:
            return "Matched a keep rule: sets, starred, rising, or not priced yet."
        }
    }

    private func stripe(_ p: Palette) -> Color {
        switch bucket {
        case .sell: p.positive
        case .floor: p.accent
        case .review: p.negative.opacity(0.8)
        case .keep: p.neutral
        }
    }

    /// Duplicates of the same item collapse into one row with a count.
    struct RowGroup: Identifiable {
        var entries: [CleanupEntry]
        var id: String { entries[0].item.priceKey + "|" + entries[0].reason }
        var first: CleanupEntry { entries[0] }
        var count: Int { entries.reduce(0) { $0 + $1.item.amount } }
    }

    static func group(_ entries: [CleanupEntry]) -> [RowGroup] {
        var order: [String] = []
        var groups: [String: [CleanupEntry]] = [:]
        for entry in entries {
            let key = entry.item.priceKey + "|" + entry.reason
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(entry)
        }
        return order.compactMap { groups[$0].map { RowGroup(entries: $0) } }
    }
}

struct BucketRow: View {
    @Environment(AppModel.self) private var model
    let group: BucketColumn.RowGroup
    let bucket: CleanupBucket
    let editable: Bool

    var body: some View {
        let p = model.palette
        let entry = group.first
        HStack(spacing: 6) {
            p.rarity(entry.item).frame(width: 3, height: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.count > 1 ? "\(entry.item.name) ×\(group.count)" : entry.item.name)
                    .lineLimit(1)
                if bucket == .keep || bucket == .review {
                    Text(entry.reason)
                        .font(p.font(10.5))
                        .foregroundStyle(p.mutedText)
                }
            }
            Spacer(minLength: 4)
            Text(Money.format(entry.buyerCents, model.currency))
                .foregroundStyle(p.accent)
        }
        .font(p.font(12))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu {
            if editable {
                ForEach(CleanupBucket.allCases.filter { $0 != bucket }) { target in
                    Button("Move to \(target.title)") { move(to: target) }
                }
                Divider()
            }
            Button(model.isStarred(entry.item) ? "Unstar" : "Star (always keep)") {
                for member in group.entries { model.toggleStar(member.item) }
            }
            Button("Show in Inventory") {
                model.browser.show(contextKey: entry.item.contextKey, quick: [], search: entry.item.name)
                model.browser.focusedID = entry.item.id
                model.tab = .inventory
            }
        }
        .help(entry.reason)
    }

    private func move(to target: CleanupBucket) {
        for member in group.entries {
            model.cleanup.overrides[member.item.id] = target
        }
    }
}

// MARK: - Step 3

struct ListStep: View {
    @Environment(AppModel.self) private var model
    let listings: [CleanupEntry]
    @Binding var showingSignIn: Bool

    var body: some View {
        let p = model.palette
        let session = model.cleanup
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("List and confirm", p)
            if let run = session.run {
                ListingProgressList(run: run)
                    .frame(maxHeight: .infinity)
                if let message = run.haltMessage {
                    Text(message).foregroundStyle(p.negative)
                }
                HStack {
                    Text("You receive \(Money.format(run.listedSellerTotal, model.currency)) of \(Money.format(run.sellerTotal, model.currency)) once buyers purchase")
                        .foregroundStyle(p.secondaryText)
                    Spacer()
                    if run.isRunning {
                        Button("Stop after this one") { run.stopRequested = true }
                            .classicButton(.secondary, p)
                    } else if !run.isComplete {
                        Button("Resume listing") { Task { await model.runListing(run) } }
                            .classicButton(.primary, p)
                    } else {
                        Button("Start a new clean up") {
                            session.run = nil
                            session.step = .rules
                        }
                        .classicButton(.primary, p)
                    }
                }
            } else {
                let buyer = listings.reduce(0) { $0 + ($1.buyerCents ?? 0) * $1.item.amount }
                let seller = listings.reduce(0) { $0 + $1.totalSellerCents }
                Text("\(listings.count.formatted()) listings · buyers pay \(Money.format(buyer, model.currency)) · you receive \(Money.format(seller, model.currency)) after fees")
                    .font(p.font(13, .bold))
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(listings) { entry in
                            ListingRow(
                                name: entry.item.name,
                                buyerCents: entry.buyerCents ?? 0,
                                sellerCents: entry.sellerCents ?? 0,
                                status: nil,
                                palette: p,
                                currency: model.currency
                            )
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .classicInset(p)
                SignInStatus(showingSignIn: $showingSignIn)
                HStack {
                    Text("Prices older than 6 hours are re-checked right before listing. Starred items are never listed.")
                        .font(p.font(11.5))
                        .foregroundStyle(p.secondaryText)
                    Spacer()
                    Button("List \(listings.count.formatted()) items") {
                        let run = ListingRun(entries: listings)
                        session.run = run
                        Task { await model.runListing(run) }
                    }
                    .classicButton(.primary, p)
                    .disabled(listings.isEmpty)
                }
            }
        }
        .padding(12)
    }
}
