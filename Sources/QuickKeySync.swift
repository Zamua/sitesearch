import Foundation

/// Programmatic Spotlight quick-key setup. Tahoe stores action quick keys in
/// the com.apple.Spotlight preference domain under SSActionKeyboardAliasStoreKey:
///
///   { "com.apple.shortcuts": { "<bundle-id>.<IntentTypeName>": "<abbrev>" } }
///
/// Spotlight observes the domain live (no restart needed; verified on
/// macOS 26.5). The key is UNDOCUMENTED: sync() degrades to a no-op if the
/// shape ever changes, and the user can always assign `ss` by hand instead.
///
/// Model: the app registers exactly ONE quick key, `ss`, for its single
/// Search Site action - it does not vary with the config. Site keywords are
/// filter text inside that action's site dropdown, not registered
/// abbreviations, so adding a site needs no write here at all. Entries
/// belonging to other apps are never touched, and an abbreviation another
/// app's action already claims is never stolen.
enum QuickKeySync {
    static let suite = "com.apple.Spotlight"
    static let storeKey = "SSActionKeyboardAliasStoreKey"
    static let namespace = "com.apple.shortcuts"

    /// The quick keys this app asks Spotlight for. Two, because searches and
    /// bookmarks have to be separate actions - see OpenBookmarkIntent.
    static let searchKey = "ss"
    static let bookmarkKey = "sb"

    static func desired(bundleID: String) -> [String: String] {
        [
            "\(bundleID).\(String(describing: SearchSiteIntent.self))": searchKey,
            "\(bundleID).\(String(describing: OpenBookmarkIntent.self))": bookmarkKey,
        ]
    }

    /// Pure merge: our entries become exactly `desired` (minus abbreviations
    /// other apps' actions already hold); everything else is preserved. Any
    /// per-site entry left by 0.4.0-0.7.0 is pruned by the same rule.
    static func merged(existing: [String: Any]?, desired: [String: String], bundleID: String) -> (store: [String: Any], changed: Bool) {
        var store = existing ?? [:]
        let ns = store[namespace] as? [String: String] ?? [:]
        let ourPrefix = "\(bundleID)."

        var next = ns.filter { !$0.key.hasPrefix(ourPrefix) }
        let foreignAbbrevs = Set(next.values.map { $0.lowercased() })
        for (key, abbrev) in desired.sorted(by: { $0.key < $1.key }) where !foreignAbbrevs.contains(abbrev.lowercased()) {
            next[key] = abbrev
        }

        let changed = next != ns
        store[namespace] = next
        return (store, changed)
    }

    /// Registers the quick key. Safe to call often; writes only when something
    /// actually changed.
    @discardableResult
    static func sync(bundleID: String = Bundle.main.bundleIdentifier ?? "com.zamua.SiteSearch") -> Bool {
        let existing = CFPreferencesCopyAppValue(storeKey as CFString, suite as CFString) as? [String: Any]
        let (store, changed) = merged(existing: existing, desired: desired(bundleID: bundleID), bundleID: bundleID)
        guard changed else { return false }
        CFPreferencesSetAppValue(storeKey as CFString, store as CFDictionary, suite as CFString)
        CFPreferencesAppSynchronize(suite as CFString)
        return true
    }
}
