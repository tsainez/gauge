//
//  SteamFees.swift
//  gauge
//
//  A port of the fee math on steamcommunity.com (CalculateFeeAmount and
//  CalculateAmountToSendForDesiredReceivedAmount in economy_common.js).
//  Steam keeps 5% (at least 1 cent) and the game's publisher keeps 10%
//  (at least 1 cent), so the cheapest listing, $0.03, pays the seller $0.01.
//

import Foundation

nonisolated enum SteamFees {
    static let steamFeeRate = 0.05
    static let defaultPublisherFeeRate = 0.10
    static let minimumFee = 1
    /// The lowest price a buyer can pay for any Community Market listing.
    static let floorBuyerCents = 3

    struct Breakdown: Equatable, Sendable {
        /// What the buyer pays.
        var buyerPays: Int
        /// What lands in the seller's Steam Wallet. This is the `price` Steam's sell endpoint expects.
        var sellerReceives: Int
        var steamFee: Int
        var publisherFee: Int

        var totalFees: Int { steamFee + publisherFee }
    }

    /// The buyer price for a listing that pays the seller `sellerReceives`.
    static func forSellerReceiving(_ sellerReceives: Int, publisherFeeRate: Double = defaultPublisherFeeRate) -> Breakdown {
        let received = Double(sellerReceives)
        let steamFee = Int(max(received * steamFeeRate, Double(minimumFee)).rounded(.down))
        let publisherFee = publisherFeeRate > 0 ? Int(max(received * publisherFeeRate, Double(minimumFee)).rounded(.down)) : 0
        return Breakdown(
            buyerPays: sellerReceives + steamFee + publisherFee,
            sellerReceives: sellerReceives,
            steamFee: steamFee,
            publisherFee: publisherFee
        )
    }

    /// Splits a buyer price into what the seller receives and what goes to fees.
    static func forBuyerPaying(_ buyerPays: Int, publisherFeeRate: Double = defaultPublisherFeeRate) -> Breakdown {
        guard buyerPays > 0 else {
            return Breakdown(buyerPays: max(buyerPays, 0), sellerReceives: 0, steamFee: 0, publisherFee: 0)
        }
        var estimate = Int(Double(buyerPays) / (steamFeeRate + publisherFeeRate + 1))
        var everUndershot = false
        var fees = forSellerReceiving(estimate, publisherFeeRate: publisherFeeRate)
        var iterations = 0
        while fees.buyerPays != buyerPays && iterations < 10 {
            if fees.buyerPays > buyerPays {
                if everUndershot {
                    fees = forSellerReceiving(estimate - 1, publisherFeeRate: publisherFeeRate)
                    fees.steamFee += buyerPays - fees.buyerPays
                    fees.buyerPays = buyerPays
                    break
                }
                estimate -= 1
            } else {
                everUndershot = true
                estimate += 1
            }
            fees = forSellerReceiving(estimate, publisherFeeRate: publisherFeeRate)
            iterations += 1
        }
        if fees.sellerReceives < 0 {
            // Below Steam's floor nothing reaches the seller; attribute the whole price to fees.
            return Breakdown(buyerPays: buyerPays, sellerReceives: 0, steamFee: buyerPays, publisherFee: 0)
        }
        return fees
    }

    /// Shorthand for the amount a sale at `buyerPays` puts in the seller's wallet.
    static func sellerReceives(buyerPays: Int, publisherFeeRate: Double = defaultPublisherFeeRate) -> Int {
        forBuyerPaying(buyerPays, publisherFeeRate: publisherFeeRate).sellerReceives
    }
}
