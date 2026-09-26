//
//  Money.swift
//  gauge
//
//  Prices are stored as integer minor units ("cents") everywhere in the app.
//  Steam does the same internally, including for currencies like JPY where
//  a displayed ¥1 is 100 units.
//

import Foundation

/// Steam wallet currencies, keyed by the `currency=` code the Community Market uses.
nonisolated enum SteamCurrency: Int, Codable, CaseIterable, Identifiable, Sendable {
    case usd = 1
    case gbp = 2
    case eur = 3
    case chf = 4
    case rub = 5
    case pln = 6
    case brl = 7
    case jpy = 8
    case nok = 9
    case sgd = 13
    case krw = 16
    case mxn = 19
    case cad = 20
    case aud = 21
    case nzd = 22
    case cny = 23
    case inr = 24
    case hkd = 29
    case twd = 30

    var id: Int { rawValue }

    var isoCode: String {
        switch self {
        case .usd: "USD"
        case .gbp: "GBP"
        case .eur: "EUR"
        case .chf: "CHF"
        case .rub: "RUB"
        case .pln: "PLN"
        case .brl: "BRL"
        case .jpy: "JPY"
        case .nok: "NOK"
        case .sgd: "SGD"
        case .krw: "KRW"
        case .mxn: "MXN"
        case .cad: "CAD"
        case .aud: "AUD"
        case .nzd: "NZD"
        case .cny: "CNY"
        case .inr: "INR"
        case .hkd: "HKD"
        case .twd: "TWD"
        }
    }

    var symbol: String {
        switch self {
        case .usd: "$"
        case .gbp: "£"
        case .eur: "€"
        case .chf: "CHF"
        case .rub: "₽"
        case .pln: "zł"
        case .brl: "R$"
        case .jpy: "¥"
        case .nok: "kr"
        case .sgd: "S$"
        case .krw: "₩"
        case .mxn: "Mex$"
        case .cad: "CDN$"
        case .aud: "A$"
        case .nzd: "NZ$"
        case .cny: "¥"
        case .inr: "₹"
        case .hkd: "HK$"
        case .twd: "NT$"
        }
    }

    var label: String { "\(isoCode) (\(symbol))" }
}

nonisolated enum Money {
    /// Formats minor units for display, e.g. `format(367, .usd)` → "$3.67".
    static func format(_ cents: Int, _ currency: SteamCurrency) -> String {
        let value = Decimal(cents) / 100
        return value.formatted(.currency(code: currency.isoCode))
    }

    /// Formats an optional amount, showing an em dash while a price is unknown.
    static func format(_ cents: Int?, _ currency: SteamCurrency, placeholder: String = "—") -> String {
        guard let cents else { return placeholder }
        return format(cents, currency)
    }

    /// Short form for tight spaces: "$1.2K", "$34", "$0.03".
    static func compact(_ cents: Int, _ currency: SteamCurrency) -> String {
        if cents >= 100_000 {
            let value = Double(cents) / 100
            return currency.symbol + value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
        }
        return format(cents, currency)
    }
}

/// Parses the formatted price strings Steam returns from `priceoverview`,
/// whose layout depends on the wallet currency: "$1,234.56", "0,03€", "12,--€",
/// "1 234,56 pуб.", "¥ 1,234", "R$ 0,03", "CDN$ 0.04".
nonisolated enum PriceParser {
    static func cents(from text: String) -> Int? {
        var kept: [Character] = []
        for ch in text {
            if ch.isASCII && ch.isNumber {
                kept.append(ch)
            } else if !kept.isEmpty && isSeparator(ch) {
                kept.append(ch)
            } else if !kept.isEmpty {
                break
            }
        }
        while let last = kept.last, !(last.isASCII && last.isNumber) {
            kept.removeLast()
        }
        guard !kept.isEmpty else { return nil }

        // The last "." or "," is a decimal point only when one or two digits follow it;
        // otherwise every separator groups thousands.
        var wholeChars = kept[...]
        var fractionDigits: [Character] = []
        if let index = kept.lastIndex(where: { $0 == "." || $0 == "," }) {
            let tail = kept[(index + 1)...]
            if tail.allSatisfy({ $0.isASCII && $0.isNumber }) && (1...2).contains(tail.count) {
                wholeChars = kept[..<index]
                fractionDigits = Array(tail)
            }
        }

        let wholeDigits = String(wholeChars.filter { $0.isASCII && $0.isNumber })
        guard let whole = Int(wholeDigits.isEmpty ? "0" : wholeDigits) else { return nil }
        var fraction = 0
        if let parsed = Int(String(fractionDigits)) {
            fraction = fractionDigits.count == 1 ? parsed * 10 : parsed
        }
        return whole * 100 + fraction
    }

    /// Parses a plain count such as a listing volume ("1,234").
    static func integer(from text: String) -> Int? {
        let digits = text.filter { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    private static func isSeparator(_ ch: Character) -> Bool {
        ch == "." || ch == "," || ch == " " || ch == "'" || ch == "\u{00A0}" || ch == "\u{202F}"
    }
}
