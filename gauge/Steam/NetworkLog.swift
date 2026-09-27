//
//  NetworkLog.swift
//  gauge
//
//  A record of every request Gauge sends to Steam, shown in Settings and
//  saved to a log file the user can export. An entry holds the method, the
//  address, the status, timings, and sizes. It never holds cookies, session
//  ids, or request bodies, so a log is safe to share.
//

import Foundation

nonisolated struct NetworkEvent: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case market
        case inventory
        case profile
        case sell
        case session

        var title: String {
            switch self {
            case .market: "Prices"
            case .inventory: "Inventories"
            case .profile: "Profiles"
            case .sell: "Listings"
            case .session: "Sign-in"
            }
        }

        var detail: String {
            switch self {
            case .market: "Market price checks"
            case .inventory: "Inventory pages"
            case .profile: "Profile and inventory list"
            case .sell: "Market listings you started"
            case .session: "Session renewals, loaded off screen"
            }
        }
    }

    enum Outcome: Hashable, Sendable {
        case ok
        /// Steam asked Gauge to slow down; requests of this kind wait this long.
        case rateLimited(retryAfter: TimeInterval)
        case failed(String)
        case cancelled
    }

    var id = UUID()
    var kind: Kind
    var startedAt: Date
    var method = "GET"
    var url: String
    /// Sent with the Steam session cookie (its value is never recorded).
    var signedIn = false
    /// Time spent waiting in Gauge's own queue before the request went out.
    var waited: TimeInterval = 0
    /// Time from sending to the last byte of the response.
    var duration: TimeInterval = 0
    /// HTTP status, when a response arrived.
    var status: Int?
    var bytes = 0
    var outcome: Outcome = .ok
    /// Extra context, such as which asset a listing was for.
    var note: String?

    var isProblem: Bool {
        if case .ok = outcome { return false }
        return true
    }

    var outcomeText: String? {
        switch outcome {
        case .ok: nil
        case .rateLimited(let wait): "rate limited, pausing \(Int(wait)) s"
        case .failed(let message): message
        case .cancelled: "cancelled"
        }
    }

    /// When requests of this kind may go out again, if Steam asked Gauge to wait.
    var resumesAt: Date? {
        guard case .rateLimited(let wait) = outcome else { return nil }
        return startedAt.addingTimeInterval(duration + wait)
    }

    /// The address without the scheme and host, for tight columns.
    var path: String {
        guard let components = URLComponents(string: url) else { return url }
        let query = components.percentEncodedQuery.map { "?" + $0 } ?? ""
        return components.percentEncodedPath + query
    }

    /// One line of the log file:
    /// `2026-09-27T20:31:05.123Z  market     GET   200  0.41s  1.2 KB  queued 3.1s  https://…`
    var logLine: String {
        var parts = [
            startedAt.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)),
            kind.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0),
            method.padding(toLength: 4, withPad: " ", startingAt: 0),
            (status.map(String.init) ?? "---").padding(toLength: 3, withPad: " ", startingAt: 0),
            String(format: "%.2fs", duration),
            ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file),
        ]
        if waited >= 0.05 { parts.append(String(format: "queued %.1fs", waited)) }
        if signedIn { parts.append("signed in") }
        parts.append(url)
        if let outcomeText { parts.append("— " + outcomeText) }
        if let note { parts.append("(\(note))") }
        return parts.joined(separator: "  ")
    }
}

/// Counts for one kind of request since launch.
nonisolated struct NetworkTotals: Hashable, Sendable {
    var requests = 0
    var problems = 0
    var rateLimited = 0
    var bytes = 0
    var totalDuration: TimeInterval = 0
    var lastAt: Date?

    var averageDuration: TimeInterval? {
        requests > 0 ? totalDuration / Double(requests) : nil
    }

    mutating func add(_ event: NetworkEvent) {
        requests += 1
        bytes += event.bytes
        totalDuration += event.duration
        lastAt = max(lastAt ?? event.startedAt, event.startedAt)
        if event.isProblem { problems += 1 }
        if case .rateLimited = event.outcome { rateLimited += 1 }
    }

    static func + (lhs: NetworkTotals, rhs: NetworkTotals) -> NetworkTotals {
        var sum = lhs
        sum.requests += rhs.requests
        sum.problems += rhs.problems
        sum.rateLimited += rhs.rateLimited
        sum.bytes += rhs.bytes
        sum.totalDuration += rhs.totalDuration
        sum.lastAt = [lhs.lastAt, rhs.lastAt].compactMap { $0 }.max()
        return sum
    }
}

/// Appends log lines to a file on a background queue, keeping one older file
/// once the current one reaches `maxBytes`, so the log never grows past twice that.
nonisolated final class NetworkLogFile: @unchecked Sendable {
    let url: URL
    let olderURL: URL
    let maxBytes: Int
    private let queue = DispatchQueue(label: "gauge.network-log", qos: .utility)

    init(directory: URL, name: String = "network", maxBytes: Int = 1_000_000) {
        url = directory.appendingPathComponent("\(name).log")
        olderURL = directory.appendingPathComponent("\(name).1.log")
        self.maxBytes = maxBytes
    }

    /// ~/Library/Logs/Gauge, inside the app's sandbox container.
    static func standard() -> NetworkLogFile? {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        return NetworkLogFile(directory: library.appendingPathComponent("Logs/Gauge", isDirectory: true))
    }

    func append(_ line: String) {
        queue.async { self.write(line + "\n") }
    }

    /// Everything saved, oldest first. Waits for pending writes.
    func contents() -> String {
        queue.sync {
            [olderURL, url].compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined()
        }
    }

    /// Bytes on disk across both files. Waits for pending writes.
    func size() -> Int {
        queue.sync {
            [olderURL, url].reduce(0) { total, file in
                let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
                return total + ((attributes?[.size] as? NSNumber)?.intValue ?? 0)
            }
        }
    }

    func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: olderURL)
        }
    }

    private func write(_ text: String) {
        let manager = FileManager.default
        let data = Data(text.utf8)
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let size = ((try? manager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
        if size > 0 && size + data.count > maxBytes {
            try? manager.removeItem(at: olderURL)
            try? manager.moveItem(at: url, to: olderURL)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
