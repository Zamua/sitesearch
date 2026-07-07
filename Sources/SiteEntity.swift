import AppIntents

/// The Spotlight-facing representation of a configured site. Spotlight shows
/// these as the dropdown for the intent's "site" parameter and filters them
/// as the user types.
struct SiteEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Website")
    static let defaultQuery = SiteEntityQuery()

    var id: String
    var keyword: String
    var name: String
    var template: String

    init(site: Site) {
        self.id = site.id.uuidString
        self.keyword = site.keyword
        self.name = site.name
        self.template = site.template
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(keyword)")
    }
}

/// The site list is small and bounded, so EnumerableEntityQuery is the right
/// query shape: allEntities() feeds the full dropdown and Spotlight's
/// type-to-filter works over it for free. entities(matching:) additionally
/// lets the keyword alias match, not just the display name.
struct SiteEntityQuery: EntityQuery, EnumerableEntityQuery, EntityStringQuery {
    func allEntities() async throws -> [SiteEntity] {
        SiteStore.load().map(SiteEntity.init)
    }

    func entities(for identifiers: [String]) async throws -> [SiteEntity] {
        let ids = Set(identifiers)
        return SiteStore.load().map(SiteEntity.init).filter { ids.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SiteEntity] {
        try await allEntities()
    }

    func entities(matching string: String) async throws -> [SiteEntity] {
        let needle = string.lowercased()
        return SiteStore.load().map(SiteEntity.init).filter {
            $0.name.lowercased().contains(needle) || $0.keyword.lowercased().hasPrefix(needle)
        }
    }
}
