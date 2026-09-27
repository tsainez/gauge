# Gauge Privacy Policy

Effective September 27, 2026

Gauge is a Mac app for the Steam Community Market. It has no servers or accounts of its own, and nothing you do in it is sent to its developer. This page explains what Gauge keeps on your Mac, what it sends to Steam, and how to delete it.

Gauge is not affiliated with or endorsed by Valve Corporation.

## What Gauge keeps on your Mac

All of this stays inside Gauge's sandbox on your Mac:

- **Settings**, including the Steam profile you chose: its SteamID64, name, avatar link, and whether it's public.
- **Your inventories** as Steam returns them, the **prices** Gauge has looked up, and a short price history for each item.
- **Daily net worth snapshots**, your **stars**, and your **clean-up choices**.
- **A listing log**: the items you listed through Gauge, with their prices and when you listed them.
- **A network log** of Gauge's requests to Steam: when each was sent, its address (which can include your SteamID64 and item names), its status, how long it took, and how much came back. It never includes your password, cookies, session ids, or request bodies. The same lines also go to macOS's system log on your Mac.
- **Item images**, cached from Steam's image servers.
- **Your Steam sign-in**, if you sign in: the cookies Steam sets, kept in Gauge's own web storage.

## Signing in with Steam

You sign in on Steam's own page, shown in a sheet inside Gauge. Gauge never sees or stores your password or Steam Guard codes. After you sign in, it reads the session cookie Steam sets and uses it to know which account is yours, to read your inventory when it's private, to list items when you ask it to, and to renew the session before it runs out. Steam's sign-in page is run by Valve and covered by [Valve's privacy policy](https://store.steampowered.com/privacy_agreement/).

## What Gauge sends, and where

Gauge's own requests go only to Steam: steamcommunity.com and Steam's sign-in pages for profiles, inventories, prices, listings, and signing in, and Steam's image servers for item artwork. Each request goes straight from your Mac to Valve and includes what Steam needs to answer it, such as the profile you're viewing, the item you're pricing, or the item and price of a listing you started. Requests that need your sign-in carry your Steam session. Like any internet request, they show Valve your IP address. Valve's privacy policy covers what Steam does with them.

Gauge has no analytics, advertising, or tracking, and no third-party SDKs. Links such as **View on Market** open in your web browser. For a Counter-Strike 2 skin, **Find it in CSFloat's database** opens the website of CSFloat, a third party, with the skin's weapon, finish, and pattern in the address; CSFloat's own privacy policy covers that site.

## What the developer receives

Nothing from Gauge itself.

If you turn on sharing with app developers in macOS (System Settings → Privacy & Security → Analytics & Improvements), Apple may share crash reports and usage statistics with the developer. If you test Gauge through TestFlight, Apple shares the information described in TestFlight's terms with the developer, such as crash reports and any feedback or screenshots you send.

## Exporting

**Export history (CSV)** and **Export log…** in Settings save a file only when you choose to, to a place you pick.

## Deleting your data

- **Settings → Clear local data…** deletes the inventory cache, prices, net worth history, stars, clean-up choices, the listing log, and the network log.
- **Settings → Sign out of Steam** deletes Steam's cookies and web storage from Gauge. To end your sessions on Steam's side too, use Steam's account security settings.
- **Settings → Change profile…** forgets the profile and everything cached for it.
- Everything Gauge stores lives in its container, `~/Library/Containers/tsainez.gauge`. Quit Gauge and delete that folder to remove all of it.

## Changes

If this policy changes, the new version will be posted here with a new effective date. Earlier versions stay in this file's history on GitHub.

## Contact

Questions about this policy: open an issue at [github.com/tsainez/gauge/issues](https://github.com/tsainez/gauge/issues).
