import Foundation

public struct TestCaseResult: Codable, Sendable {
    public let name: String
    public let passed: Bool
    public let expectedOutput: String
    public let actualOutput: String?
    public let actualBase64: String?
    public let error: ToolFailure?
}

public struct TestReport: Codable, Sendable {
    public let shortcut: String
    public let executed: Bool
    public let dryRun: Bool
    public let plannedCount: Int
    public let passed: Bool
    public let halted: Bool
    public let cases: [TestCaseResult]
}

public enum WorkflowTester {
    public static func run(
        _ project: WorkflowProject, shortcut: String, timeout: TimeInterval, caseName: String? = nil,
        dryRun: Bool = false, runner: ShortcutRunner = ShortcutRunner()
    ) throws -> TestReport {
        _ = try WorkflowCompiler.compile(project, format: .binary)
        let selected = project.tests.filter { caseName == nil || $0.name == caseName }
        guard !selected.isEmpty else {
            throw ToolFailure(
                "no_test_cases",
                "No matching runtime test cases. Add tests with name, input (optional), and expectedOutput.",
                "没有匹配的运行测试用例。请添加 name、input（可选）和 expectedOutput。", exitCode: 3)
        }
        if dryRun {
            return TestReport(
                shortcut: shortcut, executed: false, dryRun: true, plannedCount: selected.count, passed: false,
                halted: false,
                cases: selected.map {
                    TestCaseResult(
                        name: $0.name, passed: false, expectedOutput: $0.expectedOutput, actualOutput: nil,
                        actualBase64: nil, error: nil)
                })
        }
        let directory = try SafeFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var results: [TestCaseResult] = []
        var halted = false
        for (index, test) in selected.enumerated() {
            let input: URL?
            if let text = test.input {
                let file = directory.appendingPathComponent("input-\(index).txt")
                try SafeFiles.write(Data(text.utf8), to: file, overwrite: false)
                input = file
            } else {
                input = nil
            }
            do {
                let result = try runner.run(shortcut, input: input, timeout: timeout)
                let text = String(data: result.stdout, encoding: .utf8)
                results.append(
                    TestCaseResult(
                        name: test.name, passed: result.stdout == Data(test.expectedOutput.utf8),
                        expectedOutput: test.expectedOutput, actualOutput: text,
                        actualBase64: text == nil ? result.stdout.base64EncodedString() : nil, error: nil))
            } catch let failure as ToolFailure {
                results.append(
                    TestCaseResult(
                        name: test.name, passed: false, expectedOutput: test.expectedOutput, actualOutput: nil,
                        actualBase64: nil, error: failure))
                halted = true
                break
            }
        }
        return TestReport(
            shortcut: shortcut, executed: true, dryRun: false, plannedCount: selected.count,
            passed: !halted && results.allSatisfy(\.passed), halted: halted, cases: results)
    }
}
