//
//  NetworkActivity.swift
//  gauge
//
//  This session's requests to Steam, for the network section in Settings.
//  Each one is also appended to the log file and to the unified log, where
//  Console.app shows it under the app's bundle id, category "network".
//

import Foundation
import Observation
#if canImport(os)
import os

private let networkLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "gauge", category: "network")
#endif

@Observable
final class NetworkActivity {
    /// The most recent requests, oldest first.
    private(set) var events: [NetworkEvent] = []
    /// Everything since launch (or the last clear), by kind.
    private(set) var totals: [NetworkEvent.Kind: NetworkTotals] = [:]
    private(set) var startedAt = Date()
    @ObservationIgnored let file: NetworkLogFile?

    static let limit = 500

    init(file: NetworkLogFile?) {
        self.file = file
    }

    var total: NetworkTotals {
        totals.values.reduce(NetworkTotals(), +)
    }

    func record(_ event: NetworkEvent) {
        events.append(event)
        if events.count > Self.limit {
            events.removeFirst(events.count - Self.limit)
        }
        totals[event.kind, default: NetworkTotals()].add(event)
        let line = event.logLine
        file?.append(line)
        #if canImport(os)
        if event.isProblem {
            networkLogger.error("\(line, privacy: .public)")
        } else {
            networkLogger.info("\(line, privacy: .public)")
        }
        #endif
    }

    /// When requests of a kind may go out again, while Steam has Gauge waiting.
    func resumesAt(_ kind: NetworkEvent.Kind, now: Date = Date()) -> Date? {
        guard let resume = events.last(where: { $0.kind == kind })?.resumesAt, resume > now else { return nil }
        return resume
    }

    /// This session's requests, one line each.
    var sessionLog: String {
        events.map(\.logLine).joined(separator: "\n")
    }

    /// What "Export log" saves: everything in the log file across launches,
    /// or this session's requests when there's no file yet.
    func exportText(header: String) -> String {
        let saved = file?.contents() ?? ""
        return header + "\n\n" + (saved.isEmpty ? sessionLog + "\n" : saved)
    }

    func clear() {
        events = []
        totals = [:]
        startedAt = Date()
        file?.clear()
    }
}
