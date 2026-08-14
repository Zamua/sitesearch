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

    // Explicit keys so a config written by 0.4.0-0.7.0 (which carried a
    // per-site `slot`) still decodes; the dead field is dropped on rewrite.
    private enum CodingKeys: String, CodingKey { case id, keyword, name, template }
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

    /// STUB (red): runs `body` while holding an exclusive lock on the config,
    /// so the app and the MCP server cannot interleave read-modify-write.
    static func withLock<T>(at url: URL = fileURL, _ body: () throws -> T) rethrows -> T {
        try body()
    }

    /// STUB (red): the only supported way to change the config. Re-reads disk
    /// under the lock, applies an intent-shaped operation, and persists - so a
    /// caller holding a stale list cannot erase someone else's write.
    static func mutate<T>(at url: URL = fileURL, _ body: ([Site]) throws -> ([Site], T)) throws -> T {
        try body(load(from: url)).1
    }

    // Fixed IDs: entity identifiers must be stable across processes (Spotlight
    // caches them for recents and pre-filled parameters), so the out-of-box
    // defaults cannot mint fresh UUIDs per launch. Ids are retained across
    // releases even when the default set shrinks.
    // Every template is verified against the live site by scripts/e2e-sites.sh;
    // keep that script's list in sync with this one.
    static let defaults: [Site] = [
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000001")!, keyword: "google", name: "Google", template: "https://www.google.com/search?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000002")!, keyword: "code", name: "GitHub", template: "https://github.com/search?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000017")!, keyword: "repo", name: "GitHub Repos", template: "https://github.com/search?q={query}&type=repositories"),
    ]

    static func load(from url: URL = fileURL) -> [Site] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            save(defaults, to: url)
            return defaults
        }
        guard let data = try? Data(contentsOf: url),
              let sites = try? JSONDecoder().decode([Site].self, from: data) else {
            // An existing but unreadable file must never be silently replaced:
            // the UI would save defaults over the user's config. Park it for
            // recovery, then start over.
            let backup = url.appendingPathExtension("corrupt")
            try? fm.removeItem(at: backup)
            try? fm.moveItem(at: url, to: backup)
            save(defaults, to: url)
            return defaults
        }
        return sites
    }

    /// Returns the array actually persisted so callers can keep their
    /// in-memory copy in step with disk.
    @discardableResult
    static func save(_ sites: [Site], to url: URL = fileURL) -> [Site] {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(sites) {
            try? data.write(to: url, options: .atomic)
        }
        return sites
    }
}
