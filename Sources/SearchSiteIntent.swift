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

    // Required, and it must stay that way. Three variants were tried on 26.5
    // so a bookmark could share this action; all failed (see CLAUDE.md):
    //   String?          -> field renders red, refuses an empty submit
    //   out of Summary   -> not offered inline at all, killing one-line search
    //   default: ""      -> Spotlight's inline UI blanks and hangs on Tab
    // Bookmarks get their own action instead: OpenBookmarkIntent.
    @Parameter(title: "Query")
    var query: String

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
}

/// Spotlight shows an intent's error through this conformance; the text
/// itself lives on `SearchSiteError` so the MCP server reads the same words.
extension SearchSiteError: CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "\(errorDescription ?? "Search failed.")"
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
