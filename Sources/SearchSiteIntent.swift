import AppIntents
import AppKit

/// The Spotlight action: "Search <site> for <query>". Runs in the background
/// (no app window) and opens the templated search URL in the default browser.
struct SearchSiteIntent: AppIntent {
    // The TYPE name is load-bearing - the Spotlight quick-key store keys on
    // "<bundle-id>.SearchSiteIntent" - but this display title is free to change.
    static let title: LocalizedStringResource = "Search or Open Site"
    static let description = IntentDescription("Search a configured website, or open a saved bookmark, in your default browser.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Site")
    var site: SiteEntity

    // Optional: a bookmark has nothing to search for, so `ss repo1` should run
    // on Return rather than stopping to demand a query.
    @Parameter(title: "Query")
    var query: String?

    // Site comes first so text typed right after the quick key filters the
    // dropdown, and `query` MUST stay in the Summary sentence: moving it to the
    // trailing parameter list stops Spotlight offering it inline, which kills
    // one-line search (verified on 26.5). The cost is that the sentence reads
    // "for query" even for a bookmark, which has nothing to search - cosmetic,
    // and there is no way to vary a summary per selected entity.
    static var parameterSummary: some ParameterSummary {
        Summary("Search \(\.$site) for \(\.$query)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let url = try SiteURL.resolve(template: site.template, query: query)
        guard NSWorkspace.shared.open(url) else {
            throw SearchSiteError.openFailed(url.absoluteString)
        }
        return .result()
    }

    /// Kept as the app-facing spelling; the implementation lives in SiteURL so
    /// the MCP server can validate templates without importing AppIntents.
    static func buildURL(template: String, query: String) throws -> URL {
        try SiteURL.build(template: template, query: query)
    }
}

extension SearchSiteError: CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
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

struct SiteSearchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SearchSiteIntent(),
            // Non-parameterized only: per-site phrase expansions were verified
            // NOT to surface as typeable Spotlight actions on macOS 26.5, and
            // the single `ss` action replaces what they were reaching for.
            phrases: ["Search with \(.applicationName)"],
            shortTitle: "Search Site",
            systemImageName: "magnifyingglass"
        )
    }
}
