import AppIntents
import AppKit

/// Pre-compiled "slot" intents that give runtime-created sites their own
/// Spotlight actions. Spotlight can only surface compile-time intent types,
/// so the app ships 20 generic slots; SiteStore assigns each custom site the
/// lowest free slot and QuickKeySync binds the site's keyword to that slot's
/// action. Typing `keyword query` then works one-line, exactly like the
/// dedicated defaults. The visible action title is generic ("Custom Search
/// N") - Apple offers no way to rename an action at runtime - but the quick
/// key badge and the site it opens are the user's own.
@MainActor
enum SlotIntentRunner {
    static func run(slot: Int, query: String) throws {
        guard let site = SiteStore.load().first(where: { $0.slot == slot }) else {
            throw SearchSiteError.slotEmpty(slot)
        }
        let url = try SearchSiteIntent.buildURL(template: site.template, query: query)
        guard NSWorkspace.shared.open(url) else {
            throw SearchSiteError.openFailed(url.absoluteString)
        }
    }
}

struct CustomSearch1Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 1"
    static let description = IntentDescription("Runs the custom site search assigned to slot 1.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 1, query: query)
        return .result()
    }
}

struct CustomSearch2Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 2"
    static let description = IntentDescription("Runs the custom site search assigned to slot 2.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 2, query: query)
        return .result()
    }
}

struct CustomSearch3Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 3"
    static let description = IntentDescription("Runs the custom site search assigned to slot 3.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 3, query: query)
        return .result()
    }
}

struct CustomSearch4Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 4"
    static let description = IntentDescription("Runs the custom site search assigned to slot 4.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 4, query: query)
        return .result()
    }
}

struct CustomSearch5Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 5"
    static let description = IntentDescription("Runs the custom site search assigned to slot 5.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 5, query: query)
        return .result()
    }
}

struct CustomSearch6Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 6"
    static let description = IntentDescription("Runs the custom site search assigned to slot 6.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 6, query: query)
        return .result()
    }
}

struct CustomSearch7Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 7"
    static let description = IntentDescription("Runs the custom site search assigned to slot 7.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 7, query: query)
        return .result()
    }
}

struct CustomSearch8Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 8"
    static let description = IntentDescription("Runs the custom site search assigned to slot 8.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 8, query: query)
        return .result()
    }
}

struct CustomSearch9Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 9"
    static let description = IntentDescription("Runs the custom site search assigned to slot 9.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 9, query: query)
        return .result()
    }
}

struct CustomSearch10Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 10"
    static let description = IntentDescription("Runs the custom site search assigned to slot 10.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 10, query: query)
        return .result()
    }
}

struct CustomSearch11Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 11"
    static let description = IntentDescription("Runs the custom site search assigned to slot 11.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 11, query: query)
        return .result()
    }
}

struct CustomSearch12Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 12"
    static let description = IntentDescription("Runs the custom site search assigned to slot 12.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 12, query: query)
        return .result()
    }
}

struct CustomSearch13Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 13"
    static let description = IntentDescription("Runs the custom site search assigned to slot 13.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 13, query: query)
        return .result()
    }
}

struct CustomSearch14Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 14"
    static let description = IntentDescription("Runs the custom site search assigned to slot 14.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 14, query: query)
        return .result()
    }
}

struct CustomSearch15Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 15"
    static let description = IntentDescription("Runs the custom site search assigned to slot 15.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 15, query: query)
        return .result()
    }
}

struct CustomSearch16Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 16"
    static let description = IntentDescription("Runs the custom site search assigned to slot 16.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 16, query: query)
        return .result()
    }
}

struct CustomSearch17Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 17"
    static let description = IntentDescription("Runs the custom site search assigned to slot 17.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 17, query: query)
        return .result()
    }
}

struct CustomSearch18Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 18"
    static let description = IntentDescription("Runs the custom site search assigned to slot 18.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 18, query: query)
        return .result()
    }
}

struct CustomSearch19Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 19"
    static let description = IntentDescription("Runs the custom site search assigned to slot 19.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 19, query: query)
        return .result()
    }
}

struct CustomSearch20Intent: AppIntent {
    static let title: LocalizedStringResource = "Custom Search 20"
    static let description = IntentDescription("Runs the custom site search assigned to slot 20.")
    static let supportedModes: IntentModes = .background
    @Parameter(title: "Query") var query: String
    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$query)") }
    @MainActor func perform() async throws -> some IntentResult {
        try SlotIntentRunner.run(slot: 20, query: query)
        return .result()
    }
}

