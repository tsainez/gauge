//
//  SteamSignInSheet.swift
//  gauge
//
//  Steam's own sign-in page in a web view. Gauge only watches for the
//  session cookie Steam sets once the user is signed in.
//

import AppKit
import SwiftUI
import WebKit

struct SteamSignInSheet: View {
    enum Purpose {
        /// Signing in to Gauge itself: who you are, private inventories, and listing.
        case account
        /// Signing in from Clean up, to list items.
        case listing

        var title: String {
            switch self {
            case .account: "Sign in with Steam"
            case .listing: "Sign in with Steam to list items"
            }
        }

        var detail: String {
            switch self {
            case .account:
                "Use your password, or scan the QR code with the Steam Mobile app. Gauge never sees your password; it keeps only the session Steam creates, on this Mac. It lets Gauge read your inventory even when it's private, and list items when you clean up."
            case .listing:
                "Gauge never sees your password; it keeps only the session Steam creates, on this Mac. You'll still confirm every listing in the Steam Mobile app."
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var purpose: Purpose = .account
    /// Called with the signed-in SteamID64 just before the sheet closes.
    var onSignedIn: (String) -> Void = { _ in }

    @State private var page: URL?
    @State private var finished = false

    var body: some View {
        let p = model.palette
        let secure = page.map { $0.scheme == "https" } ?? true
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(purpose.title).font(p.font(14, .bold))
                    Text(purpose.detail)
                        .font(p.font(11.5))
                        .foregroundStyle(p.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .classicButton(.secondary, p)
            }
            .padding(14)
            .background(p.panel)

            // There's no address bar in a sheet, so show where the page really is.
            HStack(spacing: 6) {
                Image(systemName: secure ? "lock.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(secure ? p.positive : p.negative)
                Text(page?.host ?? SteamWebSession.loginURL.host ?? "")
                    .foregroundStyle(p.text)
                    .textSelection(.enabled)
                Spacer()
                Text("Steam's own sign-in page")
            }
            .font(p.font(11.5))
            .foregroundStyle(p.secondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .classicInset(p)

            SteamWebView(url: SteamWebSession.loginURL) { url in
                page = url
                Task { await checkSignedIn() }
            }
        }
        .frame(width: 820, height: 680)
        .background(p.window)
        .foregroundStyle(p.text)
        .task {
            // Steam's page sets the cookie from script before it navigates, so don't wait on navigation alone.
            while !Task.isCancelled && !finished {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await checkSignedIn()
            }
        }
    }

    private func checkSignedIn() async {
        guard !finished else { return }
        await model.web.refresh(renewIfNeeded: false)
        guard !finished, let steamID = model.web.signedInSteamID else { return }
        finished = true
        onSignedIn(steamID)
        dismiss()
    }
}

struct SteamWebView: NSViewRepresentable {
    let url: URL
    /// Called with the page's address whenever a page finishes loading.
    let onNavigation: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigation: onNavigation)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: SteamWebSession.webViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onNavigation: (URL?) -> Void

        init(onNavigation: @escaping (URL?) -> Void) {
            self.onNavigation = onNavigation
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onNavigation(webView.url)
        }

        /// Keeps the sheet on Steam's sign-in pages. Links anywhere else open in the browser.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }
            // Frames inside the page (a captcha, for example) load wherever they need to.
            if let frame = navigationAction.targetFrame, !frame.isMainFrame { return .allow }
            if SteamSignInPage.keepsInSheet(url) {
                if navigationAction.targetFrame == nil {
                    // A link that asked for a new window: there's only this one.
                    webView.load(navigationAction.request)
                    return .cancel
                }
                return .allow
            }
            NSWorkspace.shared.open(url)
            return .cancel
        }
    }
}
