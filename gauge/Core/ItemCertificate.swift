//
//  ItemCertificate.swift
//  gauge
//
//  Steam sends each Counter-Strike 2 item's "Item Certificate" as a hex
//  string: the item's preview data block, the same payload an inspect link
//  carries since CS2 inspect links started encoding the item themselves.
//  Decoding it here, offline, gives the finish, pattern, float, StatTrak
//  count, name tag, and every sticker and charm without asking a third-party
//  inspect service.
//
//  Layout: one mask byte XORed over every byte (0 when unmasked), then the
//  protobuf `CEconItemPreviewDataBlock`, then a 4-byte checksum. Masked
//  certificates use a checksum Gauge can't recompute, so the checksum isn't
//  checked; the structure is instead.
//

import Foundation

nonisolated enum ItemCertificate {
    /// The fields of `CEconItemPreviewDataBlock` Gauge uses.
    struct Block: Equatable, Sendable {
        var itemID: UInt64?
        var defIndex: Int?
        var paintIndex: Int?
        var rarity: Int?
        var quality: Int?
        /// The float, stored on the wire as the bits of a 32-bit float.
        var paintWear: Float?
        var paintSeed: Int?
        var killEaterScoreType: Int?
        var killEaterValue: Int?
        var customName: String?
        var stickers: [Accessory] = []
        var origin: Int?
        var keychains: [Accessory] = []
    }

    /// A sticker, patch, or charm on the item (`CEconItemPreviewDataBlock.Sticker`).
    struct Accessory: Equatable, Sendable {
        var slot: Int?
        var kitID: Int?
        /// How scraped a sticker is, 0 (new) to 1.
        var wear: Float?
        /// A charm's pattern.
        var pattern: Int?
        /// A souvenir charm's highlight.
        var highlightReel: Int?
    }

    /// Decodes a certificate, or the hex at the end of an inspect link. Nil when it isn't one.
    static func decode(_ text: String) -> Block? {
        guard var bytes = hexBytes(payload(of: text)), bytes.count > 5 else { return nil }
        let mask = bytes[0]
        if mask != 0 {
            for index in bytes.indices { bytes[index] ^= mask }
        }
        guard let block = try? parse(Array(bytes[1..<(bytes.count - 4)])) else { return nil }
        let describesSomething = block.defIndex != nil || block.paintIndex != nil || block.paintSeed != nil
            || block.paintWear != nil || !block.stickers.isEmpty || !block.keychains.isEmpty
        return describesSomething ? block : nil
    }

    /// The hex part of `steam://run/730//+csgo_econ_action_preview%20<hex>`, or the text itself.
    static func payload(of text: String) -> String {
        var hex = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let action = hex.range(of: "csgo_econ_action_preview") {
            hex = String(hex[action.upperBound...])
            if hex.hasPrefix("%20") { hex.removeFirst(3) }
            hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: " +"))
        }
        return hex
    }

    static func hexBytes(_ hex: String) -> [UInt8]? {
        let digits = Array(hex.utf8)
        guard !digits.isEmpty, digits.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        var index = 0
        while index < digits.count {
            guard let high = nibble(digits[index]), let low = nibble(digits[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
            index += 2
        }
        return bytes
    }

    private static func nibble(_ digit: UInt8) -> UInt8? {
        switch digit {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): digit - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): digit - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): digit - UInt8(ascii: "A") + 10
        default: nil
        }
    }

    // MARK: - Protobuf

    static func parse(_ bytes: [UInt8]) throws -> Block {
        var reader = ProtobufReader(bytes)
        var block = Block()
        while let entry = try reader.next() {
            switch (entry.field, entry.value) {
            case (2, .varint(let v)): block.itemID = v
            case (3, .varint(let v)): block.defIndex = Int(truncatingIfNeeded: UInt32(truncatingIfNeeded: v))
            case (4, .varint(let v)): block.paintIndex = Int(truncatingIfNeeded: UInt32(truncatingIfNeeded: v))
            case (5, .varint(let v)): block.rarity = Int(truncatingIfNeeded: UInt32(truncatingIfNeeded: v))
            case (6, .varint(let v)): block.quality = Int(truncatingIfNeeded: UInt32(truncatingIfNeeded: v))
            case (7, .varint(let v)): block.paintWear = Float(bitPattern: UInt32(truncatingIfNeeded: v))
            case (8, .varint(let v)): block.paintSeed = Int(truncatingIfNeeded: UInt32(truncatingIfNeeded: v))
            case (9, .varint(let v)): block.killEaterScoreType = Int(truncatingIfNeeded: UInt32(truncatingIfNeeded: v))
            case (10, .varint(let v)): block.killEaterValue = Int(truncatingIfNeeded: UInt32(truncatingIfNeeded: v))
            case (11, .bytes(let data)): block.customName = String(decoding: data, as: UTF8.self)
            case (12, .bytes(let data)): block.stickers.append(try accessory(data))
            case (14, .varint(let v)): block.origin = Int(truncatingIfNeeded: UInt32(truncatingIfNeeded: v))
            case (20, .bytes(let data)): block.keychains.append(try accessory(data))
            default: continue
            }
        }
        return block
    }

    private static func accessory(_ bytes: [UInt8]) throws -> Accessory {
        var reader = ProtobufReader(bytes)
        var accessory = Accessory()
        while let entry = try reader.next() {
            switch (entry.field, entry.value) {
            case (1, .varint(let v)): accessory.slot = Int(truncatingIfNeeded: UInt32(truncatingIfNeeded: v))
            case (2, .varint(let v)): accessory.kitID = Int(truncatingIfNeeded: UInt32(truncatingIfNeeded: v))
            case (3, .fixed32(let bits)): accessory.wear = Float(bitPattern: bits)
            case (10, .varint(let v)): accessory.pattern = Int(truncatingIfNeeded: UInt32(truncatingIfNeeded: v))
            case (11, .varint(let v)): accessory.highlightReel = Int(truncatingIfNeeded: UInt32(truncatingIfNeeded: v))
            default: continue
            }
        }
        return accessory
    }
}

/// Reads protobuf wire format one field at a time, without a schema.
nonisolated struct ProtobufReader {
    enum Value: Equatable {
        case varint(UInt64)
        case fixed64(UInt64)
        case bytes([UInt8])
        case fixed32(UInt32)
    }

    struct Malformed: Error {}

    private let bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// The next field and its value, or nil at the end. Throws on anything truncated or unknown.
    mutating func next() throws -> (field: Int, value: Value)? {
        guard index < bytes.count else { return nil }
        let key = try varint()
        guard let field = Int(exactly: key >> 3), field > 0 else { throw Malformed() }
        switch key & 7 {
        case 0:
            return (field, .varint(try varint()))
        case 1:
            return (field, .fixed64(try fixed(8)))
        case 2:
            guard let length = Int(exactly: try varint()), length <= bytes.count - index else { throw Malformed() }
            let value = Array(bytes[index..<(index + length)])
            index += length
            return (field, .bytes(value))
        case 5:
            return (field, .fixed32(UInt32(truncatingIfNeeded: try fixed(4))))
        default:
            throw Malformed()
        }
    }

    private mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count && shift < 64 {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte < 0x80 { return result }
            shift += 7
        }
        throw Malformed()
    }

    /// A little-endian fixed-width value.
    private mutating func fixed(_ count: Int) throws -> UInt64 {
        guard bytes.count - index >= count else { throw Malformed() }
        var result: UInt64 = 0
        for offset in 0..<count {
            result |= UInt64(bytes[index + offset]) << UInt64(8 * offset)
        }
        index += count
        return result
    }
}
