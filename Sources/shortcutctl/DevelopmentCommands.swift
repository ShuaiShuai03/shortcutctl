import ArgumentParser
import Foundation
import ShortcutCore

struct Diff: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Compare typed workflow values with deterministic JSON Pointer paths.",
        discussion:
            "Arrays are compared by index; UUIDs, metadata, and property-list types are preserved. This is a structural diff, not a behavioral equivalence test."
    )
    @Argument(help: "Original JSON, plist, or signed workflow.") var before: String
    @Argument(help: "Updated JSON, plist, or signed workflow.") var after: String
    @Flag(help: "Compare only the native workflow, excluding project names and tests.") var workflowOnly = false
    @Flag(help: "Exit 8 when differences are found; the report remains on stdout.") var check = false
    @OptionGroup var output: OutputOptions

    mutating func run() throws {
        let result = try WorkflowDiffer.compare(
            WorkflowCodec.load(fileURL(before)), WorkflowCodec.load(fileURL(after)), workflowOnly: workflowOnly)
        let encoder = OutputOptions.encoder
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let text =
            try result.equal
            ? "No differences."
            : result.changes.map { change in
                var lines = ["\(change.kind) \(change.path)"]
                if let before = change.before {
                    lines.append("- " + String(decoding: try encoder.encode(before), as: UTF8.self))
                }
                if let after = change.after {
                    lines.append("+ " + String(decoding: try encoder.encode(after), as: UTF8.self))
                }
                return lines.joined(separator: "\n")
            }.joined(separator: "\n")
        try output.emit(result, command: "diff", ok: !check || result.equal, text: text)
        if check && !result.equal { throw ExitCode(8) }
    }
}

struct Watch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Watch one source file, validate it, and optionally rebuild unsigned output.",
        discussion:
            "Builds immediately, then debounces content changes, including atomic editor saves. Failed edits preserve the last successful output. JSON mode emits one compact envelope per event (NDJSON). No signing, import, or shortcut execution occurs. Stop with Ctrl-C."
    )
    @Argument(help: "Source JSON, plist, or signed workflow.") var source: String
    @Option(name: [.short, .long], help: "Optional unsigned output path; omit for validation only.") var output: String?
    @Option(help: "Output format: xml or binary.") var format: BuildFormat = .binary
    @Flag(help: "Reject warnings as well as errors.") var strict = false
    @Flag(help: "Explicitly permit replacement of an output that existed before watching.") var force = false
    @Flag(help: "Validate/build once and exit with its result.") var once = false
    @Flag(help: "Validate the initial input and output plan without writing or watching.") var dryRun = false
    @Option(help: "Polling interval in seconds, 0.01 through 60.") var interval: Double = 0.25
    @Option(help: "Require stable content for this many seconds, 0 through 60.") var debounce: Double = 0.2
    @Option(help: "Stop after this many seconds; 0 watches until interrupted. Maximum 86400.") var duration: Double = 0
    @OptionGroup var presentation: OutputOptions

    mutating func validate() throws {
        guard interval.isFinite, (0.01...60).contains(interval), debounce.isFinite, (0...60).contains(debounce),
            duration.isFinite, (0...86400).contains(duration)
        else {
            throw ValidationError("--interval must be 0.01...60, --debounce 0...60, and --duration 0...86400 seconds.")
        }
    }

    mutating func run() throws {
        let input = fileURL(source)
        let requestedDestination = output.map(fileURL)
        if let requestedDestination {
            try requireDifferentPaths(input: input, output: requestedDestination)
            try SafeFiles.checkDestination(requestedDestination, overwrite: force)
        }
        // Bind the watched output to its initial directory, even if a parent alias changes later.
        let destination = requestedDestination.map {
            $0.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent($0.lastPathComponent)
        }
        var state = WatchState(debounce: debounce)
        var published: Data?
        var lastReadError: String?
        var sequence = 0
        let started = ProcessInfo.processInfo.systemUptime
        repeat {
            let now = ProcessInfo.processInfo.systemUptime
            do {
                let data = try SafeFiles.read(input)
                lastReadError = nil
                if state.observe(data, at: now) {
                    sequence += 1
                    var diagnostics: [Diagnostic] = []
                    do {
                        let project = try WorkflowCodec.decodeWorkflow(
                            data, name: input.deletingPathExtension().lastPathComponent)
                        diagnostics = WorkflowValidator.validate(project)
                        guard !diagnostics.contains(where: { $0.severity == .error || strict }) else {
                            throw ToolFailure(
                                "validation_failed", "Watched workflow failed validation.", "监视的工作流未通过校验。", exitCode: 3)
                        }
                        var bytes: Int?
                        if let destination {
                            let compiled = try WorkflowCompiler.compile(
                                project, format: format == .binary ? .binary : .xml)
                            if !dryRun {
                                try requireDifferentPaths(input: input, output: destination)
                                var replace = force
                                if !force, let published, FileManager.default.fileExists(atPath: destination.path) {
                                    guard try SafeFiles.read(destination) == published else {
                                        throw ToolFailure(
                                            "output_changed",
                                            "Watch output changed outside this process; refusing replacement.",
                                            "监视输出已被其他进程修改，拒绝覆盖。",
                                            hint:
                                                "Preserve the external changes, choose a new output, or restart with --force.",
                                            exitCode: 5)
                                    }
                                    replace = true
                                }
                                try SafeFiles.write(compiled, to: destination, overwrite: replace)
                                published = compiled
                            }
                            bytes = compiled.count
                        }
                        try emit(
                            WatchEvent(
                                sequence: sequence, dryRun: dryRun,
                                event: dryRun ? "planned" : destination == nil ? "validated" : "built",
                                source: input.path,
                                output: destination?.path, bytes: bytes, diagnostics: diagnostics, error: nil))
                    } catch let error as ToolFailure {
                        try emit(
                            WatchEvent(
                                sequence: sequence, dryRun: dryRun, event: "failed", source: input.path,
                                output: destination?.path,
                                bytes: nil, diagnostics: diagnostics, error: error))
                        if once || dryRun { throw ExitCode(error.exitCode) }
                    }
                }
            } catch let error as ToolFailure {
                if lastReadError != error.code + error.message {
                    lastReadError = error.code + error.message
                    state.invalidate()
                    sequence += 1
                    try emit(
                        WatchEvent(
                            sequence: sequence, dryRun: dryRun, event: "failed", source: input.path,
                            output: destination?.path,
                            bytes: nil, diagnostics: [], error: error))
                }
                if once || dryRun { throw ExitCode(error.exitCode) }
            }
            if once || dryRun { return }
            if duration > 0 && ProcessInfo.processInfo.systemUptime - started >= duration { return }
            Thread.sleep(
                forTimeInterval: min(
                    interval,
                    duration > 0 ? max(0, duration - (ProcessInfo.processInfo.systemUptime - started)) : interval))
        } while true
    }

    private func emit(_ event: WatchEvent) throws {
        let text =
            "\(event.sequence): \(event.event) \(event.output ?? event.source)\(event.error.map { ": " + (presentation.language == .zh ? $0.messageZH : $0.message) } ?? "")"
        try presentation.emit(event, command: "watch", ok: event.error == nil, text: text, stream: true)
    }
}

struct WatchEvent: Encodable {
    let sequence: Int
    let dryRun: Bool
    let event: String
    let source: String
    let output: String?
    let bytes: Int?
    let diagnostics: [Diagnostic]
    let error: ToolFailure?
}
