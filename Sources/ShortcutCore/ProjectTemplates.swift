import CryptoKit
import Foundation

public enum ProjectTemplates {
    public static let names = ["text", "dictionary", "if", "repeat", "http"]

    public static func make(name: String, template: String) throws -> WorkflowProject {
        guard names.contains(template) else {
            throw ToolFailure(
                "unknown_template", "Unknown template '\(template)'. Choose \(names.joined(separator: ", ")).",
                "未知模板 '\(template)'。可选值：\(names.joined(separator: ", "))。", exitCode: 2)
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolFailure("empty_name", "Project name must not be empty.", "项目名称不能为空。", exitCode: 2)
        }
        func id(_ index: Int) -> String { stableID("shortcutctl/v1/\(template)/\(name)/\(index)") }
        func action(_ suffix: String, _ index: Int, _ parameters: [String: PlistValue]) -> PlistValue {
            var parameters = parameters
            parameters["UUID"] = .string(id(index))
            return .dictionary([
                "WFWorkflowActionIdentifier": .string("is.workflow.actions." + suffix),
                "WFWorkflowActionParameters": .dictionary(parameters),
            ])
        }
        func reference(_ index: Int) -> PlistValue {
            token(["Type": .string("ActionOutput"), "OutputUUID": .string(id(index)), "OutputName": .string("Result")])
        }
        func referenceText(_ index: Int) -> PlistValue {
            interpolated([
                "Type": .string("ActionOutput"), "OutputUUID": .string(id(index)), "OutputName": .string("Result"),
            ])
        }
        var actions: [PlistValue]
        var tests: [RuntimeTest]
        switch template {
        case "text":
            actions = [
                action("gettext", 0, ["WFTextActionText": interpolated(["Type": .string("ExtensionInput")])]),
                action("output", 1, ["WFOutput": referenceText(0)]),
            ]
            tests = [
                RuntimeTest(name: "echo", input: "Hello from shortcutctl", expectedOutput: "Hello from shortcutctl"),
                RuntimeTest(name: "unicode", input: "Hello 世界 🧪", expectedOutput: "Hello 世界 🧪"),
            ]
        case "dictionary":
            let items: PlistValue = .dictionary([
                "WFSerializationType": .string("WFDictionaryFieldValue"),
                "Value": .dictionary([
                    "WFDictionaryFieldValueItems": .array([
                        .dictionary([
                            "WFItemType": .integer(0), "WFKey": text("message"), "WFValue": text("Dictionary passed"),
                        ])
                    ])
                ]),
            ])
            actions = [
                action("dictionary", 0, ["WFItems": items]),
                action("setvariable", 1, ["WFVariableName": .string("payload"), "WFInput": reference(0)]),
                action(
                    "getvalueforkey", 2,
                    [
                        "WFInput": token(["Type": .string("Variable"), "VariableName": .string("payload")]),
                        "WFDictionaryKey": .string("message"),
                    ]),
                action("output", 3, ["WFOutput": referenceText(2)]),
            ]
            tests = [RuntimeTest(name: "dictionary-variable", expectedOutput: "Dictionary passed")]
        case "if":
            let group: PlistValue = .string(id(100))
            actions = [
                action("gettext", 10, ["WFTextActionText": interpolated(["Type": .string("ExtensionInput")])]),
                action(
                    "conditional", 0,
                    [
                        "GroupingIdentifier": group, "WFControlFlowMode": .integer(0),
                        "WFInput": .dictionary(["Type": .string("Variable"), "Variable": reference(10)]),
                        "WFCondition": .integer(4), "WFConditionalActionString": .string("yes"),
                    ]),
                action("gettext", 1, ["WFTextActionText": .string("matched")]),
                action("output", 2, ["WFOutput": referenceText(1)]),
                action("conditional", 3, ["GroupingIdentifier": group, "WFControlFlowMode": .integer(1)]),
                action("gettext", 4, ["WFTextActionText": .string("not matched")]),
                action("output", 5, ["WFOutput": referenceText(4)]),
                action("conditional", 6, ["GroupingIdentifier": group, "WFControlFlowMode": .integer(2)]),
            ]
            tests = [
                RuntimeTest(name: "true-branch", input: "yes", expectedOutput: "matched"),
                RuntimeTest(name: "false-branch", input: "no", expectedOutput: "not matched"),
            ]
        case "repeat":
            let group: PlistValue = .string(id(100))
            actions = [
                action(
                    "repeat.count", 0,
                    ["GroupingIdentifier": group, "WFControlFlowMode": .integer(0), "WFRepeatCount": .integer(3)]),
                action("gettext", 1, ["WFTextActionText": .string("item")]),
                action("repeat.count", 2, ["GroupingIdentifier": group, "WFControlFlowMode": .integer(2)]),
                action("text.combine", 3, ["text": reference(2), "WFTextSeparator": .string("New Lines")]),
                action("output", 4, ["WFOutput": referenceText(3)]),
            ]
            tests = [RuntimeTest(name: "repeat-three", expectedOutput: "item\nitem\nitem")]
        default:
            actions = [
                action("url", 0, ["WFURLActionURL": .string("http://127.0.0.1:8765/fixture.json")]),
                action("downloadurl", 1, ["WFHTTPMethod": .string("GET"), "WFURL": referenceText(0)]),
                action("detect.dictionary", 2, ["WFInput": reference(1)]),
                action("getvalueforkey", 3, ["WFInput": reference(2), "WFDictionaryKey": .string("message")]),
                action("output", 4, ["WFOutput": referenceText(3)]),
            ]
            tests = [RuntimeTest(name: "http-json", expectedOutput: "HTTP passed")]
        }
        return WorkflowProject(
            name: name,
            workflow: .dictionary([
                "WFWorkflowName": .string(name),
                "WFWorkflowClientVersion": .string("4018.0.4"),
                "WFWorkflowMinimumClientVersion": .integer(900),
                "WFWorkflowMinimumClientVersionString": .string("900"),
                "WFWorkflowHasShortcutInputVariables": .bool(template == "text" || template == "if"),
                "WFWorkflowIcon": .dictionary([
                    "WFWorkflowIconStartColor": .integer(4_282_601_983), "WFWorkflowIconGlyphNumber": .integer(59511),
                ]),
                "WFWorkflowInputContentItemClasses": .array([.string("WFStringContentItem")]),
                "WFWorkflowOutputContentItemClasses": .array([.string("WFStringContentItem")]),
                "WFWorkflowHasOutputFallback": .bool(false),
                "WFWorkflowTypes": .array([]),
                "WFWorkflowImportQuestions": .array([]),
                "WFWorkflowActions": .array(actions),
            ]), tests: tests)
    }

    private static func token(_ value: [String: PlistValue]) -> PlistValue {
        .dictionary(["WFSerializationType": .string("WFTextTokenAttachment"), "Value": .dictionary(value)])
    }

    private static func text(_ string: String) -> PlistValue {
        .dictionary([
            "WFSerializationType": .string("WFTextTokenString"),
            "Value": .dictionary([
                "string": .string(string), "attachmentsByRange": .dictionary([:]),
            ]),
        ])
    }

    private static func interpolated(_ attachment: [String: PlistValue]) -> PlistValue {
        .dictionary([
            "WFSerializationType": .string("WFTextTokenString"),
            "Value": .dictionary([
                "string": .string("\u{FFFC}"),
                "attachmentsByRange": .dictionary(["{0, 1}": .dictionary(attachment)]),
            ]),
        ])
    }

    private static func stableID(_ seed: String) -> String {
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map { String(format: "%02X", $0) }
        return [hex[0..<4], hex[4..<6], hex[6..<8], hex[8..<10], hex[10..<16]].map { $0.joined() }.joined(
            separator: "-")
    }
}
