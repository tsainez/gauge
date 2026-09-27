//
//  AppModel+Selling.swift
//  gauge
//
//  Lists items on the Community Market one at a time. Each listing still
//  has to be confirmed in the Steam Mobile app, so nothing sells without
//  the user approving it there.
//

import Foundation
import SwiftData

extension AppModel {
    /// Re-check a price before listing when the cached one is older than this.
    static let listingPriceMaxAge: TimeInterval = 6 * 3_600

    /// Builds the listing plan for Clean up, for one inventory or all of them.
    func cleanupPlan(contextKey: String?) -> CleanupPlan {
        var rules = settings.cleanupRules
        if settings.protectStarred { rules.keepStarred = true }
        return CleanupPlanner.plan(
            items: items(in: contextKey),
            prices: prices,
            trends: monthlyChange,
            starred: starred,
            overrides: cleanup.overrides,
            rules: rules,
            currency: settings.currency
        )
    }

    /// Lists every job in `run` that hasn't finished. Stops early on sign-in or rate-limit problems.
    func runListing(_ run: ListingRun) async {
        guard !run.isRunning else { return }
        guard !settings.demoMode else {
            run.haltMessage = "Demo mode doesn't list anything. Connect your own Steam profile to sell."
            return
        }
        guard let profile = settings.profile else { return }
        guard let auth = await web.auth() else {
            run.haltMessage = web.status.hasExpired
                ? "Your Steam sign-in expired and Gauge couldn't renew it. Sign in again, then resume."
                : "Sign in with Steam to list items."
            return
        }
        guard auth.steamID64 == profile.steamID64 else {
            run.haltMessage = "You're signed in to Steam as a different account than the profile Gauge is showing. Sign out and sign in as \(profile.personaName)."
            return
        }

        run.isRunning = true
        run.stopRequested = false
        run.haltMessage = nil
        var listedIDs = Set<String>()

        for index in run.jobs.indices {
            if run.stopRequested { break }
            guard run.jobs[index].state == .queued || isRetryable(run.jobs[index].state) else { continue }
            let item = run.jobs[index].item

            if starred.contains(item.id) && settings.protectStarred {
                run.jobs[index].state = .skipped("Starred")
                continue
            }

            // Don't list at a stale price: re-check anything older than a few hours.
            if let quote = prices[item.priceKey], Date().timeIntervalSince(quote.checkedAt) > Self.listingPriceMaxAge {
                run.jobs[index].state = .checkingPrice
                if let fresh = try? await client.priceOverview(appID: item.appID, marketHashName: item.marketHashName, currency: settings.currency) {
                    store(fresh, for: item.priceKey)
                    if let buyer = CleanupPlanner.listingPrice(for: fresh, rules: settings.cleanupRules) {
                        if buyer * 2 < run.jobs[index].buyerCents {
                            run.jobs[index].state = .skipped("Price fell to \(Money.format(buyer, settings.currency)). Review it again.")
                            continue
                        }
                        run.jobs[index].buyerCents = buyer
                        run.jobs[index].sellerCents = SteamFees.sellerReceives(buyerPays: buyer)
                    }
                }
            }

            let job = run.jobs[index]
            guard job.sellerCents >= 1 else {
                run.jobs[index].state = .skipped("Below Steam's minimum price")
                continue
            }
            run.jobs[index].state = .listing
            do {
                let request = SellRequest(appID: item.appID, contextID: item.contextID, assetID: item.assetID, amount: item.amount, sellerCents: job.sellerCents)
                let result = try await client.sell(request, auth: auth)
                if result.success {
                    run.jobs[index].state = .listed(needsConfirmation: result.needsConfirmation)
                    listedIDs.insert(item.id)
                    logListing(job, outcome: result.needsConfirmation ? "awaiting confirmation" : "listed")
                } else {
                    let message = result.message ?? "Steam didn't accept this listing."
                    run.jobs[index].state = .failed(message)
                    if Self.messageEndsRun(message) {
                        run.haltMessage = message
                        break
                    }
                }
            } catch SteamClient.Failure.rateLimited(let wait) {
                run.jobs[index].state = .queued
                run.haltMessage = "Steam asked Gauge to slow down. Resume in about \(Int(wait / 60) + 1) min."
                break
            } catch SteamClient.Failure.http(let code) where code == 401 || code == 403 {
                run.jobs[index].state = .queued
                run.haltMessage = "Steam didn't accept the sign-in. Sign in again, then resume."
                await web.refresh(renewIfNeeded: false)
                break
            } catch {
                run.jobs[index].state = .failed(error.localizedDescription)
            }
        }

        run.isRunning = false
        if !listedIDs.isEmpty {
            await removeItems(withIDs: listedIDs)
            cleanup.overrides = cleanup.overrides.filter { !listedIDs.contains($0.key) }
            recordSnapshot()
        }
    }

    private func isRetryable(_ state: ListingRun.JobState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    /// Steam messages that mean every later listing would fail too.
    static func messageEndsRun(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return ["too many", "log in", "logged in", "sign in", "session", "try again later", "limit"].contains { lowered.contains($0) }
    }

    private func logListing(_ job: ListingRun.Job, outcome: String) {
        modelContext.insert(ListingRecord(
            itemKey: job.item.id,
            name: job.item.name,
            appID: job.item.appID,
            buyerCents: job.buyerCents,
            sellerCents: job.sellerCents,
            currencyCode: settings.currency.rawValue,
            listedAt: Date(),
            outcome: outcome
        ))
        try? modelContext.save()
    }
}
