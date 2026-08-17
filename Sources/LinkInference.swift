import Foundation

/// Port: given a pasted URL, propose a site entry. Adapters are tried in
/// order and the first that recognizes the link wins; a link nobody claims
/// yields nil and the caller falls back to its blank-row behavior. Pure
/// string work only - inference must never touch the network, since it runs
/// on every paste.
protocol LinkInferrer: Sendable {
    func infer(from url: URL) -> InferredSite?
}

struct InferredSite: Equatable {
    var name: String
    var keyword: String
    var template: String
}

enum LinkInference {
    /// Adapter order matters only when hosts overlap; today they don't.
    static let inferrers: [LinkInferrer] = [GitHubRepoInferrer()]

    static func infer(from text: String) -> InferredSite? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        for inferrer in inferrers {
            if let hit = inferrer.infer(from: url) { return hit }
        }
        return nil
    }
}

/// github.com/<owner>/<repo>[/...] becomes a BOOKMARK of the repo page:
/// the repo name is both display name and keyword, and the template is the
/// repo URL with no {query} - so it lands in the `sb` action and opens
/// directly. Non-repo GitHub paths (orgs, gists, marketplace, search itself)
/// are declined rather than guessed at.
struct GitHubRepoInferrer: LinkInferrer {
    private static let nonRepoOwners: Set<String> = [
        "features", "topics", "collections", "trending", "marketplace",
        "sponsors", "settings", "notifications", "explore", "search",
        "orgs", "apps", "about", "pricing", "login", "join",
    ]

    func infer(from url: URL) -> InferredSite? {
        guard url.host?.lowercased() == "github.com" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        var repo = parts[1]
        guard !Self.nonRepoOwners.contains(owner.lowercased()) else { return nil }
        if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        guard !repo.isEmpty else { return nil }
        return InferredSite(
            name: repo,
            keyword: repo.lowercased(),
            template: "https://github.com/\(owner)/\(repo)"
        )
    }
}
