import ArgumentParser
import Foundation
import ShortcutCore

enum Language: String, ExpressibleByArgument { case en, zh }

struct OutputOptions: ParsableArguments {
    @Flag(help: "Emit a versioned JSON envelope. Operational errors go to stderr.")
    var json = false

    @Option(help: "Human diagnostic language: en or zh.")
    var language: Language = .en

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    func emit<T: Encodable>(_ data: T, command: String, ok: Bool = true, text: String, chinese: String? = nil) throws {
        if json {
            let result = try Self.encoder.encode(SuccessEnvelope(command: command, ok: ok, data: data))
            FileHandle.standardOutput.write(result + Data([10]))
        } else {
            print(language == .zh ? (chinese ?? text) : text)
        }
    }

    func diagnosticText(_ diagnostics: [Diagnostic]) -> String {
        diagnostics.map {
            "\($0.severity.rawValue)[\($0.code)] \($0.path): \(language == .zh ? $0.messageZH : $0.message)"
        }.joined(separator: "\n")
    }
}

private struct SuccessEnvelope<T: Encodable>: Encodable {
    let schemaVersion = 1
    let command: String
    let ok: Bool
    let data: T
}

struct WriteOptions: ParsableArguments {
    @Flag(help: "Explicitly replace an existing regular output file. Never follows output symlinks.")
    var force = false

    @Flag(help: "Validate and report the plan without writing files or invoking Shortcuts.")
    var dryRun = false
}

struct NativeOptions: ParsableArguments {
    @Option(help: "Maximum seconds for each native invocation (greater than 0, at most 86400).")
    var timeout: Double = 60

    func validate() throws {
        guard timeout.isFinite, timeout > 0, timeout <= 86400 else {
            throw ValidationError("--timeout must be greater than 0 and at most 86400 seconds.")
        }
    }
}

func fileURL(_ path: String) -> URL { URL(fileURLWithPath: path).standardizedFileURL }

func requireDifferentPaths(input: URL, output: URL) throws {
    guard input.resolvingSymlinksInPath() != output.resolvingSymlinksInPath() else {
        throw ToolFailure(
            "input_output_conflict", "Input and output must use different paths, including with --force.",
            "输入和输出必须使用不同路径，即使指定 --force。", exitCode: 5)
    }
}
