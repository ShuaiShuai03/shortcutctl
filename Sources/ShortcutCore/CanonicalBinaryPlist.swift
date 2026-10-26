import Foundation

/// Deterministic bplist00 encoding. Foundation independently decodes every compiled result.
enum CanonicalBinaryPlist {
    private enum Node {
        case scalar(PlistValue)
        case array([Int])
        case dictionary(keys: [Int], values: [Int])
    }

    static func encode(_ value: PlistValue) throws -> Data {
        var nodes: [Node] = []
        let root = try flatten(value, nodes: &nodes, depth: 0)
        let referenceSize = width(UInt64(nodes.count - 1))
        var data = Data("bplist00".utf8)
        var offsets: [UInt64] = []
        for node in nodes {
            offsets.append(UInt64(data.count))
            switch node {
            case .scalar(let value): try appendScalar(value, to: &data)
            case .array(let references):
                appendCount(references.count, marker: 0xA0, to: &data)
                for reference in references { append(UInt64(reference), bytes: referenceSize, to: &data) }
            case .dictionary(let keys, let values):
                appendCount(keys.count, marker: 0xD0, to: &data)
                for reference in keys + values { append(UInt64(reference), bytes: referenceSize, to: &data) }
            }
        }
        let offsetTable = UInt64(data.count)
        let offsetSize = width(offsetTable)
        for offset in offsets { append(offset, bytes: offsetSize, to: &data) }
        data.append(contentsOf: [0, 0, 0, 0, 0, 0, UInt8(offsetSize), UInt8(referenceSize)])
        append(UInt64(nodes.count), bytes: 8, to: &data)
        append(UInt64(root), bytes: 8, to: &data)
        append(offsetTable, bytes: 8, to: &data)
        return data
    }

    private static func flatten(_ value: PlistValue, nodes: inout [Node], depth: Int) throws -> Int {
        guard depth <= 128 else {
            throw ToolFailure("nesting_limit", "Workflow nesting exceeds 128 levels.", "工作流嵌套超过 128 层。", exitCode: 3)
        }
        let node: Node
        switch value {
        case .array(let values):
            node = .array(try values.map { try flatten($0, nodes: &nodes, depth: depth + 1) })
        case .dictionary(let values):
            let keys = values.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            var keyIDs: [Int] = []
            var valueIDs: [Int] = []
            for key in keys {
                keyIDs.append(try flatten(.string(key), nodes: &nodes, depth: depth + 1))
                if let value = values[key] {
                    valueIDs.append(try flatten(value, nodes: &nodes, depth: depth + 1))
                }
            }
            node = .dictionary(keys: keyIDs, values: valueIDs)
        default: node = .scalar(value)
        }
        nodes.append(node)
        return nodes.count - 1
    }

    private static func appendScalar(_ value: PlistValue, to data: inout Data) throws {
        switch value {
        case .bool(let value): data.append(value ? 0x09 : 0x08)
        case .integer(let value):
            data.append(0x13)
            append(UInt64(bitPattern: value), bytes: 8, to: &data)
        case .unsigned(let value):
            if value > UInt64(Int64.max) {
                data.append(0x14)
                append(0, bytes: 8, to: &data)
            } else {
                data.append(0x13)
            }
            append(value, bytes: 8, to: &data)
        case .real(let value):
            guard value.isFinite else { throw nonfinite() }
            data.append(0x23)
            append(value.bitPattern, bytes: 8, to: &data)
        case .date(let value):
            let seconds = value.timeIntervalSinceReferenceDate
            guard seconds.isFinite else { throw nonfinite() }
            data.append(0x33)
            append(seconds.bitPattern, bytes: 8, to: &data)
        case .data(let value):
            appendCount(value.count, marker: 0x40, to: &data)
            data.append(value)
        case .string(let value):
            if value.utf8.allSatisfy({ $0 < 128 }) {
                appendCount(value.utf8.count, marker: 0x50, to: &data)
                data.append(contentsOf: value.utf8)
            } else {
                appendCount(value.utf16.count, marker: 0x60, to: &data)
                for unit in value.utf16 { append(UInt64(unit), bytes: 2, to: &data) }
            }
        case .array, .dictionary:
            preconditionFailure("Container nodes must be flattened before scalar encoding.")
        }
    }

    private static func appendCount(_ count: Int, marker: UInt8, to data: inout Data) {
        if count < 15 {
            data.append(marker | UInt8(count))
        } else {
            data.append(marker | 0x0F)
            data.append(0x13)
            append(UInt64(count), bytes: 8, to: &data)
        }
    }

    private static func width(_ value: UInt64) -> Int {
        if value <= UInt8.max { return 1 }
        if value <= UInt16.max { return 2 }
        if value <= UInt32.max { return 4 }
        return 8
    }

    private static func append(_ value: UInt64, bytes: Int, to data: inout Data) {
        for index in (0..<bytes).reversed() { data.append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
    }

    private static func nonfinite() -> ToolFailure {
        ToolFailure("invalid_plist_value", "Non-finite numbers and dates are unsupported.", "不支持非有限数值和日期。", exitCode: 3)
    }
}
