import Foundation
import Testing

@testable import ShortcutCore

@Test func canonicalBinarySupportsWideReferencesAndAllValueTypes() throws {
    var values: [PlistValue] = (0..<600).map { .string("value \($0) 世界") }
    values += [
        .integer(Int64.min), .integer(Int64.max), .unsigned(UInt64.max),
        .real(-0.0), .real(Double.leastNonzeroMagnitude), .bool(true), .bool(false),
        .data(Data(repeating: 0xFF, count: 256)),
        .date(Date(timeIntervalSinceReferenceDate: -12.125)),
        .array([]), .dictionary([:]), .string(""), .string("emoji 🧪"),
    ]
    let workflow: PlistValue = .dictionary([
        "WFWorkflowActions": .array([]), "values": .array(values),
    ])
    let project = WorkflowProject(name: "Binary types", workflow: workflow)
    let first = try WorkflowCompiler.compile(project, format: .binary)
    let decoded = try WorkflowCodec.decodeWorkflow(first, name: project.name)
    #expect(decoded.workflow == workflow)
    #expect(try WorkflowCompiler.compile(decoded, format: .binary) == first)
}

@Test func binaryEncodingDoesNotDependOnDictionaryInsertionOrder() throws {
    let keys = ["z", "a", "long key", "中文", "🧪"]
    let pairs = keys.enumerated().map { ($0.element, PlistValue.integer(Int64($0.offset))) }
    let first: PlistValue = .dictionary(Dictionary(uniqueKeysWithValues: pairs))
    let second: PlistValue = .dictionary(Dictionary(uniqueKeysWithValues: pairs.reversed()))
    #expect(try CanonicalBinaryPlist.encode(first) == CanonicalBinaryPlist.encode(second))
}
