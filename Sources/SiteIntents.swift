import AppIntents
import AppKit

/// One dedicated App Intent per default site, so each appears in Spotlight as
/// its own action with a single query field. Assign a quick key and the
/// one-line form works per site: `repo my query` + Return.
///
/// App Intents must be concrete compile-time types (Spotlight discovers them
/// from build-time metadata), so only the built-in defaults get dedicated
/// actions; user-added sites are reachable via the generic "Search Site"
/// intent. Each intent resolves its template from the live config by site id
/// (so edits to a default's URL are honored) and falls back to the built-in
/// template if that site was deleted from the config.
@MainActor
enum SiteIntentRunner {
    static func run(siteID: String, fallbackTemplate: String, query: String) throws {
        let template = SiteStore.load().first { $0.id.uuidString == siteID }?.template ?? fallbackTemplate
        let url = try SearchSiteIntent.buildURL(template: template, query: query)
        guard NSWorkspace.shared.open(url) else {
            throw SearchSiteError.openFailed(url.absoluteString)
        }
    }
}

struct SearchGoogleIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Google"
    static let description = IntentDescription("Search Google in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search Google for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000001", fallbackTemplate: "https://www.google.com/search?q={query}", query: query)
        return .result()
    }
}

struct SearchGitHubIntent: AppIntent {
    static let title: LocalizedStringResource = "Search GitHub"
    static let description = IntentDescription("Search all of GitHub in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search GitHub for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000002", fallbackTemplate: "https://github.com/search?q={query}", query: query)
        return .result()
    }
}

struct SearchGitHubReposIntent: AppIntent {
    static let title: LocalizedStringResource = "Search GitHub Repos"
    static let description = IntentDescription("Search GitHub repositories by name in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search GitHub Repos for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000017", fallbackTemplate: "https://github.com/search?q={query}&type=repositories", query: query)
        return .result()
    }
}
