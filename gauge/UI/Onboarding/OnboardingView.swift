//
//  OnboardingView.swift
//  gauge
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var input = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        let p = model.palette
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Welcome", p)
            Text("Gauge")
                .font(p.font(30, .bold))
            Text("See what your Steam inventory is worth, keep a history of it, and clear out years of drops by rule instead of one listing at a time.")
                .foregroundStyle(p.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Your Steam profile")
                HStack(spacing: 8) {
                    TextField("Profile link, custom URL, or SteamID64", text: $input)
                        .classicField(p)
                        .onSubmit(connect)
                        .disabled(working)
                    Button(working ? "Loading…" : "Load inventory", action: connect)
                        .classicButton(.primary, p)
                        .disabled(working || input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("For example steamcommunity.com/id/yourname or 76561198000000000")
                    .font(p.font(11))
                    .foregroundStyle(p.mutedText)
            }
            .padding(.top, 6)

            if working, let label = model.syncPhase.label {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(label).foregroundStyle(p.secondaryText)
                }
            }
            if let error {
                Text(error)
                    .foregroundStyle(p.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Your inventory needs to be public. Gauge reads the same public pages your browser shows, keeps everything on this Mac, and never asks for your Steam password or an API key to show your net worth.")
                .font(p.font(11.5))
                .foregroundStyle(p.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .classicInset(p)

            HStack {
                Button("Try the demo inventory") { model.enterDemo() }
                    .classicButton(.secondary, p)
                    .disabled(working)
                Spacer()
                Text("Not affiliated with Valve Corporation.")
                    .font(p.font(11))
                    .foregroundStyle(p.mutedText)
            }
        }
        .padding(28)
        .frame(width: 560)
        .classicPanel(p)
    }

    private func connect() {
        let text = input
        guard !working, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        working = true
        error = nil
        Task {
            error = await model.connect(to: text)
            working = false
        }
    }
}
