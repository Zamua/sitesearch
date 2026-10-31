import CryptoKit
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

    /// A bookmark has nothing to substitute - it just opens.
    var isBookmark: Bool { !SiteURL.requiresQuery(template) }

    /// The two kinds are surfaced as separate Spotlight actions, so each one's
    /// dropdown lists only its own kind.
    static func searches(_ sites: [Site]) -> [Site] { sites.filter { !$0.isBookmark } }
    static func bookmarks(_ sites: [Site]) -> [Site] { sites.filter(\.isBookmark) }
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

    /// Runs `body` while holding an exclusive advisory lock, so the app and the
    /// MCP server cannot interleave read-modify-write. The lock lives in a
    /// sidecar file: locking sites.json itself would race with the atomic
    /// replace in `save`, which swaps the inode out from under the holder.
    ///
    /// A lock that cannot be taken (unwritable directory, sandbox denial) must
    /// not make the app unusable - it degrades to running unlocked.
    static func withLock<T>(at url: URL = fileURL, _ body: () throws -> T) rethrows -> T {
        let lockURL = url.appendingPathExtension("lock")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return try body() }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { return try body() }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    /// The only supported way to change the config. Re-reads disk under the
    /// lock, applies an intent-shaped operation, and persists - so a caller
    /// holding a stale list cannot erase someone else's write. A throwing
    /// operation leaves the file untouched.
    static func mutate<T>(at url: URL = fileURL, _ body: ([Site]) throws -> ([Site], T)) throws -> T {
        try withLock(at: url) {
            let (updated, result) = try body(load(from: url))
            try save(updated, to: url)
            return result
        }
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
            // Seeding is best-effort: the defaults are returned either way, and
            // the next mutate reports a failed write to a caller that can act.
            try? save(defaults, to: url)
            return defaults
        }
        guard let data = try? Data(contentsOf: url),
              let sites = try? JSONDecoder().decode([Site].self, from: withIDs(data)) else {
            // An existing but unreadable file must never be silently replaced:
            // the UI would save defaults over the user's config. Park it for
            // recovery, then start over.
            let backup = url.appendingPathExtension("corrupt")
            try? fm.removeItem(at: backup)
            try? fm.moveItem(at: url, to: backup)
            try? save(defaults, to: url)
            return defaults
        }
        return sites
    }

    static func save(_ sites: [Site], to url: URL = fileURL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(sites).write(to: url, options: .atomic)
        } catch {
            throw SiteStoreError.writeFailed(path: url.path, reason: error.localizedDescription)
        }
    }

    /// A hand-written entry may omit `id`. Each gets one derived from its
    /// content before decoding, so every process resolves it to the same
    /// entity (Spotlight caches entity ids) and `Site`'s own Codable stays the
    /// only description of the format. The occurrence count keeps identical
    /// entries apart; the next save persists the ids. Anything that is not an
    /// array of objects passes through for the decoder to reject.
    private static func withIDs(_ data: Data) throws -> Data {
        guard var entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              entries.contains(where: { $0["id"] == nil }) else { return data }
        var seen: [String: Int] = [:]
        for index in entries.indices where entries[index]["id"] == nil {
            let key = ["keyword", "name", "template"]
                .map { entries[index][$0] as? String ?? "" }
                .joined(separator: "\u{0}")
            let occurrence = seen[key, default: 0]
            seen[key] = occurrence + 1
            entries[index]["id"] = derivedID(key + "\u{0}\(occurrence)").uuidString
        }
        return try JSONSerialization.data(withJSONObject: entries)
    }

    /// A name-based (version 5) UUID in a fixed namespace.
    private static func derivedID(_ name: String) -> UUID {
        let namespace = UUID(uuidString: "6F1C5A52-9B2E-4D7A-8C3B-5E0D2A9F4B18")!
        let input = withUnsafeBytes(of: namespace.uuid) { Data($0) } + Data(name.utf8)
        var bytes = Array(Insecure.SHA1.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }
}

enum SiteStoreError: Error, LocalizedError, Equatable {
    case writeFailed(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let path, let reason):
            return "Could not save sites to \(path): \(reason)"
        }
    }
}
