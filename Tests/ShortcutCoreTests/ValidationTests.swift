import Foundation
import Testing

@testable import ShortcutCore

@Test(arguments: [
    "empty-name", "bad-schema", "not-dictionary", "bad-action", "bad-parameters", "bad-uuid", "duplicate-uuid",
    "unclosed", "bad-control", "repeat-middle", "duplicate-group", "duplicate-else", "negative-repeat",
    "fractional-repeat", "text-repeat", "forward", "unknown-variable", "bad-text-range", "bad-text-type", "http-method",
    "bad-variable", "test-names",
])
func validationRejectsOrWarnsForMalformedGraphs(_ scenario: String) throws {
    let group = "A0000000-0000-4000-8000-000000000001"
    let uuid = "B0000000-0000-4000-8000-000000000001"
    func action(_ suffix: String, _ parameters: [String: PlistValue] = [:]) -> PlistValue {
        .dictionary([
            "WFWorkflowActionIdentifier": .string("is.workflow.actions." + suffix),
            "WFWorkflowActionParameters": .dictionary(parameters),
        ])
    }
    func control(_ suffix: String, _ mode: Int64) -> PlistValue {
        action(suffix, ["GroupingIdentifier": .string(group), "WFControlFlowMode": .integer(mode)])
    }
    var project = WorkflowProject(name: "Validation", workflow: .dictionary(["WFWorkflowActions": .array([])]))
    var actions: [PlistValue] = []
    var expected = ""
    switch scenario {
    case "empty-name":
        project.name = " \n"
        expected = "empty_name"
    case "bad-schema":
        project.schemaVersion = 2
        expected = "unsupported_schema"
    case "not-dictionary":
        project.workflow = .string("bad")
        expected = "invalid_workflow"
    case "bad-action":
        actions = [.string("bad")]
        expected = "invalid_action"
    case "bad-parameters":
        actions = [
            .dictionary([
                "WFWorkflowActionIdentifier": .string("is.workflow.actions.gettext"),
                "WFWorkflowActionParameters": .array([]),
            ])
        ]
        expected = "invalid_parameters"
    case "bad-uuid":
        actions = [action("gettext", ["UUID": .string("bad")])]
        expected = "invalid_uuid"
    case "duplicate-uuid":
        actions = [action("gettext", ["UUID": .string(uuid)]), action("gettext", ["UUID": .string(uuid)])]
        expected = "duplicate_output"
    case "unclosed":
        actions = [control("conditional", 0)]
        expected = "unclosed_control_flow"
    case "bad-control":
        actions = [action("conditional")]
        expected = "invalid_control_marker"
    case "repeat-middle":
        actions = [control("repeat.count", 0), control("repeat.count", 1), control("repeat.count", 2)]
        expected = "invalid_control_middle"
    case "duplicate-group":
        actions = [
            control("conditional", 0), control("conditional", 2), control("conditional", 0), control("conditional", 2),
        ]
        expected = "duplicate_control_group"
    case "duplicate-else":
        actions = [
            control("conditional", 0), control("conditional", 1), control("conditional", 1), control("conditional", 2),
        ]
        expected = "invalid_control_middle"
    case "negative-repeat", "fractional-repeat", "text-repeat":
        let value: PlistValue =
            scenario == "negative-repeat" ? .integer(-1) : scenario == "fractional-repeat" ? .real(1.5) : .string("bad")
        actions = [
            action(
                "repeat.count",
                ["GroupingIdentifier": .string(group), "WFControlFlowMode": .integer(0), "WFRepeatCount": value]),
            control("repeat.count", 2),
        ]
        expected = "invalid_repeat_count"
    case "forward":
        actions = [
            action(
                "output", ["WFOutput": .dictionary(["Type": .string("ActionOutput"), "OutputUUID": .string(uuid)])]),
            action("gettext", ["UUID": .string(uuid)]),
        ]
        expected = "forward_output"
    case "unknown-variable":
        actions = [
            action(
                "output", ["WFOutput": .dictionary(["Type": .string("Variable"), "VariableName": .string("missing")])])
        ]
        expected = "unresolved_variable"
    case "bad-text-range":
        actions = [
            action(
                "gettext",
                [
                    "WFTextActionText": .dictionary([
                        "WFSerializationType": .string("WFTextTokenString"),
                        "Value": .dictionary([
                            "string": .string("🧪\u{FFFC}"),
                            "attachmentsByRange": .dictionary([
                                "{1, 1}": .dictionary(["Type": .string("ExtensionInput")])
                            ]),
                        ]),
                    ])
                ])
        ]
        expected = "invalid_token_range"
    case "bad-text-type":
        actions = [action("gettext", ["WFTextActionText": .integer(12)])]
        expected = "invalid_parameter_type"
    case "http-method":
        actions = [action("downloadurl", ["WFHTTPMethod": .string("UNKNOWN")])]
        expected = "unrecognized_http_method"
    case "bad-variable":
        actions = [action("setvariable", ["WFVariableName": .string("")])]
        expected = "invalid_variable_name"
    default:
        project.tests = [
            RuntimeTest(name: "", expectedOutput: ""), RuntimeTest(name: "same", expectedOutput: ""),
            RuntimeTest(name: "same", expectedOutput: ""),
        ]
        expected = "invalid_test_name"
    }
    if scenario != "not-dictionary" { project.workflow = .dictionary(["WFWorkflowActions": .array(actions)]) }
    #expect(WorkflowValidator.validate(project).contains { $0.code == expected })
}

@Test func utf16AttachmentsAccountForSurrogatePairs() throws {
    let project = try ProjectTemplates.make(name: "UTF16", template: "text")
    var workflow = try #require(project.workflow.dictionary)
    var actions = try #require(workflow["WFWorkflowActions"]?.array)
    var action = try #require(actions[0].dictionary)
    var parameters = try #require(action["WFWorkflowActionParameters"]?.dictionary)
    parameters["WFTextActionText"] = .dictionary([
        "WFSerializationType": .string("WFTextTokenString"),
        "Value": .dictionary([
            "string": .string("🧪\u{FFFC}"),
            "attachmentsByRange": .dictionary(["{2, 1}": .dictionary(["Type": .string("ExtensionInput")])]),
        ]),
    ])
    action["WFWorkflowActionParameters"] = .dictionary(parameters)
    actions[0] = .dictionary(action)
    workflow["WFWorkflowActions"] = .array(actions)
    #expect(WorkflowValidator.validate(WorkflowProject(name: "UTF16", workflow: .dictionary(workflow))).isEmpty)
}

@Test(arguments: ["missing", "unknown", "null", "bad-data", "bad-real", "extra-tag", "unknown-field", "bad-test-field"])
func projectDecoderRejectsMalformedOrLossyInput(_ scenario: String) {
    let value: String
    switch scenario {
    case "missing": value = "{}"
    case "unknown": value = #"{"schemaVersion":2,"name":"X","workflow":{}}"#
    case "null": value = #"{"schemaVersion":1,"name":"X","workflow":null}"#
    case "bad-data": value = #"{"schemaVersion":1,"name":"X","workflow":{"$plist":"data","value":"!"}}"#
    case "bad-real": value = #"{"schemaVersion":1,"name":"X","workflow":{"$plist":"real","value":"nan"}}"#
    case "extra-tag":
        value = #"{"schemaVersion":1,"name":"X","workflow":{"$plist":"real","value":"1.2","ignored":true}}"#
    case "unknown-field": value = #"{"schemaVersion":1,"name":"X","workflow":{},"ignored":true}"#
    default:
        value =
            #"{"schemaVersion":1,"name":"X","workflow":{},"tests":[{"name":"x","expectedOutput":"","ignored":true}]}"#
    }
    #expect(throws: ToolFailure.self) { try WorkflowCodec.decodeProject(Data(value.utf8)) }
}

@Test func codecRejectsExcessiveNestingAndNonFiniteValues() {
    var nested: PlistValue = .string("leaf")
    for _ in 0..<130 { nested = .array([nested]) }
    #expect(throws: ToolFailure.self) { try nested.propertyList() }
    #expect(throws: ToolFailure.self) { try PlistValue(propertyList: URL(string: "https://example.com")!) }
    #expect(throws: ToolFailure.self) { try PlistValue.real(.infinity).propertyList() }
    #expect(throws: (any Error).self) { try JSONEncoder().encode(PlistValue.real(.nan)) }
}

@Test func unknownTemplateAndEmptyNameAreRejected() {
    #expect(throws: ToolFailure.self) { try ProjectTemplates.make(name: "", template: "text") }
    #expect(throws: ToolFailure.self) { try ProjectTemplates.make(name: "A", template: "missing") }
}
