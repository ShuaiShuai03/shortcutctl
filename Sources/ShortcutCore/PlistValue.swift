import CoreFoundation
import Foundation

/// JSON-compatible values with explicit escapes for types JSON cannot preserve.
public indirect enum PlistValue: Equatable, Sendable, Codable {
    case string(String)
    case integer(Int64)
    case unsigned(UInt64)
    case real(Double)
    case bool(Bool)
    case data(Data)
    case date(Date)
    case array([PlistValue])
    case dictionary([String: PlistValue])

    /// Compare stored representations, including signed zero and Unicode normalization.
    public static func == (lhs: PlistValue, rhs: PlistValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let left), .string(let right)): return left.utf8.elementsEqual(right.utf8)
        case (.integer(let left), .integer(let right)): return left == right
        case (.unsigned(let left), .unsigned(let right)): return left == right
        case (.real(let left), .real(let right)): return left.bitPattern == right.bitPattern
        case (.bool(let left), .bool(let right)): return left == right
        case (.data(let left), .data(let right)): return left == right
        case (.date(let left), .date(let right)): return left == right
        case (.array(let left), .array(let right)): return left == right
        case (.dictionary(let left), .dictionary(let right)):
            let leftKeys = left.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            let rightKeys = right.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            return leftKeys.count == rightKeys.count
                && zip(leftKeys, rightKeys).allSatisfy { $0.utf8.elementsEqual($1.utf8) }
                && left == right
        default: return false
        }
    }

    public var dictionary: [String: PlistValue]? {
        if case .dictionary(let value) = self { return value }
        return nil
    }

    public var array: [PlistValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var integer: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }

    public var number: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .unsigned(let value): Double(value)
        case .real(let value): value
        default: nil
        }
    }

    public subscript(_ key: String) -> PlistValue? { dictionary?[key] }

    private enum TagKeys: String, CodingKey {
        case type = "$plist"
        case value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            throw ToolFailure(
                "unsupported_null", "Property lists cannot represent null.", "属性列表无法表示 null。", exitCode: 3)
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode(Int64.self) {
            self = .integer(value)
            return
        }
        if let value = try? container.decode(UInt64.self) {
            self = .unsigned(value)
            return
        }
        if let value = try? container.decode(Double.self), value.isFinite {
            self = .real(value)
            return
        }
        if var values = try? decoder.unkeyedContainer() {
            var result: [PlistValue] = []
            while !values.isAtEnd { result.append(try values.decode(PlistValue.self)) }
            self = .array(result)
            return
        }
        let tags = try decoder.container(keyedBy: TagKeys.self)
        if tags.contains(.type) {
            let allKeys = try decoder.container(keyedBy: AnyKey.self).allKeys
            guard allKeys.count == 2, tags.contains(.value) else {
                throw Self.invalidTag()
            }
            let type = try tags.decode(String.self, forKey: .type)
            switch type {
            case "data":
                guard let data = Data(base64Encoded: try tags.decode(String.self, forKey: .value)) else {
                    throw Self.invalidTag()
                }
                self = .data(data)
            case "date":
                let seconds = try tags.decode(Double.self, forKey: .value)
                guard seconds.isFinite else { throw Self.invalidTag() }
                self = .date(Date(timeIntervalSinceReferenceDate: seconds))
            case "real":
                guard let value = Double(try tags.decode(String.self, forKey: .value)), value.isFinite else {
                    throw Self.invalidTag()
                }
                self = .real(value)
            case "dictionary":
                self = .dictionary(try tags.decode([String: PlistValue].self, forKey: .value))
            default: throw Self.invalidTag()
            }
        } else {
            self = .dictionary(try container.decode([String: PlistValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .unsigned(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .dictionary(let value) where value["$plist"] == nil: try container.encode(value)
        case .dictionary(let value):
            var tag = encoder.container(keyedBy: TagKeys.self)
            try tag.encode("dictionary", forKey: .type)
            try tag.encode(value, forKey: .value)
        case .data(let value):
            var tag = encoder.container(keyedBy: TagKeys.self)
            try tag.encode("data", forKey: .type)
            try tag.encode(value.base64EncodedString(), forKey: .value)
        case .date(let value):
            guard value.timeIntervalSinceReferenceDate.isFinite else { throw Self.invalidTag() }
            var tag = encoder.container(keyedBy: TagKeys.self)
            try tag.encode("date", forKey: .type)
            try tag.encode(value.timeIntervalSinceReferenceDate, forKey: .value)
        case .real(let value):
            guard value.isFinite else { throw Self.invalidTag() }
            var tag = encoder.container(keyedBy: TagKeys.self)
            try tag.encode("real", forKey: .type)
            try tag.encode(String(value), forKey: .value)
        }
    }

    public init(propertyList value: Any, depth: Int = 0) throws {
        guard depth <= 128 else {
            throw ToolFailure("nesting_limit", "Workflow nesting exceeds 128 levels.", "工作流嵌套超过 128 层。", exitCode: 3)
        }
        switch value {
        case let value as String: self = .string(value)
        case let value as Data: self = .data(value)
        case let value as Date:
            guard value.timeIntervalSinceReferenceDate.isFinite else { throw Self.invalidTag() }
            self = .date(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else if ["f", "d"].contains(String(cString: value.objCType)) {
                guard value.doubleValue.isFinite else { throw Self.invalidTag() }
                self = .real(value.doubleValue)
            } else if String(cString: value.objCType) == "Q", value.uint64Value > UInt64(Int64.max) {
                self = .unsigned(value.uint64Value)
            } else {
                self = .integer(value.int64Value)
            }
        case let value as [String: Any]:
            self = .dictionary(try value.mapValues { try PlistValue(propertyList: $0, depth: depth + 1) })
        case let value as [Any]:
            self = .array(try value.map { try PlistValue(propertyList: $0, depth: depth + 1) })
        default:
            throw ToolFailure(
                "unsupported_plist_type", "The property list contains an unsupported value type.", "属性列表包含不支持的值类型。",
                exitCode: 3)
        }
    }

    public func propertyList(depth: Int = 0) throws -> Any {
        guard depth <= 128 else {
            throw ToolFailure("nesting_limit", "Workflow nesting exceeds 128 levels.", "工作流嵌套超过 128 层。", exitCode: 3)
        }
        switch self {
        case .string(let value): return value
        case .integer(let value): return NSNumber(value: value)
        case .unsigned(let value): return NSNumber(value: value)
        case .bool(let value): return NSNumber(value: value)
        case .real(let value):
            guard value.isFinite else { throw Self.invalidTag() }
            return NSNumber(value: value)
        case .data(let value): return value
        case .date(let value):
            guard value.timeIntervalSinceReferenceDate.isFinite else { throw Self.invalidTag() }
            return value
        case .array(let value): return try value.map { try $0.propertyList(depth: depth + 1) }
        case .dictionary(let value): return try value.mapValues { try $0.propertyList(depth: depth + 1) }
        }
    }

    private static func invalidTag() -> ToolFailure {
        ToolFailure(
            "invalid_plist_value",
            "Invalid typed property-list value; data, date, real, and dictionary tags must have exactly $plist and value keys. Non-finite numbers are unsupported.",
            "属性列表类型标记无效；必须只包含 $plist 和 value，不支持非有限数值。", exitCode: 3)
    }
}

struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
