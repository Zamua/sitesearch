import Foundation

/// Errors an intent-shaped config change can fail with. Deliberately specific:
/// these surface to an agent through the MCP server, which can only recover if
/// it is told exactly what was wrong.
enum SiteOpError: Error, LocalizedError, Equatable {
    case emptyName
    case emptyKeyword
    case missingPlaceholder(String)
    case invalidTemplate(String)
    case keywordTaken(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "A site needs a name."
        case .emptyKeyword:
            return "A site needs a keyword - it is how you pick the site in Spotlight."
        case .missingPlaceholder(let t):
            return "Template is missing the {query} placeholder: \(t)"
        case .invalidTemplate(let t):
            return "Template is not a valid http(s) URL: \(t)"
        case .keywordTaken(let k):
            return "Another site already uses the keyword '\(k)'."
        case .notFound(let s):
            return "No site matches '\(s)' (try a keyword or an id)."
        }
    }
}

/// Pure, intent-shaped operations on a site list: add one, change fields of
/// one, remove one. Never "replace the whole list" - that is what let a stale
/// snapshot clobber a concurrent write. `SiteStore.mutate` applies these under
/// a lock against freshly-read state.
enum SiteOps {
    /// Looks a site up by id string or by keyword (case-insensitive). Agents
    /// tend to have the keyword to hand; the UI has the id.
    static func find(_ sites: [Site], _ selector: String) -> Site? {
        let needle = selector.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return nil }
        return sites.first { $0.id.uuidString.lowercased() == needle }
            ?? sites.first { $0.keyword.lowercased() == needle }
    }

    static func validate(name: String, keyword: String, template: String) throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw SiteOpError.emptyName }
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else { throw SiteOpError.emptyKeyword }
        try validate(template: template)
    }

    /// Templates are validated with the same resolver the search itself uses,
    /// so a site that stores successfully cannot fail only at search time.
    ///
    /// Both kinds are accepted: with {query} it is a search, without it is a
    /// bookmark. Callers needing one specific kind (the MCP tools) check
    /// `SiteURL.requiresQuery` themselves so their error names the mistake.
    static func validate(template: String) throws {
        do {
            _ = try SiteURL.resolve(template: template, query: "probe")
        } catch SearchSiteError.missingPlaceholder {
            throw SiteOpError.missingPlaceholder(template)
        } catch {
            throw SiteOpError.invalidTemplate(template)
        }
    }

    private static func assertKeywordFree(_ keyword: String, in sites: [Site], excluding id: UUID? = nil) throws {
        let needle = keyword.trimmingCharacters(in: .whitespaces).lowercased()
        let clash = sites.contains { $0.keyword.lowercased() == needle && $0.id != id }
        if clash { throw SiteOpError.keywordTaken(keyword) }
    }

    static func add(to sites: [Site], name: String, keyword: String, template: String) throws -> (sites: [Site], added: Site) {
        try validate(name: name, keyword: keyword, template: template)
        try assertKeywordFree(keyword, in: sites)
        let site = Site(
            keyword: keyword.trimmingCharacters(in: .whitespaces),
            name: name.trimmingCharacters(in: .whitespaces),
            template: template.trimmingCharacters(in: .whitespaces)
        )
        return (sites + [site], site)
    }

    /// nil means "leave this field alone" - the write carries only what the
    /// caller actually intends to change.
    static func update(in sites: [Site], selector: String, name: String?, keyword: String?, template: String?) throws -> (sites: [Site], updated: Site) {
        guard let existing = find(sites, selector), let index = sites.firstIndex(where: { $0.id == existing.id }) else {
            throw SiteOpError.notFound(selector)
        }
        var site = existing
        if let name {
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw SiteOpError.emptyName }
            site.name = name.trimmingCharacters(in: .whitespaces)
        }
        if let keyword {
            guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else { throw SiteOpError.emptyKeyword }
            try assertKeywordFree(keyword, in: sites, excluding: site.id)
            site.keyword = keyword.trimmingCharacters(in: .whitespaces)
        }
        if let template {
            try validate(template: template)
            site.template = template.trimmingCharacters(in: .whitespaces)
        }
        var result = sites
        result[index] = site
        return (result, site)
    }

    static func remove(from sites: [Site], selector: String) throws -> (sites: [Site], removed: Site) {
        guard let existing = find(sites, selector) else { throw SiteOpError.notFound(selector) }
        return (sites.filter { $0.id != existing.id }, existing)
    }
}
