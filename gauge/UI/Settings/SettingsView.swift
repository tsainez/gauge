//
//  SettingsView.swift
//  gauge
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var confirmingClear = false
    @State private var showingSignIn = false

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
                    data(p).classicPanel(p)
                }
            }
        }
        .sheet(isPresented: $showingSignIn) {
            SteamSignInSheet().environment(model)
        }
        .confirmationDialog("Clear everything Gauge has saved on this Mac?", isPresented: $confirmingClear) {
            Button("Clear Local Data", role: .destructive) { clearData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the inventory cache, prices, net worth history, stars, and the listing log. Your Steam account and items aren't affected.")
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
                        .background(p.inset)
                        .overlay(Rectangle().strokeBorder(selected ? p.accent : p.bevelDark, lineWidth: 1))
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
                    Text("Showing demo data. Nothing is sent to Steam.")
                } else if let profile = model.settings.profile {
                    Text("Profile: \(profile.personaName) · \(profile.steamID64)")
                        .textSelection(.enabled)
                }
                Spacer()
                Button(model.settings.demoMode ? "Use my own profile…" : "Change profile…") {
                    model.signOutOfProfile()
                }
                .classicButton(.secondary, p)
            }
            if !model.settings.demoMode {
                HStack {
                    if let id = model.web.signedInSteamID {
                        let matches = id == model.settings.profile?.steamID64
                        Text(matches ? "Signed in for selling." : "Signed in for selling as \(id), which isn't the profile above.")
                            .foregroundStyle(matches ? p.text : p.negative)
                    } else {
                        Text("Not signed in. Only needed to list items; browsing and prices work without it.")
                            .foregroundStyle(p.secondaryText)
                    }
                    Spacer()
                    if model.web.isSignedIn {
                        Button("Sign out of Steam") { Task { await model.web.signOut() } }
                            .classicButton(.secondary, p)
                    } else {
                        Button("Sign in…") { showingSignIn = true }
                            .classicButton(.secondary, p)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
