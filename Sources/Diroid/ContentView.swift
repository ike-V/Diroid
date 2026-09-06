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

    /// Drives the error alert off `model.errorMessage` directly — dismissing it (OK or
    /// clicking away) just clears the message, leaving `currentPath`/`entries` untouched.
    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in if !isPresented { model.clearError() } }
        )
    }

    var body: some View {
        Group {
            if viewMode == .list {
                listView
            } else {
                gridView
            }
        }
        .frame(minWidth: 320, minHeight: 420)
        .onAppear { model.connectAndLoadRoot() }
        .alert("Error", isPresented: errorAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
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

            // Each control below gets its own ToolbarItem (rather than a few grouped
            // into shared HStacks) so macOS can generate a proper overflow-menu
            // representation for every one of them individually when the window
            // narrows — a ToolbarItem wrapping several controls at once only carries
            // part of its content into the "»" overflow menu.
            ToolbarItem(placement: .primaryAction) {
                ViewModeButton(systemName: "list.bullet", isSelected: viewMode == .list) {
                    viewMode = .list
                }
            }
            .glassBackgroundHidden()

            ToolbarItem(placement: .primaryAction) {
                ViewModeButton(systemName: "square.grid.2x2", isSelected: viewMode == .icon) {
                    viewMode = .icon
                }
            }
            .glassBackgroundHidden()

            ToolbarItem(placement: .primaryAction) {
                GroupByMenu(groupBy: $groupBy)
            }
            .glassBackgroundHidden()

            ToolbarItem(placement: .primaryAction) {
                ToolbarIconButton(systemName: "folder.badge.plus") {
                    model.makeDirectory()
                }
            }
            .glassBackgroundHidden()

            ToolbarItem(placement: .primaryAction) {
                ToolbarIconButton(systemName: "square.and.arrow.up") {
                    model.uploadFiles()
                }
            }
            .glassBackgroundHidden()
        }
    }

    private var breadcrumbView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(pathComponents(model.currentPath).enumerated()), id: \.element.fullPath) { index, component in
                    // Skip the separator right after root — root's own label is "/",
                    // which already reads as the slash leading into the next segment.
                    if index > 1 {
                        Text("/")
                            .foregroundStyle(.secondary)
                    }
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
        .rowInteractions(model: model, entry: entry)
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
        .rowInteractions(model: model, entry: entry)
    }
}

@ViewBuilder
private func contextMenuItems(model: FileBrowserModel, entry: AdbDirEntry) -> some View {
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

private extension View {
    /// Double-click-to-open plus the shared context menu — the trailer common to both
    /// the list row and the grid cell.
    func rowInteractions(model: FileBrowserModel, entry: AdbDirEntry) -> some View {
        contentShape(Rectangle())
            .onTapGesture(count: 2) { model.open(entry: entry) }
            .contextMenu { contextMenuItems(model: model, entry: entry) }
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

/// Splits an absolute path like "/storage/emulated/0" into breadcrumb segments, each
/// paired with the full path up to and including that segment. The root "/" is always
/// the first segment, so it's just another clickable stop in the chain rather than a
/// special case the caller has to handle separately.
private func pathComponents(_ path: String) -> [(label: String, fullPath: String)] {
    var result: [(label: String, fullPath: String)] = [("/", "/")]
    var accumulated = ""
    for part in path.split(separator: "/") {
        accumulated += "/\(part)"
        result.append((String(part), accumulated))
    }
    return result
}
