# Gauge

A macOS companion for the Steam Community Market. It shows what your marketable items are worth across every inventory, keeps a daily history of that value, and clears out years of drops by rule instead of one listing at a time.

The working title is Steam Gauge. It will ship on the App Store as **Gauge**, so the app never uses "Steam" in its own name.

## What's in the MVP

| Tab | What it does |
| --- | --- |
| **Portfolio** | Marketable net worth (what buyers pay, and what you'd receive after fees) with a Week, Month, or Lifetime chart from daily snapshots: dates along the bottom, values up the side, and the value under the pointer. Below it, your most valuable items, the week's biggest price moves, and the items you own the most copies of, each with artwork. The sidebar shows each game's value with a bar to compare them, plus saved views (Fluff, Complete sets, Price moved this week). |
| **Inventory** | A grid like Steam's inventory page with filters built from Steam's own tags (rarity, quality, type, slot, hero, and so on), search, sort by value, rarity, name, or newest, stars, multi-select (⌘-click, ⇧-click), set ownership ("you own 3 of 5"), and a Sell sheet. |
| **Clean up** | Rules on the left pick what to sell: **extra copies** (keep one of each), **cheap items** (under $0.10 by default), and optionally everything else. Starred items are always kept, anything worth $5 or more waits in **Worth a look**, and set pieces and rising prices are Advanced options. The list shows one bucket at a time (**Sell**, **Worth a look**, **Keep**) with each item's artwork, reasons, and payout; search, filter by reason, and sort it. Move items by swiping a row (right to sell, left to keep), pressing ⌫, dragging rows onto a bucket, or from the selection bar, and undo with ⌘Z. Moves are remembered between launches. The inspector shows the selected item large, with its prices and where its copies are. Then list the Sell bucket a few at a time. |
| **Settings** | Modern (the default), Classic, and Classic Dark themes (or Classic by day and Classic Dark by night), currency, fluff threshold, refresh intervals, a menu bar net worth, a Steam account section, **network activity** (every request to Steam, Steam's pacing and back-off, and an exportable log), CSV export, and clearing local data. |

**Demo mode** loads a deterministic 3,029-item Dota 2 inventory, plus Steam, TF2, CS2, and others, with prices and 150 days of history. Nothing is sent to Steam. Use it for development, previews, and screenshots. Demo data lives only in memory, so your own profile's cache is untouched. To leave demo mode, use **Exit demo** next to the DEMO DATA badge in the header, the button in Settings → Steam account, or Inventory → Exit Demo Mode in the menu bar. You go back to your saved profile, or to the profile prompt if you haven't added one. Every tab also has an Xcode preview (`gauge/UI/PreviewSupport.swift`).

## Build and run

1. Open `gauge.xcodeproj` in Xcode 27. The project targets macOS 27.
2. Run the `gauge` scheme.
3. Choose **Sign in with Steam** and sign in on Steam's own page, with your password or the QR code in the Steam Mobile app. Gauge loads the account you signed in with, even if its inventory is private. You can instead paste a public profile link (`steamcommunity.com/id/you`), custom URL name, or SteamID64 without signing in, or choose **Try the demo inventory**.
4. Press ⌘U to run the unit tests.

The app sandbox needs **Outgoing Connections (Client)**. It's turned on through `ENABLE_OUTGOING_NETWORK_CONNECTIONS` in the target's build settings. CSV export needs user-selected read/write file access (`ENABLE_USER_SELECTED_FILES = readwrite`).

## How it stays fast: caching

Steam rate-limits anonymous traffic heavily. Price checks top out at about 20 a minute per IP address, and inventory requests are limited further still. So the UI never waits on the network:

- **Everything renders from local data.** On launch, `AppModel` loads the SwiftData cache (inventories, prices, stars, and snapshots) and the window shows it immediately. Background work refreshes the cache, and the UI updates as each result lands.
- **Inventories are re-downloaded only when they change.** A check costs one request: the public inventory page lists every game with an item count. Gauge re-fetches a game's inventory only when its count changed, or when you choose Refresh (⌘R). Checks run on a timer; the default is every 6 hours.
- **Prices come from a persistent queue.** Each unique market hash name is priced once (1,071 marketable items might be only a few hundred names). The queue prices never-priced items first, rarest first, then stale valuable items, then stale fluff. Valuable items refresh daily and fluff weekly, and both intervals are adjustable. The queue is rebuilt from the cache on every launch, so it picks up where it left off. The status bar shows how many items remain.
- **Every endpoint has its own spacing.** `SteamClient` is an actor. It spaces requests per endpoint family (market, inventory, profile, sell) and backs off from 60 seconds up to 10 minutes after a 429.
- **Item images** load through `AsyncImage` into a 512 MB `URLCache` on disk.
- **Daily snapshots** of net worth are upserted as prices arrive and stored per currency. They draw the Portfolio chart.

## Seeing what Gauge sends

Settings → Network activity lists every request Gauge has made to steamcommunity.com this session: when, what kind (prices, inventories, profiles, listings, sign-in renewals), the address, the status, how long it waited in Gauge's own queue, how long Steam took, and how much came back. It also shows each kind's pace and whether Steam has asked Gauge to wait.

Every request is also written to `~/Library/Logs/Gauge/network.log` inside the app's container (about 2 MB, with one older file kept) and to the unified log (Console.app, the app's bundle id, category `network`). **Export log…** saves the file with a short header; **Copy** copies this session's lines. Entries never include your password, cookies, session ids, or request bodies; a listing's entry names the asset and price. Item artwork loads from Steam's image servers through the shared URL cache and isn't listed.

## Signing in with Steam

Gauge never sees your password. **Sign in with Steam** opens Steam's own sign-in page (steamcommunity.com) in a sheet, where you use your password or scan the QR code with the Steam Mobile app. Steam Guard works as it does in a browser. Gauge then reads the session cookie Steam sets (`steamLoginSecure`) from WebKit's cookie store, which stays in the app's sandbox on your Mac. That one session:

- **Identifies you.** The cookie names your SteamID64, so there's no profile link to paste.
- **Reads a private inventory.** Inventory requests for your own profile carry your session, the way Steam's inventory page does for its owner. Other people's profiles are always read anonymously.
- **Lists items** from Clean up and the Sell sheet.

The sheet shows the page's real address, and only Steam's sign-in pages open in it; any other link opens in your browser. Steam's session cookie is a short-lived token (about a day) whose expiry Gauge reads from the token itself. When it's close to running out, Gauge loads a steamcommunity.com page off screen, and Steam swaps the long-lived refresh cookie it keeps on login.steampowered.com for a new session, as it does in a browser. If that fails, Settings and Clean up ask you to sign in again. **Sign out of Steam** in Settings deletes all of it. Signing in isn't required: a public profile works without it, and only listing needs it.

## Selling, and why it's safe

- Every listing still has to be confirmed in the **Steam Mobile app**. Nothing sells without your approval there.
- Clean up only sells what a rule picks or you move there yourself. Out of the box that's extra copies and items under $0.10; everything else stays in Keep.
- Starred items are never listed (Settings → Protect starred items).
- Before listing, any price older than 6 hours is re-checked. An item is skipped if its price fell by more than half.
- Listing stops at the first sign-in or rate-limit problem, and you can resume it.
- Gauge refuses to list if the signed-in Steam account isn't the profile being shown.
- Steam receives the amount *you* get after fees (the `price` field of `/market/sellitem`). The fee math is a direct port of Steam's own and is covered by tests.

## Code map

```
gauge/
  Core/          Foundation-only logic, unit tested
    Money.swift            currencies, formatting, price-string parsing
    SteamFees.swift        port of Steam's fee calculation
    SteamProfile.swift     profile links / SteamID64 / vanity parsing, profile XML
    SteamLogin.swift       the sign-in cookie: account, expiry, which pages the sign-in sheet keeps
    InventoryItem.swift    the in-memory item model
    SteamParsing.swift     inventory pages, the inventory directory, priceoverview, sellitem, sets
    InventoryQuery.swift   Inventory tab filtering, sorting, tag facets
    Cleanup.swift          clean-up rules → buckets, extra copies, valuation, price trends
    CleanupRows.swift      the Clean up list: rows per item and bucket, filters, sort, drag payloads
    Insights.swift         Portfolio lists (most valuable, movers, most copies) and chart scales
    AppSettings.swift      settings (decode with defaults)
    DemoData.swift         deterministic demo inventory
  Steam/
    SteamClient.swift      rate-limited actor for every steamcommunity.com request
    NetworkLog.swift       request records, totals, and the rotating log file
    SteamWebSession.swift  Sign in with Steam: WebKit cookies, status, renewal
  Persistence/Models.swift SwiftData cache
  Services/                AppModel (state, sync, pricing queue, snapshots, selling, clean-up choices),
                           network activity, UI sessions
  UI/                      SwiftUI: theme, components, one folder per tab
gaugeTests/                Swift Testing: fees, parsing, rules, rows, insights, queries, settings,
                           network log, client with a mock server, model tests on an in-memory store
```

## What was verified, and what wasn't

Gauge is mostly written in an environment without Xcode or network access to Steam, then built and run in Xcode. For the current version:

- `Core/`, `SteamClient`, the network log, and `NetworkActivity` compile with Swift 6.4 on Linux using the project's settings (MainActor default isolation, approachable concurrency), and their tests pass there: 87 tests, including mock-server tests of pagination, 429 back-off, the sell request, and that the network log never records the session cookie or session id.
- The services and UI layers are type-checked against stand-ins for SwiftUI, Charts, SwiftData, AppKit, and WebKit, with member import visibility on. The stand-ins follow the SDK's signatures and accept the earlier version of the app that already builds in Xcode. That catches mistakes in Gauge's own code, not every mismatch with Apple's frameworks, so a first Xcode build can still turn up a compile error or two.
- Model tests that need SwiftData or `UndoManager` (demo mode, remembered and undoable clean-up choices) are type-checked only. Run them with ⌘U.
- Interactions only a Mac can show haven't been seen yet: swipe actions and ⌫ in the Clean up list, dragging rows onto a bucket, the chart's hover readout, and how the Modern theme renders. See TODO.md.
- Steam response formats come from how the endpoints are known to behave, but they haven't been checked against live responses yet. The most uncertain piece is set detection, which reads the set list from an item's description. See TODO.md.
- Signing in follows how Steam's web sign-in is known to work: the `steamLoginSecure` cookie format, its JWT expiry, and renewal through the refresh cookie. The parsing is unit tested; the flow itself hasn't been run against Steam yet.

Not affiliated with or endorsed by Valve Corporation.
