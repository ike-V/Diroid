import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case list = "List"
    case icon = "Icons"
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var model = FileBrowserModel()
    @State private var viewMode: ViewMode = .list
    @State private var groupBy: GroupByOption = .none

    private var groups: [EntryGroup] {
        groupedEntries(model.entries, by: groupBy)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ToolbarIconButton(systemName: "arrow.clockwise") {
                    model.connectAndLoadRoot()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(pathComponents(model.currentPath), id: \.fullPath) { component in
                            Text("/")
                                .foregroundStyle(.secondary)
                            PathSegment(label: component.label) {
                                Task { await model.load(path: component.fullPath) }
                            }
                        }
                    }
                }
                .font(.system(.body, design: .monospaced))

                Spacer()

                if model.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Image(systemName: mode == .list ? "list.bullet" : "square.grid.2x2")
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .tint(Color.androidGreen)
                .frame(width: 90)

                Menu {
                    ForEach(GroupByOption.allCases) { option in
                        Button {
                            groupBy = option
                        } label: {
                            if groupBy == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "square.grid.3x1.below.line.grid.1x2")
                }
                .menuStyle(.borderlessButton)
                .tint(Color.androidGreen)
                .frame(width: 24)

                ToolbarIconButton(systemName: "square.and.arrow.up") {
                    model.uploadFiles()
                }
            }
            .padding(8)

            Divider()

            if let error = model.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if viewMode == .list {
                listView
            } else {
                gridView
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .onAppear { model.connectAndLoadRoot() }
    }

    private var listView: some View {
        List {
            ForEach(groups) { group in
                if group.title.isEmpty {
                    ForEach(group.entries) { entry in row(for: entry) }
                } else {
                    Section(header: Text(group.title)) {
                        ForEach(group.entries) { entry in row(for: entry) }
                    }
                }
            }
        }
        .listStyle(.inset)
        .tint(Color.androidGreen)
    }

    private func row(for entry: AdbDirEntry) -> some View {
        HStack {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(entry.isDirectory ? Color.androidGreen : .secondary)
            Text(entry.name)
            Spacer()
            if !entry.isDirectory {
                Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            model.open(entry: entry)
        }
        .contextMenu {
            if !entry.isDirectory {
                Button("Save to…") {
                    model.saveToFolder(entry: entry)
                }
            }
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(groups) { group in
                    if !group.title.isEmpty {
                        Text(group.title)
                            .font(.headline)
                            .padding(.horizontal, 12)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 96), spacing: 12)], spacing: 16) {
                        ForEach(group.entries) { entry in cell(for: entry) }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func cell(for entry: AdbDirEntry) -> some View {
        VStack(spacing: 4) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .font(.system(size: 40))
                .foregroundStyle(entry.isDirectory ? Color.androidGreen : .secondary)
            Text(entry.name)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 96)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            model.open(entry: entry)
        }
        .contextMenu {
            if !entry.isDirectory {
                Button("Save to…") {
                    model.saveToFolder(entry: entry)
                }
            }
        }
    }
}

/// A toolbar icon button that highlights green on hover — a plain SwiftUI Button, so
/// (unlike native Menu/List selection chrome) the hover color is fully ours to set.
private struct ToolbarIconButton: View {
    let systemName: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovering ? Color.androidGreen : .primary)
        .onHover { isHovering = $0 }
    }
}

/// One clickable, hoverable segment of the path breadcrumb.
private struct PathSegment: View {
    let label: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Text(label)
            .foregroundStyle(isHovering ? Color.androidGreen : .primary)
            .onHover { isHovering = $0 }
            .onTapGesture(perform: action)
    }
}

/// Splits an absolute path like "/sdcard/Download/Quick Share" into breadcrumb segments,
/// each paired with the full path up to and including that segment.
private func pathComponents(_ path: String) -> [(label: String, fullPath: String)] {
    var result: [(label: String, fullPath: String)] = []
    var accumulated = ""
    for part in path.split(separator: "/") {
        accumulated += "/\(part)"
        result.append((String(part), accumulated))
    }
    return result
}
