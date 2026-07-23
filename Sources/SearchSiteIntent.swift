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
        guard NSWorkspace.shared.open(url) else {
            throw SearchSiteError.openFailed(url.absoluteString)
        }
        return .result()
    }

    /// RFC 3986 unreserved characters, ASCII only. Deliberately narrower than
    /// .urlQueryAllowed (which passes '&', '=', '+' through raw) and than
    /// .alphanumerics (Unicode-wide, which would leave non-ASCII un-encoded
    /// and rely on URL(string:) leniency).
    private static let queryAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func buildURL(template: String, query: String) throws -> URL {
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

enum SearchSiteError: Error, CustomLocalizedStringResourceConvertible {
    case invalidURL(String)
    case missingPlaceholder(String)
    case openFailed(String)
    case slotEmpty(Int)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidURL(let s):
            return "The site's URL template produced an invalid URL: \(s)"
        case .missingPlaceholder(let t):
            return "The site's URL template is missing the {query} placeholder: \(t)"
        case .openFailed(let s):
            return "The browser could not open: \(s)"
        case .slotEmpty(let n):
            return "No custom site is assigned to slot \(n). Open SiteSearch to configure sites."
        }
    }
}

struct SiteSearchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SearchSiteIntent(),
            phrases: [
                "Search with \(.applicationName)",
                // Parameterized: expands per configured site at runtime
                // (updateAppShortcutParameters refreshes after config edits).
                // Whether Tahoe Spotlight surfaces the per-site expansions as
                // typeable actions is the experiment this phrase exists for.
                "Search \(\.$site) with \(.applicationName)",
            ],
            shortTitle: "Search Site",
            systemImageName: "magnifyingglass"
        )
    }
}
