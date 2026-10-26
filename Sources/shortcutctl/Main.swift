import ArgumentParser
import Darwin
import Foundation
import ShortcutCore

@main
struct ShortcutCTL: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shortcutctl",
        abstract: "Develop, inspect, validate, and test Apple Shortcuts from versioned JSON.",
        discussion:
            "Workflow serialization is experimental. Signing, importing, and execution are distinct steps. No private Shortcuts database access is used.",
        version: "0.1.0",
        subcommands: [Create.self, Build.self, Inspect.self, Decompile.self, Lint.self, Run.self, Test.self]
    )

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        var parsed = false
        do {
            var command = try parseAsRoot(arguments)
            parsed = true
            try command.run()
        } catch let code as ExitCode {
            Darwin.exit(code.rawValue)
        } catch {
            if exitCode(for: error) == .success { exit(withError: error) }
            let failure: ToolFailure
            if let known = error as? ToolFailure {
                failure = known
            } else if !parsed {
                failure = ToolFailure(
                    "invalid_arguments", message(for: error), "命令参数无效：\(message(for: error))",
                    hint: "Use shortcutctl <command> --help.", exitCode: 2)
            } else {
                failure = ToolFailure(
                    "operation_failed", error.localizedDescription, "操作失败：\(error.localizedDescription)", exitCode: 1)
            }
            let wantsJSON = arguments.contains("--json")
            let wantsChinese =
                arguments.contains("--language=zh")
                || arguments.indices.contains {
                    arguments[$0] == "--language" && arguments.indices.contains($0 + 1) && arguments[$0 + 1] == "zh"
                }
            if wantsJSON {
                let commands = ["create", "build", "inspect", "decompile", "lint", "run", "test"]
                let envelope = FailureEnvelope(
                    command: arguments.first(where: commands.contains) ?? "shortcutctl", error: failure)
                if let data = try? OutputOptions.encoder.encode(envelope) {
                    FileHandle.standardError.write(data + Data([10]))
                }
            } else {
                var message = "error[\(failure.code)]: \(wantsChinese ? failure.messageZH : failure.message)\n"
                if let hint = failure.hint { message += "\(hint)\n" }
                FileHandle.standardError.write(Data(message.utf8))
            }
            Darwin.exit(failure.exitCode)
        }
    }
}

struct FailureEnvelope: Encodable {
    let schemaVersion = 1
    let ok = false
    let command: String
    let error: ToolFailure
}
