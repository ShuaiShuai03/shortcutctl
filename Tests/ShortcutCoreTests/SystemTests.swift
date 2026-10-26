import Foundation
import Testing

@testable import ShortcutCore

@Test func safeWritesNeverOverwriteImplicitly() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("output")
    try SafeFiles.write(Data("first".utf8), to: file, overwrite: false)
    #expect(throws: ToolFailure.self) { try SafeFiles.write(Data("second".utf8), to: file, overwrite: false) }
    #expect(try SafeFiles.read(file) == Data("first".utf8))
    try SafeFiles.write(Data("second".utf8), to: file, overwrite: true)
    #expect(try SafeFiles.read(file) == Data("second".utf8))
    let symlink = directory.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: file)
    #expect(throws: ToolFailure.self) { try SafeFiles.write(Data(), to: symlink, overwrite: true) }
}

@Test func processCapturesBothStreamsAndStatus() throws {
    let result = try ProcessRunner.execute(
        executable: "/bin/sh", arguments: ["-c", "printf 'output'; printf 'diagnostic' >&2; exit 7"], timeout: 2)
    #expect(result.status == 7)
    #expect(String(decoding: result.stdout, as: UTF8.self) == "output")
    #expect(String(decoding: result.stderr, as: UTF8.self) == "diagnostic")
}

@Test func processTimeoutIsBounded() throws {
    let start = Date()
    #expect(throws: ToolFailure.self) {
        try ProcessRunner.execute(executable: "/bin/sleep", arguments: ["10"], timeout: 0.1)
    }
    #expect(Date().timeIntervalSince(start) < 3)
}

@Test func processArgumentsAreNotShellExpanded() throws {
    let literal = "$(whoami); * ' \" 中文"
    let result = try ProcessRunner.execute(executable: "/usr/bin/printf", arguments: ["%s", literal], timeout: 2)
    #expect(String(decoding: result.stdout, as: UTF8.self) == literal)
}
