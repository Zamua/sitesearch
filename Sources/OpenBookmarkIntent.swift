import AppIntents
import AppKit

/// Opens a saved URL. Separate from SearchSiteIntent because Spotlight cannot
/// vary a `parameterSummary` per selected entity, and every attempt to make one
/// action serve both kinds failed on 26.5:
///
///   query as String?        -> field renders red, refuses an empty submit
///   query out of Summary    -> not offered inline, killing one-line search
///   query with default: ""  -> Spotlight's inline UI blanks and hangs on Tab
///
/// With two actions each summary is honest, and a bookmark simply has no query
/// parameter to demand: `sb repo1` + Return.
struct OpenBookmarkIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Bookmark"
    static let description = IntentDescription("Open a saved URL in your default browser.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Bookmark")
    var bookmark: BookmarkEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$bookmark)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Resolve from the live config by id so an edited URL is honored, and
        // fall back to the entity's own copy if it has since been removed.
        let template = SiteStore.load().first { $0.id.uuidString == bookmark.id }?.template ?? bookmark.template
        let url = try SiteURL.resolve(template: template, query: nil)
        guard NSWorkspace.shared.open(url) else {
            throw SearchSiteError.openFailed(url.absoluteString)
        }
        return .result()
    }
}
