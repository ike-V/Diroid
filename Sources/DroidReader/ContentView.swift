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
                Button(action: model.navigateUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(model.currentPath == FileBrowserModel.rootPath)

                Text(model.currentPath)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)

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
    }
}
