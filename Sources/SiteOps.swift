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
///
/// STUB (red): every operation is a no-op returning placeholder values.
enum SiteOps {
    /// Looks a site up by id string or by keyword (case-insensitive).
    static func find(_ sites: [Site], _ selector: String) -> Site? {
        _ = selector
        return nil
    }

    static func validate(name: String, keyword: String, template: String) throws {
        _ = (name, keyword, template)
    }

    static func add(to sites: [Site], name: String, keyword: String, template: String) throws -> (sites: [Site], added: Site) {
        (sites, Site(keyword: "", name: "", template: ""))
    }

    static func update(in sites: [Site], selector: String, name: String?, keyword: String?, template: String?) throws -> (sites: [Site], updated: Site) {
        (sites, Site(keyword: "", name: "", template: ""))
    }

    static func remove(from sites: [Site], selector: String) throws -> (sites: [Site], removed: Site) {
        (sites, Site(keyword: "", name: "", template: ""))
    }
}
