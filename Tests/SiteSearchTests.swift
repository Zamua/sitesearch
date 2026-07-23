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

final class QuickKeySyncTests: XCTestCase {
    let bundle = "com.zamua.SiteSearch"

    func testEmptyStoreGetsAllSuggestions() {
        let (store, added, _) = QuickKeySync.merged(existing: nil, bundleID: bundle)
        XCTAssertEqual(added, QuickKeySync.suggested.count)
        let ns = store[QuickKeySync.namespace] as? [String: String]
        XCTAssertEqual(ns?["\(bundle).SearchGitHubReposIntent"], "repo")
        XCTAssertEqual(ns?["\(bundle).SearchGitHubIntent"], "code")
        XCTAssertEqual(ns?["\(bundle).SearchGoogleIntent"], "google")
    }

    func testExistingAssignmentIsNeverOverwritten() {
        let existing: [String: Any] = [QuickKeySync.namespace: ["\(bundle).SearchGoogleIntent": "goog"]]
        let (store, _, _) = QuickKeySync.merged(existing: existing, bundleID: bundle)
        let ns = store[QuickKeySync.namespace] as? [String: String]
        XCTAssertEqual(ns?["\(bundle).SearchGoogleIntent"], "goog", "user's custom key was clobbered")
    }

    func testClaimedAbbreviationIsNotStolen() {
        let existing: [String: Any] = [QuickKeySync.namespace: ["com.other.app.SomeIntent": "code"]]
        let (store, _, _) = QuickKeySync.merged(existing: existing, bundleID: bundle)
        let ns = store[QuickKeySync.namespace] as? [String: String]
        XCTAssertNil(ns?["\(bundle).SearchGitHubIntent"], "stole an abbreviation another action owns")
        XCTAssertEqual(ns?["com.other.app.SomeIntent"], "code")
    }

    func testStaleOwnEntriesArePruned() {
        let existing: [String: Any] = [QuickKeySync.namespace: [
            "\(bundle).SearchYouTubeIntent": "yt",
            "com.other.app.SomeIntent": "zz",
        ]]
        let (store, _, pruned) = QuickKeySync.merged(existing: existing, bundleID: bundle)
        let ns = store[QuickKeySync.namespace] as? [String: String]
        XCTAssertEqual(pruned, 1)
        XCTAssertNil(ns?["\(bundle).SearchYouTubeIntent"], "stale entry for removed intent kept")
        XCTAssertEqual(ns?["com.other.app.SomeIntent"], "zz", "other app's entry touched")
    }

    func testSyncIsIdempotent() {
        let (once, addedOnce, _) = QuickKeySync.merged(existing: nil, bundleID: bundle)
        let (twice, addedTwice, prunedTwice) = QuickKeySync.merged(existing: once, bundleID: bundle)
        XCTAssertGreaterThan(addedOnce, 0)
        XCTAssertEqual(addedTwice, 0)
        XCTAssertEqual(prunedTwice, 0)
        XCTAssertEqual(once[QuickKeySync.namespace] as? [String: String],
                       twice[QuickKeySync.namespace] as? [String: String])
    }

    func testSuggestionsCoverEveryPerSiteIntent() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/SiteIntents.swift"), encoding: .utf8)
        for intentName in QuickKeySync.suggested.keys where intentName != "SearchSiteIntent" {
            XCTAssertTrue(source.contains("struct \(intentName)"), "suggested quick key for unknown intent \(intentName)")
        }
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

    func testPerSiteIntentsCoverAllDefaults() throws {
        // Every default site must have a dedicated intent in SiteIntents.swift
        // carrying its exact id and fallback template.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/SiteIntents.swift"), encoding: .utf8)
        for site in SiteStore.defaults {
            XCTAssertTrue(source.contains(site.id.uuidString), "SiteIntents.swift missing intent for \(site.name) (id)")
            XCTAssertTrue(source.contains(site.template), "SiteIntents.swift fallback template drifted for \(site.name)")
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
