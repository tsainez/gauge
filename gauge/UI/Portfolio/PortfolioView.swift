//
//  PortfolioView.swift
//  gauge
//
//  The home tab: marketable net worth and its history, where the value
//  sits (by game in the sidebar, by item below the chart), what moved this
//  week, and which items are owned many times over.
//

import Charts
import SwiftUI

enum ChartRange: String, CaseIterable, Identifiable {
    case week
    case month
    case lifetime

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .lifetime: nil
        }
    }
}

struct PortfolioView: View {
    @Environment(AppModel.self) private var model
    @State private var range: ChartRange = .month
    @State private var showAllGames = false

    var body: some View {
        let p = model.palette
        let holdings = PortfolioInsights.holdings(model.allItems, prices: model.prices, weeklyChange: model.weeklyChange)
        let plan = model.cleanupPlan(contextKey: nil)
        HStack(alignment: .top, spacing: 12) {
            sidebar(p)
                .frame(width: 256)
                .frame(maxHeight: .infinity, alignment: .top)
                .classicPanel(p)
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    netWorth(p)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .classicPanel(p)
                    actions(plan, p)
                        .frame(width: 310)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .classicPanel(p)
                }
                .frame(height: 340)
                HStack(alignment: .top, spacing: 12) {
                    mostValuable(holdings, p)
                    movers(holdings, p)
                    mostCopies(holdings, plan: plan, p)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Sidebar

    /// Shows up to six rows; beyond that the smallest inventories fold into "Other".
    private var gameRows: (shown: [InventoryContext], other: [InventoryContext]) {
        let contexts = model.contexts
        guard contexts.count > 6, !showAllGames else { return (contexts, []) }
        return (Array(contexts.prefix(5)), Array(contexts.dropFirst(5)))
    }

    private func sidebar(_ p: Palette) -> some View {
        let rows = gameRows
        let values = Dictionary(model.contexts.map { ($0.id, model.contextValuation($0.id)) }, uniquingKeysWith: { first, _ in first })
        let largest = values.values.map(displayCents).max() ?? 0
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("— Inventories (\(model.contexts.count))")
                    .foregroundStyle(p.accent)
                    .padding(.bottom, 4)
                ForEach(rows.shown) { context in
                    InventoryShareRow(
                        title: context.name,
                        value: valueText(values[context.id] ?? Valuation()),
                        count: context.assetCount,
                        share: share(values[context.id] ?? Valuation(), of: largest),
                        palette: p
                    ) {
                        openInventory(context.id, quick: model.settings.hideUnmarketable ? [.marketable] : [])
                    }
                }
                if !rows.other.isEmpty {
                    let other = Valuation.of(rows.other.flatMap { model.itemsByContext[$0.id] ?? [] }, prices: model.prices)
                    InventoryShareRow(
                        title: "Other (\(rows.other.count) games)",
                        value: valueText(other),
                        count: rows.other.reduce(0) { $0 + $1.assetCount },
                        share: share(other, of: largest),
                        palette: p
                    ) {
                        showAllGames = true
                    }
                }
                Text(model.settings.showAfterFees ? "Values after Steam's fees. Bars compare games." : "Values at lowest listing. Bars compare games.")
                    .font(p.font(11))
                    .foregroundStyle(p.mutedText)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                Text("— Saved views")
                    .foregroundStyle(p.accent)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                SidebarRow(title: "Fluff (under \(Money.format(model.settings.fluffThresholdCents, model.currency)))", palette: p) {
                    openInventory(model.browser.contextKey ?? model.contexts.first?.id, quick: [.fluff])
                }
                SidebarRow(title: "Complete sets", palette: p) {
                    openInventory(model.browser.contextKey ?? model.contexts.first?.id, quick: [.completeSets])
                }
                SidebarRow(title: "Price moved this week", palette: p) {
                    openInventory(model.browser.contextKey ?? model.contexts.first?.id, quick: [.priceMoved])
                }
            }
            .padding(12)
        }
    }

    private func displayCents(_ value: Valuation) -> Int {
        model.settings.showAfterFees ? value.sellerCents : value.buyerCents
    }

    private func share(_ value: Valuation, of largest: Int) -> Double {
        largest > 0 ? Double(displayCents(value)) / Double(largest) : 0
    }

    private func valueText(_ value: Valuation) -> String {
        guard value.pricedCount > 0 else { return value.marketableCount > 0 ? "Pricing…" : "—" }
        return Money.format(displayCents(value), model.currency)
    }

    private func openInventory(_ key: String?, quick: Set<QuickFilter>) {
        model.browser.show(contextKey: key, quick: quick)
        model.tab = .inventory
    }

    private func open(_ holding: Holding) {
        model.browser.show(contextKey: holding.item.contextKey, quick: [], search: holding.item.name)
        model.browser.focusedID = holding.item.id
        model.tab = .inventory
    }

    // MARK: - Net worth

    private var rangePoints: [NetWorthPoint] {
        guard let days = range.days else { return model.snapshots }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
        return model.snapshots.filter { $0.day >= start }
    }

    private func netWorth(_ p: Palette) -> some View {
        let value = model.valuation
        let points = rangePoints
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                SectionLabel("Marketable net worth", p)
                Spacer()
                HStack(spacing: 0) {
                    ForEach(ChartRange.allCases) { option in
                        Button(option.title) { range = option }
                            .classicButton(range == option ? .primary : .secondary, p)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(value.pricedCount > 0 ? Money.format(value.buyerCents, model.currency) : "—")
                    .font(p.font(40, .bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let delta = change(in: points) {
                    HStack(spacing: 3) {
                        Image(systemName: delta.cents >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(delta.text)
                    }
                    .font(p.font(13, .bold))
                    .foregroundStyle(delta.cents >= 0 ? p.positive : p.negative)
                }
            }
            Group {
                if value.pricedCount > 0 {
                    Text("You would receive about \(Text(Money.format(value.sellerCents, model.currency)).bold()) in Steam Wallet funds")
                } else {
                    Text("Prices appear here as Gauge checks the Market.")
                }
            }
            .foregroundStyle(p.secondaryText)
            if value.unpricedCount > 0 {
                Text(pricingProgress(value))
                    .font(p.font(11))
                    .foregroundStyle(p.mutedText)
            }
            NetWorthChart(points: points, range: range, palette: p, currency: model.currency)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .classicInset(p)
                .padding(.top, 4)
            Text("One point a day, saved on this Mac. History starts the day you first synced. Export it from Settings.")
                .font(p.font(11))
                .foregroundStyle(p.secondaryText)
        }
        .padding(14)
    }

    /// "1,066 of 1,528 marketable items still waiting for a price · about 45 min to go"
    private func pricingProgress(_ value: Valuation) -> String {
        let waiting = "\(value.unpricedCount.formatted()) of \(value.marketableCount.formatted()) marketable items still waiting for a price"
        let names = model.pricingQueue.count
        guard !model.settings.demoMode, names > 0, model.pricingResumesAt == nil else { return waiting }
        let minutes = Int((Double(names) * SteamClient.Endpoint.market.interval / 60).rounded(.up))
        return waiting + " · about \(minutes.formatted()) min to go"
    }

    private func change(in points: [NetWorthPoint]) -> (cents: Int, text: String)? {
        guard points.count >= 2, let first = points.first, let last = points.last, first.buyerCents > 0 else { return nil }
        let delta = last.buyerCents - first.buyerCents
        let percent = Double(delta) / Double(first.buyerCents)
        let sign = delta >= 0 ? "+" : "−"
        let label = range == .lifetime ? "all time" : "this \(range.rawValue)"
        return (delta, "\(sign)\(Money.format(abs(delta), model.currency)) (\(abs(percent).formatted(.percent.precision(.fractionLength(1))))) \(label)")
    }

    // MARK: - Actions

    private func actions(_ plan: CleanupPlan, _ p: Palette) -> some View {
        let listings = plan.listings
        let units = listings.reduce(0) { $0 + $1.item.amount }
        let receive = listings.reduce(0) { $0 + $1.totalSellerCents }
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("What do you want to do?", p)
                .padding(.bottom, 2)
            ActionCard(
                title: "Clean up my inventory",
                detail: units > 0
                    ? "\(units.formatted()) item\(units == 1 ? "" : "s") to sell for about \(Money.format(receive, model.currency))"
                    : "Sell extra copies and cheap items, by rule",
                palette: p
            ) {
                model.cleanup.step = .review
                model.tab = .cleanup
            }
            ActionCard(title: "Browse my collection", detail: "Sets, rarities, value by item", palette: p) {
                openInventory(model.browser.contextKey ?? model.contexts.first?.id, quick: model.settings.hideUnmarketable ? [.marketable] : [])
            }
            ActionCard(title: "See my starred items", detail: "Favorites are always kept out of clean up", palette: p) {
                model.browser.show(contextKey: nil, quick: [.starred])
                model.browser.contextKey = model.contexts.first { context in
                    (model.itemsByContext[context.id] ?? []).contains { model.starred.contains($0.id) }
                }?.id ?? model.browser.contextKey
                model.tab = .inventory
            }
        }
        .padding(14)
    }

    // MARK: - Insights

    private func mostValuable(_ holdings: [Holding], _ p: Palette) -> some View {
        let top = PortfolioInsights.mostValuable(holdings)
        return InsightPanel(
            title: "Most valuable",
            subtitle: "Lowest listing for one",
            empty: model.allItems.isEmpty ? "Your items appear here after the first sync." : "Prices appear here as Gauge checks the Market.",
            isEmpty: top.isEmpty,
            palette: p
        ) {
            ForEach(top) { holding in
                HoldingRow(holding: holding, detail: detail(holding), palette: p, action: { open(holding) }) {
                    Text(Money.format(holding.unitCents, model.currency))
                        .foregroundStyle(p.text)
                        .monospacedDigit()
                }
            }
        } footer: {
            EmptyView()
        }
    }

    private func movers(_ holdings: [Holding], _ p: Palette) -> some View {
        let minimum = max(model.settings.fluffThresholdCents, 10)
        let top = PortfolioInsights.movers(holdings, minimumCents: minimum)
        return InsightPanel(
            title: "Price moves this week",
            subtitle: "Items worth \(Money.format(minimum, model.currency)) or more",
            empty: "Moves show up once Gauge has a few days of prices. It checks each item daily, or weekly for fluff.",
            isEmpty: top.isEmpty,
            palette: p
        ) {
            ForEach(top) { holding in
                let change = holding.weeklyChange ?? 0
                HoldingRow(holding: holding, detail: "\(Money.format(holding.unitCents, model.currency)) · \(model.context(for: holding.item.contextKey)?.name ?? "")", palette: p, action: { open(holding) }) {
                    HStack(spacing: 3) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(abs(change).formatted(.percent.precision(.fractionLength(0))))
                    }
                    .font(p.font(12, .bold))
                    .foregroundStyle(change >= 0 ? p.positive : p.negative)
                    .monospacedDigit()
                    .help(change >= 0 ? "Up over the last 7 days" : "Down over the last 7 days")
                }
            }
        } footer: {
            EmptyView()
        }
    }

    private func mostCopies(_ holdings: [Holding], plan: CleanupPlan, _ p: Palette) -> some View {
        let top = PortfolioInsights.mostCopies(holdings)
        let rules = model.settings.cleanupRules
        let extras = plan.entries(in: .sell).filter { $0.reason.kind == .extraCopy }
        return InsightPanel(
            title: "Most copies",
            subtitle: "Clean up can sell every copy but one",
            empty: model.allItems.isEmpty ? "Your items appear here after the first sync." : "No duplicates. Nice and tidy.",
            isEmpty: top.isEmpty,
            palette: p
        ) {
            ForEach(top) { holding in
                HoldingRow(holding: holding, detail: "\(Money.format(holding.unitCents, model.currency)) each · \(model.context(for: holding.item.contextKey)?.name ?? "")", palette: p, action: { open(holding) }) {
                    Text("×\(holding.copies)")
                        .font(p.font(12.5, .bold))
                        .foregroundStyle(p.text)
                        .monospacedDigit()
                }
            }
        } footer: {
            if !top.isEmpty {
                Button {
                    let session = model.cleanup
                    session.contextKey = nil
                    session.step = .review
                    session.search = ""
                    session.show(.sell)
                    session.filter = rules.sellDuplicates ? .reason(.extraCopy) : nil
                    model.tab = .cleanup
                } label: {
                    Text(rules.sellDuplicates && !extras.isEmpty
                        ? "Sell \(extras.count.formatted()) extra copies for \(Money.format(extras.reduce(0) { $0 + $1.totalSellerCents }, model.currency))…"
                        : "Review duplicates in Clean up…")
                }
                .classicButton(.secondary, p)
            }
        }
    }

    private func detail(_ holding: Holding) -> String {
        let game = model.context(for: holding.item.contextKey)?.name ?? ""
        return holding.units > 1 ? "×\(holding.units) · \(game)" : "\(holding.item.subtitle) · \(game)"
    }
}

struct ActionCard: View {
    var title: String
    var detail: String
    var palette: Palette
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(palette.font(13))
                Text(detail).font(palette.font(11.5)).foregroundStyle(palette.secondaryText)
            }
        }
        .classicButton(.card, palette)
    }
}

/// A sidebar inventory: its value, and a bar comparing it with the largest one.
struct InventoryShareRow: View {
    var title: String
    var value: String
    var count: Int
    /// 0...1 of the largest inventory's value.
    var share: Double
    var palette: Palette
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        let p = palette
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).foregroundStyle(p.text).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(value).foregroundStyle(p.text).monospacedDigit()
                }
                HStack(spacing: 8) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(p.accent.opacity(0.15))
                            Capsule().fill(p.accent)
                                .frame(width: max(share > 0 ? 4 : 0, proxy.size.width * min(max(share, 0), 1)))
                        }
                    }
                    .frame(height: 4)
                    Text("\(count.formatted()) items")
                        .font(p.font(11))
                        .foregroundStyle(p.secondaryText)
                        .fixedSize()
                }
            }
            .font(p.font(12.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hovering && !p.bevels ? p.selection.opacity(0.45) : Color.clear, in: RoundedRectangle(cornerRadius: p.bevels ? 0 : 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open \(title) in Inventory")
    }
}

/// One of the lists under the chart.
struct InsightPanel<Content: View, Footer: View>: View {
    var title: String
    var subtitle: String
    var empty: String
    var isEmpty: Bool
    var palette: Palette
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        let p = palette
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title, p)
            Text(subtitle)
                .font(p.font(11))
                .foregroundStyle(p.mutedText)
            if isEmpty {
                Text(empty)
                    .font(p.font(12))
                    .foregroundStyle(p.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        content()
                    }
                }
                footer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .classicPanel(p)
    }
}

/// An item in an insight list: artwork, name, a detail line, and a value on the right.
struct HoldingRow<Trailing: View>: View {
    let holding: Holding
    let detail: String
    let palette: Palette
    let action: () -> Void
    @ViewBuilder let trailing: () -> Trailing
    @State private var hovering = false

    var body: some View {
        let p = palette
        Button(action: action) {
            HStack(spacing: 8) {
                ItemArtwork(item: holding.item, size: 96, palette: p)
                    .frame(width: 40, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: p.bevels ? 0 : 4))
                    .overlay(alignment: .bottom) { p.rarity(holding.item).frame(height: 2) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(holding.item.name)
                        .foregroundStyle(p.text)
                        .lineLimit(1)
                    Text(detail)
                        .font(p.font(11))
                        .foregroundStyle(p.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                trailing()
            }
            .font(p.font(12.5))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(hovering ? p.selection.opacity(0.45) : Color.clear, in: RoundedRectangle(cornerRadius: p.bevels ? 0 : 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Show \(holding.item.name) in Inventory")
    }
}

// MARK: - Chart

/// Net worth over the chosen range, with dates along the bottom, values up the
/// side, and the value under the pointer.
struct NetWorthChart: View {
    var points: [NetWorthPoint]
    var range: ChartRange
    var palette: Palette
    var currency: SteamCurrency
    @State private var hoveredDay: Date?

    var body: some View {
        if points.isEmpty {
            Text("Your first snapshot is saved once prices come in.")
                .font(palette.font(12))
                .foregroundStyle(palette.mutedText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            chart
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 8)
        }
    }

    private var chart: some View {
        let p = palette
        let values = NetWorthAxis.valueDomain(points.map(\.buyerCents))
        let hovered = nearest(to: hoveredDay)
        let last = points.last
        return Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Day", point.day),
                    yStart: .value("Value", values.lowerBound),
                    yEnd: .value("Value", dollars(point))
                )
                .foregroundStyle(LinearGradient(colors: [p.positive.opacity(0.16), p.positive.opacity(0)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("Day", point.day),
                    y: .value("Value", dollars(point))
                )
                .foregroundStyle(p.positive)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }
            if let last, hovered == nil {
                PointMark(x: .value("Day", last.day), y: .value("Value", dollars(last)))
                    .foregroundStyle(p.positive)
                    .symbolSize(70)
            }
            if let hovered {
                RuleMark(x: .value("Day", hovered.day))
                    .foregroundStyle(p.secondaryText.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        readout(hovered)
                    }
                PointMark(x: .value("Day", hovered.day), y: .value("Value", dollars(hovered)))
                    .foregroundStyle(p.positive)
                    .symbolSize(70)
            }
        }
        .chartXScale(domain: NetWorthAxis.dayDomain(points.map(\.day), window: range.days))
        .chartYScale(domain: values)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: range == .week ? 7 : 5)) { _ in
                AxisGridLine().foregroundStyle(p.gridLine)
                AxisTick().foregroundStyle(p.bevelLight.opacity(0.6))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(p.secondaryText)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(p.gridLine)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(Money.tick(Int((amount * 100).rounded()), currency))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(p.secondaryText)
            }
        }
        .chartXSelection(value: $hoveredDay)
        .chartPlotStyle { plot in
            // Hairline axis rules along the bottom and the value side.
            plot
                .overlay(alignment: .bottom) { p.bevelLight.opacity(0.5).frame(height: 1) }
                .overlay(alignment: .leading) { p.bevelLight.opacity(0.5).frame(width: 1) }
        }
        .font(p.font(11))
    }

    /// Value first, date second.
    private func readout(_ point: NetWorthPoint) -> some View {
        let p = palette
        return VStack(alignment: .center, spacing: 1) {
            Text(Money.format(point.buyerCents, currency))
                .font(p.font(12.5, .bold))
                .foregroundStyle(p.text)
            Text(point.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(p.font(11))
                .foregroundStyle(p.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(p.raised, in: RoundedRectangle(cornerRadius: p.bevels ? 0 : 5))
        .overlay { RoundedRectangle(cornerRadius: p.bevels ? 0 : 5).strokeBorder(p.bevelLight.opacity(0.5), lineWidth: 1) }
    }

    private func dollars(_ point: NetWorthPoint) -> Double {
        Double(point.buyerCents) / 100
    }

    /// The day with a snapshot closest to where the pointer is.
    private func nearest(to day: Date?) -> NetWorthPoint? {
        guard let day else { return nil }
        return points.min { abs($0.day.timeIntervalSince(day)) < abs($1.day.timeIntervalSince(day)) }
    }
}
