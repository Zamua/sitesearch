import AppIntents

/// What both Spotlight entity types share: each is a projection of one
/// configured site, shown with its cached favicon. They stay separate types
/// because a dropdown comes from the entity's `defaultQuery`, so two kinds of
/// list means two types; that is what lets "Open Bookmark" offer only
/// bookmarks and skip the query parameter.
protocol SiteBackedEntity: AppEntity where ID == String {
    var id: String { get }
    var keyword: String { get }
    var name: String { get }
    var template: String { get }
    init(id: String, keyword: String, name: String, template: String)
    /// The sites this entity's dropdown lists.
    static func listed(in sites: [Site]) -> [Site]
    /// Shown when the site has no cached favicon.
    static var fallbackSymbol: String { get }
}

extension SiteBackedEntity {
    init(site: Site) {
        self.init(id: site.id.uuidString, keyword: site.keyword, name: site.name, template: site.template)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(keyword)", image: icon)
    }

    /// Read from disk synchronously and deliberately: Spotlight calls this
    /// while drawing the list, so it must never touch the network.
    private var icon: DisplayRepresentation.Image {
        if let id = UUID(uuidString: id),
           let data = Favicon.cachedData(for: Site(id: id, keyword: keyword, name: name, template: template)) {
            return DisplayRepresentation.Image(data: data)
        }
        return DisplayRepresentation.Image(systemName: Self.fallbackSymbol)
    }
}

/// A searchable site: the `ss` action's dropdown.
struct SiteEntity: SiteBackedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Website")
    static let defaultQuery = SiteEntityQuery()
    static let fallbackSymbol = "magnifyingglass"
    static func listed(in sites: [Site]) -> [Site] { Site.searches(sites) }

    var id: String
    var keyword: String
    var name: String
    var template: String
}

/// A saved URL with nothing to substitute: the `sb` action's dropdown.
struct BookmarkEntity: SiteBackedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bookmark")
    static let defaultQuery = BookmarkEntityQuery()
    static let fallbackSymbol = "bookmark"
    static func listed(in sites: [Site]) -> [Site] { Site.bookmarks(sites) }

    var id: String
    var keyword: String
    var name: String
    var template: String
}

/// The site list is small and bounded, so EnumerableEntityQuery is the right
/// query shape: allEntities() feeds the full dropdown and Spotlight's
/// type-to-filter works over it. entities(matching:) additionally lets the
/// keyword alias match, not just the display name. Every call reads the file
/// fresh, so a site added behind the app's back shows up immediately.
protocol SiteBackedQuery: EnumerableEntityQuery, EntityStringQuery where Entity: SiteBackedEntity {}

extension SiteBackedQuery {
    func allEntities() async throws -> [Entity] {
        Entity.listed(in: SiteStore.load()).map(Entity.init(site:))
    }

    func entities(for identifiers: [String]) async throws -> [Entity] {
        let ids = Set(identifiers)
        return SiteStore.load().map(Entity.init(site:)).filter { ids.contains($0.id) }
    }

    func suggestedEntities() async throws -> [Entity] {
        try await allEntities()
    }

    func entities(matching string: String) async throws -> [Entity] {
        Self.filter(Entity.listed(in: SiteStore.load()), matching: string).map(Entity.init(site:))
    }

    /// A site matches on a name substring or a keyword prefix: the keyword is
    /// how you pick a site once `ss` is running, so prefix matching is what
    /// makes `ss hn` land on Hacker News.
    static func filter(_ sites: [Site], matching needle: String) -> [Site] {
        let needle = needle.lowercased()
        guard !needle.isEmpty else { return sites }
        return sites.filter {
            $0.name.lowercased().contains(needle) || $0.keyword.lowercased().hasPrefix(needle)
        }
    }
}

struct SiteEntityQuery: SiteBackedQuery {
    typealias Entity = SiteEntity
}

struct BookmarkEntityQuery: SiteBackedQuery {
    typealias Entity = BookmarkEntity
}
