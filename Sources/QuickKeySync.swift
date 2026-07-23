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
        "SearchGoogleIntent": "google",
        "SearchGitHubIntent": "code",
        "SearchGitHubReposIntent": "repo",
    ]

    /// Pure merge: adds suggestions for intents that have no assignment yet,
    /// skipping abbreviations already claimed by anything else, and prunes
    /// OUR bundle's entries that point at intents this build no longer ships
    /// (so a shrunk default set does not leave dead quick keys behind).
    /// Never mutates entries belonging to other apps.
    static func merged(existing: [String: Any]?, bundleID: String) -> (store: [String: Any], added: Int, pruned: Int) {
        var store = existing ?? [:]
        var ns = store[namespace] as? [String: String] ?? [:]

        let ourPrefix = "\(bundleID)."
        let validOurKeys = Set(suggested.keys.map { ourPrefix + $0 })
        var pruned = 0
        for key in ns.keys where key.hasPrefix(ourPrefix) && !validOurKeys.contains(key) {
            ns.removeValue(forKey: key)
            pruned += 1
        }

        var taken = Set(ns.values.map { $0.lowercased() })
        var added = 0
        for (intent, quickKey) in suggested.sorted(by: { $0.key < $1.key }) {
            let fullKey = ourPrefix + intent
            guard ns[fullKey] == nil, !taken.contains(quickKey.lowercased()) else { continue }
            ns[fullKey] = quickKey
            taken.insert(quickKey.lowercased())
            added += 1
        }
        store[namespace] = ns
        return (store, added, pruned)
    }

    /// Writes the merged store through cfprefsd. Returns how many quick keys
    /// were added (0 = everything was already assigned).
    @discardableResult
    static func sync(bundleID: String = Bundle.main.bundleIdentifier ?? "com.zamua.SiteSearch") -> Int {
        let existing = CFPreferencesCopyAppValue(storeKey as CFString, suite as CFString) as? [String: Any]
        let (store, added, pruned) = merged(existing: existing, bundleID: bundleID)
        guard added > 0 || pruned > 0 else { return 0 }
        CFPreferencesSetAppValue(storeKey as CFString, store as CFDictionary, suite as CFString)
        CFPreferencesAppSynchronize(suite as CFString)
        return added
    }
}
