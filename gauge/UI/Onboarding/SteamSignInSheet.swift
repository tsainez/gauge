//
//  SteamSignInSheet.swift
//  gauge
//
//  Steam's own sign-in page in a web view. Gauge only watches for the
//  session cookie Steam sets once the user is signed in.
//

import SwiftUI
import WebKit

struct SteamSignInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let p = model.palette
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sign in to Steam to list items").font(p.font(14, .bold))
                    Text("This is steamcommunity.com. Gauge never sees your password; it keeps only the session Steam creates, on this Mac. You'll still confirm every listing in the Steam Mobile app.")
                        .font(p.font(11.5))
                        .foregroundStyle(p.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .classicButton(.secondary, p)
            }
            .padding(14)
            .background(p.panel)

            SteamWebView(url: SteamWebSession.loginURL) {
                Task {
                    await model.web.refresh()
                    if model.web.isSignedIn { dismiss() }
                }
            }
        }
        .frame(width: 820, height: 680)
        .background(p.window)
        .foregroundStyle(p.text)
    }
}

struct SteamWebView: NSViewRepresentable {
    let url: URL
    let onNavigation: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigation: onNavigation)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onNavigation: () -> Void

        init(onNavigation: @escaping () -> Void) {
            self.onNavigation = onNavigation
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onNavigation()
        }
    }
}
