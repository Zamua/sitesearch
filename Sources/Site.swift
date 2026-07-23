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
    // Every template is verified against the live site by scripts/e2e-sites.sh;
    // keep that script's list in sync with this one.
    static let defaults: [Site] = [
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000001")!, keyword: "g", name: "Google", template: "https://www.google.com/search?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000002")!, keyword: "gh", name: "GitHub", template: "https://github.com/search?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000003")!, keyword: "w", name: "Wikipedia", template: "https://en.wikipedia.org/w/index.php?search={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000004")!, keyword: "yt", name: "YouTube", template: "https://www.youtube.com/results?search_query={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000005")!, keyword: "ddg", name: "DuckDuckGo", template: "https://duckduckgo.com/?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000006")!, keyword: "r", name: "Reddit", template: "https://www.reddit.com/search/?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000007")!, keyword: "a", name: "Amazon", template: "https://www.amazon.com/s?k={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000008")!, keyword: "gm", name: "Google Maps", template: "https://www.google.com/maps/search/{query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000009")!, keyword: "so", name: "Stack Overflow", template: "https://stackoverflow.com/search?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000010")!, keyword: "hn", name: "Hacker News", template: "https://hn.algolia.com/?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000011")!, keyword: "mdn", name: "MDN", template: "https://developer.mozilla.org/en-US/search?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000012")!, keyword: "npm", name: "npm", template: "https://www.npmjs.com/search?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000013")!, keyword: "pypi", name: "PyPI", template: "https://pypi.org/search/?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000014")!, keyword: "go", name: "Go Packages", template: "https://pkg.go.dev/search?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000015")!, keyword: "nix", name: "nixpkgs", template: "https://search.nixos.org/packages?query={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000016")!, keyword: "imdb", name: "IMDb", template: "https://www.imdb.com/find/?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000017")!, keyword: "ghr", name: "GitHub Repos", template: "https://github.com/search?q={query}&type=repositories"),
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
