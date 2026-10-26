import AppleArchive
import CryptoKit
import Foundation
import Testing

@testable import ShortcutCore

@Test func syntheticSignedContainerPreservesWorkflow() throws {
    let project = WorkflowProject(
        name: "Signed",
        workflow: .dictionary([
            "WFWorkflowActions": .array([]), "custom": .data(Data([0, 255])),
            "date": .date(Date(timeIntervalSinceReferenceDate: 123.25)), "unicode": .string("中文 🧪"),
        ]))
    let signed = try signedFixture(WorkflowCompiler.compile(project, format: .binary), rootDirectory: true)
    #expect(try WorkflowCodec.decodeWorkflow(signed, name: project.name).workflow == project.workflow)
    let prefixed = Data(repeating: 0, count: 16) + signed
    #expect(try SignedContainer.decode(prefixed.dropFirst(16)) == WorkflowCompiler.compile(project, format: .binary))
    #expect(throws: ToolFailure.self) { try SignedContainer.decode(signed + Data([0])) }
    for count in [0, 4, 11, 12, signed.count / 2, signed.count - 1] {
        #expect(throws: ToolFailure.self) { try SignedContainer.decode(Data(signed.prefix(count))) }
    }
    var corrupt = signed
    corrupt[corrupt.count - 12] ^= 0xFF
    #expect(throws: ToolFailure.self) { try SignedContainer.decode(corrupt) }
}

@Test func signedContainerRejectsUnexpectedArchiveEntries() throws {
    let payload = try WorkflowCompiler.compile(ProjectTemplates.make(name: "Test", template: "text"), format: .binary)
    for path in ["../Shortcut.wflow", "/Shortcut.wflow", "Other.wflow"] {
        let signed = try signedFixture(payload, path: path)
        #expect(throws: ToolFailure.self) { try SignedContainer.decode(signed) }
    }
    let duplicate = try signedFixture(payload, duplicate: true)
    #expect(throws: ToolFailure.self) { try SignedContainer.decode(duplicate) }
    let nonWorkflow = try signedFixture(Data("{}".utf8))
    #expect(throws: ToolFailure.self) { try SignedContainer.decode(nonWorkflow) }
    var unsupported = try signedFixture(payload)
    unsupported[4] = 1
    do {
        _ = try SignedContainer.decode(unsupported)
        Issue.record("Expected unsupported profile")
    } catch let error as ToolFailure { #expect(error.code == "encrypted_container_unsupported") }
}

@Test func signedContainerHandlesCertificateKeysAndRejectsMalformedAuth() throws {
    let payload = try WorkflowCompiler.compile(
        ProjectTemplates.make(name: "Certificate", template: "text"), format: .binary)
    #expect(try SignedContainer.decode(signedFixture(payload, certificate: true)) == payload)
    for auth: [String: Any] in [
        [:], ["SigningPublicKey": Data([1])], ["SigningPublicKey": "wrong type"],
        ["SigningCertificateChain": [Data([1])]],
    ] {
        let signed = try signedFixture(payload, auth: auth)
        #expect(throws: ToolFailure.self) { try SignedContainer.decode(signed) }
    }
    var signed = try signedFixture(payload)
    let authLength = (0..<4).reduce(0) { $0 | Int(signed[8 + $1]) << (8 * $1) }
    signed[12 + authLength + 24] ^= 0xFF
    #expect(throws: ToolFailure.self) { try SignedContainer.decode(signed) }
}

@Test func signedContainerBoundsDecompressionAndRejectsLinks() throws {
    let payload = try WorkflowCompiler.compile(ProjectTemplates.make(name: "Limits", template: "text"), format: .binary)
    let link = try signedFixture(payload, entryType: .link)
    let empty = try signedFixture(Data())
    let largeBlock = try signedFixture(payload, blockSize: 32 * 1024 * 1024)
    let oversized = try signedFixture(Data(repeating: 65, count: 18 * 1024 * 1024))
    for signed in [link, empty, largeBlock, oversized] {
        #expect(throws: ToolFailure.self) { try SignedContainer.decode(signed) }
    }
}

private func ephemeralCertificate(_ key: P256.Signing.PrivateKey) throws -> Data {
    let directory = try SafeFiles.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let pem = directory.appendingPathComponent("synthetic-key.pem")
    let certificate = directory.appendingPathComponent("synthetic-certificate.der")
    try SafeFiles.write(Data(key.pemRepresentation.utf8), to: pem, overwrite: false)
    let result = try ProcessRunner.execute(
        executable: "/usr/bin/openssl",
        arguments: [
            "req", "-new", "-x509", "-key", pem.path, "-outform", "DER", "-out", certificate.path,
            "-days", "1", "-subj", "/CN=shortcutctl-synthetic-test",
        ], timeout: 5)
    #expect(result.status == 0)
    return try SafeFiles.read(certificate)
}

private func signedFixture(
    _ payload: Data, path: String = "Shortcut.wflow", duplicate: Bool = false, rootDirectory: Bool = false,
    entryType: ArchiveHeader.EntryType = .regularFile, blockSize: Int = 1024 * 1024,
    auth: [String: Any]? = nil, certificate: Bool = false
) throws -> Data {
    let destination = try #require(ArchiveByteStream.temporaryFileStream())
    defer { try? destination.close() }
    let key = P256.Signing.PrivateKey()
    let context = ArchiveEncryptionContext(
        profile: .hkdf_sha256_hmac__none__ecdsa_p256, compressionAlgorithm: .zlib, compressionBlockSize: blockSize)
    try context.setSigningPrivateKey(key)
    let authFields: [String: Any] =
        try auth
        ?? (certificate
            ? ["SigningCertificateChain": [ephemeralCertificate(key)]]
            : ["SigningPublicKey": key.publicKey.x963Representation])
    context.authData = try PropertyListSerialization.data(fromPropertyList: authFields, format: .binary, options: 0)
    let encrypted = try #require(
        ArchiveByteStream.encryptionStream(writingTo: destination, encryptionContext: context, threadCount: 1))
    let archive = try #require(ArchiveStream.encodeStream(writingTo: encrypted, threadCount: 1))
    if rootDirectory {
        let header = ArchiveHeader()
        header.append(.uint(key: .init("TYP"), value: UInt64(ArchiveHeader.EntryType.directory.rawValue)))
        header.append(.string(key: .init("PAT"), value: ""))
        try archive.writeHeader(header)
    }
    for _ in 0..<(duplicate ? 2 : 1) {
        let header = ArchiveHeader()
        header.append(.uint(key: .init("TYP"), value: UInt64(entryType.rawValue)))
        header.append(.string(key: .init("PAT"), value: path))
        header.append(.blob(key: .init("DAT"), size: UInt64(payload.count)))
        try archive.writeHeader(header)
        try payload.withUnsafeBytes { try archive.writeBlob(key: .init("DAT"), from: $0) }
    }
    try archive.close()
    try encrypted.close()
    _ = try destination.seek(toOffset: 0, relativeTo: .start)
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 65536)
    while true {
        let count = try buffer.withUnsafeMutableBytes { try destination.read(into: $0) }
        if count == 0 { return result }
        result.append(contentsOf: buffer.prefix(count))
    }
}
