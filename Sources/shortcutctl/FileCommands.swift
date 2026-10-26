import ArgumentParser
import CryptoKit
import Foundation
import ShortcutCore

struct Create: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a versioned workflow project with runtime assertions.")
    @Argument(help: "New JSON project file. Its parent directory must exist.") var path: String
    @Option(help: "Project display name. Defaults to the output filename without its extension.") var name: String?
    @Option(help: "Template: text, dictionary, if, repeat, or http. HTTP uses a local fixture server.") var template =
        "text"
    @OptionGroup var output: OutputOptions
    @OptionGroup var write: WriteOptions

    mutating func run() throws {
        let destination = fileURL(path)
        let project = try ProjectTemplates.make(
            name: name ?? destination.deletingPathExtension().lastPathComponent, template: template)
        let data = try WorkflowCodec.encodeProject(project)
        try SafeFiles.checkDestination(destination, overwrite: write.force)
        if !write.dryRun { try SafeFiles.write(data, to: destination, overwrite: write.force) }
        try output.emit(
            FileResult(output: destination.path, dryRun: write.dryRun, bytes: data.count), command: "create",
            text: "\(write.dryRun ? "Would create" : "Created") \(destination.path) (\(template))",
            chinese: "\(write.dryRun ? "计划创建" : "已创建") \(destination.path)（\(template)）")
    }
}

enum BuildFormat: String, ExpressibleByArgument { case xml, binary }
enum BuildSign: String, ExpressibleByArgument {
    case none, anyone
    case peopleWhoKnowMe = "people-who-know-me"
}

struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Validate and compile a project; optionally sign using Apple's CLI.",
        discussion:
            "Unsigned output is the default. --sign anyone may send a copy to Apple for validation. people-who-know-me may include contact information. Signing is not import or execution."
    )
    @Argument(help: "Source project JSON, plist, or signed AEA1 workflow.") var source: String
    @Option(name: [.short, .long], help: "Output .shortcut path. Use the intended import name as its basename.")
    var output: String
    @Option(help: "Property-list encoding: xml or binary. Fractional dates require binary.") var format: BuildFormat =
        .xml
    @Option(help: "Signing mode: none, anyone, people-who-know-me.") var sign: BuildSign = .none
    @Flag(help: "Reject validation warnings as well as errors.") var strict = false
    @OptionGroup var presentation: OutputOptions
    @OptionGroup var write: WriteOptions
    @OptionGroup var native: NativeOptions

    mutating func run() throws {
        let input = fileURL(source)
        let destination = fileURL(output)
        try requireDifferentPaths(input: input, output: destination)
        try SafeFiles.checkDestination(destination, overwrite: write.force)
        let project = try WorkflowCodec.load(input)
        let diagnostics = WorkflowValidator.validate(project)
        if strict && diagnostics.contains(where: { $0.severity == .warning }) {
            throw ToolFailure(
                "validation_warnings", "Strict validation rejected workflow warnings.", "严格校验不允许工作流警告。",
                hint: "Run lint --json to inspect diagnostics.", exitCode: 3)
        }
        var data = try WorkflowCompiler.compile(project, format: format == .xml ? .xml : .binary)
        if !write.dryRun, let mode = SigningMode(rawValue: sign.rawValue) {
            data = try ShortcutRunner().sign(data, mode: mode, timeout: native.timeout)
        }
        if !write.dryRun { try SafeFiles.write(data, to: destination, overwrite: write.force) }
        let result = BuildResult(
            output: destination.path, dryRun: write.dryRun, format: format.rawValue,
            signed: !write.dryRun && sign != .none, signingMode: sign.rawValue, bytes: data.count,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), diagnostics: diagnostics)
        var message =
            "\(write.dryRun ? "Would build" : "Built") \(destination.path); \(result.bytes) bytes; \(result.signed ? "signed" : "unsigned")."
        if !diagnostics.isEmpty { message += "\n" + presentation.diagnosticText(diagnostics) }
        try presentation.emit(result, command: "build", text: message)
    }
}

struct Inspect: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inspect all actions, parameters, metadata, and structural diagnostics.")
    @Argument(help: "Project JSON, XML/binary plist, or signed AEA1 workflow.") var source: String
    @OptionGroup var output: OutputOptions

    mutating func run() throws {
        let project = try WorkflowCodec.load(fileURL(source))
        let actions = project.workflow["WFWorkflowActions"]?.array ?? []
        let diagnostics = WorkflowValidator.validate(project)
        let result = InspectionResult(
            name: project.name, actionCount: actions.count,
            structurallyValid: !diagnostics.contains { $0.severity == .error }, project: project,
            diagnostics: diagnostics)
        let description = try WorkflowCodec.encodeProject(project)
        var text = "\(project.name): \(actions.count) action(s)\n" + String(decoding: description, as: UTF8.self)
        if !diagnostics.isEmpty { text += output.diagnosticText(diagnostics) }
        try output.emit(result, command: "inspect", text: text)
    }
}

struct Decompile: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Convert a workflow or signed AEA1 container to loss-preserving project JSON.",
        discussion:
            "Signed, unencrypted AEA1 profile 0 is decoded with AppleArchive. Embedded-key integrity does not establish certificate trust or shortcut safety. Output is JSON, not Swift source."
    )
    @Argument(help: "Project JSON, XML/binary plist, or signed AEA1 workflow.") var source: String
    @Option(name: [.short, .long], help: "Write project JSON here; omit to print it.") var output: String?
    @OptionGroup var presentation: OutputOptions
    @OptionGroup var write: WriteOptions

    mutating func run() throws {
        let input = fileURL(source)
        let project = try WorkflowCodec.load(input)
        let data = try WorkflowCodec.encodeProject(project)
        if let output {
            let destination = fileURL(output)
            try requireDifferentPaths(input: input, output: destination)
            try SafeFiles.checkDestination(destination, overwrite: write.force)
            if !write.dryRun { try SafeFiles.write(data, to: destination, overwrite: write.force) }
            try presentation.emit(
                FileResult(output: destination.path, dryRun: write.dryRun, bytes: data.count), command: "decompile",
                text: "\(write.dryRun ? "Would write" : "Wrote") \(destination.path)")
        } else {
            try presentation.emit(project, command: "decompile", text: String(decoding: data, as: UTF8.self))
        }
    }
}

struct Lint: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Validate workflow structure, control flow, references, and known parameter types.",
        discussion:
            "Unknown actions are preserved and produce warnings. Passing lint does not establish that an action exists or runs on this device."
    )
    @Argument(help: "Project JSON, plist, or signed AEA1 workflow.") var source: String
    @Flag(help: "Return validation failure for warnings too.") var strict = false
    @OptionGroup var output: OutputOptions

    mutating func run() throws {
        let project = try WorkflowCodec.load(fileURL(source))
        let diagnostics = WorkflowValidator.validate(project)
        let valid = !diagnostics.contains { $0.severity == .error || strict }
        let result = LintResult(valid: valid, strict: strict, diagnostics: diagnostics)
        let text =
            diagnostics.isEmpty
            ? "Structural validation passed. Runtime behavior is unverified." : output.diagnosticText(diagnostics)
        try output.emit(
            result, command: "lint", ok: valid, text: text, chinese: diagnostics.isEmpty ? "结构校验通过；尚未验证实际运行。" : text)
        if !valid { throw ExitCode(3) }
    }
}

struct FileResult: Encodable {
    let output: String
    let dryRun: Bool
    let bytes: Int
}
struct BuildResult: Encodable {
    let output: String
    let dryRun: Bool
    let format: String
    let signed: Bool
    let signingMode: String
    let bytes: Int
    let sha256: String
    let diagnostics: [Diagnostic]
}
struct InspectionResult: Encodable {
    let name: String
    let actionCount: Int
    let structurallyValid: Bool
    let project: WorkflowProject
    let diagnostics: [Diagnostic]
}
struct LintResult: Encodable {
    let valid: Bool
    let strict: Bool
    let diagnostics: [Diagnostic]
}
