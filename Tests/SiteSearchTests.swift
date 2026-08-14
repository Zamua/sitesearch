import XCTest
@testable import SiteSearch

final class BuildURLTests: XCTestCase {
    func testSpacesArePercentEncoded() throws {
        let url = try SearchSiteIntent.buildURL(template: "https://example.com/s?q={query}", query: "hello world")
        XCTAssertEqual(url.absoluteString, "https://example.com/s?q=hello%20world")
    }

    func testReservedCharactersAreEncoded() throws {
        let url = try SearchSiteIntent.buildURL(template: "https://example.com/s?q={query}", query: "c++ & a=b?")
        XCTAssertEqual(url.absoluteString, "https://example.com/s?q=c%2B%2B%20%26%20a%3Db%3F")
    }

    func testNonASCIIIsEncoded() throws {
        let url = try SearchSiteIntent.buildURL(template: "https://example.com/s?q={query}", query: "café")
        XCTAssertEqual(url.absoluteString, "https://example.com/s?q=caf%C3%A9")
    }

    func testUnreservedCharactersPassThrough() throws {
        let url = try SearchSiteIntent.buildURL(template: "https://example.com/s?q={query}", query: "a-b_c.d~e")
        XCTAssertEqual(url.absoluteString, "https://example.com/s?q=a-b_c.d~e")
    }

    func testMissingPlaceholderThrows() {
        XCTAssertThrowsError(try SearchSiteIntent.buildURL(template: "https://example.com/s?q=", query: "x")) { error in
            guard case SearchSiteError.missingPlaceholder = error else {
                return XCTFail("expected missingPlaceholder, got \(error)")
            }
        }
    }

    func testNonHTTPSchemeThrows() {
        XCTAssertThrowsError(try SearchSiteIntent.buildURL(template: "file:///tmp/{query}", query: "x")) { error in
            guard case SearchSiteError.invalidURL = error else {
                return XCTFail("expected invalidURL, got \(error)")
            }
        }
    }

    func testUppercaseSchemeAccepted() throws {
        let url = try SearchSiteIntent.buildURL(template: "HTTPS://example.com/s?q={query}", query: "x")
        XCTAssertEqual(url.scheme?.lowercased(), "https")
    }
}

/// The app registers exactly ONE Spotlight quick key - `ss` for the single
/// Search Site action. Site keywords are filter text inside that action's
/// entity dropdown, not registered abbreviations, so the quick-key store no
/// longer varies with the config.
final class QuickKeySyncTests: XCTestCase {
    let bundle = "com.zamua.SiteSearch"

    func testDesiredIsExactlyTheSingleSearchAction() {
        XCTAssertEqual(QuickKeySync.desired(bundleID: bundle),
                       ["\(bundle).SearchSiteIntent": "ss"])
    }

    func testMergeInstallsOnlyOurSingleEntry() {
        let want = QuickKeySync.desired(bundleID: bundle)
        let (store, changed) = QuickKeySync.merged(existing: nil, desired: want, bundleID: bundle)
        XCTAssertTrue(changed)
        XCTAssertEqual(store[QuickKeySync.namespace] as? [String: String],
                       ["\(bundle).SearchSiteIntent": "ss"])
    }

    /// Upgrade path: installs from 0.4.0-0.7.0 left per-site dedicated and
    /// slot entries behind. They must be pruned, not inherited.
    func testLegacyDedicatedAndSlotEntriesArePruned() {
        let want = QuickKeySync.desired(bundleID: bundle)
        let existing: [String: Any] = [QuickKeySync.namespace: [
            "\(bundle).SearchSiteIntent": "ws",
            "\(bundle).SearchGoogleIntent": "google",
            "\(bundle).SearchGitHubIntent": "code",
            "\(bundle).CustomSearch3Intent": "hn",
            "com.other.app.SomeIntent": "zz",
        ]]
        let (store, changed) = QuickKeySync.merged(existing: existing, desired: want, bundleID: bundle)
        let ns = store[QuickKeySync.namespace] as? [String: String]
        XCTAssertTrue(changed)
        XCTAssertEqual(ns?["\(bundle).SearchSiteIntent"], "ss", "single action should be registered as ss")
        XCTAssertNil(ns?["\(bundle).SearchGoogleIntent"], "legacy dedicated entry survived")
        XCTAssertNil(ns?["\(bundle).CustomSearch3Intent"], "legacy slot entry survived")
        XCTAssertEqual(ns?["com.other.app.SomeIntent"], "zz", "other app's entry touched")
    }

    func testForeignOwnerOfSSIsNotRobbed() {
        let want = QuickKeySync.desired(bundleID: bundle)
        let existing: [String: Any] = [QuickKeySync.namespace: ["com.other.app.SomeIntent": "ss"]]
        let (store, _) = QuickKeySync.merged(existing: existing, desired: want, bundleID: bundle)
        let ns = store[QuickKeySync.namespace] as? [String: String]
        XCTAssertNil(ns?["\(bundle).SearchSiteIntent"], "stole an abbreviation another action owns")
        XCTAssertEqual(ns?["com.other.app.SomeIntent"], "ss")
    }

    func testMergeIsIdempotent() {
        let want = QuickKeySync.desired(bundleID: bundle)
        let (once, changedOnce) = QuickKeySync.merged(existing: nil, desired: want, bundleID: bundle)
        let (twice, changedTwice) = QuickKeySync.merged(existing: once, desired: want, bundleID: bundle)
        XCTAssertTrue(changedOnce)
        XCTAssertFalse(changedTwice)
        XCTAssertEqual(once[QuickKeySync.namespace] as? [String: String],
                       twice[QuickKeySync.namespace] as? [String: String])
    }
}

/// Configs written by 0.4.0-0.7.0 carry a per-site `slot`. Reading one must
/// keep working, and rewriting it must drop the dead field.
final class SiteMigrationTests: XCTestCase {
    private let legacyJSON = """
    [{"id":"9D2C63A0-5B21-4A2E-9C5A-000000000099","keyword":"hn","name":"Hacker News","template":"https://hn.algolia.com/?q={query}","slot":3}]
    """

    func testLegacyConfigWithSlotFieldStillDecodes() throws {
        let sites = try JSONDecoder().decode([Site].self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(sites.count, 1)
        XCTAssertEqual(sites.first?.keyword, "hn")
        XCTAssertEqual(sites.first?.template, "https://hn.algolia.com/?q={query}")
    }

    func testResavingLegacyConfigDropsTheSlotField() throws {
        let sites = try JSONDecoder().decode([Site].self, from: Data(legacyJSON.utf8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let round = String(decoding: try encoder.encode(sites), as: UTF8.self)
        XCTAssertFalse(round.contains("slot"), "slot should no longer be persisted")
    }
}

final class SiteExchangeTests: XCTestCase {
    func testExportParseRoundtrip() throws {
        let data = try SiteExchange.export(SiteStore.defaults)
        let entries = try SiteExchange.parse(data)
        XCTAssertEqual(entries.map(\.name), SiteStore.defaults.map(\.name))
        XCTAssertEqual(entries.map(\.template), SiteStore.defaults.map(\.template))
    }

    func testUnsupportedVersionThrows() {
        let data = Data(#"{"version": 99, "sites": []}"#.utf8)
        XCTAssertThrowsError(try SiteExchange.parse(data))
    }

    func testMergeSkipsExactDuplicates() {
        let entries = [SiteExchange.Entry(name: "Google", keyword: "google", template: "https://www.google.com/search?q={query}")]
        let (result, added) = SiteExchange.merge(entries, into: SiteStore.defaults)
        XCTAssertEqual(added, 0)
        XCTAssertEqual(result.count, SiteStore.defaults.count)
    }

    func testMergeSuffixesCollidingKeywords() {
        let entries = [SiteExchange.Entry(name: "My Google", keyword: "google", template: "https://google.example/{query}")]
        let (result, added) = SiteExchange.merge(entries, into: SiteStore.defaults)
        XCTAssertEqual(added, 1)
        XCTAssertEqual(result.last?.keyword, "google2", "colliding keyword should get a numeric suffix")
    }

    func testMergeMintsFreshIDs() {
        let entries = [SiteExchange.Entry(name: "New Site", keyword: "ns", template: "https://ns.example/?q={query}")]
        let (result, _) = SiteExchange.merge(entries, into: SiteStore.defaults)
        let newSite = result.last!
        XCTAssertFalse(SiteStore.defaults.map(\.id).contains(newSite.id))
    }
}

final class DefaultSitesTests: XCTestCase {
    func testIDsAreUnique() {
        let ids = SiteStore.defaults.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate default site ids")
    }

    func testKeywordsAreUniqueAndNonEmpty() {
        let keywords = SiteStore.defaults.map(\.keyword)
        XCTAssertEqual(keywords.count, Set(keywords).count, "duplicate default keywords")
        XCTAssertFalse(keywords.contains(""), "empty default keyword")
    }

    func testEveryTemplateHasPlaceholderAndHTTPS() {
        for site in SiteStore.defaults {
            XCTAssertTrue(site.template.contains("{query}"), "\(site.name) template missing {query}")
            XCTAssertTrue(site.template.hasPrefix("https://"), "\(site.name) template not https")
        }
    }

    func testEveryDefaultBuildsAValidURL() throws {
        for site in SiteStore.defaults {
            let url = try SearchSiteIntent.buildURL(template: site.template, query: "hello world")
            XCTAssertNotNil(url.host, "\(site.name) built URL without a host")
        }
    }

    func testScriptListMatchesDefaults() throws {
        // scripts/e2e-sites.sh carries a copy of the templates for live
        // verification; fail if the two lists drift.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("scripts/e2e-sites.sh"), encoding: .utf8)
        for site in SiteStore.defaults {
            XCTAssertTrue(script.contains(site.template), "scripts/e2e-sites.sh missing template for \(site.name)")
        }
    }
}

/// The whole point of dropping slots: a site added behind the app's back (an
/// agent writing sites.json, an import) is searchable with no slot
/// allocation, no quick-key write, and no relaunch.
final class RuntimeSiteVisibilityTests: XCTestCase {
    func testAnyStoredSiteBecomesAnEntityWithoutSetup() async throws {
        let added = Site(keyword: "hn", name: "Hacker News", template: "https://hn.algolia.com/?q={query}")
        let entities = ([added] + SiteStore.defaults).map(SiteEntity.init)
        XCTAssertEqual(entities.first?.id, added.id.uuidString)
        XCTAssertEqual(entities.first?.keyword, "hn")
    }

    func testKeywordPrefixAndNameSubstringBothMatch() {
        let sites = [Site(keyword: "hn", name: "Hacker News", template: "https://hn.algolia.com/?q={query}")]
        XCTAssertTrue(SiteEntityQuery.matches(sites, "hn"), "keyword prefix should match")
        XCTAssertTrue(SiteEntityQuery.matches(sites, "hacker"), "name substring should match")
        XCTAssertFalse(SiteEntityQuery.matches(sites, "zzz"))
    }
}
