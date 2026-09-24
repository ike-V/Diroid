import SwiftUI

/// A second take on the file browser, styled like Syndroid's Synd Apps and Actions windows:
/// a plain list of icon/title/caption rows and a bottom-right button bar instead of a toolbar.
struct FileBrowserTestView: View {
    @StateObject private var model = FileBrowserModel()

    var body: some View {
        VStack(spacing: 0) {
            pathBar
            Group {
                if let problem = model.connectionProblem {
                    connectionProblemView(problem)
                } else {
                    List {
                        ForEach(model.entries) { entry in row(for: entry) }
                    }
                }
            }
            HStack {
                Button("New Folder…") { model.makeDirectory() }
                Spacer()
                Button("Upload Files…") { model.uploadFiles() }
            }
            .padding(12)
        }
        .frame(minWidth: 500, minHeight: 420)
        .onAppear { model.connectAndLoadRoot() }
        .alert("Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in if !isPresented { model.clearError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            Button {
                if let parent = parentPath(model.currentPath) {
                    Task { await model.load(path: parent) }
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(model.currentPath == "/")
            Text(model.currentPath)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if model.isLoading {
                ProgressView().scaleEffect(0.6)
            }
            Button { model.connectAndLoadRoot() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private func row(for entry: AdbDirEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isDirectory ? "folder" : "doc")
                .frame(width: 20, height: 20)
                .foregroundStyle(Color.androidGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.system(size: 12.5)).lineLimit(1)
                if !entry.isDirectory {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.open(entry: entry) }
        .contextMenu {
            Button("Rename…") { model.rename(entry: entry) }
            if !entry.isDirectory {
                Button("Save to…") { model.saveToFolder(entry: entry) }
            }
            Button("Delete", role: .destructive) { model.delete(entry: entry) }
        }
    }

    private func connectionProblemView(_ problem: ConnectionProblem) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(problem.title).font(.headline)
            Text(problem.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The path one level up, or nil at the root.
private func parentPath(_ path: String) -> String? {
    guard path != "/" else { return nil }
    let parent = (path as NSString).deletingLastPathComponent
    return parent.isEmpty ? "/" : parent
}
