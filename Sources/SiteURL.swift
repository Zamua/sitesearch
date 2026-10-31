import Foundation

/// URL construction and template validation, with no framework dependencies
/// beyond Foundation so both the app and the MCP server can share it.
enum SiteURL {
    /// RFC 3986 unreserved characters, ASCII only. Deliberately narrower than
    /// .urlQueryAllowed (which passes '&', '=', '+' through raw) and than
    /// .alphanumerics (Unicode-wide, which would leave non-ASCII un-encoded
    /// and rely on URL(string:) leniency).
    private static let queryAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Whether a template is a search (has the placeholder) or a bookmark
    /// (a plain URL to open as-is).
    static func requiresQuery(_ template: String) -> Bool {
        template.contains("{query}")
    }

    /// Resolves either kind: substitutes into a search template, or returns a
    /// bookmark's URL untouched. A search with no query resolves to the bare
    /// search page rather than failing - the same thing a browser would do.
    static func resolve(template: String, query: String?) throws -> URL {
        guard requiresQuery(template) else { return try validated(template) }
        return try build(template: template, query: query ?? "")
    }

    /// A bookmark carries no placeholder, so there is nothing to encode - but
    /// it still has to be a real http(s) URL.
    private static func validated(_ template: String) throws -> URL {
        guard let url = URL(string: template), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host?.isEmpty == false
        else { throw SearchSiteError.invalidURL(template) }
        return url
    }

    static func build(template: String, query: String) throws -> URL {
        guard template.contains("{query}") else {
            throw SearchSiteError.missingPlaceholder(template)
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? query
        let urlString = template.replacingOccurrences(of: "{query}", with: encoded)
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw SearchSiteError.invalidURL(urlString)
        }
        return url
    }
}

enum SearchSiteError: Error, LocalizedError {
    case invalidURL(String)
    case missingPlaceholder(String)
    case openFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let s):
            return "The site's URL template produced an invalid URL: \(s)"
        case .missingPlaceholder(let t):
            return "The site's URL template is missing the {query} placeholder: \(t)"
        case .openFailed(let s):
            return "The browser could not open: \(s)"
        }
    }
}
