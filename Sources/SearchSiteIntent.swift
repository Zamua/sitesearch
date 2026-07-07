import AppIntents
import AppKit

/// The Spotlight action: "Search <site> for <query>". Runs in the background
/// (no app window) and opens the templated search URL in the default browser.
struct SearchSiteIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Site"
    static let description = IntentDescription("Search a configured website in your default browser.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Site")
    var site: SiteEntity

    @Parameter(title: "Query")
    var query: String

    // Every required no-default parameter MUST appear here, or the action is
    // silently excluded from Spotlight. Site comes first so text typed right
    // after a quick key filters the site dropdown.
    static var parameterSummary: some ParameterSummary {
        Summary("Search \(\.$site) for \(\.$query)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let url = try Self.buildURL(template: site.template, query: query)
        NSWorkspace.shared.open(url)
        return .result()
    }

    /// RFC 3986 unreserved characters. Deliberately narrower than
    /// .urlQueryAllowed, which would leave '&', '=', '+' and friends raw and
    /// let a query like "c++" or "a&b" corrupt the URL.
    private static let queryAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    static func buildURL(template: String, query: String) throws -> URL {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? query
        let urlString = template.replacingOccurrences(of: "{query}", with: encoded)
        guard let url = URL(string: urlString), url.scheme == "https" || url.scheme == "http" else {
            throw SearchSiteError.invalidURL(urlString)
        }
        return url
    }
}

enum SearchSiteError: Error, CustomLocalizedStringResourceConvertible {
    case invalidURL(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidURL(let s):
            return "The site's URL template produced an invalid URL: \(s)"
        }
    }
}

struct SiteSearchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SearchSiteIntent(),
            phrases: ["Search with \(.applicationName)"],
            shortTitle: "Search Site",
            systemImageName: "magnifyingglass"
        )
    }
}
