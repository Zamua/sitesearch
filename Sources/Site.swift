import Foundation

/// A configured website search: a display name, a short keyword alias, and a
/// URL template containing the literal placeholder `{query}`.
struct Site: Codable, Identifiable, Hashable {
    var id: UUID
    var keyword: String
    var name: String
    var template: String
    /// Which pre-compiled CustomSearchNIntent slot this site occupies.
    /// nil for the built-in defaults (they have dedicated intents) and for
    /// sites not yet assigned; SiteStore.save allocates the lowest free slot.
    var slot: Int?

    init(id: UUID = UUID(), keyword: String, name: String, template: String, slot: Int? = nil) {
        self.id = id
        self.keyword = keyword
        self.name = name
        self.template = template
        self.slot = slot
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
    // defaults cannot mint fresh UUIDs per launch. Ids are retained across
    // releases even when the default set shrinks.
    // Every template is verified against the live site by scripts/e2e-sites.sh;
    // keep that script's list in sync with this one.
    static let defaults: [Site] = [
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000001")!, keyword: "google", name: "Google", template: "https://www.google.com/search?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000002")!, keyword: "code", name: "GitHub", template: "https://github.com/search?q={query}"),
        Site(id: UUID(uuidString: "9D2C63A0-5B21-4A2E-9C5A-000000000017")!, keyword: "repo", name: "GitHub Repos", template: "https://github.com/search?q={query}&type=repositories"),
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

    static let slotCount = 20

    /// Assigns the lowest free slot (1...slotCount) to every custom site that
    /// lacks one. Defaults never consume slots; existing assignments are
    /// stable; slots free up when their site is deleted. Sites beyond
    /// slotCount stay slotless (still usable via the generic Search Site).
    static func allocatingSlots(_ sites: [Site]) -> [Site] {
        let defaultIDs = Set(defaults.map(\.id))
        var used = Set(sites.compactMap(\.slot))
        var result = sites
        for i in result.indices where result[i].slot == nil && !defaultIDs.contains(result[i].id) {
            if let free = (1...slotCount).first(where: { !used.contains($0) }) {
                result[i].slot = free
                used.insert(free)
            }
        }
        return result
    }

    /// Returns the array actually persisted (with slots allocated) so callers
    /// can keep their in-memory copy in sync and slot assignments stay stable.
    @discardableResult
    static func save(_ sites: [Site]) -> [Site] {
        let slotted = allocatingSlots(sites)
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(slotted) {
            try? data.write(to: fileURL, options: .atomic)
        }
        // Quick keys mirror the config (keyword == quick key), so every save
        // re-syncs them; Spotlight picks the change up live.
        QuickKeySync.sync()
        return slotted
    }
}
