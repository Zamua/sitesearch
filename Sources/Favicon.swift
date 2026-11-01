import Foundation

/// Favicon fetching and on-disk caching.
///
/// Icons are fetched when a site is added or its template changes, never while
/// Spotlight is drawing: `SiteEntity.displayRepresentation` is synchronous, so
/// a network call there would stall the dropdown. Cached bytes live beside the
/// config as `icons/<site-uuid>/<origin>` and the config itself stays clean
/// JSON. Keying by origin as well as site is what keeps a slow fetch for an
/// origin the site has since left (from this window or from the MCP server's
/// process) from landing on the icon of the origin it has now.
///
/// Icons come from the site's own origin - no third-party favicon proxy, which
/// would report every configured site to someone else.
enum Favicon {
    static var directoryURL: URL {
        SiteStore.fileURL.deletingLastPathComponent().appendingPathComponent("icons")
    }

    private static func siteDirectory(for id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Where the icon of the site's current origin lives; nil when the
    /// template has no web origin.
    static func cacheURL(for site: Site, in directory: URL = directoryURL) -> URL? {
        guard let origin = origin(forTemplate: site.template),
              let name = "\(origin.scheme ?? "")-\(origin.host ?? "")\(origin.port.map { "-\($0)" } ?? "")"
                .addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ".-")))
        else { return nil }
        return siteDirectory(for: site.id, in: directory).appendingPathComponent(name)
    }

    static func cachedData(for site: Site, in directory: URL = directoryURL) -> Data? {
        guard let url = cacheURL(for: site, in: directory) else { return nil }
        let data = try? Data(contentsOf: url)
        return (data?.isEmpty == false) ? data : nil
    }

    /// The scheme+host the icon should come from, derived from the template.
    static func origin(forTemplate template: String) -> URL? {
        guard let url = SiteURL.webURL(template.replacingOccurrences(of: "{query}", with: "probe")) else { return nil }
        var components = URLComponents()
        components.scheme = url.scheme?.lowercased()
        components.host = url.host
        components.port = url.port
        return components.url
    }

    /// Icon URLs declared by a page's <link rel="... icon ..."> tags, resolved
    /// against the origin and ordered best-first (declared order, which puts
    /// the page's preferred icon first in practice).
    ///
    /// A regex, not an HTML parser: we need one attribute out of <head>, and
    /// pulling in a parser for that is not a trade worth making.
    static func iconHrefs(inHTML html: String, origin: URL) -> [URL] {
        let pattern = #"<link\b[^>]*>"#
        guard let linkRegex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)

        var results: [URL] = []
        for match in linkRegex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            // Matches rel="icon", "shortcut icon", "apple-touch-icon" and its
            // -precomposed variant; "stylesheet" and friends fall out.
            guard let rel = attribute("rel", in: tag)?.lowercased(),
                  rel.split(whereSeparator: \.isWhitespace).contains(where: { $0.contains("icon") })
            else { continue }
            guard let href = attribute("href", in: tag),
                  let url = URL(string: href, relativeTo: origin)?.absoluteURL
            else { continue }
            results.append(url)
        }
        return results
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\(name)\\s*=\\s*(\"([^\"]*)\"|'([^']*)')"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag))
        else { return nil }
        for group in 2...3 {
            if let range = Range(match.range(at: group), in: tag) {
                return String(tag[range])
            }
        }
        return nil
    }

    /// Fetches and caches an icon for `site`, returning whether one is now
    /// cached. `fetch` is injected so the logic is testable without a network.
    ///
    /// Order: the conventional /favicon.ico first (one request, usually hits),
    /// then whatever the page declares. Anything empty is treated as a miss.
    @discardableResult
    static func ensureCached(for site: Site, in directory: URL = directoryURL, fetch: (URL) -> Data?) -> Bool {
        if cachedData(for: site, in: directory) != nil { return true }
        guard let origin = origin(forTemplate: site.template), let target = cacheURL(for: site, in: directory) else { return false }
        func hit(_ url: URL) -> Data? { fetch(url).flatMap { $0.isEmpty ? nil : $0 } }

        let conventional = origin.appendingPathComponent("favicon.ico")
        if let data = hit(conventional) { return write(data, to: target) }
        guard let html = hit(origin), let markup = String(data: html, encoding: .utf8) else { return false }
        var tried: Set<URL> = [conventional]
        for declared in iconHrefs(inHTML: markup, origin: origin) where tried.insert(declared).inserted {
            if let data = hit(declared) { return write(data, to: target) }
        }
        return false
    }

    private static func write(_ data: Data, to url: URL) -> Bool {
        let siteDirectory = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        // A plain file here is the per-site layout without origins; it gives way.
        if FileManager.default.fileExists(atPath: siteDirectory.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            try? FileManager.default.removeItem(at: siteDirectory)
        }
        try? FileManager.default.createDirectory(at: siteDirectory, withIntermediateDirectories: true)
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Removes `url` if present, returning whether anything was there.
    private static func remove(_ url: URL?) -> Bool {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return false }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    /// Brings the icon cache in line with a change from `old` to `new`: a
    /// removed site, or one whose origin moved, loses its icon, and a new or
    /// moved site is fetched unless already cached. `old: []` backfills a whole
    /// list. Blocks on the network, so callers run it off the main thread.
    /// Returns whether the cache changed.
    @discardableResult
    static func refresh(from old: [Site], to new: [Site], in directory: URL = directoryURL, fetch: (URL) -> Data?) -> Bool {
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newIDs = Set(new.map(\.id))
        var changed = false
        for site in old where !newIDs.contains(site.id) {
            changed = remove(siteDirectory(for: site.id, in: directory)) || changed
        }
        for site in new {
            if let before = oldByID[site.id] {
                guard origin(forTemplate: before.template) != origin(forTemplate: site.template) else { continue }
                changed = remove(cacheURL(for: before, in: directory)) || changed
            }
            if cachedData(for: site, in: directory) == nil, ensureCached(for: site, in: directory, fetch: fetch) {
                changed = true
            }
        }
        return changed
    }

    /// The real network fetch: a short timeout, because this runs inline on an
    /// agent's add_site call and no one wants that to hang.
    static func download(_ url: URL) -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("SiteSearch/1.0", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            result = data
        }.resume()
        _ = semaphore.wait(timeout: .now() + 6)
        return result
    }
}
