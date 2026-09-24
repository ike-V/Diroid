import Foundation
import AppKit

/// Why nothing can be listed, shown centered in place of the file list.
struct ConnectionProblem {
    let title: String
    let detail: String
}

@MainActor
final class FileBrowserModel: ObservableObject {
    /// Where `/sdcard` resolves to.
    static let rootPath = "/storage/emulated/0"

    @Published private(set) var currentPath: String = rootPath
    @Published private(set) var entries: [AdbDirEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var connectionProblem: ConnectionProblem?

    private var client: AdbClient?

    /// Dismisses the error without touching `currentPath` or `entries`.
    func clearError() {
        errorMessage = nil
    }

    /// Joins `base` (default `currentPath`) and `name`, avoiding "//" when `base` is "/".
    private func childPath(_ name: String, in base: String? = nil) -> String {
        let base = base ?? currentPath
        return base == "/" ? "/\(name)" : "\(base)/\(name)"
    }

    /// Runs `operation`, reporting any error via `errorMessage`.
    private func catching(_ operation: () async throws -> Void) async {
        do {
            try await operation()
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Runs a device-mutating `operation` off the main actor, then reloads.
    private func mutate(_ operation: @escaping @Sendable () throws -> Void) async {
        await catching {
            try await Task.detached(operation: operation).value
            await load(path: currentPath)
        }
    }

    func connectAndLoadRoot() {
        Task {
            connectionProblem = nil
            do {
                let serials = try await Task.detached { try AdbClient.listDeviceSerials() }.value
                guard let serial = serials.first else {
                    connectionProblem = ConnectionProblem(
                        title: "No device found",
                        detail: "Plug in your phone with USB debugging enabled, then press refresh.")
                    return
                }
                client = AdbClient(serial: serial)
                await load(path: Self.rootPath)
            } catch AdbError.connectionFailed(_) {
                connectionProblem = ConnectionProblem(
                    title: "The adb server isn't running",
                    detail: "Run `adb start-server` in Terminal, then press refresh.")
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
            if fetched.isEmpty {
                // Empty may mean a swallowed permission error; check.
                try await Task.detached { try client.checkDirectoryAccess(path) }.value
            }
            currentPath = path
            entries = fetched.sorted(by: nameAscending)
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }

    func open(entry: AdbDirEntry) {
        let fullPath = childPath(entry.name)
        if entry.isDirectory {
            Task { await load(path: fullPath) }
            return
        }
        guard let client else { return }
        Task {
            await catching {
                try await downloadAndOpen(client: client, remotePath: fullPath, fileName: entry.name)
            }
        }
    }

    /// Pulls a file to a temp directory and opens it with its default app.
    private func downloadAndOpen(client: AdbClient, remotePath: String, fileName: String) async throws {
        let data = try await Task.detached { try client.readFile(remotePath) }.value

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(fileName)
        try data.write(to: fileURL)

        NSWorkspace.shared.open(fileURL)
    }

    /// Pulls a file into a user-chosen folder, suffixing the name on collision.
    func saveToFolder(entry: AdbDirEntry) {
        guard !entry.isDirectory, let client else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Save"
        panel.message = "Choose a folder to save \"\(entry.name)\" to"

        guard panel.runModal() == .OK, let destinationFolder = panel.url else { return }

        let remotePath = childPath(entry.name)
        Task {
            await catching {
                let data = try await Task.detached { try client.readFile(remotePath) }.value

                let fileManager = FileManager.default
                let fileName = Self.uniqueName(for: entry.name) { candidate in
                    fileManager.fileExists(atPath: destinationFolder.appendingPathComponent(candidate).path)
                }

                try data.write(to: destinationFolder.appendingPathComponent(fileName))
            }
        }
    }

    /// Deletes after confirmation; folders are deleted recursively.
    func delete(entry: AdbDirEntry) {
        guard let client else { return }

        let alert = NSAlert()
        if entry.isDirectory {
            alert.messageText = "Delete \"\(entry.name)\" and everything inside it?"
            alert.informativeText = "This permanently deletes the folder and all its contents from your phone. This can't be undone."
        } else {
            alert.messageText = "Delete \"\(entry.name)\"?"
            alert.informativeText = "This permanently deletes the file from your phone. This can't be undone."
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let remotePath = childPath(entry.name)
        let isDirectory = entry.isDirectory
        Task {
            await mutate {
                try client.delete(remotePath, recursive: isDirectory)
            }
        }
    }

    /// Prompts for a new name and renames the entry.
    func rename(entry: AdbDirEntry) {
        guard let client else { return }
        guard let newName = Self.promptForText(title: "Rename \"\(entry.name)\"", actionTitle: "Rename", defaultValue: entry.name),
              newName != entry.name else { return }

        let oldPath = childPath(entry.name)
        let newPath = childPath(newName)
        Task {
            await mutate {
                try client.rename(oldPath, to: newPath)
            }
        }
    }

    /// Prompts for a name and creates a new folder in the current directory.
    func makeDirectory() {
        guard let client else { return }

        let existingNames = Set(entries.map(\.name))
        let defaultName = Self.uniqueName(for: "New Folder") { existingNames.contains($0) }
        guard let name = Self.promptForText(title: "New Folder", actionTitle: "Create", defaultValue: defaultName) else { return }

        let path = childPath(name)
        Task {
            await mutate {
                try client.makeDirectory(path)
            }
        }
    }

    /// Pushes user-picked local files into the current directory, suffixing names on collision.
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
                await catching {
                    let data = try Data(contentsOf: localURL)
                    let originalName = localURL.lastPathComponent
                    let fileName = Self.uniqueName(for: originalName) { existingNames.contains($0) }
                    existingNames.insert(fileName)

                    let remotePath = childPath(fileName, in: destinationPath)
                    try await Task.detached { try client.writeFile(remotePath, data: data) }.value
                }
            }
            await load(path: currentPath)
        }
    }

    /// Modal single-line text prompt. Returns the trimmed text, or nil if cancelled or empty.
    private static func promptForText(title: String, actionTitle: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.alertStyle = .informational
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: defaultValue)
        textField.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Appends " (1)", " (2)", ... before the extension until `exists` reports the name is free.
    private static func uniqueName(for originalName: String, exists: (String) -> Bool) -> String {
        guard exists(originalName) else { return originalName }
        let baseName = (originalName as NSString).deletingPathExtension
        let ext = (originalName as NSString).pathExtension
        var candidate: String
        var counter = 1
        repeat {
            candidate = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
            counter += 1
        } while exists(candidate)
        return candidate
    }
}
