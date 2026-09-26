//
//  SteamProfile.swift
//  gauge
//

import Foundation

/// What the user typed to identify a Steam profile.
nonisolated enum ProfileReference: Equatable, Sendable {
    case steamID64(String)
    case vanity(String)

    /// Accepts a SteamID64, a custom URL name, or any steamcommunity.com profile link.
    static func parse(_ input: String) -> ProfileReference? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let lowered = text.lowercased()
        if lowered.hasPrefix("steamcommunity.com") || lowered.hasPrefix("www.steamcommunity.com") {
            return parse("https://" + text)
        }
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            guard let url = URL(string: text),
                  let host = url.host?.lowercased(),
                  host == "steamcommunity.com" || host.hasSuffix(".steamcommunity.com")
            else { return nil }
            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { return nil }
            if parts[0] == "profiles", isSteamID64(parts[1]) { return .steamID64(parts[1]) }
            if parts[0] == "id", isVanity(parts[1]) { return .vanity(parts[1]) }
            return nil
        }
        if isSteamID64(text) { return .steamID64(text) }
        if isVanity(text) { return .vanity(text) }
        return nil
    }

    static func isSteamID64(_ text: String) -> Bool {
        text.count == 17 && text.hasPrefix("7656119") && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func isVanity(_ text: String) -> Bool {
        (2...32).contains(text.count) && text.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" || $0 == "-" }
    }

    /// The `?xml=1` profile document works without an API key for both forms.
    var profileXMLURL: URL {
        switch self {
        case .steamID64(let id): URL(string: "https://steamcommunity.com/profiles/\(id)/?xml=1")!
        case .vanity(let name): URL(string: "https://steamcommunity.com/id/\(name)/?xml=1")!
        }
    }
}

/// The public profile fields Gauge shows: whose inventory this is and whether it can be read.
nonisolated struct ProfileSummary: Codable, Equatable, Sendable {
    var steamID64: String
    var personaName: String
    var avatarURL: String?
    /// `privacyState` is "public" when the profile, and usually the inventory, is visible to everyone.
    var isPublic: Bool

    var inventoryPageURL: URL { URL(string: "https://steamcommunity.com/profiles/\(steamID64)/inventory/")! }
    var profileURL: URL { URL(string: "https://steamcommunity.com/profiles/\(steamID64)/")! }

    enum ParseError: Error, Equatable {
        case steam(String)
        case malformed
    }

    /// Parses `https://steamcommunity.com/id/<name>/?xml=1`.
    static func parse(xml: String) throws -> ProfileSummary {
        if let message = XMLTag.value("error", in: xml) {
            throw ParseError.steam(message)
        }
        guard let id = XMLTag.value("steamID64", in: xml), ProfileReference.isSteamID64(id) else {
            throw ParseError.malformed
        }
        return ProfileSummary(
            steamID64: id,
            personaName: XMLTag.value("steamID", in: xml) ?? id,
            avatarURL: XMLTag.value("avatarMedium", in: xml),
            isPublic: (XMLTag.value("privacyState", in: xml) ?? "public") == "public"
        )
    }
}

/// Just enough XML to read Steam's flat profile document.
nonisolated enum XMLTag {
    static func value(_ tag: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<\(tag)>"),
              let close = xml.range(of: "</\(tag)>", range: open.upperBound..<xml.endIndex)
        else { return nil }
        var inner = String(xml[open.upperBound..<close.lowerBound])
        if let start = inner.range(of: "<![CDATA["), let end = inner.range(of: "]]>", options: .backwards), start.upperBound <= end.lowerBound {
            inner = String(inner[start.upperBound..<end.lowerBound])
        }
        let trimmed = HTMLText.decodeEntities(inner).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Steam item descriptions are small HTML fragments. These helpers turn them into plain lines.
nonisolated enum HTMLText {
    static func lines(from html: String) -> [String] {
        var text = html
        for breakTag in ["<br>", "<br/>", "<br />", "<BR>"] {
            text = text.replacingOccurrences(of: breakTag, with: "\n")
        }
        text = stripTags(text)
        return decodeEntities(text)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func stripTags(_ html: String) -> String {
        var result = ""
        result.reserveCapacity(html.count)
        var insideTag = false
        for ch in html {
            if ch == "<" { insideTag = true; continue }
            if ch == ">" && insideTag { insideTag = false; continue }
            if !insideTag { result.append(ch) }
        }
        return result
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
