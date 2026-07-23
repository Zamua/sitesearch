import Foundation

/// Programmatic Spotlight quick-key setup. Tahoe stores action quick keys in
/// the com.apple.Spotlight preference domain under SSActionKeyboardAliasStoreKey:
///
///   { "com.apple.shortcuts": { "<bundle-id>.<IntentTypeName>": "<abbrev>" } }
///
/// Spotlight observes the domain live (no restart needed; verified on
/// macOS 26.5). The key is UNDOCUMENTED: sync() no-ops gracefully if the
/// shape ever changes, and never overwrites or steals existing assignments.
enum QuickKeySync {
    static let suite = "com.apple.Spotlight"
    static let storeKey = "SSActionKeyboardAliasStoreKey"
    static let namespace = "com.apple.shortcuts"

    /// Intent type name -> suggested quick key (the site keywords).
    static let suggested: [String: String] = [
        "SearchSiteIntent": "ws",
        "SearchGoogleIntent": "g",
        "SearchGitHubIntent": "gh",
        "SearchGitHubReposIntent": "repo",
        "SearchWikipediaIntent": "w",
        "SearchYouTubeIntent": "yt",
        "SearchDuckDuckGoIntent": "ddg",
        "SearchRedditIntent": "r",
        "SearchAmazonIntent": "a",
        "SearchGoogleMapsIntent": "gm",
        "SearchStackOverflowIntent": "so",
        "SearchHackerNewsIntent": "hn",
        "SearchMDNIntent": "mdn",
        "SearchNpmIntent": "npm",
        "SearchPyPIIntent": "pypi",
        "SearchGoPackagesIntent": "go",
        "SearchNixpkgsIntent": "nix",
        "SearchIMDbIntent": "imdb",
    ]

    /// Pure merge: adds suggestions for intents that have no assignment yet,
    /// skipping abbreviations already claimed by anything else. Never mutates
    /// existing entries.
    static func merged(existing: [String: Any]?, bundleID: String) -> (store: [String: Any], added: Int) {
        var store = existing ?? [:]
        var ns = store[namespace] as? [String: String] ?? [:]
        var taken = Set(ns.values.map { $0.lowercased() })
        var added = 0
        for (intent, quickKey) in suggested.sorted(by: { $0.key < $1.key }) {
            let fullKey = "\(bundleID).\(intent)"
            guard ns[fullKey] == nil, !taken.contains(quickKey.lowercased()) else { continue }
            ns[fullKey] = quickKey
            taken.insert(quickKey.lowercased())
            added += 1
        }
        store[namespace] = ns
        return (store, added)
    }

    /// Writes the merged store through cfprefsd. Returns how many quick keys
    /// were added (0 = everything was already assigned).
    @discardableResult
    static func sync(bundleID: String = Bundle.main.bundleIdentifier ?? "com.zamua.SiteSearch") -> Int {
        let existing = CFPreferencesCopyAppValue(storeKey as CFString, suite as CFString) as? [String: Any]
        let (store, added) = merged(existing: existing, bundleID: bundleID)
        guard added > 0 else { return 0 }
        CFPreferencesSetAppValue(storeKey as CFString, store as CFDictionary, suite as CFString)
        CFPreferencesAppSynchronize(suite as CFString)
        return added
    }
}
