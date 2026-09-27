//
//  CleanupView.swift
//  gauge
//
//  Clean up in two steps. Review: the rules on the left sort marketable
//  items into Sell, Worth a look, and Keep. The list shows one bucket at a
//  time with each item's artwork, so it can be skimmed, and anything can be
//  moved by swiping its row (right to sell, left to keep), with the Delete
//  key, from the selection bar, or by dragging rows onto a bucket. Every
//  move can be undone with ⌘Z. List and confirm: the Sell bucket goes out a
//  few listings at a time.
//

import SwiftUI

struct CleanupView: View {
    @Environment(AppModel.self) private var model
    @State private var showingSignIn = false

    var body: some View {
        let p = model.palette
        let session = model.cleanup
        let plan = model.cleanupPlan(contextKey: session.contextKey)
        let rows = CleanupRow.rows(from: plan.entries(in: session.bucket), search: session.search, filter: session.filter, sort: session.sort)

        HStack(alignment: .top, spacing: 12) {
            CleanupSidebar(plan: plan)
                .frame(width: 250)
                .frame(maxHeight: .infinity, alignment: .top)
                .classicPanel(p)
            switch session.step {
            case .review:
                CleanupReview(plan: plan, rows: rows)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .classicPanel(p)
                CleanupInspector(plan: plan, rows: rows)
                    .frame(width: 280)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .classicPanel(p)
            case .list:
                ListStep(listings: plan.listings, showingSignIn: $showingSignIn)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .classicPanel(p)
            }
        }
        .sheet(isPresented: $showingSignIn) {
            SteamSignInSheet(purpose: .listing).environment(model)
        }
    }
}

extension CleanupBucket {
    func color(_ p: Palette) -> Color {
        switch self {
        case .sell: p.positive
        case .review: p.accent
        case .keep: p.neutral
        }
    }
}

// MARK: - Rules

struct CleanupSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let plan: CleanupPlan
    @State private var showingAdvanced = false

    var body: some View {
        let p = model.palette
        let session = model.cleanup
        let rules = model.binding(\.cleanupRules)
        let current = model.settings.cleanupRules
        let currency = model.currency
        let hasSkins = plan.hasSkins
        VStack(alignment: .leading, spacing: 0) {
            PopoverPicker(
                title: "Clean up \(model.context(for: session.contextKey)?.name ?? "every inventory")",
                options: [PickerOption(value: "", label: "Every inventory")] + model.contexts.map { PickerOption(value: $0.id, label: $0.name) },
                selection: session.contextKey ?? "",
                palette: p
            ) { key in
                session.contextKey = key.isEmpty ? nil : key
                session.selection = []
                session.run = nil
            }
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Sell", p)
                    rule("Extra copies", isOn: rules.sellDuplicates, p) {
                        Text(hasSkins ? "Keeps one of each item, the lowest float for skins, and sells the rest" : "Keeps one of each item and sells the rest")
                    }
                    rule("Cheap items", isOn: rules.sellCheap, p) {
                        HStack(spacing: 6) {
                            Text("Anything under")
                            PopoverPicker(
                                title: Money.format(current.cheapBelowCents, currency),
                                options: [5, 10, 25, 50, 100, 200].map { PickerOption(value: $0, label: Money.format($0, currency)) },
                                selection: current.cheapBelowCents,
                                palette: p
                            ) { rules.wrappedValue.cheapBelowCents = $0 }
                        }
                    }
                    rule("Everything else with a price", isOn: rules.sellEverythingElse, p)
                    rule("Items that pay \(Money.format(1, currency))", isOn: rules.sellFloorItems, p) {
                        Text("Steam's lowest price is \(Money.format(SteamFees.floorBuyerCents, currency)), and fees take two thirds of it")
                    }

                    SectionLabel("Keep", p)
                        .padding(.top, 10)
                    rule(model.settings.protectStarred ? "Starred items (set in Settings)" : "Starred items", isOn: rules.keepStarred, p)
                        .disabled(model.settings.protectStarred)
                    rule("Ask first about expensive items", isOn: rules.reviewExpensive, p) {
                        HStack(spacing: 6) {
                            PopoverPicker(
                                title: Money.format(current.reviewAboveCents, currency),
                                options: [100, 200, 500, 1_000, 2_500, 5_000, 10_000].map { PickerOption(value: $0, label: Money.format($0, currency)) },
                                selection: current.reviewAboveCents,
                                palette: p
                            ) { rules.wrappedValue.reviewAboveCents = $0 }
                            Text("or more")
                        }
                    }

                    if hasSkins {
                        skinRules(rules, current, p)
                    }

                    DisclosureRow(title: "Advanced", isOpen: showingAdvanced, trailing: advancedSummary, palette: p) {
                        showingAdvanced.toggle()
                    }
                    .padding(.top, 10)
                    if showingAdvanced {
                        advanced(rules, current, p)
                    }
                }
                .padding(.trailing, 2)
            }

            Spacer(minLength: 10)
            if !session.overrides.isEmpty {
                HStack {
                    Text("\(session.overrides.count.formatted()) moved by hand")
                        .foregroundStyle(p.secondaryText)
                    Spacer()
                    Button("Use rules") { model.resetCleanupOverrides(undoManager: undoManager) }
                        .buttonStyle(.plain)
                        .foregroundStyle(p.accent)
                        .help("Put every item you moved back where the rules sort it")
                }
                .font(p.font(11.5))
                .padding(.bottom, 8)
            }
            VStack(alignment: .leading, spacing: 4) {
                Label("Swipe right to sell, left to keep", systemImage: "hand.draw")
                Label("Drag rows onto a bucket to move them", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                Label("⌫ keeps the selection · ⌘Z undoes", systemImage: "keyboard")
            }
            .font(p.font(11))
            .foregroundStyle(p.secondaryText)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .classicInset(p)
        }
        .font(p.font(12.5))
        .padding(12)
        .disabled(session.run?.isRunning == true)
    }

    private func rule(_ title: String, isOn: Binding<Bool>, _ p: Palette) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(ClassicCheckboxStyle(palette: p))
    }

    /// A rule's checkbox, with its detail or setting indented beneath it.
    private func rule<Detail: View>(_ title: String, isOn: Binding<Bool>, _ p: Palette, @ViewBuilder detail: () -> Detail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: isOn)
                .toggleStyle(ClassicCheckboxStyle(palette: p))
            detail()
                .font(p.font(11.5))
                .foregroundStyle(p.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 21)
                .opacity(isOn.wrappedValue ? 1 : 0.55)
        }
    }

    /// Counter-Strike 2: every copy of a skin sells at the same Market price, but its float
    /// and stickers can make it worth more, so those wait for a look.
    @ViewBuilder
    private func skinRules(_ rules: Binding<CleanupRules>, _ current: CleanupRules, _ p: Palette) -> some View {
        SectionLabel("Counter-Strike 2", p)
            .padding(.top, 10)
        rule("Ask first about low floats", isOn: rules.reviewLowFloats, p) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("The cleanest")
                    PopoverPicker(
                        title: Self.percent(current.lowFloatShare),
                        options: [0.01, 0.02, 0.05, 0.1, 0.25].map { PickerOption(value: $0, label: Self.percent($0)) },
                        selection: current.lowFloatShare,
                        palette: p
                    ) { rules.wrappedValue.lowFloatShare = $0 }
                    Text("of each wear,")
                }
                Text("such as under \(Self.factoryNewThreshold(current.lowFloatShare)) in Factory New")
            }
        }
        rule("Ask first about stickers and charms", isOn: rules.reviewApplied, p) {
            Text("Skins with stickers, patches, or a charm applied. The Market price leaves them out.")
        }
    }

    private static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    /// 0.0035 for the cleanest 5%.
    private static func factoryNewThreshold(_ share: Double) -> String {
        FloatText.full((Exterior.factoryNew.bounds.upper * share * 1_000_000).rounded() / 1_000_000)
    }

    @ViewBuilder
    private func advanced(_ rules: Binding<CleanupRules>, _ current: CleanupRules, _ p: Palette) -> some View {
        let currency = model.currency
        rule("Set pieces", isOn: rules.keepSetPieces, p) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Once I own")
                    PopoverPicker(
                        title: "\(current.setThreshold)",
                        options: (2...6).map { PickerOption(value: $0, label: "\($0) pieces") },
                        selection: current.setThreshold,
                        palette: p
                    ) { rules.wrappedValue.setThreshold = $0 }
                    Text("of a set,")
                }
                Text("keep one copy of each piece")
            }
        }
        rule("Rising prices", isOn: rules.holdRising, p) {
            Text("Keep anything up \(Int(current.risingThreshold * 100))% or more this month")
        }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Price at")
                PopoverPicker(
                    title: current.pricing.label,
                    options: ListingPriceStrategy.allCases.map { PickerOption(value: $0, label: $0.label) },
                    selection: current.pricing,
                    palette: p
                ) { rules.wrappedValue.pricing = $0 }
            }
            Text("Never below \(Money.format(current.floorCents, currency)), Steam's minimum")
                .font(p.font(11.5))
                .foregroundStyle(p.secondaryText)
        }
        .padding(.top, 2)
    }

    /// What's on under Advanced, so it's visible while the section is closed.
    private var advancedSummary: String? {
        let rules = model.settings.cleanupRules
        var parts: [String] = []
        if rules.keepSetPieces { parts.append("sets") }
        if rules.holdRising { parts.append("rising") }
        if rules.pricing != .lowestListing { parts.append("pricing") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Review

struct CleanupReview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let plan: CleanupPlan
    let rows: [CleanupRow]
    @FocusState private var searchFocused: Bool

    var body: some View {
        let p = model.palette
        let session = model.cleanup
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(CleanupBucket.allCases) { bucket in
                    BucketTab(bucket: bucket, plan: plan)
                }
            }
            if plan.unpricedCount > 0 && !model.settings.demoMode {
                unpricedBanner(p)
            }
            toolbar(p)
            CleanupList(plan: plan, rows: rows)
                .frame(maxHeight: .infinity)
                .classicInset(p)
            CleanupSelectionBar(rows: rows)
            footer(p)
        }
        .padding(12)
        .onChange(of: session.contextKey) {
            session.filter = nil
            session.selection = []
        }
    }

    private func toolbar(_ p: Palette) -> some View {
        @Bindable var session = model.cleanup
        let filters = CleanupRow.filters(for: plan.entries(in: session.bucket))
        let rules = model.settings.cleanupRules
        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    searchFocused = true
                } label: {
                    Image(systemName: "magnifyingglass").foregroundStyle(p.mutedText)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("f", modifiers: .command)
                .help("Search (⌘F)")
                TextField("Search items", text: $session.search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !session.search.isEmpty {
                    Button {
                        session.search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(p.mutedText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: 210)
            .classicInset(p)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if filters.count > 1 || session.filter != nil {
                        ForEach(filters, id: \.filter) { option in
                            let selected = session.filter == option.filter
                            Button {
                                session.filter = selected ? nil : option.filter
                                session.selection = []
                            } label: {
                                HStack(spacing: 5) {
                                    Text(option.filter.title(rules: rules, currency: model.currency))
                                    Text(option.count.formatted()).foregroundStyle(selected ? p.text : p.secondaryText)
                                }
                                .font(p.font(11.5))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .chipBackground(p, selected: selected)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            PopoverPicker(
                title: "Sort: \(session.sort.title)",
                options: CleanupSort.allCases.map { PickerOption(value: $0, label: $0.title) },
                selection: session.sort,
                palette: p
            ) { session.sort = $0 }
        }
        .font(p.font(12))
    }

    private func unpricedBanner(_ p: Palette) -> some View {
        let waiting = plan.entries(in: .keep).filter { $0.reason.kind == .notPriced }.map(\.item)
        let names = Set(waiting.map(\.priceKey)).count
        let minutes = Int((Double(names) * SteamClient.Endpoint.market.interval / 60).rounded(.up))
        return HStack(spacing: 8) {
            Image(systemName: "clock").foregroundStyle(p.accent)
            Text("\(plan.unpricedCount.formatted()) items are waiting for a price and stay in Keep until they have one\(names > 0 ? ", about \(minutes.formatted()) min at Steam's pace" : "").")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Price these first") { model.prioritizePricing(for: waiting) }
                .classicButton(.secondary, p)
                .help("Move these items to the front of the pricing queue")
        }
        .font(p.font(11.5))
        .foregroundStyle(p.secondaryText)
    }

    private func footer(_ p: Palette) -> some View {
        let session = model.cleanup
        let listings = plan.listings
        let seller = listings.reduce(0) { $0 + $1.totalSellerCents }
        let units = listings.reduce(0) { $0 + $1.item.amount }
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(listings.isEmpty ? "Nothing to list yet" : "\(units.formatted()) item\(units == 1 ? "" : "s") to list · you receive \(Money.format(seller, model.currency))")
                    .font(p.font(13, .bold))
                Text("Listings go out a few at a time to stay under Steam's limits. Confirm them all at once in the Steam Mobile app.")
                    .font(p.font(11.5))
                    .foregroundStyle(p.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Review \(listings.count.formatted()) listing\(listings.count == 1 ? "" : "s")…") {
                session.run = nil
                session.selection = []
                session.step = .list
            }
            .classicButton(.primary, p)
            .disabled(listings.isEmpty)
        }
        .padding(.top, 2)
    }
}

/// One bucket in the strip above the list. Rows dropped on it move there.
struct BucketTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let bucket: CleanupBucket
    let plan: CleanupPlan
    @State private var isTargeted = false

    var body: some View {
        let p = model.palette
        let selected = model.cleanup.bucket == bucket
        let shape = RoundedRectangle(cornerRadius: p.corner)
        Button {
            model.cleanup.show(bucket)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Circle().fill(bucket.color(p)).frame(width: 8, height: 8)
                    Text(bucket.title).font(p.font(13.5, .bold))
                    Spacer()
                    Text(plan.itemCount(in: bucket).formatted())
                        .font(p.font(13))
                        .foregroundStyle(selected ? p.text : p.secondaryText)
                }
                Text(bucket == .sell ? "You receive \(Money.format(plan.receive(in: bucket), model.currency))" : "Worth \(Money.format(plan.receive(in: bucket), model.currency)) after fees")
                    .font(p.font(11.5))
                    .foregroundStyle(p.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? p.selection : p.raised, in: shape)
            .overlay(alignment: .top) {
                bucket.color(p).frame(height: selected ? 3 : 0)
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(isTargeted ? p.accent : (selected ? bucket.color(p).opacity(0.6) : p.bevelLight.opacity(0.45)), lineWidth: isTargeted ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { payloads, _ in
            let rowIDs = CleanupDrag.rowIDs(from: payloads).filter { !$0.hasPrefix(bucket.rawValue + "|") }
            let ids = rowIDs.flatMap { plan.itemIDs(inRow: $0) }
            guard !ids.isEmpty else { return false }
            model.moveCleanupItems(ids, to: bucket, undoManager: undoManager)
            model.cleanup.selection.subtract(rowIDs)
            return true
        } isTargeted: { isTargeted = $0 }
        .help(help)
    }

    private var help: String {
        switch bucket {
        case .sell: return "Listed when you continue. Drop rows here to sell them."
        case .review:
            guard let reasons = model.settings.cleanupRules.reviewSummary(currency: model.currency, skins: plan.hasSkins) else {
                return "Waits until you decide. Drop rows here to decide later."
            }
            return "Picked by a selling rule, but \(reasons). Drop rows here to decide later."
        case .keep: return "Never listed. Drop rows here to keep them."
        }
    }
}

// MARK: - List

struct CleanupList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openURL) private var openURL
    let plan: CleanupPlan
    let rows: [CleanupRow]

    var body: some View {
        let p = model.palette
        @Bindable var session = model.cleanup
        let bucket = session.bucket
        if rows.isEmpty {
            emptyState(p)
        } else {
            List(selection: $session.selection) {
                ForEach(rows) { row in
                    let starred = row.itemIDs.allSatisfy(model.starred.contains)
                    CleanupRowView(
                        row: row,
                        isStarred: starred,
                        game: session.contextKey == nil ? model.context(for: row.item.contextKey)?.name : nil,
                        palette: p,
                        currency: model.currency
                    )
                    .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 10))
                    .listRowSeparatorTint(p.gridLine)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if bucket != .sell {
                            Button {
                                move([row], to: .sell)
                            } label: {
                                Label("Sell", systemImage: "tag")
                            }
                            .tint(.green)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: bucket != .keep) {
                        if bucket != .keep {
                            Button {
                                move([row], to: .keep)
                            } label: {
                                Label("Keep", systemImage: "tray.and.arrow.down")
                            }
                            .tint(.blue)
                        }
                        Button {
                            model.setStarred(row.entries.map(\.item), !starred)
                        } label: {
                            Label(starred ? "Unstar" : "Star", systemImage: starred ? "star.slash" : "star")
                        }
                        .tint(.orange)
                    }
                    .draggable(dragPayload(for: row))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: String.self) { ids in
                menu(for: rows.filter { ids.contains($0.id) })
            }
            .onDeleteCommand {
                // Delete means "don't sell", so it does nothing in Keep.
                guard bucket != .keep else { return }
                move(rows.filter { session.selection.contains($0.id) }, to: .keep)
            }
        }
    }

    @ViewBuilder
    private func menu(for targets: [CleanupRow]) -> some View {
        if !targets.isEmpty {
            let bucket = model.cleanup.bucket
            ForEach(CleanupBucket.allCases.filter { $0 != bucket }) { destination in
                Button("Move to \(destination.title)") { move(targets, to: destination) }
            }
            if targets.contains(where: { $0.reasons.contains { $0.kind == .movedByYou } }) {
                Button("Use Rules") { move(targets, to: nil) }
            }
            Divider()
            let items = targets.flatMap { $0.entries.map(\.item) }
            let allStarred = items.allSatisfy { model.starred.contains($0.id) }
            Button(allStarred ? "Unstar" : "Star (Always Keep)") { model.setStarred(items, !allStarred) }
            if targets.count == 1, let row = targets.first {
                Button("Show in Inventory") { showInInventory(row.item) }
                if let url = row.item.marketURL {
                    Button("View on Market") { openURL(url) }
                }
            }
        }
    }

    private func emptyState(_ p: Palette) -> some View {
        let session = model.cleanup
        let narrowed = !session.search.isEmpty || session.filter != nil
        return VStack(spacing: 10) {
            Image(systemName: narrowed ? "magnifyingglass" : (session.bucket == .sell ? "checkmark.circle" : "tray"))
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(p.mutedText)
            Text(emptyText(narrowed: narrowed))
                .multilineTextAlignment(.center)
                .foregroundStyle(p.secondaryText)
                .frame(maxWidth: 360)
            if narrowed {
                Button("Show everything") {
                    session.search = ""
                    session.filter = nil
                }
                .classicButton(.secondary, p)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyText(narrowed: Bool) -> String {
        if narrowed { return "Nothing here matches." }
        if model.allItems.isEmpty { return "Your inventory appears here after the first sync." }
        switch model.cleanup.bucket {
        case .sell: return "Nothing to sell with these rules. Turn on another rule at the left, or swipe items right in Keep."
        case .review:
            guard let reasons = model.settings.cleanupRules.reviewSummary(currency: model.currency, skins: plan.hasSkins) else {
                return "Nothing to look at. Rows you drop here wait until you decide."
            }
            return "Nothing to look at. Items a rule picks wait here when they're \(reasons)."
        case .keep: return "Nothing kept. Starred items, and anything no rule picks, show up here."
        }
    }

    private func move(_ targets: [CleanupRow], to bucket: CleanupBucket?) {
        guard !targets.isEmpty else { return }
        model.cleanup.selectNext(afterRemoving: Set(targets.map(\.id)), from: rows)
        model.moveCleanupItems(targets.flatMap(\.itemIDs), to: bucket, undoManager: undoManager)
    }

    /// Dragging a selected row carries the whole selection.
    private func dragPayload(for row: CleanupRow) -> String {
        let selection = model.cleanup.selection
        let ids = selection.contains(row.id) ? rows.map(\.id).filter(selection.contains) : [row.id]
        return CleanupDrag.payload(rowIDs: ids)
    }

    private func showInInventory(_ item: InventoryItem) {
        model.browser.show(contextKey: item.contextKey, quick: [], search: item.name)
        model.browser.focusedID = item.id
        model.tab = .inventory
    }
}

struct CleanupRowView: View {
    let row: CleanupRow
    let isStarred: Bool
    /// Shown when cleaning up every inventory at once.
    let game: String?
    let palette: Palette
    let currency: SteamCurrency

    var body: some View {
        let p = palette
        let item = row.item
        HStack(spacing: 10) {
            ItemArtwork(item: item, size: 96, palette: p)
                .frame(width: 58, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: p.bevels ? 0 : 5))
                .overlay(alignment: .bottom) { p.rarity(item).frame(height: 2) }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .lineLimit(1)
                    if row.count > 1 {
                        Text("×\(row.count)")
                            .font(p.font(11, .bold))
                            .foregroundStyle(p.accent)
                    }
                    if isStarred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(p.accent)
                    }
                }
                Text("\(Text(details).foregroundStyle(p.secondaryText)) · \(Text(row.reasons.map(\.text).joined(separator: " · ")).foregroundStyle(reasonColor))")
                    .font(p.font(11))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Money.format(row.buyerCents, currency))
                    .foregroundStyle(p.accent)
                if row.sellerCents != nil {
                    Text("you get \(Money.format(row.totalSellerCents, currency))")
                        .font(p.font(11))
                        .foregroundStyle(p.secondaryText)
                }
            }
            .monospacedDigit()
        }
        .font(p.font(12.5))
        .foregroundStyle(p.text)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .help(row.reasons.map(\.text).joined(separator: "\n"))
    }

    /// "Mythical Tail · Slark · Dota 2", or "0.0712 · #661 · Classified Rifle" for a skin.
    private var details: String {
        var parts = [row.item.skin?.summary ?? "", row.item.subtitle]
        if let hero = row.item.usedBy, !row.item.subtitle.contains(hero) { parts.append(hero) }
        if let game { parts.append(game) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var reasonColor: Color {
        if row.reasons.contains(where: { $0.kind == .movedByYou }) { return palette.accent }
        return row.bucket == .keep ? palette.mutedText : row.bucket.color(palette)
    }
}

// MARK: - Selection

struct CleanupSelectionBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let rows: [CleanupRow]

    var body: some View {
        let p = model.palette
        let session = model.cleanup
        let selected = rows.filter { session.selection.contains($0.id) }
        let units = selected.reduce(0) { $0 + $1.count }
        HStack(spacing: 8) {
            if selected.isEmpty {
                Text(rows.isEmpty ? " " : "Click to select · ⌘-click to add · ⇧-click for a range · ⌘A for all \(rows.count.formatted())")
                    .foregroundStyle(p.secondaryText)
            } else {
                Text("\(units.formatted()) selected · you'd receive \(Money.format(selected.reduce(0) { $0 + $1.totalSellerCents }, model.currency))")
                Button("Deselect") { session.selection = [] }
                    .buttonStyle(.plain)
                    .foregroundStyle(p.accent)
                Spacer()
                let items = selected.flatMap { $0.entries.map(\.item) }
                let allStarred = items.allSatisfy { model.starred.contains($0.id) }
                Button(allStarred ? "Unstar" : "Star") { model.setStarred(items, !allStarred) }
                    .classicButton(.secondary, p)
                ForEach(CleanupBucket.allCases.filter { $0 != session.bucket }) { bucket in
                    Button(bucket == .review ? "Worth a look" : bucket.title) {
                        session.selectNext(afterRemoving: Set(selected.map(\.id)), from: rows)
                        model.moveCleanupItems(selected.flatMap(\.itemIDs), to: bucket, undoManager: undoManager)
                    }
                    .classicButton(bucket == .sell ? .primary : .secondary, p)
                }
            }
            Spacer(minLength: 0)
        }
        .font(p.font(12))
        .frame(minHeight: 28)
    }
}

// MARK: - Inspector

struct CleanupInspector: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openURL) private var openURL
    let plan: CleanupPlan
    let rows: [CleanupRow]

    var body: some View {
        let p = model.palette
        let selected = rows.filter { model.cleanup.selection.contains($0.id) }
        Group {
            if selected.count == 1, let row = selected.first {
                detail(row, p)
            } else if selected.count > 1 {
                summary(selected, p)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "hand.point.up.left")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(p.mutedText)
                    Text("Select an item to see it up close before it's listed.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(p.mutedText)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .font(p.font(12.5))
    }

    private func detail(_ row: CleanupRow, _ p: Palette) -> some View {
        let item = row.item
        let quote = model.quote(for: item)
        let starred = row.itemIDs.allSatisfy(model.starred.contains)
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ItemArtwork(item: item, size: 256, palette: p)
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .classicInset(p)
                    .overlay(alignment: .bottom) { p.rarity(item).frame(height: 3) }
                Text(item.name)
                    .font(p.font(16, .bold))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.subtitle) · \(model.context(for: item.contextKey)?.name ?? "")")
                        .foregroundStyle(p.rarity(item))
                    if let hero = item.usedBy {
                        Text("Used by \(hero)").foregroundStyle(p.secondaryText)
                    }
                }
                copies(row, p)
                if item.isOneOfAKind && row.copies > 1 {
                    skinCopies(row, p)
                }
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(row.reasons, id: \.self) { reason in
                        Label(reason.text, systemImage: reason.kind == .movedByYou ? "hand.raised" : "line.3.horizontal.decrease")
                            .foregroundStyle(p.secondaryText)
                    }
                }
                .font(p.font(11.5))
                if let skin = item.skin {
                    SkinDetailsBox(skin: skin, palette: p)
                }
                prices(item, quote: quote, row: row, p)
                HStack(spacing: 6) {
                    ForEach(CleanupBucket.allCases.filter { $0 != row.bucket }) { bucket in
                        Button(bucket == .review ? "Worth a look" : bucket.title) {
                            model.cleanup.selectNext(afterRemoving: [row.id], from: rows)
                            model.moveCleanupItems(row.itemIDs, to: bucket, undoManager: undoManager)
                        }
                        .classicButton(bucket == .sell ? .primary : .secondary, p)
                    }
                }
                Button(starred ? "★ Starred · always kept" : "☆ Star so it's always kept") {
                    model.setStarred(row.entries.map(\.item), !starred)
                }
                .classicButton(.card, p)
                HStack(spacing: 12) {
                    Button("Show in Inventory") {
                        model.browser.show(contextKey: item.contextKey, quick: [], search: item.name)
                        model.browser.focusedID = item.id
                        model.tab = .inventory
                    }
                    if let url = item.marketURL {
                        Button("View on Market") { openURL(url) }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(p.accent)
                .font(p.font(12))
                if !item.details.isEmpty {
                    Text(item.details.filter { !$0.hasPrefix("Used By:") }.prefix(10).joined(separator: "\n"))
                        .font(p.font(11))
                        .foregroundStyle(p.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
        }
    }

    /// "You have 3: 2 to sell, 1 kept."
    private func copies(_ row: CleanupRow, _ p: Palette) -> some View {
        let key = row.item.copyKey
        let counts = CleanupBucket.allCases.map { bucket in
            (bucket, plan.entries(in: bucket).filter { $0.item.copyKey == key }.count)
        }
        let placed = counts.reduce(0) { $0 + $1.1 }
        let locked = max(0, row.copies - placed)
        var parts = counts.filter { $0.1 > 0 }.map { bucket, count in
            switch bucket {
            case .sell: "\(count) to sell"
            case .review: "\(count) worth a look"
            case .keep: "\(count) kept"
            }
        }
        if locked > 0 { parts.append("\(locked) can't be sold") }
        return Text(row.copies > 1 ? "You have \(row.copies): \(parts.joined(separator: ", "))" : "Your only copy")
            .font(p.font(12, .bold))
    }

    /// Each copy's float and where it's going, the best first, with this row's copy in bold.
    private func skinCopies(_ row: CleanupRow, _ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(plan.copies(of: row.item)) { entry in
                let isThis = row.itemIDs.contains(entry.item.id)
                HStack(spacing: 6) {
                    Circle()
                        .fill(entry.bucket.color(p))
                        .frame(width: 7, height: 7)
                    Text(entry.item.skin?.summary ?? "No float")
                        .font(isThis ? p.font(11.5, .bold) : p.font(11.5))
                        .foregroundStyle(isThis ? p.text : p.secondaryText)
                    Spacer()
                    Text(entry.bucket.title)
                        .foregroundStyle(entry.bucket.color(p))
                }
            }
        }
        .font(p.font(11.5))
        .monospacedDigit()
        .padding(8)
        .classicInset(p)
    }

    private func prices(_ item: InventoryItem, quote: PriceQuote?, row: CleanupRow, _ p: Palette) -> some View {
        let currency = model.currency
        return VStack(spacing: 5) {
            priceRow("Lists at", Money.format(row.buyerCents, currency), p)
            priceRow("You receive", Money.format(row.sellerCents, currency) + (row.count > 1 ? " each" : ""), p)
            if let median = quote?.medianCents {
                priceRow("Median sale", Money.format(median, currency), p)
            }
            if let volume = quote?.volume {
                priceRow("Sold in 24 hours", volume.formatted(), p)
            }
            if let change = model.monthlyChange[item.priceKey] {
                priceRow("30-day change", change.formatted(.percent.precision(.fractionLength(0))), p)
            }
            HStack {
                Text("Price checked").foregroundStyle(p.secondaryText)
                Spacer()
                if let quote {
                    Text(RelativeTime.short(quote.checkedAt))
                } else if !model.settings.demoMode {
                    Button("Check now") { model.prioritizePricing(for: [item]) }
                        .buttonStyle(.plain)
                        .foregroundStyle(p.accent)
                } else {
                    Text("—")
                }
            }
        }
        .font(p.font(12))
        .padding(10)
        .classicInset(p)
    }

    private func priceRow(_ title: String, _ value: String, _ p: Palette) -> some View {
        HStack {
            Text(title).foregroundStyle(p.secondaryText)
            Spacer()
            Text(value)
        }
    }

    private func summary(_ selected: [CleanupRow], _ p: Palette) -> some View {
        let units = selected.reduce(0) { $0 + $1.count }
        let buyer = selected.reduce(0) { $0 + $1.totalBuyerCents }
        let seller = selected.reduce(0) { $0 + $1.totalSellerCents }
        let items = selected.flatMap { $0.entries.map(\.item) }
        let allStarred = items.allSatisfy { model.starred.contains($0.id) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(units.formatted()) items selected")
                    .font(p.font(16, .bold))
                VStack(spacing: 5) {
                    priceRow("Buyers pay", Money.format(buyer, model.currency), p)
                    priceRow("You receive", Money.format(seller, model.currency), p)
                }
                .font(p.font(12))
                .padding(10)
                .classicInset(p)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 6)], spacing: 6) {
                    ForEach(selected.prefix(24)) { row in
                        ItemArtwork(item: row.item, size: 96, palette: p)
                            .frame(height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: p.bevels ? 0 : 5))
                            .overlay(alignment: .bottom) { p.rarity(row.item).frame(height: 2) }
                            .help(row.item.name)
                    }
                }
                if selected.count > 24 {
                    Text("and \((selected.count - 24).formatted()) more")
                        .font(p.font(11.5))
                        .foregroundStyle(p.secondaryText)
                }
                HStack(spacing: 6) {
                    ForEach(CleanupBucket.allCases.filter { $0 != model.cleanup.bucket }) { bucket in
                        Button(bucket == .review ? "Worth a look" : bucket.title) {
                            model.cleanup.selectNext(afterRemoving: Set(selected.map(\.id)), from: rows)
                            model.moveCleanupItems(selected.flatMap(\.itemIDs), to: bucket, undoManager: undoManager)
                        }
                        .classicButton(bucket == .sell ? .primary : .secondary, p)
                    }
                }
                Button(allStarred ? "Unstar all" : "☆ Star all so they're always kept") {
                    model.setStarred(items, !allStarred)
                }
                .classicButton(.card, p)
            }
            .padding(12)
        }
    }
}

// MARK: - List and confirm

struct ListStep: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let listings: [CleanupEntry]
    @Binding var showingSignIn: Bool

    var body: some View {
        let p = model.palette
        let session = model.cleanup
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    session.step = .review
                } label: {
                    Label("Back to review", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(p.accent)
                .disabled(session.run?.isRunning == true)
                Spacer()
                SectionLabel("List and confirm", p)
            }
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
                            session.step = .review
                        }
                        .classicButton(.primary, p)
                    }
                }
            } else {
                let rows = CleanupRow.rows(from: listings)
                let buyer = listings.reduce(0) { $0 + $1.totalBuyerCents }
                let seller = listings.reduce(0) { $0 + $1.totalSellerCents }
                Text("\(listings.count.formatted()) listings · buyers pay \(Money.format(buyer, model.currency)) · you receive \(Money.format(seller, model.currency)) after fees")
                    .font(p.font(13, .bold))
                Text("A last look. Swipe a row left to keep it instead.")
                    .font(p.font(11.5))
                    .foregroundStyle(p.secondaryText)
                List {
                    ForEach(rows) { row in
                        ListingRow(
                            item: row.item,
                            count: row.count,
                            buyerCents: row.buyerCents ?? 0,
                            sellerCents: row.sellerCents ?? 0,
                            status: nil,
                            palette: p,
                            currency: model.currency
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                model.moveCleanupItems(row.itemIDs, to: .keep, undoManager: undoManager)
                            } label: {
                                Label("Keep", systemImage: "tray.and.arrow.down")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
