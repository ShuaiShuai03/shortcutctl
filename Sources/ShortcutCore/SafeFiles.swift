import Darwin
import Foundation

public enum SafeFiles {
    public static let maximumBytes = 16 * 1024 * 1024

    public static func read(_ url: URL, maximumBytes: Int = maximumBytes) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw ioFailure("read_failed", "Cannot open input", url) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw ToolFailure(
                "not_regular_file",
                "Input must be a regular file, not a directory, symbolic link, or stream: \(url.path)",
                "输入必须是普通文件，不能是目录、符号链接或数据流。", exitCode: 5)
        }
        guard info.st_size <= maximumBytes else { throw sizeFailure(maximumBytes) }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw ioFailure("read_failed", "Cannot read input", url)
            }
            guard result.count + count <= maximumBytes else { throw sizeFailure(maximumBytes) }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }

    public static func checkDestination(_ url: URL, overwrite: Bool) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFREG else {
                throw ToolFailure(
                    "unsafe_destination",
                    "Destination must not be a symbolic link, directory, or special file: \(url.path)",
                    "目标不能是符号链接、目录或特殊文件。", exitCode: 5)
            }
            guard overwrite else {
                throw ToolFailure(
                    "output_exists", "Output already exists: \(url.path)", "输出文件已存在：\(url.path)",
                    hint: "Choose another path or explicitly pass --force to replace this file.", exitCode: 5)
            }
        } else if errno != ENOENT {
            throw ioFailure("write_failed", "Cannot inspect destination", url)
        }
        var parent = stat()
        guard stat(url.deletingLastPathComponent().path, &parent) == 0, parent.st_mode & S_IFMT == S_IFDIR else {
            throw ToolFailure(
                "missing_parent", "Output parent directory does not exist: \(url.deletingLastPathComponent().path)",
                "输出的父目录不存在。", exitCode: 5)
        }
    }

    public static func write(_ data: Data, to url: URL, overwrite: Bool) throws {
        try checkDestination(url, overwrite: overwrite)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".shortcutctl-\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ioFailure("write_failed", "Cannot create output", url) }
        defer {
            close(fd)
            unlink(temporary.path)
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ioFailure("write_failed", "Cannot write output", url) }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw ioFailure("write_failed", "Cannot flush output", url) }
        try checkDestination(url, overwrite: overwrite)
        if overwrite {
            guard rename(temporary.path, url.path) == 0 else {
                throw ioFailure("write_failed", "Cannot replace output", url)
            }
        } else {
            guard link(temporary.path, url.path) == 0 else {
                if errno == EEXIST {
                    throw ToolFailure(
                        "output_exists", "Output appeared during write: \(url.path)", "写入期间目标文件已存在。", exitCode: 5)
                }
                throw ioFailure("write_failed", "Cannot publish output", url)
            }
        }
    }

    public static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "shortcutctl-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            return url
        } catch {
            throw ToolFailure(
                "temporary_directory_failed", "Cannot create temporary directory: \(error.localizedDescription)",
                "无法创建临时目录。", exitCode: 5)
        }
    }

    private static func ioFailure(_ code: String, _ message: String, _ url: URL) -> ToolFailure {
        ToolFailure(
            code, "\(message): \(url.path) (\(String(cString: strerror(errno))))", "文件操作失败：\(url.path)", exitCode: 5)
    }

    private static func sizeFailure(_ bytes: Int) -> ToolFailure {
        ToolFailure("file_too_large", "File exceeds the \(bytes)-byte limit.", "文件超过 \(bytes) 字节限制。", exitCode: 5)
    }
}
