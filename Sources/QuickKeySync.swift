import Foundation

/// Programmatic Spotlight quick-key setup. Tahoe stores action quick keys in
/// the com.apple.Spotlight preference domain under SSActionKeyboardAliasStoreKey:
///
///   { "com.apple.shortcuts": { "<bundle-id>.<IntentTypeName>": "<abbrev>" } }
///
/// Spotlight observes the domain live (no restart needed; verified on
/// macOS 26.5). The key is UNDOCUMENTED: sync() degrades to a no-op if the
/// shape ever changes.
///
/// Model: a site's KEYWORD is its quick key - one source of truth, edited in
/// the config window. Our entries in the store are derived state mirrored
/// from the config on every launch and save (add/update/prune). Entries
/// belonging to other apps are never touched, and an abbreviation another
/// app's action already claims is never stolen.
enum QuickKeySync {
    static let suite = "com.apple.Spotlight"
    static let storeKey = "SSActionKeyboardAliasStoreKey"
    static let namespace = "com.apple.shortcuts"

    /// Default site id -> its dedicated intent type name.
    static let dedicatedIntentsByID: [String: String] = [
        "9D2C63A0-5B21-4A2E-9C5A-000000000001": "SearchGoogleIntent",
        "9D2C63A0-5B21-4A2E-9C5A-000000000002": "SearchGitHubIntent",
        "9D2C63A0-5B21-4A2E-9C5A-000000000017": "SearchGitHubReposIntent",
    ]

    /// STUB (red): the single-action map this app wants.
    static func desired(bundleID: String) -> [String: String] {
        [:]
    }

    /// The full intent->abbrev map this config wants: the generic action,
    /// the dedicated defaults (keyword tracks config), and one entry per
    /// slotted custom site.
    static func desired(bundleID: String, sites: [Site]) -> [String: String] {
        var map = ["\(bundleID).SearchSiteIntent": "ws"]
        for site in sites {
            let keyword = site.keyword.trimmingCharacters(in: .whitespaces)
            guard !keyword.isEmpty else { continue }
            if let intent = dedicatedIntentsByID[site.id.uuidString] {
                map["\(bundleID).\(intent)"] = keyword
            } else if let slot = site.slot, (1...SiteStore.slotCount).contains(slot) {
                map["\(bundleID).CustomSearch\(slot)Intent"] = keyword
            }
        }
        return map
    }

    /// Pure merge: our entries become exactly `desired` (minus abbreviations
    /// other apps' actions already hold); everything else is preserved.
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

    /// Reads the config and mirrors it into Spotlight's store. Safe to call
    /// often; writes only when something actually changed.
    @discardableResult
    static func sync(bundleID: String = Bundle.main.bundleIdentifier ?? "com.zamua.SiteSearch") -> Bool {
        let existing = CFPreferencesCopyAppValue(storeKey as CFString, suite as CFString) as? [String: Any]
        let want = desired(bundleID: bundleID, sites: SiteStore.load())
        let (store, changed) = merged(existing: existing, desired: want, bundleID: bundleID)
        guard changed else { return false }
        CFPreferencesSetAppValue(storeKey as CFString, store as CFDictionary, suite as CFString)
        CFPreferencesAppSynchronize(suite as CFString)
        return true
    }
}
