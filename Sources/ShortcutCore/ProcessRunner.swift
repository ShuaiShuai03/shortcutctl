import Darwin
import Foundation

public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data
}

public enum ProcessRunner {
    public static func execute(
        executable: String, arguments: [String], timeout: TimeInterval, maximumOutputBytes: Int = SafeFiles.maximumBytes
    ) throws -> ProcessResult {
        guard timeout.isFinite, timeout > 0, timeout <= 86400 else {
            throw ToolFailure(
                "invalid_timeout", "Timeout must be finite and between 0 and 86400 seconds.",
                "超时时间必须大于 0 且不超过 86400 秒。", exitCode: 2)
        }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ToolFailure(
                "executable_unavailable", "Executable is unavailable: \(executable)", "可执行文件不可用：\(executable)",
                exitCode: 4)
        }
        let directory = try SafeFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdoutURL = directory.appendingPathComponent("stdout")
        let stderrURL = directory.appendingPathComponent("stderr")
        try SafeFiles.write(Data(), to: stdoutURL, overwrite: false)
        try SafeFiles.write(Data(), to: stderrURL, overwrite: false)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdout.close()
            try? stderr.close()
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() } catch {
            throw ToolFailure(
                "launch_failed", "Cannot launch \(executable): \(error.localizedDescription)", "无法启动系统命令。", exitCode: 4)
        }
        let start = ProcessInfo.processInfo.systemUptime
        while process.isRunning {
            if ProcessInfo.processInfo.systemUptime - start >= timeout {
                stop(process)
                throw ToolFailure(
                    "process_timeout",
                    "Command exceeded \(timeout) seconds. Effects inside Shortcuts may already have occurred.",
                    "命令超过 \(timeout) 秒；快捷指令中的操作可能已经执行。",
                    hint:
                        "Inspect Shortcuts for permission dialogs. A timeout does not roll back actions or guarantee app-side cancellation.",
                    exitCode: 124)
            }
            if fileSize(stdoutURL) + fileSize(stderrURL) > maximumOutputBytes {
                stop(process)
                throw ToolFailure(
                    "output_limit", "Command output exceeded \(maximumOutputBytes) bytes.",
                    "命令输出超过 \(maximumOutputBytes) 字节限制。", exitCode: 5)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        process.waitUntilExit()
        let out = try SafeFiles.read(stdoutURL, maximumBytes: maximumOutputBytes)
        let err = try SafeFiles.read(stderrURL, maximumBytes: maximumOutputBytes)
        guard out.count + err.count <= maximumOutputBytes else {
            throw ToolFailure(
                "output_limit", "Command output exceeded \(maximumOutputBytes) bytes.",
                "命令输出超过 \(maximumOutputBytes) 字节限制。", exitCode: 5)
        }
        return ProcessResult(status: process.terminationStatus, stdout: out, stderr: err)
    }

    private static func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? 0
    }

    private static func stop(_ process: Process) {
        if process.isRunning { process.terminate() }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.2
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }
}

public enum SigningMode: String, CaseIterable, Sendable {
    case anyone
    case peopleWhoKnowMe = "people-who-know-me"
}

public struct ShortcutRunner: Sendable {
    public let executable: String

    public init(executable: String = "/usr/bin/shortcuts") { self.executable = executable }

    public func sign(_ data: Data, mode: SigningMode, timeout: TimeInterval) throws -> Data {
        let directory = try SafeFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("unsigned.shortcut")
        let output = directory.appendingPathComponent("signed.shortcut")
        try SafeFiles.write(data, to: input, overwrite: false)
        let result = try ProcessRunner.execute(
            executable: executable,
            arguments: ["sign", "--mode", mode.rawValue, "--input", input.path, "--output", output.path],
            timeout: timeout)
        try requireSuccess(result)
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw ToolFailure(
                "missing_signed_output", "Signing exited successfully but produced no output file.",
                "签名进程成功退出，但未生成输出文件。", exitCode: 6)
        }
        let signed = try SafeFiles.read(output)
        guard !signed.isEmpty else {
            throw ToolFailure("empty_signed_output", "Signing produced an empty file.", "签名生成了空文件。", exitCode: 6)
        }
        return signed
    }

    public func run(_ shortcut: String, input: URL?, outputType: String = "public.plain-text", timeout: TimeInterval)
        throws -> ProcessResult
    {
        guard !shortcut.isEmpty, !shortcut.hasPrefix("-"), !shortcut.contains("\0") else {
            throw ToolFailure(
                "invalid_shortcut",
                "Specify a nonempty shortcut name or identifier that does not begin with '-'. Use its identifier for names beginning with '-'.",
                "请指定非空快捷指令名称或标识符；以 - 开头的名称请使用标识符。", exitCode: 2)
        }
        if let input { _ = try SafeFiles.read(input) }
        var arguments = ["run", shortcut]
        if let input { arguments += ["--input-path", input.path] }
        arguments += ["--output-path", "-", "--output-type", outputType]
        let result = try ProcessRunner.execute(executable: executable, arguments: arguments, timeout: timeout)
        try requireSuccess(result)
        return result
    }

    public func list(folder: String? = nil, folders: Bool = false, timeout: TimeInterval) throws -> Data {
        guard !(folders && folder != nil),
            folder.map({ !$0.isEmpty && !$0.contains("\0") && !$0.hasPrefix("-") }) ?? true
        else {
            throw ToolFailure(
                "invalid_listing_options",
                "Use a nonempty folder name or identifier, and do not combine folder filtering with folder listing.",
                "请使用非空文件夹名称或标识符，且不能同时筛选和列出文件夹。", exitCode: 2)
        }
        var arguments = ["list"]
        arguments += folders ? ["--folders"] : ["--show-identifiers"]
        if let folder { arguments += ["--folder-name", folder] }
        let result = try ProcessRunner.execute(executable: executable, arguments: arguments, timeout: timeout)
        try requireSuccess(result)
        return result.stdout
    }

    public func view(_ shortcut: String, timeout: TimeInterval) throws {
        guard !shortcut.isEmpty, !shortcut.contains("\0") else {
            throw ToolFailure(
                "invalid_shortcut", "Use a nonempty shortcut name or identifier.", "请使用非空快捷指令名称或标识符。", exitCode: 2)
        }
        var name = shortcut
        if let identifier = UUID(uuidString: shortcut) {
            let entries = try ShortcutListing.parse(list(timeout: timeout))
            if let selected = entries.first(where: { UUID(uuidString: $0.identifier) == identifier }) {
                guard entries.filter({ $0.name == selected.name }).count == 1,
                    !entries.contains(where: { $0.name == shortcut && UUID(uuidString: $0.identifier) != identifier })
                else {
                    throw ToolFailure(
                        "ambiguous_shortcut",
                        "Apple's editor command accepts names only; the selected identifier does not resolve to a unique name.",
                        "Apple 编辑器命令仅接受名称；所选标识符无法解析为唯一名称。",
                        hint: "Select the intended shortcut directly in Shortcuts.app.", exitCode: 6)
                }
                name = selected.name
            }
        }
        let result = try ProcessRunner.execute(
            executable: executable, arguments: ["view", "--", name], timeout: timeout)
        try requireSuccess(result)
    }

    private func requireSuccess(_ result: ProcessResult) throws {
        guard result.status == 0 else {
            let details = String(decoding: result.stderr.prefix(4096), as: UTF8.self).trimmingCharacters(
                in: .whitespacesAndNewlines)
            throw ToolFailure(
                "native_command_failed", "Apple Shortcuts command exited \(result.status). \(details)",
                "Apple 快捷指令命令退出码为 \(result.status)。\(details)",
                hint: "Check that the shortcut is installed and permissions are granted. No retry was performed.",
                exitCode: 6)
        }
    }
}
