import ArgumentParser
import Foundation
import ShortcutCore

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run an explicitly selected installed shortcut and capture its real output.",
        discussion:
            "Prefer an identifier to avoid ambiguous names. This command can perform all side effects of the selected shortcut and may require app permissions. It does not import or execute project files. Timeout cannot roll back effects or guarantee app-side cancellation."
    )
    @Argument(help: "Installed shortcut name or identifier.") var shortcut: String
    @Option(name: [.short, .long], help: "Regular input file (maximum 16 MiB). Stdin is not read implicitly.")
    var input: String?
    @Option(name: [.short, .long], help: "Save raw result bytes to this path instead of embedding them in the report.")
    var output: String?
    @Option(help: "Apple Uniform Type Identifier for output serialization.") var outputType = "public.plain-text"
    @OptionGroup var presentation: OutputOptions
    @OptionGroup var write: WriteOptions
    @OptionGroup var native: NativeOptions

    mutating func validate() throws {
        guard !shortcut.isEmpty, !shortcut.hasPrefix("-"), !shortcut.contains("\0") else {
            throw ValidationError(
                "Use a nonempty shortcut name or identifier. Names beginning with '-' require an identifier.")
        }
        guard !outputType.isEmpty, !outputType.hasPrefix("-"), !outputType.contains("\0") else {
            throw ValidationError("--output-type must be a nonempty Uniform Type Identifier.")
        }
    }

    mutating func run() throws {
        let inputURL = input.map(fileURL)
        let outputURL = output.map(fileURL)
        if let inputURL { _ = try SafeFiles.read(inputURL) }
        if let outputURL {
            if let inputURL { try requireDifferentPaths(input: inputURL, output: outputURL) }
            try SafeFiles.checkDestination(outputURL, overwrite: write.force)
        }
        if write.dryRun {
            try presentation.emit(
                RunResult(
                    shortcut: shortcut, executed: false, dryRun: true, outputPath: outputURL?.path, output: nil,
                    stderr: nil), command: "run",
                text: "Would run installed shortcut \(shortcut); no execution performed.")
            return
        }
        let result = try ShortcutRunner().run(
            shortcut, input: inputURL, outputType: outputType, timeout: native.timeout)
        if let outputURL { try SafeFiles.write(result.stdout, to: outputURL, overwrite: write.force) }
        let report = RunResult(
            shortcut: shortcut, executed: true, dryRun: false, outputPath: outputURL?.path,
            output: outputURL == nil ? CapturedData(result.stdout) : nil,
            stderr: result.stderr.isEmpty ? nil : CapturedData(result.stderr))
        let text: String
        if let outputURL {
            text = "Executed \(shortcut); wrote \(result.stdout.count) bytes to \(outputURL.path)."
        } else {
            text =
                String(data: result.stdout, encoding: .utf8)
                ?? "Binary output (\(result.stdout.count) bytes): \(result.stdout.base64EncodedString())"
        }
        try presentation.emit(report, command: "run", text: text)
    }
}

struct Test: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run a project's assertions against an explicitly selected installed shortcut.",
        discussion:
            "Tests compare exact UTF-8 output bytes. The CLI cannot verify that the installed shortcut matches the source project; import the newly built artifact first. No runtime emulation is used. A native failure stops the remaining cases; assertion mismatches do not."
    )
    @Argument(help: "Project JSON containing runtime tests.") var source: String
    @Option(help: "Installed shortcut name or identifier to execute.") var shortcut: String
    @Option(name: .customLong("case"), help: "Execute only the named test case.") var caseName: String?
    @Flag(help: "Validate and list test cases without executing any shortcut.") var dryRun = false
    @OptionGroup var output: OutputOptions
    @OptionGroup var native: NativeOptions

    mutating func validate() throws {
        guard !shortcut.isEmpty, !shortcut.hasPrefix("-"), !shortcut.contains("\0") else {
            throw ValidationError("Use a nonempty installed shortcut name or identifier.")
        }
    }

    mutating func run() throws {
        let project = try WorkflowCodec.load(fileURL(source))
        let report = try WorkflowTester.run(
            project, shortcut: shortcut, timeout: native.timeout, caseName: caseName, dryRun: dryRun)
        let text =
            dryRun
            ? "Planned \(report.plannedCount) test(s); no execution performed."
            : report.cases.map {
                "\($0.passed ? "PASS" : "FAIL") \($0.name)\($0.error.map { ": " + (output.language == .zh ? $0.messageZH : $0.message) } ?? "")"
            }.joined(separator: "\n")
        try output.emit(report, command: "test", ok: dryRun || report.passed, text: text)
        if !dryRun && !report.passed { throw ExitCode(7) }
    }
}

struct CapturedData: Encodable {
    let encoding: String
    let content: String
    let byteCount: Int

    init(_ data: Data) {
        if let text = String(data: data, encoding: .utf8) {
            encoding = "utf8"
            content = text
        } else {
            encoding = "base64"
            content = data.base64EncodedString()
        }
        byteCount = data.count
    }
}

struct RunResult: Encodable {
    let shortcut: String
    let executed: Bool
    let dryRun: Bool
    let outputPath: String?
    let output: CapturedData?
    let stderr: CapturedData?
}
