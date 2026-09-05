import SwiftUI

enum ViewMode: String {
    case list = "List"
    case icon = "Icons"
}

struct ContentView: View {
    @StateObject private var model = FileBrowserModel()
    @State private var viewMode: ViewMode = .list
    @State private var groupBy: GroupByOption = .none

    private var groups: [EntryGroup] {
        groupedEntries(model.entries, by: groupBy)
    }

    var body: some View {
        Group {
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
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ToolbarIconButton(systemName: "arrow.clockwise") {
                    model.connectAndLoadRoot()
                }
            }
            .glassBackgroundHidden()

            ToolbarItem(placement: .principal) { breadcrumbView }
                .glassBackgroundHidden()

            ToolbarItem(placement: .primaryAction) {
                if model.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .glassBackgroundHidden()

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 10) {
                    ViewModeButton(systemName: "list.bullet", isSelected: viewMode == .list) {
                        viewMode = .list
                    }
                    ViewModeButton(systemName: "square.grid.2x2", isSelected: viewMode == .icon) {
                        viewMode = .icon
                    }
                    GroupByMenu(groupBy: $groupBy)
                }
            }
            .glassBackgroundHidden()

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 10) {
                    ToolbarIconButton(systemName: "folder.badge.plus") {
                        model.makeDirectory()
                    }
                    ToolbarIconButton(systemName: "square.and.arrow.up") {
                        model.uploadFiles()
                    }
                }
            }
            .glassBackgroundHidden()
        }
    }

    private var breadcrumbView: some View {
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
        .frame(maxWidth: 400)
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
        .contextMenu { contextMenuItems(for: entry) }
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
        .contextMenu { contextMenuItems(for: entry) }
    }

    @ViewBuilder
    private func contextMenuItems(for entry: AdbDirEntry) -> some View {
        Button("Rename…") {
            model.rename(entry: entry)
        }
        if !entry.isDirectory {
            Button("Save to…") {
                model.saveToFolder(entry: entry)
            }
        }
        Button("Delete", role: .destructive) {
            model.delete(entry: entry)
        }
    }
}

private extension ToolbarContent {
    /// Hides the macOS 26 "Liquid Glass" grouped background macOS otherwise draws behind
    /// every toolbar item; a no-op on older macOS, where that background doesn't exist.
    @ToolbarContentBuilder
    func glassBackgroundHidden() -> some ToolbarContent {
        if #available(macOS 26, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// Tints a view green while hovered (or `active`) — the hover-highlight shared by every
/// control below. A plain SwiftUI modifier, so (unlike native Menu/List selection chrome)
/// the color is fully ours to set.
private struct HoverTint: ViewModifier {
    var active: Bool = false
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(active || isHovering ? Color.androidGreen : .primary)
            .onHover { isHovering = $0 }
    }
}

private extension View {
    func hoverTint(active: Bool = false) -> some View {
        modifier(HoverTint(active: active))
    }
}

/// A toolbar icon button that highlights green on hover.
private struct ToolbarIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(.plain)
        .hoverTint()
    }
}

/// A view-mode toggle icon: green while selected, and green on hover otherwise — no
/// picker/segmented-control background behind it, unlike SwiftUI's built-in `Picker`.
private struct ViewModeButton: View {
    let systemName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(.plain)
        .hoverTint(active: isSelected)
    }
}

/// The Group By menu button — green only on hover, matching `ToolbarIconButton`/`ViewModeButton`.
private struct GroupByMenu: View {
    @Binding var groupBy: GroupByOption

    var body: some View {
        Menu {
            Picker("Group By", selection: $groupBy) {
                ForEach(GroupByOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "square.grid.3x1.below.line.grid.1x2")
                .hoverTint()
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
    }
}

/// One clickable, hoverable segment of the path breadcrumb.
private struct PathSegment: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Text(label)
            .hoverTint()
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
