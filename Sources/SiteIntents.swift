import AppIntents
import AppKit

/// One dedicated App Intent per default site, so each appears in Spotlight as
/// its own action ("Search Google", "Search GitHub", ...) with a single
/// query field. That makes the one-line form work per site: assign a quick
/// key (e.g. "g"), then `g my query` + Return runs it.
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
    static let description = IntentDescription("Search GitHub in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search GitHub for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000002", fallbackTemplate: "https://github.com/search?q={query}", query: query)
        return .result()
    }
}

struct SearchWikipediaIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Wikipedia"
    static let description = IntentDescription("Search Wikipedia in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search Wikipedia for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000003", fallbackTemplate: "https://en.wikipedia.org/w/index.php?search={query}", query: query)
        return .result()
    }
}

struct SearchYouTubeIntent: AppIntent {
    static let title: LocalizedStringResource = "Search YouTube"
    static let description = IntentDescription("Search YouTube in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search YouTube for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000004", fallbackTemplate: "https://www.youtube.com/results?search_query={query}", query: query)
        return .result()
    }
}

struct SearchDuckDuckGoIntent: AppIntent {
    static let title: LocalizedStringResource = "Search DuckDuckGo"
    static let description = IntentDescription("Search DuckDuckGo in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search DuckDuckGo for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000005", fallbackTemplate: "https://duckduckgo.com/?q={query}", query: query)
        return .result()
    }
}

struct SearchRedditIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Reddit"
    static let description = IntentDescription("Search Reddit in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search Reddit for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000006", fallbackTemplate: "https://www.reddit.com/search/?q={query}", query: query)
        return .result()
    }
}

struct SearchAmazonIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Amazon"
    static let description = IntentDescription("Search Amazon in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search Amazon for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000007", fallbackTemplate: "https://www.amazon.com/s?k={query}", query: query)
        return .result()
    }
}

struct SearchGoogleMapsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Google Maps"
    static let description = IntentDescription("Search Google Maps in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search Google Maps for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000008", fallbackTemplate: "https://www.google.com/maps/search/{query}", query: query)
        return .result()
    }
}

struct SearchStackOverflowIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Stack Overflow"
    static let description = IntentDescription("Search Stack Overflow in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search Stack Overflow for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000009", fallbackTemplate: "https://stackoverflow.com/search?q={query}", query: query)
        return .result()
    }
}

struct SearchHackerNewsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Hacker News"
    static let description = IntentDescription("Search Hacker News in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search Hacker News for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000010", fallbackTemplate: "https://hn.algolia.com/?q={query}", query: query)
        return .result()
    }
}

struct SearchMDNIntent: AppIntent {
    static let title: LocalizedStringResource = "Search MDN"
    static let description = IntentDescription("Search MDN Web Docs in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search MDN for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000011", fallbackTemplate: "https://developer.mozilla.org/en-US/search?q={query}", query: query)
        return .result()
    }
}

struct SearchNpmIntent: AppIntent {
    static let title: LocalizedStringResource = "Search npm"
    static let description = IntentDescription("Search the npm registry in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search npm for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000012", fallbackTemplate: "https://www.npmjs.com/search?q={query}", query: query)
        return .result()
    }
}

struct SearchPyPIIntent: AppIntent {
    static let title: LocalizedStringResource = "Search PyPI"
    static let description = IntentDescription("Search the Python Package Index in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search PyPI for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000013", fallbackTemplate: "https://pypi.org/search/?q={query}", query: query)
        return .result()
    }
}

struct SearchGoPackagesIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Go Packages"
    static let description = IntentDescription("Search pkg.go.dev in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search Go Packages for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000014", fallbackTemplate: "https://pkg.go.dev/search?q={query}", query: query)
        return .result()
    }
}

struct SearchNixpkgsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search nixpkgs"
    static let description = IntentDescription("Search nixpkgs packages in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search nixpkgs for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000015", fallbackTemplate: "https://search.nixos.org/packages?query={query}", query: query)
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

struct SearchIMDbIntent: AppIntent {
    static let title: LocalizedStringResource = "Search IMDb"
    static let description = IntentDescription("Search IMDb in your default browser.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search IMDb for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SiteIntentRunner.run(siteID: "9D2C63A0-5B21-4A2E-9C5A-000000000016", fallbackTemplate: "https://www.imdb.com/find/?q={query}", query: query)
        return .result()
    }
}
