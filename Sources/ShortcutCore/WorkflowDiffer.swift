import Foundation

public struct WorkflowChange: Encodable, Sendable {
    public let kind: String
    public let path: String
    public let before: PlistValue?
    public let after: PlistValue?
}

public struct WorkflowDifference: Encodable, Sendable {
    public let equal: Bool
    public let workflowOnly: Bool
    public let changes: [WorkflowChange]
}

/// Compare typed values, with ordered arrays and RFC 6901 paths; never normalize identifiers or values.
public enum WorkflowDiffer {
    public static func compare(_ before: WorkflowProject, _ after: WorkflowProject, workflowOnly: Bool = false)
        throws -> WorkflowDifference
    {
        var changes: [WorkflowChange] = []
        func walk(_ left: PlistValue?, _ right: PlistValue?, _ path: String) {
            guard left != right else { return }
            if let lhs = left?.dictionary, let rhs = right?.dictionary {
                let leftFields = Dictionary(uniqueKeysWithValues: lhs.map { (Array($0.key.utf8), $0) })
                let rightFields = Dictionary(uniqueKeysWithValues: rhs.map { (Array($0.key.utf8), $0) })
                for bytes in Set(leftFields.keys).union(rightFields.keys).sorted(by: {
                    $0.lexicographicallyPrecedes($1)
                }) {
                    let key = String(decoding: bytes, as: UTF8.self)
                    let escaped = key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(
                        of: "/", with: "~1")
                    walk(leftFields[bytes]?.value, rightFields[bytes]?.value, path + "/" + escaped)
                }
            } else if let lhs = left?.array, let rhs = right?.array {
                for index in 0..<max(lhs.count, rhs.count) {
                    walk(index < lhs.count ? lhs[index] : nil, index < rhs.count ? rhs[index] : nil, path + "/\(index)")
                }
            } else {
                changes.append(
                    WorkflowChange(
                        kind: left == nil ? "added" : right == nil ? "removed" : "changed",
                        path: path, before: left, after: right))
            }
        }
        if workflowOnly {
            walk(before.workflow, after.workflow, "/workflow")
        } else {
            func value(_ project: WorkflowProject) -> PlistValue {
                var fields: [String: PlistValue] = [
                    "schemaVersion": .integer(Int64(project.schemaVersion)), "name": .string(project.name),
                    "workflow": project.workflow,
                ]
                fields["tests"] = .array(
                    project.tests.map { test in
                        var fields: [String: PlistValue] = [
                            "name": .string(test.name), "expectedOutput": .string(test.expectedOutput),
                        ]
                        if let input = test.input { fields["input"] = .string(input) }
                        return .dictionary(fields)
                    })
                return .dictionary(fields)
            }
            walk(value(before), value(after), "")
        }
        return WorkflowDifference(equal: changes.isEmpty, workflowOnly: workflowOnly, changes: changes)
    }
}
