//
//  OnboardingView.swift
//  gauge
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var input = ""
    @State private var error: String?
    @State private var working = false
    @State private var showingSignIn = false

    var body: some View {
        let p = model.palette
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Welcome", p)
            Text("Gauge")
                .font(p.font(30, .bold))
            Text("See what your Steam inventory is worth, keep a history of it, and clear out years of drops by rule instead of one listing at a time.")
                .foregroundStyle(p.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            signIn(p)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                Text("Or look up a public profile without signing in")
                HStack(spacing: 8) {
                    TextField("Profile link, custom URL, or SteamID64", text: $input)
                        .classicField(p)
                        .onSubmit(lookUp)
                        .disabled(working)
                    Button("Load inventory", action: lookUp)
                        .classicButton(.secondary, p)
                        .disabled(working || input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("For example steamcommunity.com/id/yourname or 76561198000000000. The inventory has to be public.")
                    .font(p.font(11))
                    .foregroundStyle(p.mutedText)
            }

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

            VStack(alignment: .leading, spacing: 6) {
                Text("Gauge keeps your inventory, prices, and history on this Mac. It never sees your Steam password and doesn't need an API key.")
                    .foregroundStyle(p.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Privacy policy") { openURL(GaugeLinks.privacyPolicy) }
                    .buttonStyle(.plain)
                    .foregroundStyle(p.accent)
            }
            .font(p.font(11.5))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .sheet(isPresented: $showingSignIn) {
            SteamSignInSheet(purpose: .account) { _ in connectSignedIn() }
                .environment(model)
        }
        .task { await model.web.refresh(renewIfNeeded: false) }
    }

    @ViewBuilder
    private func signIn(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let steamID = model.web.signedInSteamID {
                // Still signed in from before, for example after Change profile.
                HStack(spacing: 8) {
                    Button(working ? "Loading…" : "Continue with your Steam account", action: connectSignedIn)
                        .classicButton(.primary, p)
                        .disabled(working)
                    Button("Use a different account") {
                        Task {
                            await model.web.signOut()
                            showingSignIn = true
                        }
                    }
                    .classicButton(.secondary, p)
                    .disabled(working)
                }
                Text("Signed in to Steam as \(steamID)")
                    .font(p.font(11))
                    .foregroundStyle(p.mutedText)
                    .textSelection(.enabled)
            } else {
                Button(working ? "Loading…" : "Sign in with Steam") { showingSignIn = true }
                    .classicButton(.primary, p)
                    .disabled(working)
                Text("On Steam's own page, with your password or the QR code in the Steam Mobile app. Signing in lets Gauge read your inventory even when it's private, and list items when you clean up.")
                    .font(p.font(11))
                    .foregroundStyle(p.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func connectSignedIn() {
        run { await model.connectSignedInAccount() }
    }

    private func lookUp() {
        let text = input
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        run { await model.connect(to: text) }
    }

    /// Runs one connect attempt at a time and shows its error, if any.
    private func run(_ attempt: @escaping () async -> String?) {
        guard !working else { return }
        working = true
        error = nil
        Task {
            error = await attempt()
            working = false
        }
    }
}
