import Foundation
import Testing

@testable import ShortcutCore

@Test func unknownValuesRoundTripWithoutLoss() throws {
    let original: PlistValue = .dictionary([
        "WFWorkflowActions": .array([
            .dictionary([
                "WFWorkflowActionIdentifier": .string("example.unknown"),
                "WFWorkflowActionParameters": .dictionary([
                    "blob": .data(Data([0, 255, 128])),
                    "date": .date(Date(timeIntervalSinceReferenceDate: 123456)),
                    "integer": .integer(Int64.max),
                    "real": .real(2.0),
                    "flag": .bool(true),
                    "unknown": .dictionary(["$plist": .string("literal"), "value": .string("keep")]),
                ]),
            ])
        ]),
        "vendor": .array([.string("中文 🧪"), .bool(false), .integer(-2)]),
    ])
    let project = WorkflowProject(name: "Round trip", workflow: original)
    let json = try WorkflowCodec.encodeProject(project)
    let decoded = try WorkflowCodec.decodeProject(json)
    #expect(decoded == project)
    let binary = try WorkflowCompiler.compile(decoded, format: .binary)
    let decompiled = try WorkflowCodec.decodeWorkflow(binary, name: "Round trip")
    #expect(decompiled.workflow == original)
    let xml = try WorkflowCompiler.compile(decoded, format: .xml)
    #expect(try WorkflowCodec.decodeWorkflow(xml, name: "Round trip").workflow == original)
}

@Test func fractionalDatesCannotBeSilentlyTruncatedByXML() throws {
    let project = WorkflowProject(
        name: "Date",
        workflow: .dictionary([
            "WFWorkflowActions": .array([]), "unknownDate": .date(Date(timeIntervalSinceReferenceDate: 123456.25)),
        ]))
    #expect(throws: ToolFailure.self) { try WorkflowCompiler.compile(project, format: .xml) }
    let binary = try WorkflowCompiler.compile(project, format: .binary)
    #expect(try WorkflowCodec.decodeWorkflow(binary, name: project.name).workflow == project.workflow)
}

@Test func compilationIsDeterministic() throws {
    let project = try ProjectTemplates.make(name: "Example", template: "text")
    #expect(try WorkflowCompiler.compile(project, format: .xml) == WorkflowCompiler.compile(project, format: .xml))
    #expect(try WorkflowCodec.encodeProject(project) == WorkflowCodec.encodeProject(project))
}

@Test func signedAndMalformedInputsAreRejected() {
    #expect(throws: ToolFailure.self) { try WorkflowCodec.decodeWorkflow(Data("AEA1bogus".utf8), name: "Signed") }
    #expect(throws: ToolFailure.self) { try WorkflowCodec.decodeWorkflow(Data("not a plist".utf8), name: "Bad") }
    #expect(throws: (any Error).self) { try WorkflowCodec.decodeProject(Data("{\"schemaVersion\":999}".utf8)) }
    #expect(throws: (any Error).self) { try JSONDecoder().decode(PlistValue.self, from: Data("null".utf8)) }
}

@Test func invalidGraphCannotCompile() throws {
    let project = WorkflowProject(name: "Bad", workflow: .dictionary(["WFWorkflowActions": .string("not an array")]))
    #expect(WorkflowValidator.validate(project).contains { $0.severity == .error })
    #expect(throws: ToolFailure.self) { try WorkflowCompiler.compile(project, format: .xml) }
}

@Test func unknownActionIsPreservedAndWarned() throws {
    let project = WorkflowProject(
        name: "Unknown",
        workflow: .dictionary([
            "WFWorkflowActions": .array([
                action("com.example.future", ["newParameter": .integer(42)])
            ])
        ]))
    let diagnostics = WorkflowValidator.validate(project)
    #expect(diagnostics.contains { $0.code == "unknown_action" && $0.severity == .warning })
    #expect(!diagnostics.contains { $0.severity == .error })
    #expect(
        try WorkflowCodec.decodeWorkflow(WorkflowCompiler.compile(project, format: .xml), name: "Unknown").workflow
            == project.workflow)
}

@Test func controlsAndReferencesAreValidated() {
    let group = "A0000000-0000-4000-8000-000000000001"
    let output = "B0000000-0000-4000-8000-000000000001"
    let valid = WorkflowProject(
        name: "Control",
        workflow: .dictionary([
            "WFWorkflowActions": .array([
                action("is.workflow.actions.gettext", ["UUID": .string(output), "WFTextActionText": .string("Hi")]),
                action(
                    "is.workflow.actions.repeat.count",
                    ["GroupingIdentifier": .string(group), "WFControlFlowMode": .integer(0), "WFRepeatCount": .real(2)]),
                action(
                    "is.workflow.actions.getvalueforkey",
                    [
                        "WFInput": .dictionary([
                            "WFSerializationType": .string("WFTextTokenAttachment"),
                            "Value": .dictionary([
                                "Type": .string("ActionOutput"), "OutputUUID": .string(output),
                            ]),
                        ])
                    ]),
                action(
                    "is.workflow.actions.repeat.count",
                    ["GroupingIdentifier": .string(group), "WFControlFlowMode": .integer(2)]),
            ])
        ]))
    #expect(!WorkflowValidator.validate(valid).contains { $0.severity == .error })
    let invalid = WorkflowProject(
        name: "Invalid",
        workflow: .dictionary([
            "WFWorkflowActions": .array([
                action(
                    "is.workflow.actions.conditional",
                    ["GroupingIdentifier": .string(group), "WFControlFlowMode": .integer(2)]),
                action(
                    "is.workflow.actions.gettext",
                    ["WFTextActionText": .dictionary(["Type": .string("ActionOutput"), "OutputUUID": .string(output)])]),
            ])
        ]))
    let codes = Set(WorkflowValidator.validate(invalid).map(\.code))
    #expect(codes.contains("unbalanced_control_flow"))
    #expect(codes.contains("unresolved_output"))
}

@Test func textTemplateUsesInterpolatedStringForShortcutInput() throws {
    let project = try ProjectTemplates.make(name: "Input", template: "text")
    let text = project.workflow["WFWorkflowActions"]?.array?.first?["WFWorkflowActionParameters"]?["WFTextActionText"]
    #expect(text?["WFSerializationType"]?.string == "WFTextTokenString")
    #expect(text?["Value"]?["string"]?.string == "\u{FFFC}")
    #expect(text?["Value"]?["attachmentsByRange"]?["{0, 1}"]?["Type"]?.string == "ExtensionInput")
    let bad = WorkflowProject(
        name: "Bad text",
        workflow: .dictionary([
            "WFWorkflowActions": .array([
                action(
                    "is.workflow.actions.gettext",
                    [
                        "WFTextActionText": .dictionary([
                            "WFSerializationType": .string("WFTextTokenAttachment"),
                            "Value": .dictionary(["Type": .string("ExtensionInput")]),
                        ])
                    ])
            ])
        ]))
    #expect(WorkflowValidator.validate(bad).contains { $0.code == "invalid_parameter_type" })
}

@Test func allTemplatesCompileAndContainRuntimeAssertions() throws {
    for name in ProjectTemplates.names {
        let project = try ProjectTemplates.make(name: "Acceptance \(name)", template: name)
        #expect(!project.tests.isEmpty)
        #expect(!WorkflowValidator.validate(project).contains { $0.severity == .error })
        let data = try WorkflowCompiler.compile(project, format: .xml)
        #expect(try WorkflowCodec.decodeWorkflow(data, name: project.name).workflow == project.workflow)
    }
}

@Test func outputAndHTTPURLFieldsUseTextTokens() throws {
    for name in ProjectTemplates.names {
        let project = try ProjectTemplates.make(name: "Tokens", template: name)
        for action in project.workflow["WFWorkflowActions"]?.array ?? [] {
            let id = action["WFWorkflowActionIdentifier"]?.string
            if id == "is.workflow.actions.output" {
                #expect(
                    action["WFWorkflowActionParameters"]?["WFOutput"]?["WFSerializationType"]?.string
                        == "WFTextTokenString")
            }
            if id == "is.workflow.actions.downloadurl" {
                #expect(
                    action["WFWorkflowActionParameters"]?["WFURL"]?["WFSerializationType"]?.string
                        == "WFTextTokenString")
            }
        }
    }
}

@Test func conditionalInputUsesOperandWrapperAndRepeatCombinesResults() throws {
    let conditional = try ProjectTemplates.make(name: "Branch", template: "if")
    let actions = try #require(conditional.workflow["WFWorkflowActions"]?.array)
    #expect(actions.first?["WFWorkflowActionIdentifier"]?.string == "is.workflow.actions.gettext")
    let input = actions.first { $0["WFWorkflowActionIdentifier"]?.string == "is.workflow.actions.conditional" }?[
        "WFWorkflowActionParameters"]?["WFInput"]
    #expect(input?["Type"]?.string == "Variable")
    #expect(input?["Variable"]?["WFSerializationType"]?.string == "WFTextTokenAttachment")
    #expect(input?["Variable"]?["Value"]?["Type"]?.string == "ActionOutput")
    let repeated = try ProjectTemplates.make(name: "Loop", template: "repeat")
    #expect(
        repeated.workflow["WFWorkflowActions"]?.array?.contains {
            $0["WFWorkflowActionIdentifier"]?.string == "is.workflow.actions.text.combine"
        } == true)
}

@Test func lossChecksDistinguishSignedZeroAndUnicodeRepresentation() throws {
    #expect(PlistValue.real(-0.0) != .real(0.0))
    #expect(PlistValue.string("\u{00E9}") != .string("e\u{0301}"))
    let value = PlistValue.real(-0.0)
    let encoded = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(PlistValue.self, from: encoded)
    #expect(decoded == value)
    let project = WorkflowProject(
        name: "Signed zero",
        workflow: .dictionary([
            "WFWorkflowActions": .array([]), "negativeZero": value,
        ]))
    let binary = try WorkflowCompiler.compile(project, format: .binary)
    #expect(try WorkflowCodec.decodeWorkflow(binary, name: project.name).workflow == project.workflow)
    do {
        _ = try WorkflowCompiler.compile(project, format: .xml)
        Issue.record("XML must not silently normalize negative zero")
    } catch let failure as ToolFailure {
        #expect(failure.code == "lossy_serialization")
    }
}

@Test func projectDetectionAcceptsLeadingWhitespaceAndUTF8BOM() throws {
    let project = try ProjectTemplates.make(name: "Whitespace", template: "text")
    let json = try WorkflowCodec.encodeProject(project)
    for prefix in [Data(repeating: 32, count: 512), Data([0xEF, 0xBB, 0xBF])] {
        #expect(try WorkflowCodec.decodeWorkflow(prefix + json, name: "ignored") == project)
    }
}

private func action(_ identifier: String, _ parameters: [String: PlistValue]) -> PlistValue {
    .dictionary([
        "WFWorkflowActionIdentifier": .string(identifier), "WFWorkflowActionParameters": .dictionary(parameters),
    ])
}
