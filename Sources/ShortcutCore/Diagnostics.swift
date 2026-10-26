import Foundation

public struct ToolFailure: Error, LocalizedError, Codable, Sendable {
    public let code: String
    public let message: String
    public let messageZH: String
    public let hint: String?
    public let exitCode: Int32

    public init(_ code: String, _ message: String, _ messageZH: String, hint: String? = nil, exitCode: Int32 = 1) {
        self.code = code
        self.message = message
        self.messageZH = messageZH
        self.hint = hint
        self.exitCode = exitCode
    }

    public var errorDescription: String? { message }
}

public enum Severity: String, Codable, Sendable {
    case error, warning
}

public struct Diagnostic: Codable, Equatable, Sendable {
    public let severity: Severity
    public let code: String
    public let path: String
    public let message: String
    public let messageZH: String

    public init(_ severity: Severity, _ code: String, path: String, _ message: String, _ messageZH: String) {
        self.severity = severity
        self.code = code
        self.path = path
        self.message = message
        self.messageZH = messageZH
    }
}
