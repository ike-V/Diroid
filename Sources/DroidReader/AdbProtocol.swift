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

    init(host: String = "127.0.0.1", port: Int = 5037) throws {
        var inputStream: InputStream?
        var outputStream: OutputStream?
        Stream.getStreamsToHost(withName: host, port: port, inputStream: &inputStream, outputStream: &outputStream)
        guard let input = inputStream, let output = outputStream else {
            throw AdbError.connectionFailed("could not create streams to \(host):\(port)")
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
        precondition(token.utf8.count == 4, "sync token must be 4 bytes")
        let pathBytes = Array(path.utf8)
        var payload = Array(token.utf8)
        payload += withUnsafeBytes(of: Int32(pathBytes.count).littleEndian) { Array($0) }
        payload += pathBytes
        try writeAll(payload)
    }

    /// Reads a 4-byte token. If it's "FAIL", reads the length-prefixed error and throws;
    /// otherwise returns the raw token (DENT/DONE/DATA/STAT/...) for the caller to switch on.
    func readSyncToken() throws -> String {
        let token = String(decoding: try readExact(4), as: UTF8.self)
        if token == "FAIL" {
            let length = try readInt32LE()
            throw AdbError.serverError(String(decoding: try readExact(Int(length)), as: UTF8.self))
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
}

// MARK: - ADB file mode bits (from Android's bionic bits/stat.h; mirrors goadb's ParseFileModeFromAdb)

private let sIfDir: UInt32 = 0o040000
private let sIfSymlink: UInt32 = 0o120000

private func adbModeIsDirectory(_ mode: UInt32) -> Bool { mode & sIfDir == sIfDir }
private func adbModeIsSymlink(_ mode: UInt32) -> Bool { mode & sIfSymlink == sIfSymlink }

struct AdbDirEntry: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let isDirectory: Bool
    let isSymlink: Bool
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
                isSymlink: adbModeIsSymlink(modeRaw),
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
}
