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

    // Fixed IDs: entity identifiers must be stable across processes (Spotlight
    // caches them for recents and pre-filled parameters), so the out-of-box
    // defaults cannot mint fresh UUIDs per launch.
    static let defaults: [Site] = [
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000001")!, keyword: "g", name: "Google", template: "https://www.google.com/search?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000002")!, keyword: "gh", name: "GitHub", template: "https://github.com/search?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000003")!, keyword: "w", name: "Wikipedia", template: "https://en.wikipedia.org/w/index.php?search={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000004")!, keyword: "yt", name: "YouTube", template: "https://www.youtube.com/results?search_query={query}"),
    ]

    static func load() -> [Site] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            save(defaults)
            return defaults
        }
        guard let data = try? Data(contentsOf: fileURL),
              let sites = try? JSONDecoder().decode([Site].self, from: data) else {
            // An existing but unreadable file must never be silently replaced:
            // the UI would save defaults over the user's config. Park it for
            // recovery, then start over.
            let backup = fileURL.appendingPathExtension("corrupt")
            try? fm.removeItem(at: backup)
            try? fm.moveItem(at: fileURL, to: backup)
            save(defaults)
            return defaults
        }
        return sites
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
