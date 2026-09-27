//
//  NetworkLogTests.swift
//  gaugeTests
//

import Foundation
import Testing
@testable import gauge

struct NetworkLogTests {
    static let start = Date(timeIntervalSince1970: 1_790_000_000)

    static func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gauge-log-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func logLinesSayWhatWasSent() {
        var event = NetworkEvent(
            kind: .market,
            startedAt: Self.start,
            url: "https://steamcommunity.com/market/priceoverview/?appid=570&currency=1&market_hash_name=A%2BB",
            waited: 3.1,
            duration: 0.412,
            status: 429,
            outcome: .rateLimited(retryAfter: 60)
        )
        let line = event.logLine
        #expect(line.hasPrefix(Self.start.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))))
        #expect(line.contains("market"))
        #expect(line.contains(" 429 "))
        #expect(line.contains("0.41s"))
        #expect(line.contains("queued 3.1s"))
        #expect(line.contains("— rate limited, pausing 60 s"))
        #expect(!line.contains("signed in"))
        #expect(event.path == "/market/priceoverview/?appid=570&currency=1&market_hash_name=A%2BB")
        #expect(event.isProblem)
        #expect(event.resumesAt == Self.start.addingTimeInterval(60.412))

        event.outcome = .ok
        event.signedIn = true
        #expect(!event.logLine.contains("—"))
        #expect(event.logLine.contains("signed in"))
        #expect(event.resumesAt == nil)
        #expect(!event.isProblem)
    }

    @Test func totalsAddUp() {
        var market = NetworkTotals()
        market.add(NetworkEvent(kind: .market, startedAt: Self.start, url: "a", duration: 1, bytes: 100))
        market.add(NetworkEvent(kind: .market, startedAt: Self.start.addingTimeInterval(5), url: "b", duration: 3, status: 429, outcome: .rateLimited(retryAfter: 60)))
        #expect(market.requests == 2)
        #expect(market.problems == 1)
        #expect(market.rateLimited == 1)
        #expect(market.averageDuration == 2)
        #expect(market.lastAt == Self.start.addingTimeInterval(5))

        var inventory = NetworkTotals()
        inventory.add(NetworkEvent(kind: .inventory, startedAt: Self.start, url: "c", bytes: 50, outcome: .failed("HTTP 500")))
        let sum = market + inventory
        #expect(sum.requests == 3)
        #expect(sum.bytes == 150)
        #expect(sum.problems == 2)
        #expect(sum.lastAt == Self.start.addingTimeInterval(5))
    }

    @Test func logFileRotatesAndKeepsOrder() {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = NetworkLogFile(directory: folder, maxBytes: 100)
        for index in 1...12 {
            file.append("line \(index) xxxxxxxxxx")
        }
        let lines = file.contents().split(separator: "\n").map(String.init)
        // The older file rolls off, so only the newest lines are left, oldest first.
        #expect(lines.first == "line 6 xxxxxxxxxx")
        #expect(lines.last == "line 12 xxxxxxxxxx")
        #expect(lines.count == 7)
        #expect(file.size() <= 200)

        file.clear()
        #expect(file.contents().isEmpty)
        #expect(file.size() == 0)
    }
}

@MainActor
struct NetworkActivityTests {
    @Test func keepsTheNewestAndCountsEverything() {
        let activity = NetworkActivity(file: nil)
        for index in 0..<(NetworkActivity.limit + 5) {
            activity.record(NetworkEvent(kind: .market, startedAt: Date(timeIntervalSince1970: Double(index)), url: "\(index)"))
        }
        #expect(activity.events.count == NetworkActivity.limit)
        #expect(activity.events.first?.url == "5")
        #expect(activity.totals[.market]?.requests == NetworkActivity.limit + 5)
        #expect(activity.total.requests == NetworkActivity.limit + 5)
    }

    @Test func knowsWhenSteamHasItWaiting() {
        let activity = NetworkActivity(file: nil)
        let now = Date()
        activity.record(NetworkEvent(kind: .market, startedAt: now.addingTimeInterval(-10), url: "a", status: 429, outcome: .rateLimited(retryAfter: 60)))
        #expect(activity.resumesAt(.market, now: now) == now.addingTimeInterval(50))
        #expect(activity.resumesAt(.inventory, now: now) == nil)
        activity.record(NetworkEvent(kind: .market, startedAt: now, url: "b", status: 200))
        #expect(activity.resumesAt(.market, now: now) == nil)
    }

    @Test func exportsTheFileOrThisSession() {
        let folder = NetworkLogTests.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let activity = NetworkActivity(file: NetworkLogFile(directory: folder))
        let event = NetworkEvent(kind: .inventory, startedAt: NetworkLogTests.start, url: "https://steamcommunity.com/inventory/1/570/2", status: 200)
        activity.record(event)
        let exported = activity.exportText(header: "Gauge network log")
        #expect(exported.hasPrefix("Gauge network log\n\n"))
        #expect(exported.contains(event.logLine))
        #expect(activity.sessionLog == event.logLine)

        activity.clear()
        #expect(activity.events.isEmpty)
        #expect(activity.total.requests == 0)
        #expect(!activity.exportText(header: "H").contains(event.url))
    }
}
