import AppleArchive
import CryptoKit
import Foundation
import Security

/// Decode signed, unencrypted AEA1 archives without extracting archive-controlled paths.
/// Integrity against an embedded key is not certificate trust or approval to run a shortcut.
public enum SignedContainer {
    private static let archiveLimit = SafeFiles.maximumBytes + 1024 * 1024

    public static func decode(_ input: Data) throws -> Data {
        do {
            guard input.count <= SafeFiles.maximumBytes else { throw invalid() }
            let data = Data(input)
            guard data.count >= 12, data.starts(with: Data("AEA1".utf8)) else {
                throw invalid()
            }
            func word(_ offset: Int) -> UInt32 {
                (0..<4).reduce(0) { $0 | UInt32(data[offset + $1]) << (8 * $1) }
            }
            guard word(4) == 0 else {
                guard (1...5).contains(word(4)) else { throw invalid() }
                throw ToolFailure(
                    "encrypted_container_unsupported", "Only signed, unencrypted AEA1 profile 0 is supported.",
                    "仅支持已签名且未加密的 AEA1 profile 0。", exitCode: 4)
            }
            let authLength = Int(word(8))
            guard authLength > 0, authLength <= data.count - 12,
                let auth = try PropertyListSerialization.propertyList(
                    from: data.subdata(in: 12..<12 + authLength), format: nil) as? [String: Any]
            else { throw invalid() }
            let keyData: Data
            if let chain = auth["SigningCertificateChain"] as? [Data], let leaf = chain.first {
                guard let certificate = SecCertificateCreateWithData(nil, leaf as CFData),
                    let key = SecCertificateCopyKey(certificate),
                    let external = SecKeyCopyExternalRepresentation(key, nil)
                else { throw invalid() }
                keyData = external as Data
            } else if let publicKey = auth["SigningPublicKey"] as? Data {
                keyData = publicKey
            } else {
                throw invalid()
            }
            let key = try P256.Signing.PublicKey(x963Representation: keyData)
            let input = try temporaryStream(data)
            defer { try? input.close() }
            guard let context = ArchiveEncryptionContext(from: input) else { throw invalid() }
            try context.setSigningPublicKey(key)
            guard context.decryptAttributes() else { throw invalid() }
            guard context.rawSize >= 0, context.rawSize <= archiveLimit,
                context.compressionBlockSize > 0, context.compressionBlockSize <= archiveLimit,
                context.containerSize == data.count
            else { throw invalid() }
            guard
                let decrypted = ArchiveByteStream.decryptionStream(
                    readingFrom: input, encryptionContext: context, threadCount: 1)
            else { throw invalid() }
            defer { try? decrypted.close() }
            var archiveData = Data()
            var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                let count = try buffer.withUnsafeMutableBytes { try decrypted.read(into: $0) }
                if count == 0 { break }
                guard count > 0, count <= buffer.count, archiveData.count <= archiveLimit - count else {
                    throw invalid()
                }
                archiveData.append(contentsOf: buffer.prefix(count))
            }
            try decrypted.close()
            guard archiveData.count == context.rawSize else { throw invalid() }
            let raw = try temporaryStream(archiveData)
            defer { try? raw.close() }
            guard let archive = ArchiveStream.decodeStream(readingFrom: raw, threadCount: 1) else { throw invalid() }
            defer { try? archive.close() }
            var entry = try archive.readHeader()
            if let root = entry, root.entryType == .directory, root.entryPath?.string == "",
                root.field(forKey: .init("DAT")) == nil
            {
                entry = try archive.readHeader()
            }
            guard let header = entry, header.entryType == .regularFile,
                header.entryPath?.string == "Shortcut.wflow",
                case .blob(let blobKey, let size, _) = header.field(forKey: .init("DAT")),
                size > 0, size <= SafeFiles.maximumBytes
            else { throw invalid() }
            var payload = Data(count: Int(size))
            try payload.withUnsafeMutableBytes { try archive.readBlob(key: blobKey, into: $0) }
            guard try archive.readHeader() == nil else { throw invalid() }
            try archive.close()
            // Accept a native workflow plist only, never nested containers or project JSON.
            let plist = try PropertyListSerialization.propertyList(from: payload, options: [], format: nil)
            guard let workflow = plist as? [String: Any], workflow["WFWorkflowActions"] is [Any] else {
                throw invalid()
            }
            return payload
        } catch let failure as ToolFailure { throw failure } catch { throw invalid() }
    }

    private static func temporaryStream(_ data: Data) throws -> ArchiveByteStream {
        guard let stream = ArchiveByteStream.temporaryFileStream() else { throw invalid() }
        do {
            try data.withUnsafeBytes {
                guard try stream.write(from: $0) == $0.count else { throw invalid() }
            }
            _ = try stream.seek(toOffset: 0, relativeTo: .start)
            return stream
        } catch {
            try? stream.close()
            throw error
        }
    }

    private static func invalid() -> ToolFailure {
        ToolFailure(
            "invalid_signed_container",
            "Signed container is malformed, corrupt, oversized, or has an unsupported archive layout.",
            "已签名容器格式错误、损坏、过大或包含不支持的归档结构。",
            hint:
                "Expected an intact signed AEA1 archive containing one Shortcut.wflow. Certificate trust and shortcut safety are not established.",
            exitCode: 4)
    }
}
