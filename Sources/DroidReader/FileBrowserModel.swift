import Foundation
import AppKit

@MainActor
final class FileBrowserModel: ObservableObject {
    static let rootPath = "/sdcard"

    @Published private(set) var currentPath: String = rootPath
    @Published private(set) var entries: [AdbDirEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var client: AdbClient?

    func connectAndLoadRoot() {
        Task {
            do {
                let serials = try await Task.detached { try AdbClient.listDeviceSerials() }.value
                guard let serial = serials.first else {
                    errorMessage = "No device attached. Plug in your phone with USB debugging enabled."
                    return
                }
                client = AdbClient(serial: serial)
                await load(path: Self.rootPath)
            } catch {
                errorMessage = "\(error)"
            }
        }
    }

    func load(path: String) async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await Task.detached { try client.listDirectory(path) }.value
            currentPath = path
            entries = fetched.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }

    func navigateUp() {
        guard currentPath != Self.rootPath else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        Task { await load(path: parent.isEmpty ? Self.rootPath : parent) }
    }

    func open(entry: AdbDirEntry) {
        let fullPath = currentPath + "/" + entry.name
        if entry.isDirectory {
            Task { await load(path: fullPath) }
            return
        }
        guard let client else { return }
        Task {
            do {
                try await downloadAndOpen(client: client, remotePath: fullPath, fileName: entry.name)
            } catch {
                errorMessage = "\(error)"
            }
        }
    }

    /// Pulls a file from the device and opens it with the user's default app for its type,
    /// mirroring what Android Studio's Device File Explorer does on double-click.
    private func downloadAndOpen(client: AdbClient, remotePath: String, fileName: String) async throws {
        let data = try await Task.detached { try client.readFile(remotePath) }.value

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(fileName)
        try data.write(to: fileURL)

        NSWorkspace.shared.open(fileURL)
    }
}
