import Foundation
import Testing

@testable import ShortcutCore

private func withExecutable(_ body: String, test: (ShortcutRunner, URL) throws -> Void) throws {
    let directory = try SafeFiles.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("fixture-runner")
    try SafeFiles.write(Data(("#!/bin/sh\n" + body).utf8), to: file, overwrite: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
    try test(ShortcutRunner(executable: file.path), directory)
}

@Test func nativeSigningRequiresSuccessfulNonemptyArtifact() throws {
    try withExecutable("while [ \"$1\" != \"--output\" ]; do shift; done\nprintf 'synthetic signed bytes' > \"$2\"\n") {
        runner, _ in
        let signed = try runner.sign(Data("source".utf8), mode: .anyone, timeout: 2)
        #expect(signed == Data("synthetic signed bytes".utf8))
    }
    try withExecutable("exit 0\n") { runner, _ in
        #expect(throws: ToolFailure.self) { try runner.sign(Data(), mode: .peopleWhoKnowMe, timeout: 2) }
    }
    try withExecutable("while [ \"$1\" != \"--output\" ]; do shift; done\n: > \"$2\"\n") { runner, _ in
        #expect(throws: ToolFailure.self) { try runner.sign(Data(), mode: .anyone, timeout: 2) }
    }
    try withExecutable("printf 'permission denied' >&2\nexit 9\n") { runner, _ in
        do {
            _ = try runner.sign(Data(), mode: .anyone, timeout: 2)
            Issue.record("Expected native error")
        } catch let failure as ToolFailure {
            #expect(failure.code == "native_command_failed")
            #expect(failure.message.contains("9"))
            #expect(failure.errorDescription == failure.message)
        }
    }
}

@Test func runtimeTestsCompareExactBytesAndNeverEmulateSuccess() throws {
    try withExecutable(
        "while [ \"$#\" -gt 0 ]; do\nif [ \"$1\" = \"--input-path\" ]; then /bin/cat \"$2\"; exit 0; fi\nshift\ndone\nprintf 'no input'\n"
    ) { runner, _ in
        var project = try ProjectTemplates.make(name: "Echo", template: "text")
        let good = try WorkflowTester.run(project, shortcut: "installed", timeout: 2, runner: runner)
        #expect(good.passed && good.executed && !good.halted)
        project.tests = [
            RuntimeTest(name: "mismatch", input: "actual", expectedOutput: "expected"),
            RuntimeTest(name: "without-input", expectedOutput: "no input"),
        ]
        let bad = try WorkflowTester.run(project, shortcut: "installed", timeout: 2, runner: runner)
        #expect(!bad.passed && bad.cases.count == 2 && !bad.halted)
        #expect(bad.cases[0].actualOutput == "actual")
        #expect(bad.cases[1].passed)
        let selected = try WorkflowTester.run(
            project, shortcut: "installed", timeout: 2, caseName: "without-input", runner: runner)
        #expect(selected.passed && selected.cases.count == 1)
        let plan = try WorkflowTester.run(project, shortcut: "installed", timeout: 2, dryRun: true, runner: runner)
        #expect(!plan.executed && !plan.passed && plan.dryRun)
        #expect(throws: ToolFailure.self) {
            try WorkflowTester.run(project, shortcut: "installed", timeout: 2, caseName: "missing", runner: runner)
        }
    }
    try withExecutable("exit 8\n") { runner, _ in
        let project = try ProjectTemplates.make(name: "Failure", template: "text")
        let report = try WorkflowTester.run(project, shortcut: "installed", timeout: 2, runner: runner)
        #expect(!report.passed && report.halted && report.cases.count == 1)
        #expect(report.cases[0].error?.code == "native_command_failed")
    }
    try withExecutable("printf '\\377'\n") { runner, _ in
        let project = try ProjectTemplates.make(name: "Binary", template: "text")
        let report = try WorkflowTester.run(project, shortcut: "installed", timeout: 2, runner: runner)
        #expect(!report.passed)
        #expect(report.cases[0].actualOutput == nil)
        #expect(report.cases[0].actualBase64 == "/w==")
    }
}

@Test func processLimitsAndInvalidArgumentsFailExplicitly() throws {
    #expect(throws: ToolFailure.self) {
        try ProcessRunner.execute(executable: "/not/a/program", arguments: [], timeout: 1)
    }
    #expect(throws: ToolFailure.self) {
        try ProcessRunner.execute(executable: "/bin/echo", arguments: [], timeout: .nan)
    }
    #expect(throws: ToolFailure.self) { try ProcessRunner.execute(executable: "/bin/echo", arguments: [], timeout: 0) }
    #expect(throws: ToolFailure.self) {
        try ProcessRunner.execute(executable: "/usr/bin/yes", arguments: [], timeout: 2, maximumOutputBytes: 32)
    }
    #expect(throws: ToolFailure.self) { try ShortcutRunner().run("-invalid", input: nil, timeout: 1) }
}

@Test func nativeTextOutputRequestsInteroperablePlainText() throws {
    try withExecutable("printf '%s\\n' \"$@\"\n") { runner, _ in
        let result = try runner.run("fixture", input: nil, timeout: 2)
        #expect(String(decoding: result.stdout, as: UTF8.self).hasSuffix("--output-type\npublic.plain-text\n"))
    }
}

@Test func fileInputConstraintsAreEnforced() throws {
    let directory = try SafeFiles.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(throws: ToolFailure.self) { try SafeFiles.read(directory) }
    #expect(throws: ToolFailure.self) { try SafeFiles.read(directory.appendingPathComponent("missing")) }
    let file = directory.appendingPathComponent("file")
    try SafeFiles.write(Data("12345".utf8), to: file, overwrite: false)
    #expect(throws: ToolFailure.self) { try SafeFiles.read(file, maximumBytes: 2) }
    #expect(throws: ToolFailure.self) {
        try SafeFiles.write(Data(), to: directory.appendingPathComponent("missing/output"), overwrite: false)
    }
}
