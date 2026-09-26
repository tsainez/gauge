# TODO

## Verify against real Steam data

- [ ] First build in Xcode 27: fix any framework API mismatches the stubbed type-check couldn't catch (see README, "What was verified").
- [ ] Load your own profile and confirm that inventory pages, the inventory directory (`g_rgAppContextData` on `/profiles/<id>/inventory/`), and `priceoverview` parse as expected.
- [ ] Confirm the Dota 2 set format in item descriptions. `ItemSetDetector` expects the set name followed by its pieces, with the pieces sharing a color. If it's wrong, capture one real description into `gaugeTests/SteamParsingTests.swift` and adjust.
- [ ] Check whether `count=2000` is still the inventory page maximum. The client already falls back to 500 on HTTP 400.
- [ ] List one cheap item end to end: sign in, list, confirm in the Steam Mobile app, and see it leave the inventory.

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
- [ ] Undo overrides in Clean up, and remember overrides between launches.
- [ ] Show active listings and cancel them from Gauge (`/market/mylistings`, signed in).
- [ ] Notifications when net worth moves more than X% in a day.
- [ ] Localize the UI, and parse prices in every Steam currency with live samples.
- [ ] App icon and About artwork. The asset catalog is still empty.

## Engineering

- [ ] Move inventory JSON encoding and decoding fully off the main actor for very large inventories (100k+ items); consider a `ModelActor`.
- [ ] Add UI tests driven by Demo mode (`gaugeUITests`).
- [ ] App Store review: explain the sign-in web view and the confirmation step in the review notes.
