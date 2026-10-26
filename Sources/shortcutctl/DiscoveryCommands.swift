import ArgumentParser
import Foundation
import ShortcutCore

struct Discover: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search the compatibility catalog, observed workflow actions, or an app's App Intents metadata.",
        discussion:
            "Metadata is experimental evidence, not proof of availability. App Intent identifiers are not native workflow action identifiers. No private database or action execution is used."
    )
    @Option(help: "Case-insensitive identifier or title substring.") var query: String?
    @Option(help: "Exact identifier to inspect.") var identifier: String?
    @Option(help: "Read observed actions and parameter keys from a workflow.") var workflow: String?
    @Option(help: "Read an extract.actionsdata JSON file.") var metadata: String?
    @Option(help: "Read Contents/Resources/Metadata.appintents/extract.actionsdata from this .app bundle.") var app:
        String?
    @OptionGroup var output: OutputOptions

    mutating func validate() throws {
        guard [workflow, metadata, app].compactMap({ $0 }).count <= 1 else {
            throw ValidationError("Use only one of --workflow, --metadata, or --app.")
        }
    }

    mutating func run() throws {
        var actions: [DiscoveredAction]
        if let workflow {
            actions = ActionDiscovery.observed(
                try WorkflowCodec.load(fileURL(workflow)), source: fileURL(workflow).path)
        } else if let path = metadata.map(fileURL)
            ?? app.map({
                fileURL($0).appendingPathComponent("Contents/Resources/Metadata.appintents/extract.actionsdata")
            })
        {
            actions = try ActionDiscovery.metadata(SafeFiles.read(path), source: path.path)
        } else {
            actions = ActionDiscovery.catalog()
        }
        actions = actions.filter {
            ActionDiscovery.matches($0, query: query) && (identifier == nil || $0.identifier == identifier)
        }
        let report = DiscoveryResult(complete: false, actions: actions)
        let text = actions.map {
            "\($0.identifier) [\($0.kind)]\n  \($0.title)\n  Parameters: \($0.parameters.joined(separator: ", "))\($0.metadataJSON.map { "\n  " + $0 } ?? "")"
        }.joined(separator: "\n")
        try output.emit(report, command: "discover", text: text.isEmpty ? "No matching actions." : text)
    }
}

struct DiscoveryResult: Encodable {
    let complete: Bool
    let actions: [DiscoveredAction]
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List installed shortcuts with identifiers, or folder names, using Apple's CLI.")
    @Option(help: "Restrict shortcuts to a folder name or identifier; 'none' means unfiled.") var folder: String?
    @Flag(help: "List folder names instead of shortcuts.") var folders = false
    @OptionGroup var output: OutputOptions
    @OptionGroup var native: NativeOptions

    mutating func validate() throws {
        if folders && folder != nil { throw ValidationError("--folders and --folder cannot be combined.") }
        if let folder, folder.isEmpty || folder.contains("\0") || folder.hasPrefix("-") {
            throw ValidationError(
                "--folder must be nonempty and contain no NUL; use an identifier for names beginning with a hyphen.")
        }
    }

    mutating func run() throws {
        let data = try ShortcutRunner().list(folder: folder, folders: folders, timeout: native.timeout)
        if folders {
            guard let text = String(data: data, encoding: .utf8) else {
                throw ToolFailure("unrecognized_listing", "Folder listing is not UTF-8.", "文件夹列表不是 UTF-8。", exitCode: 6)
            }
            let names = text.split(separator: "\n").map(String.init)
            try output.emit(FolderResult(folders: names), command: "list", text: names.joined(separator: "\n"))
        } else {
            let shortcuts = try ShortcutListing.parse(data)
            try output.emit(
                ShortcutListResult(shortcuts: shortcuts), command: "list",
                text: shortcuts.map { "\($0.name) (\($0.identifier))" }.joined(separator: "\n"))
        }
    }
}

struct FolderResult: Encodable { let folders: [String] }
struct ShortcutListResult: Encodable { let shortcuts: [InstalledShortcut] }

struct View: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open an explicitly selected installed shortcut in Apple's editor.")
    @Argument(help: "Installed shortcut name or identifier.") var shortcut: String
    @Flag(help: "Report the plan without opening Shortcuts.") var dryRun = false
    @OptionGroup var output: OutputOptions
    @OptionGroup var native: NativeOptions

    mutating func validate() throws {
        guard !shortcut.isEmpty, !shortcut.contains("\0") else {
            throw ValidationError(
                "Use a nonempty shortcut name or identifier.")
        }
    }

    mutating func run() throws {
        if !dryRun { try ShortcutRunner().view(shortcut, timeout: native.timeout) }
        try output.emit(
            ViewResult(shortcut: shortcut, executed: !dryRun), command: "view",
            text: "\(dryRun ? "Would open" : "Requested editor for") \(shortcut).")
    }
}

struct ViewResult: Encodable {
    let shortcut: String
    let executed: Bool
}
