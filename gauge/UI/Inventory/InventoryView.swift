//
//  InventoryView.swift
//  gauge
//
//  Like the Steam inventory page, plus filters by tag, value sorting,
//  multi-select, and stars. Click selects one item; ⌘-click adds to the
//  selection and ⇧-click selects a range.
//

import AppKit
import SwiftUI

struct SellBatch: Identifiable {
    let id = UUID()
    var items: [InventoryItem]
}

struct InventoryView: View {
    @Environment(AppModel.self) private var model
    @State private var sellBatch: SellBatch?

    var body: some View {
        let p = model.palette
        let browser = model.browser
        let key = browser.contextKey ?? model.contexts.first?.id
        let items = model.items(in: key)
        let facts = model.facts()
        let shown = browser.query.apply(to: items, facts: facts)

        HStack(alignment: .top, spacing: 12) {
            InventorySidebar(contextKey: key, items: items, facts: facts)
                .frame(width: 250)
                .frame(maxHeight: .infinity, alignment: .top)
                .classicPanel(p)
            VStack(spacing: 8) {
                FilterBar(shownCount: shown.count, totalCount: items.count)
                SelectionBar(shown: shown, facts: facts) { sellBatch = SellBatch(items: $0) }
                ItemGrid(items: shown) { sellBatch = SellBatch(items: [$0]) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ItemDetailPanel(item: model.item(withID: browser.focusedID)) { sellBatch = SellBatch(items: [$0]) }
                .frame(width: 290)
                .frame(maxHeight: .infinity, alignment: .top)
                .classicPanel(p)
        }
        .sheet(item: $sellBatch) { batch in
            SellSheet(items: batch.items)
                .environment(model)
        }
        .onAppear {
            if browser.contextKey == nil { browser.contextKey = model.contexts.first?.id }
        }
    }
}

// MARK: - Sidebar

private struct QuickCounts {
    var counts: [QuickFilter: Int] = [:]

    init(items: [InventoryItem], facts: InventoryFacts) {
        for item in items {
            if facts.starred.contains(item.id) { counts[.starred, default: 0] += 1 }
            if item.marketable { counts[.marketable, default: 0] += 1 }
            if item.tradable { counts[.tradable, default: 0] += 1 }
            if facts.isFluff(item) { counts[.fluff, default: 0] += 1 }
            if facts.completesSet(item) { counts[.completeSets, default: 0] += 1 }
            if facts.priceMoved(item) { counts[.priceMoved, default: 0] += 1 }
        }
    }

    subscript(_ filter: QuickFilter) -> Int { counts[filter] ?? 0 }
}

struct InventorySidebar: View {
    @Environment(AppModel.self) private var model
    let contextKey: String?
    let items: [InventoryItem]
    let facts: InventoryFacts
    @State private var choosingContext = false

    var body: some View {
        let p = model.palette
        @Bindable var browser = model.browser
        let counts = QuickCounts(items: items, facts: facts)
        let facets = TagCategoryFacet.facets(for: items)

        VStack(alignment: .leading, spacing: 10) {
            contextButton(p)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(p.mutedText)
                TextField("Search items or heroes", text: $browser.query.search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .classicInset(p)

            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    DisclosureRow(title: "Quick", isOpen: browser.expanded.contains("Quick"), trailing: nil, palette: p) {
                        toggleSection("Quick")
                    }
                    if browser.expanded.contains("Quick") {
                        quickRow(.starred, "★ Starred", counts, p)
                        quickRow(.marketable, "Marketable", counts, p)
                        quickRow(.tradable, "Tradable", counts, p)
                        quickRow(.fluff, "Fluff (under \(Money.format(model.settings.fluffThresholdCents, model.currency)))", counts, p)
                        quickRow(.completeSets, "Complete sets", counts, p)
                        quickRow(.priceMoved, "Price moved this week", counts, p)
                    }
                    ForEach(facets) { facet in
                        tagSection(facet, p)
                    }
                }
                .padding(.trailing, 4)
            }
        }
        .padding(12)
    }

    private func contextButton(_ p: Palette) -> some View {
        let current = model.context(for: contextKey)
        let title = current.map { "\($0.name) (\($0.assetCount.formatted()))" } ?? "No inventories yet"
        return Button {
            choosingContext.toggle()
        } label: {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
        }
        .classicButton(.card, p)
        .disabled(model.contexts.isEmpty)
        .popover(isPresented: $choosingContext, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.contexts) { context in
                    SidebarRow(
                        title: context.name,
                        detail: context.assetCount.formatted(),
                        isSelected: context.id == contextKey,
                        palette: p
                    ) {
                        let browser = model.browser
                        browser.contextKey = context.id
                        browser.selection = []
                        browser.focusedID = nil
                        browser.query.tags = [:]
                        choosingContext = false
                    }
                }
            }
            .padding(6)
            .frame(width: 240)
            .background(p.panel)
            .foregroundStyle(p.text)
        }
    }

    private func quickRow(_ filter: QuickFilter, _ title: String, _ counts: QuickCounts, _ p: Palette) -> some View {
        let browser = model.browser
        return Toggle(isOn: Binding(
            get: { browser.query.quick.contains(filter) },
            set: { _ in browser.toggleQuick(filter) }
        )) {
            HStack {
                Text(title)
                Spacer()
                Text(filter == .fluff && facts.prices.isEmpty ? "—" : counts[filter].formatted())
                    .foregroundStyle(p.secondaryText)
            }
        }
        .toggleStyle(ClassicCheckboxStyle(palette: p))
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func tagSection(_ facet: TagCategoryFacet, _ p: Palette) -> some View {
        let browser = model.browser
        let isOpen = browser.expanded.contains(facet.category)
        let searchable = facet.values.count > 12
        DisclosureRow(
            title: facet.title,
            isOpen: isOpen,
            trailing: searchable ? "searchable" : facet.values.count.formatted(),
            palette: p
        ) {
            toggleSection(facet.category)
        }
        .padding(.top, 4)
        if isOpen {
            if searchable {
                TextField("Filter \(facet.title.lowercased())", text: Binding(
                    get: { browser.sectionSearch[facet.category] ?? "" },
                    set: { browser.sectionSearch[facet.category] = $0 }
                ))
                .classicField(p)
                .padding(.leading, 4)
            }
            let needle = (browser.sectionSearch[facet.category] ?? "").lowercased()
            let matching = needle.isEmpty ? facet.values : facet.values.filter { $0.name.lowercased().contains(needle) }
            let showAll = browser.showingAll.contains(facet.category) || !needle.isEmpty
            let checked = browser.query.tags[facet.category] ?? []
            // Keep checked values visible even when the list is collapsed.
            let visible = showAll ? matching : Array(matching.prefix(4)) + matching.dropFirst(4).filter { checked.contains($0.name) }
            ForEach(visible) { value in
                Toggle(isOn: Binding(
                    get: { checked.contains(value.name) },
                    set: { _ in browser.toggleTag(facet.category, value.name) }
                )) {
                    HStack {
                        Text(value.name)
                            .foregroundStyle(Color(hex: value.color) ?? p.text)
                            .lineLimit(1)
                        Spacer()
                        Text(value.count.formatted()).foregroundStyle(p.secondaryText)
                    }
                }
                .toggleStyle(ClassicCheckboxStyle(palette: p))
                .padding(.leading, 4)
            }
            if !showAll && matching.count > 4 {
                Button("+ \(matching.count - 4) more") {
                    browser.showingAll.insert(facet.category)
                }
                .buttonStyle(.plain)
                .foregroundStyle(p.accent)
                .padding(.leading, 18)
            }
        }
    }

    private func toggleSection(_ id: String) {
        let browser = model.browser
        if browser.expanded.contains(id) { browser.expanded.remove(id) } else { browser.expanded.insert(id) }
    }
}

// MARK: - Filter chips

struct FilterBar: View {
    @Environment(AppModel.self) private var model
    let shownCount: Int
    let totalCount: Int

    var body: some View {
        let p = model.palette
        let browser = model.browser
        let query = browser.query
        HStack(spacing: 6) {
            Text("Filters:").foregroundStyle(p.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(QuickFilter.allCases.filter { query.quick.contains($0) }) { filter in
                        FilterChip(title: Self.title(filter), palette: p) { browser.toggleQuick(filter) }
                    }
                    ForEach(query.tags.keys.sorted(), id: \.self) { category in
                        ForEach((query.tags[category] ?? []).sorted(), id: \.self) { value in
                            FilterChip(title: value, palette: p) { browser.toggleTag(category, value) }
                        }
                    }
                    if !query.search.isEmpty {
                        FilterChip(title: "“\(query.search)”", palette: p) { browser.query.search = "" }
                    }
                    if !query.isEmpty {
                        Button("Clear all") { browser.clearFilters() }
                            .buttonStyle(.plain)
                            .foregroundStyle(p.accent)
                    } else {
                        Text("None").foregroundStyle(p.mutedText)
                    }
                }
            }
            Text("\(shownCount.formatted()) of \(totalCount.formatted()) shown")
                .foregroundStyle(p.secondaryText)
                .fixedSize()
        }
        .font(p.font(12))
        .frame(height: 26)
    }

    static func title(_ filter: QuickFilter) -> String {
        switch filter {
        case .starred: "Starred"
        case .marketable: "Marketable"
        case .tradable: "Tradable"
        case .fluff: "Fluff"
        case .completeSets: "Complete sets"
        case .priceMoved: "Price moved"
        }
    }
}

// MARK: - Selection bar

struct SelectionBar: View {
    @Environment(AppModel.self) private var model
    let shown: [InventoryItem]
    let facts: InventoryFacts
    let onSell: ([InventoryItem]) -> Void

    var body: some View {
        let p = model.palette
        let browser = model.browser
        let selected = shown.filter { browser.selection.contains($0.id) }
        let buyerTotal = selected.reduce(0) { $0 + (facts.value(of: $1) ?? 0) * $1.amount }
        let sellable = selected.filter(\.marketable)

        HStack(spacing: 8) {
            if selected.isEmpty {
                Text("Click to select · ⌘-click to add · ⇧-click for a range")
                    .foregroundStyle(p.secondaryText)
            } else {
                Text("\(selected.count.formatted()) selected · buyers pay \(Money.format(buyerTotal, model.currency))")
                Button("Deselect") { browser.selection = [] }
                    .buttonStyle(.plain)
                    .foregroundStyle(p.accent)
            }
            Spacer()
            Button("Select fluff") {
                browser.selection = Set(shown.filter { facts.isFluff($0) && !facts.starred.contains($0.id) }.map(\.id))
            }
            .classicButton(.secondary, p)
            .help("Select every shown item worth less than \(Money.format(model.settings.fluffThresholdCents, model.currency)) that isn't starred")
            PopoverPicker(
                title: "Sort: \(browser.query.sort.title)",
                options: InventorySort.allCases.map { PickerOption(value: $0, label: $0.title) },
                selection: browser.query.sort,
                palette: p
            ) { browser.query.sort = $0 }
            Button {
                browser.query.ascending.toggle()
            } label: {
                Image(systemName: browser.query.ascending ? "arrow.up" : "arrow.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .classicButton(.secondary, p)
            .help(browser.query.ascending ? "Ascending — click for descending" : "Descending — click for ascending")
            Button("Sell selected…") { onSell(sellable) }
                .classicButton(.primary, p)
                .disabled(sellable.isEmpty)
        }
        .font(p.font(12.5))
        .padding(8)
        .classicPanel(p)
    }
}

struct PickerOption<Value: Hashable>: Identifiable {
    var value: Value
    var label: String
    var id: Value { value }
}

/// A classic-styled dropdown built from a button and a popover.
struct PopoverPicker<Value: Hashable>: View {
    var title: String
    var options: [PickerOption<Value>]
    var selection: Value
    var palette: Palette
    var onSelect: (Value) -> Void
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
        }
        .classicButton(.secondary, palette)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(options) { option in
                    SidebarRow(title: option.label, isSelected: option.value == selection, palette: palette) {
                        onSelect(option.value)
                        isOpen = false
                    }
                }
            }
            .padding(6)
            .frame(minWidth: 180)
            .background(palette.panel)
            .foregroundStyle(palette.text)
        }
    }
}

// MARK: - Grid

struct ItemGrid: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let items: [InventoryItem]
    let onSell: (InventoryItem) -> Void

    var body: some View {
        let p = model.palette
        let browser = model.browser
        ScrollView {
            if items.isEmpty {
                Text(model.contexts.isEmpty ? "Your inventory will appear here after the first sync." : "No items match these filters.")
                    .foregroundStyle(p.mutedText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 124, maximum: 170), spacing: 8)], spacing: 8) {
                ForEach(items) { item in
                    let starred = model.starred.contains(item.id)
                    ItemTile(
                        item: item,
                        price: model.prices[item.priceKey]?.valueCents,
                        currency: model.currency,
                        isSelected: browser.selection.contains(item.id),
                        isStarred: starred,
                        palette: p
                    ) {
                        model.toggleStar(item)
                    }
                    .onTapGesture { select(item) }
                    .contextMenu {
                        Button(starred ? "Unstar" : "Star") { model.toggleStar(item) }
                        if let url = item.marketURL, item.marketable {
                            Button("View on Market") { openURL(url) }
                        }
                        Button("Sell…") { onSell(item) }
                            .disabled(!item.marketable)
                    }
                }
            }
            .padding(8)
        }
        .classicInset(p)
    }

    private func select(_ item: InventoryItem) {
        let browser = model.browser
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if browser.selection.contains(item.id) {
                browser.selection.remove(item.id)
            } else {
                browser.selection.insert(item.id)
            }
        } else if flags.contains(.shift),
                  let anchor = browser.focusedID,
                  let start = items.firstIndex(where: { $0.id == anchor }),
                  let end = items.firstIndex(where: { $0.id == item.id }) {
            browser.selection.formUnion(items[min(start, end)...max(start, end)].map(\.id))
        } else {
            browser.selection = [item.id]
        }
        browser.focusedID = item.id
        if model.prices[item.priceKey] == nil {
            model.prioritizePricing(for: [item])
        }
    }
}

struct ItemTile: View {
    let item: InventoryItem
    let price: Int?
    let currency: SteamCurrency
    let isSelected: Bool
    let isStarred: Bool
    let palette: Palette
    let onStar: () -> Void

    var body: some View {
        let p = palette
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ItemArtwork(item: item, size: 128, palette: p)
                    .frame(height: 74)
                    .frame(maxWidth: .infinity)
                StarToggle(isOn: isStarred, palette: p, action: onStar)
                    .padding(4)
                if item.amount > 1 {
                    Text("×\(item.amount)")
                        .font(p.font(10.5, .bold))
                        .padding(.horizontal, 4)
                        .background(p.inset.opacity(0.85))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(4)
                }
            }
            .frame(height: 74)
            p.rarity(item).frame(height: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(p.font(11.5))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(item.marketable ? Money.format(price, currency) : "Not marketable")
                    .font(p.font(11.5))
                    .foregroundStyle(item.marketable ? p.accent : p.mutedText)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 138)
        .background(p.raised)
        .clipShape(RoundedRectangle(cornerRadius: p.corner))
        .overlay { RoundedRectangle(cornerRadius: p.corner).strokeBorder(isSelected ? p.accent : p.bevelDark, lineWidth: isSelected ? 1.5 : 1) }
        .contentShape(Rectangle())
    }
}

// MARK: - Detail

struct ItemDetailPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let item: InventoryItem?
    let onSell: (InventoryItem) -> Void

    var body: some View {
        let p = model.palette
        if let item {
            let quote = model.quote(for: item)
            let starred = model.isStarred(item)
            VStack(alignment: .leading, spacing: 9) {
                ItemArtwork(item: item, size: 256, palette: p)
                    .frame(height: 150)
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
                    if item.amount > 1 {
                        Text("Stack of \(item.amount.formatted())").foregroundStyle(p.secondaryText)
                    }
                }
                Button(starred ? "★ Starred · always kept" : "☆ Star this item") { model.toggleStar(item) }
                    .classicButton(.card, p)
                if let set = item.itemSet {
                    Text("SET: \(set.name.uppercased()) (you own \(model.ownership.owned(set, appID: item.appID)) of \(set.members.count))")
                        .foregroundStyle(p.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                priceBox(item, quote: quote, p)
                if !item.marketable {
                    Text("This item can't be sold on the Community Market.")
                        .foregroundStyle(p.mutedText)
                }
                ScrollView {
                    Text(item.details.filter { !$0.hasPrefix("Used By:") }.prefix(12).joined(separator: "\n"))
                        .font(p.font(11))
                        .foregroundStyle(p.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    Button("View on Market") {
                        if let url = item.marketURL { openURL(url) }
                    }
                    .classicButton(.secondary, p)
                    .disabled(!item.marketable)
                    Spacer()
                    Button("Sell…") { onSell(item) }
                        .classicButton(.primary, p)
                        .disabled(!item.marketable)
                }
            }
            .padding(12)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(p.mutedText)
                Text("Select an item to see its price, set, and details.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(p.mutedText)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func priceBox(_ item: InventoryItem, quote: PriceQuote?, _ p: Palette) -> some View {
        let currency = model.currency
        let value = quote?.valueCents
        return VStack(spacing: 5) {
            detailRow("Lowest listing", Money.format(quote?.lowestCents, currency), p)
            detailRow("You'd receive", Money.format(value.map { SteamFees.sellerReceives(buyerPays: $0) }, currency), p)
            if let median = quote?.medianCents {
                detailRow("Median sale", Money.format(median, currency), p)
            }
            if let volume = quote?.volume {
                detailRow("Sold in 24 hours", volume.formatted(), p)
            }
            if let change = model.monthlyChange[item.priceKey] {
                detailRow("30-day change", change.formatted(.percent.precision(.fractionLength(0))), p)
            }
            HStack {
                Text("Price checked").foregroundStyle(p.secondaryText)
                Spacer()
                if let quote {
                    Text(RelativeTime.short(quote.checkedAt))
                } else if item.marketable && !model.settings.demoMode {
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

    private func detailRow(_ title: String, _ value: String, _ p: Palette) -> some View {
        HStack {
            Text(title).foregroundStyle(p.secondaryText)
            Spacer()
            Text(value)
        }
    }
}
