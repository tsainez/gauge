//
//  SettingsView.swift
//  gauge
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SwiftData

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var confirmingClear = false
    @State private var showingSignIn = false
    @State private var problemsOnly = false

    var body: some View {
        let p = model.palette
        HStack(alignment: .top, spacing: 12) {
            about(p)
                .frame(width: 340)
                .frame(maxHeight: .infinity, alignment: .top)
                .classicPanel(p)
            ScrollView {
                VStack(spacing: 12) {
                    appearance(p).classicPanel(p)
                    HStack(alignment: .top, spacing: 12) {
                        pricing(p).classicPanel(p)
                        inventory(p).classicPanel(p)
                    }
                    account(p).classicPanel(p)
                    network(p).classicPanel(p)
                    data(p).classicPanel(p)
                }
            }
        }
        .sheet(isPresented: $showingSignIn) {
            SteamSignInSheet(purpose: .account) { steamID in
                // A private inventory may have been out of reach until now.
                if steamID == model.settings.profile?.steamID64 {
                    Task { await model.syncInventories(force: false) }
                }
            }
            .environment(model)
        }
        .confirmationDialog("Clear everything Gauge has saved on this Mac?", isPresented: $confirmingClear) {
            Button("Clear Local Data", role: .destructive) { clearData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the inventory cache, prices, net worth history, stars, clean-up choices, the listing log, and the network log. Your Steam account and items aren't affected.")
        }
    }

    // MARK: - About

    private func about(_ p: Palette) -> some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("About", p)
            Text("Gauge").font(p.font(26, .bold))
            Text("Version \(version)").foregroundStyle(p.secondaryText)
            Text("Gauge is a companion app for the Steam Community Market. It shows what your marketable items are worth, keeps a history of that value over time, and helps you clean out years of drops by rule instead of one listing at a time.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Your inventory, prices, and history are stored on this Mac and nowhere else. Gauge never asks for your Steam password or API key to show your net worth.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Not affiliated with or endorsed by Valve Corporation.")
                .font(p.font(11.5))
                .foregroundStyle(p.secondaryText)
            Spacer()
            HStack {
                Button("Steam privacy settings") {
                    openURL(URL(string: "https://steamcommunity.com/my/edit/settings")!)
                }
                .classicButton(.secondary, p)
                Button("Source code") {
                    openURL(URL(string: "https://github.com/tsainez/gauge")!)
                }
                .classicButton(.secondary, p)
            }
        }
        .padding(16)
    }

    // MARK: - Appearance

    private func appearance(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Appearance", p)
            HStack(spacing: 10) {
                ForEach(ThemeChoice.allCases) { theme in
                    let swatch = Palette.named(theme)
                    let selected = !model.settings.matchSystemAppearance && model.settings.theme == theme
                    Button {
                        model.updateSettings {
                            $0.theme = theme
                            $0.matchSystemAppearance = false
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 0) {
                                ForEach(Array(swatch.swatches.enumerated()), id: \.offset) { index, color in
                                    color.frame(maxWidth: index < 2 ? .infinity : 36)
                                }
                            }
                            .frame(height: 42)
                            HStack(spacing: 6) {
                                RadioDot(isOn: selected, palette: p)
                                Text(theme.title)
                            }
                        }
                        .padding(8)
                        .background(p.inset, in: RoundedRectangle(cornerRadius: p.corner))
                        .overlay { RoundedRectangle(cornerRadius: p.corner).strokeBorder(selected ? p.accent : p.bevelDark, lineWidth: selected ? 1.5 : 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Toggle("Match macOS appearance (Classic by day, Classic Dark by night)", isOn: model.binding(\.matchSystemAppearance))
                .toggleStyle(ClassicCheckboxStyle(palette: p))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pricing

    private func pricing(_ p: Palette) -> some View {
        let settings = model.settings
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Pricing", p)
            settingRow("Currency", p) {
                PopoverPicker(
                    title: settings.currency.label,
                    options: SteamCurrency.allCases.map { PickerOption(value: $0, label: $0.label) },
                    selection: settings.currency,
                    palette: p
                ) { value in model.updateSettings { $0.currency = value } }
            }
            settingRow("Count items as fluff under", p) {
                PopoverPicker(
                    title: Money.format(settings.fluffThresholdCents, settings.currency),
                    options: [4, 5, 10, 25, 50, 100].map { PickerOption(value: $0, label: Money.format($0, settings.currency)) },
                    selection: settings.fluffThresholdCents,
                    palette: p
                ) { value in model.updateSettings { $0.fluffThresholdCents = value } }
            }
            settingRow("Refresh valuable items", p) {
                intervalPicker(settings.refreshValuable, [.hourly, .sixHours, .daily, .weekly, .manually], p) { value in
                    model.updateSettings { $0.refreshValuable = value }
                }
            }
            settingRow("Refresh fluff", p) {
                intervalPicker(settings.refreshFluff, [.daily, .weekly, .manually], p) { value in
                    model.updateSettings { $0.refreshFluff = value }
                }
            }
            Toggle("Show values after Steam fees", isOn: model.binding(\.showAfterFees))
                .toggleStyle(ClassicCheckboxStyle(palette: p))
            Text("Steam allows about 20 price checks a minute, so a large inventory takes a while to price the first time. Gauge keeps going in the background and remembers where it left off.")
                .font(p.font(11))
                .foregroundStyle(p.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Inventory

    private func inventory(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Inventory", p)
            Toggle("Hide items that can't be sold", isOn: model.binding(\.hideUnmarketable))
                .toggleStyle(ClassicCheckboxStyle(palette: p))
            Toggle("Protect starred items from clean up", isOn: model.binding(\.protectStarred))
                .toggleStyle(ClassicCheckboxStyle(palette: p))
            Toggle("Show the menu bar net worth", isOn: model.binding(\.showMenuBarNetWorth))
                .toggleStyle(ClassicCheckboxStyle(palette: p))
            settingRow("Check for inventory changes", p) {
                intervalPicker(model.settings.inventoryCheck, [.hourly, .sixHours, .daily, .manually], p) { value in
                    model.updateSettings { $0.inventoryCheck = value }
                }
            }
            HStack {
                Button("Refresh now") { Task { await model.syncInventories(force: true) } }
                    .classicButton(.secondary, p)
                    .disabled(model.settings.demoMode || model.syncPhase.isBusy)
                Text(model.lastInventoryCheck.map { "Last checked \(RelativeTime.short($0))" } ?? "Not checked yet")
                    .font(p.font(11))
                    .foregroundStyle(p.secondaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Account

    private func account(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Steam account", p)
            HStack {
                if model.settings.demoMode {
                    if let profile = model.settings.profile {
                        Text("Showing demo data. Nothing is sent to Steam. Exiting returns to \(profile.personaName).")
                    } else {
                        Text("Showing demo data. Nothing is sent to Steam.")
                    }
                } else if let profile = model.settings.profile {
                    Text("Profile: \(profile.personaName) · \(profile.steamID64)")
                        .textSelection(.enabled)
                }
                Spacer()
                if model.settings.demoMode {
                    Button(model.settings.profile == nil ? "Exit demo and add my profile" : "Exit demo") {
                        Task { await model.exitDemo() }
                    }
                    .classicButton(.primary, p)
                } else {
                    Button("Change profile…") {
                        model.signOutOfProfile()
                    }
                    .classicButton(.secondary, p)
                }
            }
            if !model.settings.demoMode {
                HStack {
                    signInSummary(p)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if model.web.isSignedIn {
                        Button("Sign out of Steam") { Task { await model.web.signOut() } }
                            .classicButton(.secondary, p)
                    } else if model.web.status.hasExpired {
                        Button("Sign in again…") { showingSignIn = true }
                            .classicButton(.primary, p)
                    } else {
                        Button("Sign in with Steam…") { showingSignIn = true }
                            .classicButton(.secondary, p)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func signInSummary(_ p: Palette) -> some View {
        let text: String
        var color = p.secondaryText
        if let id = model.web.signedInSteamID {
            if id == model.settings.profile?.steamID64 {
                text = model.web.isRenewing
                    ? "Signed in with Steam. Renewing the session…"
                    : "Signed in with Steam. Gauge can read your inventory even when it's private, and list items. The session renews on its own."
                color = p.text
            } else {
                text = "Signed in to Steam as \(id), which isn't the profile above. Gauge won't use it to read inventories or list items."
                color = p.negative
            }
        } else if model.web.status.hasExpired {
            text = "Your Steam sign-in ran out and couldn't be renewed. Sign in again to list items or read a private inventory."
            color = p.negative
        } else {
            text = "Not signed in. Only needed to list items or to read a private inventory; public inventories and prices work without it."
        }
        return Text(text).foregroundStyle(color)
    }

    // MARK: - Network

    private func network(_ p: Palette) -> some View {
        let activity = model.network
        let total = activity.total
        let recent = activity.events.reversed().filter { !problemsOnly || $0.isProblem }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SectionLabel("Network activity", p)
                Spacer()
                Button("Copy") { copyLog() }
                    .classicButton(.secondary, p)
                    .disabled(activity.events.isEmpty)
                    .help("Copy this session's requests")
                Button("Show log file") { revealLog() }
                    .classicButton(.secondary, p)
                    .disabled(activity.file == nil)
                Button("Export log…") { exportLog() }
                    .classicButton(.secondary, p)
                    .help("Save every logged request, including earlier launches, as a text file")
                Button("Clear") { activity.clear() }
                    .classicButton(.secondary, p)
            }
            Text("Gauge talks to steamcommunity.com and nothing else. Logs never include your password, cookies, or session tokens.")
                .font(p.font(11.5))
                .foregroundStyle(p.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Since \(activity.startedAt.formatted(date: .omitted, time: .shortened)): \(total.requests.formatted()) request\(total.requests == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: Int64(total.bytes), countStyle: .file)) received · \(total.problems.formatted()) with problems")
                .font(p.font(12.5, .bold))

            VStack(spacing: 0) {
                kindRow(nil, p)
                ForEach(NetworkEvent.Kind.allCases, id: \.self) { kind in
                    kindRow(kind, p)
                }
            }
            .classicInset(p)
            if let queue = pricingQueueLine {
                Text(queue)
                    .font(p.font(11.5))
                    .foregroundStyle(p.secondaryText)
            }

            HStack {
                Text("Recent requests")
                Spacer()
                Toggle("Problems only", isOn: $problemsOnly)
                    .toggleStyle(ClassicCheckboxStyle(palette: p))
            }
            .padding(.top, 4)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if recent.isEmpty {
                        Text(model.settings.demoMode ? "Demo mode doesn't send anything to Steam." : (problemsOnly ? "No problems this session." : "Nothing sent yet this session."))
                            .foregroundStyle(p.mutedText)
                            .padding(10)
                    }
                    ForEach(recent) { event in
                        NetworkEventRow(event: event, palette: p)
                    }
                }
            }
            .frame(height: 230)
            .classicInset(p)
            Text("Item images load from Steam's image servers (community.akamai.steamstatic.com) and are cached on this Mac; they aren't listed here. The log file keeps about 2 MB, newest last.")
                .font(p.font(11))
                .foregroundStyle(p.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One kind of request with its totals and pace; nil draws the header.
    private func kindRow(_ kind: NetworkEvent.Kind?, _ p: Palette) -> some View {
        let totals = kind.flatMap { model.network.totals[$0] } ?? NetworkTotals()
        let pace = kind.flatMap(SteamClient.Endpoint.init).map { "every \($0.interval.formatted(.number.precision(.fractionLength(0...1)))) s" } ?? "as needed"
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(kind?.title ?? "Kind")
                if let kind {
                    Text(kind.detail)
                        .font(p.font(11))
                        .foregroundStyle(p.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(kind == nil ? "Requests" : totals.requests.formatted())
                .frame(width: 70, alignment: .trailing)
            Text(kind == nil ? "Problems" : totals.problems.formatted())
                .foregroundStyle(kind != nil && totals.problems > 0 ? p.negative : (kind == nil ? p.accent : p.text))
                .frame(width: 70, alignment: .trailing)
            Text(kind == nil ? "Average" : totals.averageDuration.map { "\($0.formatted(.number.precision(.fractionLength(2)))) s" } ?? "—")
                .frame(width: 70, alignment: .trailing)
            Text(kind == nil ? "Pace" : pace)
                .frame(width: 90, alignment: .trailing)
            Group {
                if let kind, let resume = model.network.resumesAt(kind) {
                    Text("Paused until \(resume.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(p.negative)
                        .help("Steam asked Gauge to slow down. Requests of this kind wait until then.")
                } else {
                    Text(kind == nil ? "Last" : totals.lastAt.map { RelativeTime.short($0) } ?? "—")
                }
            }
            .frame(width: 150, alignment: .trailing)
        }
        .font(p.font(12))
        .foregroundStyle(kind == nil ? p.accent : p.text)
        .monospacedDigit()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { p.gridLine.frame(height: 1) }
    }

    private var pricingQueueLine: String? {
        let count = model.pricingQueue.count
        guard !model.settings.demoMode, count > 0 else { return nil }
        let minutes = Int((Double(count) * SteamClient.Endpoint.market.interval / 60).rounded(.up))
        return "Pricing queue: \(count.formatted()) item\(count == 1 ? "" : "s") left, about \(minutes.formatted()) min at Steam's pace."
    }

    private func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.network.sessionLog, forType: .string)
    }

    private func revealLog() {
        guard let file = model.network.file else { return }
        if FileManager.default.fileExists(atPath: file.url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file.url])
        } else {
            let folder = file.url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
    }

    private func exportLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Gauge network log.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let header = """
        Gauge network log
        Exported \(Date().formatted(.iso8601)) · Gauge \(version) · \(ProcessInfo.processInfo.operatingSystemVersionString)
        Requests to Steam only. No passwords, cookies, session ids, or request bodies.
        """
        do {
            try model.network.exportText(header: header).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            model.notice = "Couldn't save the log: \(error.localizedDescription)"
        }
    }

    // MARK: - Data

    private func data(_ p: Palette) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Data on this Mac", p)
                Text("Inventory cache, price history, and daily net worth snapshots · \(storeSize())")
            }
            Spacer()
            Button("Export history (CSV)") { exportHistory() }
                .classicButton(.secondary, p)
                .disabled(model.snapshots.isEmpty)
            Button("Clear local data…") { confirmingClear = true }
                .classicButton(.secondary, p)
        }
        .padding(14)
    }

    // MARK: - Helpers

    private func settingRow<Control: View>(_ title: String, _ p: Palette, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            control()
        }
    }

    private func intervalPicker(_ value: RefreshInterval, _ options: [RefreshInterval], _ p: Palette, onSelect: @escaping (RefreshInterval) -> Void) -> some View {
        PopoverPicker(
            title: value.title,
            options: options.map { PickerOption(value: $0, label: $0.title) },
            selection: value,
            palette: p,
            onSelect: onSelect
        )
    }

    /// Size of the store folder: the SwiftData files plus externally stored inventory payloads.
    private func storeSize() -> String {
        guard let url = model.container.configurations.first?.url else { return "—" }
        let folder = url.deletingLastPathComponent().path
        let storeName = url.deletingPathExtension().lastPathComponent
        var total = 0
        let paths = FileManager.default.subpaths(atPath: folder) ?? []
        for path in paths where path.hasPrefix(storeName) || path.hasPrefix("." + storeName) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: folder + "/" + path)
            total += (attributes?[.size] as? Int) ?? 0
        }
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Gauge net worth history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.historyCSV().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            model.notice = "Couldn't save the CSV: \(error.localizedDescription)"
        }
    }

    private func clearData() {
        let demo = model.settings.demoMode
        model.clearLocalData(keepSettings: true)
        if demo {
            model.loadDemo()
        } else {
            Task {
                await model.syncInventories(force: true)
                model.startScheduler()
            }
        }
    }
}

/// One request in the recent list: time, kind, status, timing, size, and address.
struct NetworkEventRow: View {
    let event: NetworkEvent
    let palette: Palette

    var body: some View {
        let p = palette
        HStack(spacing: 10) {
            Text(event.startedAt.formatted(date: .omitted, time: .standard))
                .foregroundStyle(p.secondaryText)
                .frame(width: 84, alignment: .leading)
            Text(event.kind.title)
                .frame(width: 80, alignment: .leading)
            Text(event.method)
                .foregroundStyle(p.secondaryText)
                .frame(width: 40, alignment: .leading)
            Text(event.status.map(String.init) ?? "—")
                .foregroundStyle(statusColor)
                .frame(width: 34, alignment: .leading)
            Text("\(event.duration.formatted(.number.precision(.fractionLength(2)))) s")
                .frame(width: 58, alignment: .trailing)
            Text(ByteCountFormatter.string(fromByteCount: Int64(event.bytes), countStyle: .file))
                .foregroundStyle(p.secondaryText)
                .frame(width: 70, alignment: .trailing)
            if event.signedIn {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(p.secondaryText)
                    .help("Sent with your Steam sign-in")
            }
            Text(event.path)
                .lineLimit(1)
                .truncationMode(.middle)
            if let outcome = event.outcomeText {
                Text(outcome)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(p.font(11.5))
        .foregroundStyle(p.text)
        .monospacedDigit()
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { p.gridLine.frame(height: 1) }
        .textSelection(.enabled)
        .help(event.logLine)
    }

    private var statusColor: Color {
        switch event.outcome {
        case .ok: palette.secondaryText
        case .rateLimited: palette.accent
        case .failed: palette.negative
        case .cancelled: palette.mutedText
        }
    }
}
