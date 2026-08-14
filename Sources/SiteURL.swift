import Foundation

/// URL construction and template validation, with no framework dependencies
/// beyond Foundation so both the app and the MCP server can share it.
/// `SearchSiteIntent` adds the AppIntents-facing error conformance on top.
enum SiteURL {
    /// RFC 3986 unreserved characters, ASCII only. Deliberately narrower than
    /// .urlQueryAllowed (which passes '&', '=', '+' through raw) and than
    /// .alphanumerics (Unicode-wide, which would leave non-ASCII un-encoded
    /// and rely on URL(string:) leniency).
    private static let queryAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

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

enum SearchSiteError: Error {
    case invalidURL(String)
    case missingPlaceholder(String)
    case openFailed(String)
}
