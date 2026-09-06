import Foundation

enum AdbError: Error, CustomStringConvertible {
    case connectionFailed(String)
    case connectionClosed
    case serverError(String)
    case protocolError(String)

    var description: String {
        switch self {
        case .connectionFailed(let m): return "connection failed: \(m)"
        case .connectionClosed: return "connection closed unexpectedly"
        case .serverError(let m): return "adb server error: \(m)"
        case .protocolError(let m): return "protocol error: \(m)"
        }
    }
}

/// A single TCP connection to the adb server (127.0.0.1:5037).
///
/// adb speaks two framings on the same connection, one after the other:
///  - "host" framing, used for the initial handshake: a 4-byte ASCII hex length,
///    followed by that many message bytes.
///  - "sync" framing, entered only after sending "sync:" — raw 4-byte ASCII
///    tokens (LIST/DENT/DONE/DATA/...) and little-endian 32-bit integers, no hex.
///
/// This mirrors goadb (github.com/zach-klippenstein/goadb), a Go implementation
/// of this same protocol proven working against a real device earlier tonight.
final class AdbConnection {
    private let input: InputStream
    private let output: OutputStream

    init() throws {
        var inputStream: InputStream?
        var outputStream: OutputStream?
        Stream.getStreamsToHost(withName: "127.0.0.1", port: 5037, inputStream: &inputStream, outputStream: &outputStream)
        guard let input = inputStream, let output = outputStream else {
            throw AdbError.connectionFailed("could not create streams to the adb server")
        }
        input.open()
        output.open()
        self.input = input
        self.output = output
    }

    func close() {
        input.close()
        output.close()
    }

    // MARK: - Raw byte I/O

    private func writeAll(_ bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let remaining = bytes.count - offset
            let n = bytes.withUnsafeBufferPointer { buf -> Int in
                output.write(buf.baseAddress! + offset, maxLength: remaining)
            }
            if n <= 0 {
                throw AdbError.connectionFailed(output.streamError?.localizedDescription ?? "write failed")
            }
            offset += n
        }
    }

    private func readExact(_ count: Int) throws -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(count)
        var buffer = [UInt8](repeating: 0, count: min(count, 4096))
        while result.count < count {
            let toRead = min(buffer.count, count - result.count)
            let n = input.read(&buffer, maxLength: toRead)
            if n < 0 {
                throw AdbError.connectionFailed(input.streamError?.localizedDescription ?? "read failed")
            }
            if n == 0 {
                throw AdbError.connectionClosed
            }
            result.append(contentsOf: buffer[0..<n])
        }
        return result
    }

    // MARK: - Host framing (hex-length-prefixed, used only before "sync:")

    func sendHostMessage(_ message: String) throws {
        let payload = Array(message.utf8)
        let header = Array(String(format: "%04x", payload.count).utf8)
        try writeAll(header + payload)
    }

    /// Reads the 4-byte OKAY/FAIL status that follows every host request.
    func readHostStatus() throws {
        let status = String(decoding: try readExact(4), as: UTF8.self)
        if status == "FAIL" {
            throw AdbError.serverError(try readHostMessageText())
        } else if status != "OKAY" {
            throw AdbError.protocolError("expected OKAY/FAIL, got '\(status)'")
        }
    }

    /// Reads a second hex-length-prefixed payload after a status (e.g. host:devices' device list).
    func readHostMessageText() throws -> String {
        let lengthHex = String(decoding: try readExact(4), as: UTF8.self)
        guard let length = Int(lengthHex, radix: 16) else {
            throw AdbError.protocolError("invalid hex length '\(lengthHex)'")
        }
        return String(decoding: try readExact(length), as: UTF8.self)
    }

    // MARK: - Sync framing (raw tokens + little-endian ints, used after "sync:")

    /// Sends a 4-character command token followed by a length-prefixed path, e.g. "LIST" + path.
    func sendSyncRequest(_ token: String, path: String) throws {
        try sendSyncData(token, bytes: Array(path.utf8))
    }

    /// Reads a 4-byte token. If it's "FAIL", reads the length-prefixed error and throws;
    /// otherwise returns the raw token (DENT/DONE/DATA/STAT/...) for the caller to switch on.
    func readSyncToken() throws -> String {
        let token = String(decoding: try readExact(4), as: UTF8.self)
        if token == "FAIL" {
            throw AdbError.serverError(try readSyncString())
        }
        return token
    }

    func readInt32LE() throws -> Int32 {
        let bytes = try readExact(4)
        let raw = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        return Int32(littleEndian: raw)
    }

    func readSyncString() throws -> String {
        let length = try readInt32LE()
        return String(decoding: try readExact(Int(length)), as: UTF8.self)
    }

    func readSyncBytes() throws -> [UInt8] {
        let length = try readInt32LE()
        return try readExact(Int(length))
    }

    /// Sends a 4-character token followed by a length-prefixed raw byte chunk, e.g. "DATA" + bytes.
    /// Unlike `sendSyncRequest`, this takes raw bytes rather than a UTF-8 path string, since file
    /// contents aren't necessarily valid text.
    func sendSyncData(_ token: String, bytes: [UInt8]) throws {
        precondition(token.utf8.count == 4, "sync token must be 4 bytes")
        var payload = Array(token.utf8)
        payload += withUnsafeBytes(of: Int32(bytes.count).littleEndian) { Array($0) }
        payload += bytes
        try writeAll(payload)
    }

    /// Sends the "DONE" token that terminates a SEND, followed by a raw (not length-prefixed)
    /// little-endian mtime — the one place the sync protocol's usual token+length+payload shape
    /// doesn't apply, per goadb's syncFileWriter.Close().
    func sendSyncDone(mtime: Int32) throws {
        var payload = Array("DONE".utf8)
        payload += withUnsafeBytes(of: mtime.littleEndian) { Array($0) }
        try writeAll(payload)
    }

    // MARK: - Shell service (used for operations sync framing has no op for, e.g. delete)

    /// Reads until the peer closes the connection — how a "shell:" command's combined
    /// stdout/stderr arrives, with no length prefix and no further framing.
    func readAllRemainingText() throws -> String {
        var data = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = input.read(&buffer, maxLength: buffer.count)
            if n < 0 {
                throw AdbError.connectionFailed(input.streamError?.localizedDescription ?? "read failed")
            }
            if n == 0 { break }
            data.append(contentsOf: buffer[0..<n])
        }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - ADB file mode bits (from Android's bionic bits/stat.h; mirrors goadb's ParseFileModeFromAdb)

private let sIfDir: UInt32 = 0o040000

private func adbModeIsDirectory(_ mode: UInt32) -> Bool { mode & sIfDir == sIfDir }

struct AdbDirEntry: Identifiable {
    var id: String { name }
    let name: String
    let isDirectory: Bool
    let size: Int32
    let modified: Date
}

/// High-level, read-only ADB client for one device. Each call opens its own
/// connection and closes it when done — mirroring goadb/the real adb client,
/// which does not keep a sync-mode connection open across multiple commands.
struct AdbClient {
    let serial: String

    static func listDeviceSerials() throws -> [String] {
        let conn = try AdbConnection()
        defer { conn.close() }
        try conn.sendHostMessage("host:devices")
        try conn.readHostStatus()
        let text = try conn.readHostMessageText()
        return text.split(separator: "\n").compactMap { line in
            line.split(separator: "\t").first.map(String.init)
        }
    }

    private func openSyncConnection() throws -> AdbConnection {
        let conn = try AdbConnection()
        do {
            try conn.sendHostMessage("host:transport:\(serial)")
            try conn.readHostStatus()
            try conn.sendHostMessage("sync:")
            try conn.readHostStatus()
        } catch {
            conn.close()
            throw error
        }
        return conn
    }

    func listDirectory(_ path: String) throws -> [AdbDirEntry] {
        let conn = try openSyncConnection()
        defer { conn.close() }

        try conn.sendSyncRequest("LIST", path: path)
        var entries: [AdbDirEntry] = []
        while true {
            let token = try conn.readSyncToken()
            if token == "DONE" { break }
            guard token == "DENT" else {
                throw AdbError.protocolError("expected DENT or DONE, got '\(token)'")
            }
            let modeRaw = UInt32(bitPattern: try conn.readInt32LE())
            let size = try conn.readInt32LE()
            let mtimeRaw = try conn.readInt32LE()
            let name = try conn.readSyncString()
            if name == "." || name == ".." { continue }
            entries.append(AdbDirEntry(
                name: name,
                isDirectory: adbModeIsDirectory(modeRaw),
                size: size,
                modified: Date(timeIntervalSince1970: TimeInterval(mtimeRaw))
            ))
        }
        return entries
    }

    func readFile(_ path: String) throws -> Data {
        let conn = try openSyncConnection()
        defer { conn.close() }

        try conn.sendSyncRequest("RECV", path: path)
        var data = Data()
        while true {
            let token = try conn.readSyncToken()
            if token == "DONE" { break }
            guard token == "DATA" else {
                throw AdbError.protocolError("expected DATA or DONE, got '\(token)'")
            }
            data.append(contentsOf: try conn.readSyncBytes())
        }
        return data
    }

    /// Pushes local data to a path on the device, creating/overwriting the file there.
    /// Mirrors readFile's shape but in reverse: SEND + "path,mode" instead of RECV + path,
    /// then DATA chunks (max 64KB each, the sync protocol's documented limit) instead of
    /// reading them, then DONE + mtime to close out the transfer.
    func writeFile(_ path: String, data: Data) throws {
        let conn = try openSyncConnection()
        defer { conn.close() }

        let mode = 0o644
        try conn.sendSyncRequest("SEND", path: "\(path),\(mode)")

        let bytes = [UInt8](data)
        let maxChunkSize = 64 * 1024
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + maxChunkSize, bytes.count)
            try conn.sendSyncData("DATA", bytes: Array(bytes[offset..<end]))
            offset = end
        }

        try conn.sendSyncDone(mtime: Int32(Date().timeIntervalSince1970))

        let status = try conn.readSyncToken()
        guard status == "OKAY" else {
            throw AdbError.protocolError("expected OKAY after SEND, got '\(status)'")
        }
    }

    /// Checks whether `path` is actually listable, to disambiguate an empty `LIST` result:
    /// adbd's sync service returns DONE with zero entries both when a directory is
    /// genuinely empty and when opendir() failed (e.g. permission denied). `ls`'s own
    /// exit status tells the two apart — its output doesn't, since `ls` also prints
    /// plenty of output on success whenever the directory has real contents.
    func checkDirectoryAccess(_ path: String) throws {
        let (exitCode, output) = try runShellCommand("ls \(shellQuoted(path))")
        guard exitCode == 0 else {
            throw AdbError.serverError(output.isEmpty ? "cannot access \(path)" : output)
        }
    }

    /// Deletes a file or directory on the device (`adb shell rm -f`/`rm -rf`) — the sync
    /// protocol used by list/read/write has no delete operation.
    func delete(_ path: String, recursive: Bool) throws {
        try runQuietShellCommand("rm \(recursive ? "-rf" : "-f") \(shellQuoted(path))")
    }

    /// Creates a directory on the device (`adb shell mkdir <path>`).
    func makeDirectory(_ path: String) throws {
        try runQuietShellCommand("mkdir \(shellQuoted(path))")
    }

    /// Renames or moves a file/directory on the device (`adb shell mv -n <from> <to>`).
    /// `-n` refuses to clobber an existing file at the destination rather than overwriting it.
    func rename(_ path: String, to newPath: String) throws {
        try runQuietShellCommand("mv -n \(shellQuoted(path)) \(shellQuoted(newPath))")
    }

    /// Runs a shell command that's expected to be silent and exit 0 on success — the
    /// shape shared by delete, mkdir, and rename.
    private func runQuietShellCommand(_ command: String) throws {
        let (exitCode, output) = try runShellCommand(command)
        guard exitCode == 0, output.isEmpty else {
            throw AdbError.serverError(output.isEmpty ? "command failed (exit \(exitCode))" : output)
        }
    }

    /// Runs one shell command on the device and returns its exit status alongside the
    /// combined stdout/stderr text. The exit status doesn't come from the shell service
    /// itself (it exposes no framing for one) — it's smuggled through by appending a
    /// marker-prefixed `echo $?` and parsing it back off the last line.
    private func runShellCommand(_ command: String) throws -> (exitCode: Int32, output: String) {
        let conn = try AdbConnection()
        defer { conn.close() }

        try conn.sendHostMessage("host:transport:\(serial)")
        try conn.readHostStatus()
        try conn.sendHostMessage("shell:\(command); echo \(Self.exitMarker)$?")
        try conn.readHostStatus()

        var lines = try conn.readAllRemainingText()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
        guard let last = lines.popLast(), last.hasPrefix(Self.exitMarker),
              let exitCode = Int32(last.dropFirst(Self.exitMarker.count)) else {
            throw AdbError.protocolError("missing exit status for shell command")
        }
        return (exitCode, lines.joined(separator: "\n"))
    }

    private static let exitMarker = "__diroid_exit__:"

    private func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
