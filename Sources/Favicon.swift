import Foundation

/// Favicon fetching and on-disk caching.
///
/// Icons are fetched when a site is added or its template changes, never while
/// Spotlight is drawing: `SiteEntity.displayRepresentation` is synchronous, so
/// a network call there would stall the dropdown. Cached bytes live beside the
/// config as `icons/<site-uuid>` and the config itself stays clean JSON.
///
/// Icons come from the site's own origin - no third-party favicon proxy, which
/// would report every configured site to someone else.
///
/// STUB (red).
enum Favicon {
    static var directoryURL: URL {
        SiteStore.fileURL.deletingLastPathComponent().appendingPathComponent("icons")
    }

    static func cacheURL(for id: UUID, in directory: URL = directoryURL) -> URL {
        directory.appendingPathComponent(id.uuidString)
    }

    static func cachedData(for id: UUID, in directory: URL = directoryURL) -> Data? {
        _ = (id, directory)
        return nil
    }

    /// The scheme+host the icon should come from, derived from the template.
    static func origin(forTemplate template: String) -> URL? {
        _ = template
        return nil
    }

    /// Icon URLs declared by a page's <link rel="... icon ..."> tags, resolved
    /// against the origin and ordered best-first.
    static func iconHrefs(inHTML html: String, origin: URL) -> [URL] {
        _ = (html, origin)
        return []
    }

    /// Fetches and caches an icon for `site`, returning whether one is now
    /// cached. `fetch` is injected so the logic is testable without a network.
    @discardableResult
    static func ensureCached(for site: Site, in directory: URL = directoryURL, fetch: (URL) -> Data?) -> Bool {
        _ = (site, directory, fetch)
        return false
    }
}
