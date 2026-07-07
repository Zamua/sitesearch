import Foundation

/// A configured website search: a display name, a short keyword alias, and a
/// URL template containing the literal placeholder `{query}`.
struct Site: Codable, Identifiable, Hashable {
    var id: UUID
    var keyword: String
    var name: String
    var template: String

    init(id: UUID = UUID(), keyword: String, name: String, template: String) {
        self.id = id
        self.keyword = keyword
        self.name = name
        self.template = template
    }
}

/// Reads and writes the site list as JSON under Application Support.
///
/// Stateless by design: every load hits disk so the App Intents machinery
/// (which may run in a background-launched instance) always sees the latest
/// config saved from the UI.
enum SiteStore {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SiteSearch/sites.json")
    }

    static let defaults: [Site] = [
        Site(keyword: "g", name: "Google", template: "https://www.google.com/search?q={query}"),
        Site(keyword: "gh", name: "GitHub", template: "https://github.com/search?q={query}"),
        Site(keyword: "w", name: "Wikipedia", template: "https://en.wikipedia.org/w/index.php?search={query}"),
        Site(keyword: "yt", name: "YouTube", template: "https://www.youtube.com/results?search_query={query}"),
    ]

    static func load() -> [Site] {
        guard let data = try? Data(contentsOf: fileURL) else { return defaults }
        return (try? JSONDecoder().decode([Site].self, from: data)) ?? defaults
    }

    static func save(_ sites: [Site]) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(sites) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
