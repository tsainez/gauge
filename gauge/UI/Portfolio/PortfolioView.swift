//
//  PortfolioView.swift
//  gauge
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
                    actions(p)
                        .frame(width: 310)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .classicPanel(p)
                }
                .frame(height: 320)
                gamesTable(p)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .classicPanel(p)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("— Inventories (\(model.contexts.count))")
                    .foregroundStyle(p.accent)
                    .padding(.bottom, 4)
                ForEach(gameRows.shown) { context in
                    SidebarRow(title: context.name, detail: context.assetCount.formatted(), palette: p) {
                        openInventory(context.id, quick: model.settings.hideUnmarketable ? [.marketable] : [])
                    }
                }
                let other = gameRows.other
                if !other.isEmpty {
                    SidebarRow(
                        title: "Other (\(other.count) games)",
                        detail: other.reduce(0) { $0 + $1.assetCount }.formatted(),
                        palette: p
                    ) {
                        showAllGames = true
                    }
                }

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

    private func openInventory(_ key: String?, quick: Set<QuickFilter>) {
        model.browser.show(contextKey: key, quick: quick)
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
                    Text(delta.text)
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
                Text("\(value.unpricedCount.formatted()) of \(value.marketableCount.formatted()) marketable items still waiting for a price")
                    .font(p.font(11))
                    .foregroundStyle(p.mutedText)
            }
            NetWorthChart(points: points, palette: p, currency: model.currency)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .classicInset(p)
                .padding(.top, 4)
            Text("Snapshots are saved on this Mac only. History starts the day you first sync.")
                .font(p.font(11))
                .foregroundStyle(p.secondaryText)
        }
        .padding(14)
    }

    private func change(in points: [NetWorthPoint]) -> (cents: Int, text: String)? {
        guard points.count >= 2, let first = points.first, let last = points.last, first.buyerCents > 0 else { return nil }
        let delta = last.buyerCents - first.buyerCents
        let percent = Double(delta) / Double(first.buyerCents)
        let sign = delta >= 0 ? "+" : "−"
        let label = range == .lifetime ? "all time" : "this \(range.rawValue)"
        return (delta, "\(sign)\(Money.format(abs(delta), model.currency)) (\(percent.formatted(.percent.precision(.fractionLength(1))))) \(label)")
    }

    // MARK: - Actions

    private func actions(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("What do you want to do?", p)
                .padding(.bottom, 2)
            ActionCard(title: "Clean up my inventory", detail: "Bulk sell, or keep, by rule", palette: p) {
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

    // MARK: - Games table

    private func gamesTable(_ p: Palette) -> some View {
        VStack(spacing: 0) {
            GameTableRow(
                cells: ["Game", "Items", "Marketable", "Prices as of", "Value"],
                palette: p,
                isHeader: true
            )
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(gameRows.shown) { context in
                        let items = model.itemsByContext[context.id] ?? []
                        let value = model.contextValuation(context.id)
                        Button {
                            openInventory(context.id, quick: model.settings.hideUnmarketable ? [.marketable] : [])
                        } label: {
                            GameTableRow(
                                cells: [
                                    context.name,
                                    items.count.formatted(),
                                    value.marketableCount.formatted(),
                                    pricesAsOf(context.id, value: value),
                                    valueText(value),
                                ],
                                palette: p,
                                isHeader: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    let other = gameRows.other
                    if !other.isEmpty {
                        let items = other.flatMap { model.itemsByContext[$0.id] ?? [] }
                        let value = Valuation.of(items, prices: model.prices)
                        Button {
                            showAllGames = true
                        } label: {
                            GameTableRow(
                                cells: ["Other (\(other.count) games)", items.count.formatted(), value.marketableCount.formatted(), "—", valueText(value)],
                                palette: p,
                                isHeader: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func valueText(_ value: Valuation) -> String {
        guard value.pricedCount > 0 else { return value.marketableCount > 0 ? "Pricing…" : "—" }
        return Money.format(model.settings.showAfterFees ? value.sellerCents : value.buyerCents, model.currency)
    }

    private func pricesAsOf(_ key: String, value: Valuation) -> String {
        guard value.marketableCount > 0 else { return "—" }
        if value.unpricedCount > 0 && value.pricedCount == 0 { return "Pricing…" }
        return RelativeTime.day(model.oldestPriceCheck(in: key))
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

struct GameTableRow: View {
    var cells: [String]
    var palette: Palette
    var isHeader: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                Text(cell)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: index == cells.count - 1 ? .trailing : .leading)
                    .layoutPriority(index == 0 ? 1 : 0)
            }
        }
        .font(palette.font(12.5))
        .foregroundStyle(isHeader ? palette.accent : palette.text)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            (isHeader ? palette.bevelDark : palette.gridLine).frame(height: 1)
        }
    }
}

struct NetWorthChart: View {
    var points: [NetWorthPoint]
    var palette: Palette
    var currency: SteamCurrency

    var body: some View {
        if points.isEmpty {
            Text("Your first snapshot is saved once prices come in.")
                .font(palette.font(12))
                .foregroundStyle(palette.mutedText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart(points) { point in
                LineMark(
                    x: .value("Day", point.day),
                    y: .value("Value", Double(point.buyerCents) / 100)
                )
                .foregroundStyle(palette.positive)
                .lineStyle(StrokeStyle(lineWidth: 2))
                if points.count == 1 {
                    PointMark(
                        x: .value("Day", point.day),
                        y: .value("Value", Double(point.buyerCents) / 100)
                    )
                    .foregroundStyle(palette.positive)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(palette.gridLine)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .padding(10)
            .help(helpText)
        }
    }

    private var helpText: String {
        guard let first = points.first, let last = points.last else { return "" }
        return "\(first.day.formatted(date: .abbreviated, time: .omitted)): \(Money.format(first.buyerCents, currency))\n\(last.day.formatted(date: .abbreviated, time: .omitted)): \(Money.format(last.buyerCents, currency))"
    }
}
