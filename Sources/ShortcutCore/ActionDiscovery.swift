import Foundation

public struct DiscoveredAction: Encodable, Sendable {
    public let identifier: String
    public let title: String
    public let kind: String
    public let source: String
    public let parameters: [String]
    public let metadataJSON: String?
}

/// Evidence about actions is separate from action availability and validator coverage.
public enum ActionDiscovery {
    public static func catalog(query: String? = nil) -> [DiscoveredAction] {
        var parameters: [String: Set<String>] = [:]
        for template in ProjectTemplates.names {
            guard let project = try? ProjectTemplates.make(name: "Catalog", template: template) else { continue }
            for action in observed(project, source: "shortcutctl") {
                parameters[action.identifier, default: []].formUnion(action.parameters)
            }
        }
        return ActionRegistry.identifiers.sorted().map {
            DiscoveredAction(
                identifier: $0, title: titles[$0] ?? $0, kind: "compatibility", source: "shortcutctl",
                parameters: parameters[$0]?.sorted() ?? [], metadataJSON: nil)
        }.filter { matches($0, query: query) }
    }

    public static func observed(_ project: WorkflowProject, source: String) -> [DiscoveredAction] {
        var parameters: [String: Set<String>] = [:]
        for action in project.workflow["WFWorkflowActions"]?.array ?? [] {
            guard let identifier = action["WFWorkflowActionIdentifier"]?.string else { continue }
            parameters[identifier, default: []].formUnion(
                action["WFWorkflowActionParameters"]?.dictionary?.keys.map { $0 } ?? [])
        }
        return parameters.keys.sorted().map {
            DiscoveredAction(
                identifier: $0, title: $0, kind: "observed", source: source,
                parameters: parameters[$0]!.sorted(), metadataJSON: nil)
        }
    }

    public static func metadata(_ data: Data, source: String) throws -> [DiscoveredAction] {
        do {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let actions = root["actions"] as? [String: [String: Any]]
            else { throw invalidMetadata() }
            return try actions.keys.sorted().map { key in
                let item = actions[key]!
                let title = item["title"] as? String ?? (item["title"] as? [String: Any])?["key"] as? String ?? key
                let raw = try JSONSerialization.data(withJSONObject: item, options: [.sortedKeys, .fragmentsAllowed])
                return DiscoveredAction(
                    identifier: item["identifier"] as? String ?? key, title: title,
                    kind: "app-intent", source: source,
                    parameters: (item["parameters"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                        .sorted(),
                    metadataJSON: String(decoding: raw, as: UTF8.self))
            }
        } catch let failure as ToolFailure { throw failure } catch { throw invalidMetadata() }
    }

    public static func matches(_ action: DiscoveredAction, query: String?) -> Bool {
        guard let query, !query.isEmpty else { return true }
        return [action.identifier, action.title].joined(separator: " ").localizedCaseInsensitiveContains(query)
    }

    private static let titles: [String: String] = [
        "is.workflow.actions.gettext": "Text", "is.workflow.actions.comment": "Comment",
        "is.workflow.actions.setvariable": "Set Variable", "is.workflow.actions.getvariable": "Get Variable",
        "is.workflow.actions.dictionary": "Dictionary", "is.workflow.actions.getvalueforkey": "Get Dictionary Value",
        "is.workflow.actions.conditional": "If", "is.workflow.actions.repeat.count": "Repeat",
        "is.workflow.actions.repeat.each": "Repeat with Each", "is.workflow.actions.choosefrommenu": "Choose from Menu",
        "is.workflow.actions.url": "URL", "is.workflow.actions.downloadurl": "Get Contents of URL",
        "is.workflow.actions.detect.dictionary": "Get Dictionary from Input",
        "is.workflow.actions.output": "Stop and Output",
        "is.workflow.actions.showresult": "Show Result", "is.workflow.actions.nothing": "Nothing",
        "is.workflow.actions.text.combine": "Combine Text",
    ]

    private static func invalidMetadata() -> ToolFailure {
        ToolFailure(
            "invalid_action_metadata", "Expected App Intents JSON metadata containing an actions dictionary.",
            "需要包含 actions 字典的 App Intents JSON 元数据。", exitCode: 3)
    }
}

public struct InstalledShortcut: Encodable, Sendable {
    public let name: String
    public let identifier: String
}

public enum ShortcutListing {
    public static func parse(_ data: Data) throws -> [InstalledShortcut] {
        guard let text = String(data: data, encoding: .utf8) else { throw invalidListing() }
        return try text.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            guard line.hasSuffix(")"), let separator = line.range(of: " (", options: .backwards) else {
                throw invalidListing()
            }
            let name = String(line[..<separator.lowerBound])
            let identifier = String(line[separator.upperBound..<line.index(before: line.endIndex)])
            guard !name.isEmpty, UUID(uuidString: identifier) != nil else { throw invalidListing() }
            return InstalledShortcut(name: name, identifier: identifier)
        }
    }

    private static func invalidListing() -> ToolFailure {
        ToolFailure(
            "unrecognized_listing", "Apple's shortcut listing is not in the expected name (UUID) format.",
            "Apple 快捷指令列表不符合预期的名称和 UUID 格式。", hint: "Inspect /usr/bin/shortcuts list --show-identifiers directly.",
            exitCode: 6)
    }
}
