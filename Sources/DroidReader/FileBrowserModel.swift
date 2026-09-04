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

    /// Pulls a file from the device and saves a real copy wherever the user chooses,
    /// without opening it — the explicit "give me a copy" path a drag-and-drop would
    /// otherwise provide.
    func saveToFolder(entry: AdbDirEntry) {
        guard !entry.isDirectory, let client else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Save"
        panel.message = "Choose a folder to save \"\(entry.name)\" to"

        guard panel.runModal() == .OK, let destinationFolder = panel.url else { return }

        let remotePath = currentPath + "/" + entry.name
        Task {
            do {
                let data = try await Task.detached { try client.readFile(remotePath) }.value

                let fileManager = FileManager.default
                let baseName = (entry.name as NSString).deletingPathExtension
                let ext = (entry.name as NSString).pathExtension

                var destinationURL = destinationFolder.appendingPathComponent(entry.name)
                var counter = 1
                while fileManager.fileExists(atPath: destinationURL.path) {
                    let candidateName = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
                    destinationURL = destinationFolder.appendingPathComponent(candidateName)
                    counter += 1
                }

                try data.write(to: destinationURL)
            } catch {
                errorMessage = "\(error)"
            }
        }
    }

    /// Picks one or more local files and pushes them into the current phone directory.
    func uploadFiles() {
        guard let client else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"
        panel.message = "Choose files to upload to \(currentPath)"

        guard panel.runModal() == .OK else { return }
        let localURLs = panel.urls
        let destinationPath = currentPath
        var existingNames = Set(entries.map(\.name))

        Task {
            for localURL in localURLs {
                do {
                    let data = try Data(contentsOf: localURL)
                    let originalName = localURL.lastPathComponent
                    let baseName = (originalName as NSString).deletingPathExtension
                    let ext = (originalName as NSString).pathExtension

                    var fileName = originalName
                    var counter = 1
                    while existingNames.contains(fileName) {
                        fileName = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
                        counter += 1
                    }
                    existingNames.insert(fileName)

                    let remotePath = destinationPath + "/" + fileName
                    try await Task.detached { try client.writeFile(remotePath, data: data) }.value
                } catch {
                    errorMessage = "\(error)"
                }
            }
            await load(path: currentPath)
        }
    }
}
