# TODO

## Verify against real Steam data

- [ ] First build in Xcode 27: fix any framework API mismatches the stubbed type-check couldn't catch (see README, "What was verified").
- [ ] Load your own profile and confirm that inventory pages, the inventory directory (`g_rgAppContextData` on `/profiles/<id>/inventory/`), and `priceoverview` parse as expected.
- [ ] Confirm the Dota 2 set format in item descriptions. `ItemSetDetector` expects the set name followed by its pieces, with the pieces sharing a color. If it's wrong, capture one real description into `gaugeTests/SteamParsingTests.swift` and adjust.
- [x] Check whether `count=2000` is still the inventory page maximum. The client already falls back to 500 on HTTP 400.
- [ ] Sign in with Steam from onboarding, with a password and with the QR code. Confirm the sheet closes on its own and loads the signed-in account.
- [ ] Set your inventory to private and confirm Gauge still loads it while signed in (the inventory page and `/inventory/` JSON, sent with your session).
- [ ] Session renewal: leave Gauge signed in for more than a day (or delete only the `steamLoginSecure` cookie) and confirm the off-screen load of `steamcommunity.com/my/` brings back a fresh cookie. If Steam doesn't renew on page load, fall back to `login.steampowered.com/jwt/refresh?redir=…`.
- [ ] If Steam's sign-in page misbehaves in `WKWebView` (for example an "unsupported browser" notice), set `applicationNameForUserAgent` to Safari's in `SteamWebSession.webViewConfiguration()`.
- [ ] List one cheap item end to end: sign in, list, confirm in the Steam Mobile app, and see it leave the inventory.

## Check on a Mac (Clean up, Portfolio, network log)

- [ ] Clean up list: two-finger swipe right sells and left keeps (a full swipe acts at once), ⌫ keeps the selection and selects the next row, ⌘Z and ⇧⌘Z undo and redo from the Edit menu, and right-clicking a selection acts on all of it.
- [ ] Drag one row, then a multi-row selection, onto each bucket tab. If a selected row drags only itself, switch to the macOS 26 multi-item drag API.
- [ ] Rows dragged out of Gauge paste as text elsewhere. Consider an exported UTType for the payload.
- [ ] List selection, row separators, and swipe colors under Modern and both classic themes, including with macOS in light mode.
- [ ] Portfolio chart: axis labels fit at the window's minimum size, the hover readout stays inside the chart, and a one-day history shows its single point at the right edge.
- [ ] Network activity: Show log file opens `~/Library/Containers/tsainez.gauge/Data/Library/Logs/Gauge`, Export log saves earlier launches too, and Console.app shows the `network` category.
- [ ] Log artwork requests too (a custom image loader or `URLProtocol`), or keep saying they aren't listed.

## Screenshot dataset from a large public inventory

The goal is a realistic, image-rich dataset for App Store screenshots.

- [ ] Pick a candidate. [Steam Ladder's profile value ladder](https://steamladder.com/ladder/value/) and the [ShowMyItems leaderboard](https://showmyitems.com/leaderboard) rank public profiles by inventory value and item count.
- [ ] Add a fixture capture tool (`Tools/capture-fixture`) that saves the raw Steam responses for a profile: each inventory page plus a `priceoverview` per unique item. Keep the files raw so the app parses them with the same code as live data (`InventoryPageParser`, `PriceOverviewParser`).
- [ ] Add a Demo mode option that loads a bundled fixture instead of the synthetic set. That gives real item art, names, and prices.
- [ ] Before publishing: screenshots shouldn't show another person's name, avatar, or profile. Replace the persona with a neutral name (Demo mode already hides the profile), or get the owner's permission. Review Apple's guidelines on third-party content, and Valve's, for item art in marketing images.

## Product

- [ ] Price history: Steam's `/market/pricehistory` needs a signed-in session. When the user is signed in, backfill 30-day trends instead of waiting for Gauge's own daily points.
- [ ] Bulk pricing for huge inventories: page `/market/search/render?norender=1` (100 items a request) for games where the user owns a large share of the catalog.
- [ ] Gem breakdown: "Turn into Gems" for Steam community items as a Clean up bucket. The storyboard mentions gems.
- [ ] Show active listings and cancel them from Gauge (`/market/mylistings`, signed in).
- [ ] Notifications when net worth moves more than X% in a day.
- [ ] Localize the UI, and parse prices in every Steam currency with live samples.
- [ ] App icon and About artwork. The asset catalog is still empty.

## Engineering

- [ ] Move inventory JSON encoding and decoding fully off the main actor for very large inventories (100k+ items); consider a `ModelActor`.
- [ ] Add UI tests driven by Demo mode (`gaugeUITests`), then remove `-skip-testing:gaugeUITests` from `.github/workflows/ci.yml` so CI runs them.
- [ ] App Store review: explain the sign-in web view and the confirmation step in the review notes.
- [ ] Sign out on Steam's side too (revoke the refresh token), not only by deleting the cookies on this Mac.

## Delivery

Releases should go through Xcode Cloud, with GitHub Actions staying the pull request check. Archiving a signed build on a GitHub runner needs a signing certificate and its private key stored as repository secrets (an App Store Connect API key only covers the export and upload). Xcode Cloud manages signing itself and comes with the developer program (25 compute hours a month).

- [ ] Create the app record in App Store Connect: bundle ID `tsainez.gauge`, name Gauge.
- [ ] Add the app icon first (see Product). App Store Connect won't accept a build without one.
- [ ] Create one Xcode Cloud workflow from Xcode. Start condition: Tag Changes, tags beginning with `v`. Action: Archive for macOS, prepared for TestFlight and the App Store. Post-action: TestFlight internal testing. Leave out branch and pull request start conditions; CI already covers those, and the compute hours go further.
- [ ] To release: raise `MARKETING_VERSION` in a pull request and merge it, then tag that commit on `main` as `vX.Y.Z` and push the tag. Xcode Cloud sets the build number. Mac builds need build numbers that only go up, so upload every build through Xcode Cloud, or set its next build number above any build you uploaded by hand.
