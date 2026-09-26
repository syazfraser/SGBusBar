import Foundation

/// One version from CHANGELOG.md.
struct ChangelogEntry: Identifiable, Equatable {
    struct Section: Equatable {
        /// "Added", "Changed", "Fixed"; nil for bullets straight under the version.
        var title: String?
        var items: [String] = []
    }

    let version: String
    let date: String?
    var summary: [String] = []
    var sections: [Section] = []

    var id: String { version }
    var isEmpty: Bool { summary.isEmpty && sections.allSatisfy(\.items.isEmpty) }
}

/// Reads the CHANGELOG.md that ships inside the app, in the Keep a Changelog layout:
/// "## [0.2.0] - 2026-09-26", then "### Added" and "- item" lines.
enum Changelog {
    static func load(from bundle: Bundle = .main) -> [ChangelogEntry] {
        guard let url = bundle.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return parse(text)
    }

    /// Newest first, as written; empty versions (like an unused "Unreleased") are dropped.
    static func parse(_ markdown: String) -> [ChangelogEntry] {
        var entries: [ChangelogEntry] = []
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                let (version, date) = versionAndDate(String(line.dropFirst(3)))
                entries.append(ChangelogEntry(version: version, date: date))
            } else if entries.isEmpty || line.isEmpty || line.hasPrefix("[") && line.contains("]:") {
                continue  // the intro above the first version, blank lines, link references
            } else if line.hasPrefix("### ") {
                entries[entries.count - 1].sections.append(.init(title: String(line.dropFirst(4))))
            } else if line.hasPrefix("- ") {
                if entries[entries.count - 1].sections.isEmpty {
                    entries[entries.count - 1].sections.append(.init(title: nil))
                }
                let last = entries[entries.count - 1].sections.count - 1
                entries[entries.count - 1].sections[last].items.append(String(line.dropFirst(2)))
            } else {
                entries[entries.count - 1].summary.append(line)
            }
        }
        return entries.filter { !$0.isEmpty }
    }

    /// "[0.2.0] - 2026-09-26" → ("0.2.0", "2026-09-26")
    private static func versionAndDate(_ heading: String) -> (String, String?) {
        let parts = heading.components(separatedBy: " - ")
        let version = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        return (version, parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil)
    }
}
