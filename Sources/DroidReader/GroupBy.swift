import Foundation

enum GroupByOption: String, CaseIterable, Identifiable {
    case none = "None"
    case name = "Name"
    case size = "Size"
    case dateModified = "Date Modified"

    var id: String { rawValue }
}

struct EntryGroup: Identifiable {
    let title: String
    let entries: [AdbDirEntry]
    var id: String { title }
}

func groupedEntries(_ entries: [AdbDirEntry], by option: GroupByOption) -> [EntryGroup] {
    switch option {
    case .none:
        return [EntryGroup(title: "", entries: entries.sorted(by: nameAscending))]

    case .name:
        let buckets = Dictionary(grouping: entries) { entry -> String in
            guard let first = entry.name.first, first.isLetter else { return "#" }
            return String(first).uppercased()
        }
        return buckets.keys.sorted().map {
            EntryGroup(title: $0, entries: buckets[$0]!.sorted(by: nameAscending))
        }

    case .size:
        let order = ["Folders", "Empty (0 KB)", "Under 1 MB", "1 MB – 10 MB", "10 MB – 100 MB", "Over 100 MB"]
        let buckets = Dictionary(grouping: entries, by: sizeBucket)
        return order.compactMap { title in
            buckets[title].map { EntryGroup(title: title, entries: $0.sorted(by: nameAscending)) }
        }

    case .dateModified:
        let order = ["Today", "Yesterday", "This Week", "This Month", "This Year", "Older"]
        let buckets = Dictionary(grouping: entries, by: dateBucket)
        return order.compactMap { title in
            buckets[title].map { EntryGroup(title: title, entries: $0.sorted(by: nameAscending)) }
        }
    }
}

func nameAscending(_ a: AdbDirEntry, _ b: AdbDirEntry) -> Bool {
    if a.isDirectory != b.isDirectory { return a.isDirectory }
    return a.name.localizedStandardCompare(b.name) == .orderedAscending
}

private func sizeBucket(for entry: AdbDirEntry) -> String {
    if entry.isDirectory { return "Folders" }
    let size = Int(entry.size)
    let mb = 1024 * 1024
    switch size {
    case 0: return "Empty (0 KB)"
    case 1..<mb: return "Under 1 MB"
    case mb..<(10 * mb): return "1 MB – 10 MB"
    case (10 * mb)..<(100 * mb): return "10 MB – 100 MB"
    default: return "Over 100 MB"
    }
}

private func dateBucket(for entry: AdbDirEntry) -> String {
    let calendar = Calendar.current
    let now = Date()
    if calendar.isDateInToday(entry.modified) { return "Today" }
    if calendar.isDateInYesterday(entry.modified) { return "Yesterday" }
    if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), entry.modified > weekAgo {
        return "This Week"
    }
    if calendar.isDate(entry.modified, equalTo: now, toGranularity: .month) { return "This Month" }
    if calendar.isDate(entry.modified, equalTo: now, toGranularity: .year) { return "This Year" }
    return "Older"
}
