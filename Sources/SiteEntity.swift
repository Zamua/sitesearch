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
        DisplayRepresentation(title: "\(name)", subtitle: "\(keyword)", image: icon)
    }

    /// The site's cached favicon if we have one, else a neutral glyph. Read
    /// from disk synchronously and deliberately: this is called while Spotlight
    /// draws the list, so it must never touch the network.
    private var icon: DisplayRepresentation.Image {
        if let id = UUID(uuidString: id), let data = Favicon.cachedData(for: id) {
            return DisplayRepresentation.Image(data: data)
        }
        return DisplayRepresentation.Image(systemName: "magnifyingglass")
    }
}

/// The site list is small and bounded, so EnumerableEntityQuery is the right
/// query shape: allEntities() feeds the full dropdown and Spotlight's
/// type-to-filter works over it for free. entities(matching:) additionally
/// lets the keyword alias match, not just the display name.
struct SiteEntityQuery: EnumerableEntityQuery, EntityStringQuery {
    func allEntities() async throws -> [SiteEntity] {
        Site.searches(SiteStore.load()).map(SiteEntity.init)
    }

    func entities(for identifiers: [String]) async throws -> [SiteEntity] {
        let ids = Set(identifiers)
        return SiteStore.load().map(SiteEntity.init).filter { ids.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SiteEntity] {
        try await allEntities()
    }

    /// The filter behind entities(matching:), extracted as a pure function so
    /// it is unit-testable. A site matches on a name substring or a keyword
    /// prefix - the keyword is how you pick a site once `ss` is running, so
    /// prefix matching is what makes `ss hn` land on Hacker News.
    static func filter(_ sites: [Site], matching needle: String) -> [Site] {
        let needle = needle.lowercased()
        guard !needle.isEmpty else { return sites }
        return sites.filter {
            $0.name.lowercased().contains(needle) || $0.keyword.lowercased().hasPrefix(needle)
        }
    }

    static func matches(_ sites: [Site], _ needle: String) -> Bool {
        !filter(sites, matching: needle).isEmpty
    }

    func entities(matching string: String) async throws -> [SiteEntity] {
        Self.filter(Site.searches(SiteStore.load()), matching: string).map(SiteEntity.init)
    }
}

/// A saved URL with nothing to substitute. Deliberately a separate entity type
/// from SiteEntity: an entity's dropdown comes from its `defaultQuery`, so two
/// kinds of list means two types. That is what lets "Open Bookmark" offer only
/// bookmarks and skip the query parameter entirely.
struct BookmarkEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bookmark")
    static let defaultQuery = BookmarkEntityQuery()

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
        DisplayRepresentation(title: "\(name)", subtitle: "\(keyword)", image: icon)
    }

    private var icon: DisplayRepresentation.Image {
        if let id = UUID(uuidString: id), let data = Favicon.cachedData(for: id) {
            return DisplayRepresentation.Image(data: data)
        }
        return DisplayRepresentation.Image(systemName: "bookmark")
    }
}

struct BookmarkEntityQuery: EnumerableEntityQuery, EntityStringQuery {
    func allEntities() async throws -> [BookmarkEntity] {
        Site.bookmarks(SiteStore.load()).map(BookmarkEntity.init)
    }

    func entities(for identifiers: [String]) async throws -> [BookmarkEntity] {
        let ids = Set(identifiers)
        return SiteStore.load().map(BookmarkEntity.init).filter { ids.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BookmarkEntity] {
        try await allEntities()
    }

    func entities(matching string: String) async throws -> [BookmarkEntity] {
        SiteEntityQuery.filter(Site.bookmarks(SiteStore.load()), matching: string).map(BookmarkEntity.init)
    }
}
