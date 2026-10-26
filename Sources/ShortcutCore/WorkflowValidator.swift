import Foundation

public enum ActionRegistry {
    /// A deliberately small compatibility registry, not a list of all installed actions.
    public static let identifiers: Set<String> = [
        "is.workflow.actions.gettext", "is.workflow.actions.comment",
        "is.workflow.actions.setvariable", "is.workflow.actions.getvariable",
        "is.workflow.actions.dictionary", "is.workflow.actions.getvalueforkey",
        "is.workflow.actions.conditional", "is.workflow.actions.repeat.count",
        "is.workflow.actions.repeat.each", "is.workflow.actions.choosefrommenu",
        "is.workflow.actions.url", "is.workflow.actions.downloadurl",
        "is.workflow.actions.detect.dictionary", "is.workflow.actions.output",
        "is.workflow.actions.showresult", "is.workflow.actions.nothing",
        "is.workflow.actions.text.combine",
    ]

    static let controls: Set<String> = [
        "is.workflow.actions.conditional", "is.workflow.actions.repeat.count",
        "is.workflow.actions.repeat.each", "is.workflow.actions.choosefrommenu",
    ]
}

public enum WorkflowValidator {
    public static func validate(_ project: WorkflowProject) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        func error(_ code: String, _ path: String, _ en: String, _ zh: String) {
            diagnostics.append(Diagnostic(.error, code, path: path, en, zh))
        }
        if project.schemaVersion != 1 {
            error("unsupported_schema", "schemaVersion", "Only schemaVersion 1 is supported.", "仅支持 schemaVersion 1。")
        }
        if project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error("empty_name", "name", "Project name must not be empty.", "项目名称不能为空。")
        }
        guard let workflow = project.workflow.dictionary else {
            error("invalid_workflow", "workflow", "Workflow must be a dictionary.", "workflow 必须是字典。")
            return diagnostics
        }
        guard let actions = workflow["WFWorkflowActions"]?.array else {
            error(
                "invalid_actions", "workflow.WFWorkflowActions", "WFWorkflowActions must be an array.",
                "WFWorkflowActions 必须是数组。")
            return diagnostics
        }
        var outputs: [String: Int] = [:]
        for (index, action) in actions.enumerated() {
            if let uuid = action["WFWorkflowActionParameters"]?["UUID"]?.string {
                if outputs[uuid] != nil {
                    error(
                        "duplicate_output", path(index) + ".UUID", "Duplicate action UUID: \(uuid).",
                        "动作 UUID 重复：\(uuid)。")
                }
                outputs[uuid] = index
            }
        }
        var stack: [(identifier: String, group: String, index: Int, middle: Bool)] = []
        var usedGroups: Set<String> = []
        var variables: Set<String> = []
        for (index, action) in actions.enumerated() {
            let location = path(index)
            guard let object = action.dictionary,
                let identifier = object["WFWorkflowActionIdentifier"]?.string, !identifier.isEmpty
            else {
                error(
                    "invalid_action", location, "Action requires a nonempty WFWorkflowActionIdentifier.",
                    "动作必须包含非空 WFWorkflowActionIdentifier。")
                continue
            }
            if !ActionRegistry.identifiers.contains(identifier) {
                diagnostics.append(
                    Diagnostic(
                        .warning, "unknown_action", path: location,
                        "Unknown action \(identifier) is preserved; its parameter semantics are not validated.",
                        "保留未知动作 \(identifier)，但未验证其参数语义。"))
            }
            guard object["WFWorkflowActionParameters"] == nil || object["WFWorkflowActionParameters"]?.dictionary != nil
            else {
                error(
                    "invalid_parameters", location, "WFWorkflowActionParameters must be a dictionary.",
                    "WFWorkflowActionParameters 必须是字典。")
                continue
            }
            let parameters = object["WFWorkflowActionParameters"]?.dictionary ?? [:]
            if let uuid = parameters["UUID"], uuid.string.flatMap(UUID.init(uuidString:)) == nil {
                error(
                    "invalid_uuid", location + ".UUID", "Action UUID must be a UUID string.", "动作 UUID 必须是有效的 UUID 字符串。"
                )
            }
            if ActionRegistry.controls.contains(identifier) {
                guard let mode = parameters["WFControlFlowMode"]?.integer, [0, 1, 2].contains(mode),
                    let group = parameters["GroupingIdentifier"]?.string, UUID(uuidString: group) != nil
                else {
                    error(
                        "invalid_control_marker", location,
                        "Control markers need an integer mode (0, 1, 2) and UUID GroupingIdentifier.",
                        "控制流标记必须包含整数模式（0、1、2）和有效的 GroupingIdentifier。")
                    continue
                }
                if mode == 0 {
                    if !usedGroups.insert(group).inserted {
                        error(
                            "duplicate_control_group", location, "Control group is reused: \(group).",
                            "控制组重复使用：\(group)。")
                    }
                    stack.append((identifier, group, index, false))
                    if identifier == "is.workflow.actions.repeat.count", let count = parameters["WFRepeatCount"] {
                        if let number = count.number {
                            if !number.isFinite || number < 0 || number.rounded(.towardZero) != number {
                                error(
                                    "invalid_repeat_count", location,
                                    "Repeat count must be a nonnegative whole number or a variable token.",
                                    "重复次数必须是非负整数或变量引用。")
                            }
                        } else if !isToken(count) {
                            error(
                                "invalid_repeat_count", location, "Repeat count has an unsupported type.", "重复次数类型不受支持。"
                            )
                        }
                    }
                } else if let current = stack.last, current.identifier == identifier, current.group == group {
                    if mode == 2 {
                        stack.removeLast()
                    } else if identifier.hasPrefix("is.workflow.actions.repeat.")
                        || (identifier == "is.workflow.actions.conditional" && current.middle)
                    {
                        error(
                            "invalid_control_middle", location, "Unexpected or duplicate middle control marker.",
                            "控制流中间标记无效或重复。")
                    } else {
                        stack[stack.count - 1].middle = true
                    }
                } else {
                    error(
                        "unbalanced_control_flow", location, "Control marker does not match the innermost open block.",
                        "控制流标记与最内层未结束块不匹配。")
                }
            }
            inspectReferences(
                .dictionary(parameters), path: location, index: index, outputs: outputs, variables: variables,
                diagnostics: &diagnostics)
            if identifier == "is.workflow.actions.setvariable" {
                if let variable = parameters["WFVariableName"]?.string, !variable.isEmpty {
                    variables.insert(variable)
                } else {
                    error(
                        "invalid_variable_name", location, "Set Variable requires a nonempty WFVariableName.",
                        "设置变量需要非空 WFVariableName。")
                }
            }
            validateKnownParameters(identifier, parameters: parameters, location: location, diagnostics: &diagnostics)
        }
        for block in stack {
            error(
                "unclosed_control_flow", path(block.index), "Control block is not closed: \(block.group).",
                "控制流块未结束：\(block.group)。")
        }
        var testNames: Set<String> = []
        for (index, test) in project.tests.enumerated() {
            if test.name.isEmpty || !testNames.insert(test.name).inserted {
                error(
                    "invalid_test_name", "tests[\(index)].name", "Test names must be nonempty and unique.",
                    "测试名称必须非空且唯一。")
            }
        }
        return diagnostics
    }

    private static func path(_ index: Int) -> String { "workflow.WFWorkflowActions[\(index)]" }

    private static func isToken(_ value: PlistValue) -> Bool {
        guard let type = value["WFSerializationType"]?.string else { return false }
        return ["WFTextTokenString", "WFTextTokenAttachment"].contains(type) && value["Value"]?.dictionary != nil
    }

    private static func inspectReferences(
        _ value: PlistValue, path: String, index: Int, outputs: [String: Int], variables: Set<String>,
        diagnostics: inout [Diagnostic], depth: Int = 0
    ) {
        guard depth <= 128 else {
            diagnostics.append(
                Diagnostic(
                    .error, "nesting_limit", path: path, "Workflow nesting exceeds 128 levels.", "工作流嵌套超过 128 层。"))
            return
        }
        if let object = value.dictionary {
            if object["Type"]?.string == "ActionOutput" {
                if let uuid = object["OutputUUID"]?.string, let producer = outputs[uuid] {
                    if producer >= index {
                        diagnostics.append(
                            Diagnostic(
                                .error, "forward_output", path: path,
                                "Output reference must refer to an earlier action.", "输出引用必须指向前面的动作。"))
                    }
                } else {
                    diagnostics.append(
                        Diagnostic(
                            .error, "unresolved_output", path: path,
                            "Action output reference does not resolve to an action UUID.", "动作输出引用找不到对应 UUID。"))
                }
            }
            if object["Type"]?.string == "Variable", let name = object["VariableName"]?.string,
                !variables.contains(name)
            {
                diagnostics.append(
                    Diagnostic(
                        .warning, "unresolved_variable", path: path,
                        "Named variable \(name) has no preceding Set Variable action; dynamic variables are not fully validated.",
                        "变量 \(name) 未找到前置设置动作；动态变量未完全验证。"))
            }
            if object["WFSerializationType"]?.string == "WFTextTokenString",
                let body = object["Value"]?.dictionary,
                let text = body["string"]?.string,
                let attachments = body["attachmentsByRange"]?.dictionary
            {
                let units = Array(text.utf16)
                for range in attachments.keys.sorted() {
                    let parts = range.dropFirst().dropLast().split(separator: ",").map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }
                    let start = parts.first.flatMap(Int.init)
                    let length = parts.count == 2 ? Int(parts[1]) : nil
                    if !range.hasPrefix("{") || !range.hasSuffix("}") || start == nil || length != 1 || start! < 0
                        || start! >= units.count || units[start!] != 0xFFFC
                    {
                        diagnostics.append(
                            Diagnostic(
                                .error, "invalid_token_range", path: path,
                                "Text attachment \(range) must address a U+FFFC placeholder using UTF-16 offsets.",
                                "文本引用 \(range) 必须使用 UTF-16 偏移指向 U+FFFC 占位符。"))
                    }
                }
            }
            for key in object.keys.sorted() {
                if let item = object[key] {
                    inspectReferences(
                        item, path: path + "." + key, index: index, outputs: outputs, variables: variables,
                        diagnostics: &diagnostics, depth: depth + 1)
                }
            }
        } else if let values = value.array {
            for (offset, item) in values.enumerated() {
                inspectReferences(
                    item, path: path + "[\(offset)]", index: index, outputs: outputs, variables: variables,
                    diagnostics: &diagnostics, depth: depth + 1)
            }
        }
    }

    private static func validateKnownParameters(
        _ identifier: String, parameters: [String: PlistValue], location: String, diagnostics: inout [Diagnostic]
    ) {
        if identifier == "is.workflow.actions.conditional", parameters["WFInput"]?["WFSerializationType"] != nil {
            diagnostics.append(
                Diagnostic(
                    .error, "invalid_condition_input", path: location + ".WFInput",
                    "If operands require a Type: Variable wrapper with the token in Variable.",
                    "如果条件的输入需要 Type: Variable 包装，并将引用放入 Variable 字段。"))
        }
        let textKeys: [String: String] = [
            "is.workflow.actions.gettext": "WFTextActionText",
            "is.workflow.actions.comment": "WFCommentActionText",
            "is.workflow.actions.url": "WFURLActionURL",
            "is.workflow.actions.getvalueforkey": "WFDictionaryKey",
            "is.workflow.actions.output": "WFOutput",
            "is.workflow.actions.downloadurl": "WFURL",
        ]
        if let key = textKeys[identifier], let value = parameters[key],
            value.string == nil && !(value["WFSerializationType"]?.string == "WFTextTokenString" && isToken(value))
        {
            diagnostics.append(
                Diagnostic(
                    .error, "invalid_parameter_type", path: location + "." + key,
                    "\(key) must be text or WFTextTokenString; embed variables in attachmentsByRange, not a standalone WFTextTokenAttachment.",
                    "\(key) 必须是文本或 WFTextTokenString；变量应嵌入 attachmentsByRange，而非独立 WFTextTokenAttachment。"))
        }
        if identifier == "is.workflow.actions.downloadurl", let method = parameters["WFHTTPMethod"]?.string,
            !["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"].contains(method)
        {
            diagnostics.append(
                Diagnostic(
                    .warning, "unrecognized_http_method", path: location,
                    "HTTP method \(method) is not in the compatibility registry.", "HTTP 方法 \(method) 不在兼容性列表中。"))
        }
    }
}
