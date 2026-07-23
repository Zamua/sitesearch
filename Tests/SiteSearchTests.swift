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

final class SlotAllocationTests: XCTestCase {
    func testDefaultsNeverConsumeSlots() {
        let result = SiteStore.allocatingSlots(SiteStore.defaults)
        XCTAssertTrue(result.allSatisfy { $0.slot == nil })
    }

    func testCustomSitesGetLowestFreeSlots() {
        var sites = SiteStore.defaults
        sites.append(Site(keyword: "one", name: "One", template: "https://one.example/{query}"))
        sites.append(Site(keyword: "two", name: "Two", template: "https://two.example/{query}"))
        let result = SiteStore.allocatingSlots(sites)
        XCTAssertEqual(result.compactMap(\.slot), [1, 2])
    }

    func testExistingSlotsAreStableAndGapsFill() {
        var sites = SiteStore.defaults
        sites.append(Site(keyword: "kept", name: "Kept", template: "https://kept.example/{query}", slot: 2))
        sites.append(Site(keyword: "new", name: "New", template: "https://new.example/{query}"))
        let result = SiteStore.allocatingSlots(sites)
        XCTAssertEqual(result.first { $0.keyword == "kept" }?.slot, 2, "existing slot moved")
        XCTAssertEqual(result.first { $0.keyword == "new" }?.slot, 1, "gap not filled")
    }

    func testOverflowBeyondSlotCountStaysSlotless() {
        var sites: [Site] = []
        for i in 0..<(SiteStore.slotCount + 3) {
            sites.append(Site(keyword: "k\(i)", name: "S\(i)", template: "https://s\(i).example/{query}"))
        }
        let result = SiteStore.allocatingSlots(sites)
        XCTAssertEqual(result.compactMap(\.slot).count, SiteStore.slotCount)
    }
}

final class QuickKeySyncTests: XCTestCase {
    let bundle = "com.zamua.SiteSearch"

    func testDesiredMapsDefaultsToDedicatedIntents() {
        let map = QuickKeySync.desired(bundleID: bundle, sites: SiteStore.defaults)
        XCTAssertEqual(map["\(bundle).SearchGoogleIntent"], "google")
        XCTAssertEqual(map["\(bundle).SearchGitHubIntent"], "code")
        XCTAssertEqual(map["\(bundle).SearchGitHubReposIntent"], "repo")
        XCTAssertEqual(map["\(bundle).SearchSiteIntent"], "ws")
    }

    func testDesiredMapsSlottedSitesToSlotIntents() {
        var sites = SiteStore.defaults
        sites.append(Site(keyword: "hn", name: "Hacker News", template: "https://hn.algolia.com/?q={query}", slot: 3))
        let map = QuickKeySync.desired(bundleID: bundle, sites: sites)
        XCTAssertEqual(map["\(bundle).CustomSearch3Intent"], "hn")
    }

    func testKeywordEditUpdatesOurEntry() {
        var sites = SiteStore.defaults
        sites[0].keyword = "goog"
        let want = QuickKeySync.desired(bundleID: bundle, sites: sites)
        let existing: [String: Any] = [QuickKeySync.namespace: ["\(bundle).SearchGoogleIntent": "google"]]
        let (store, changed) = QuickKeySync.merged(existing: existing, desired: want, bundleID: bundle)
        let ns = store[QuickKeySync.namespace] as? [String: String]
        XCTAssertTrue(changed)
        XCTAssertEqual(ns?["\(bundle).SearchGoogleIntent"], "goog", "our entry should mirror the config")
    }

    func testForeignAbbreviationIsNotStolenAndForeignEntriesSurvive() {
        let want = QuickKeySync.desired(bundleID: bundle, sites: SiteStore.defaults)
        let existing: [String: Any] = [QuickKeySync.namespace: ["com.other.app.SomeIntent": "code"]]
        let (store, _) = QuickKeySync.merged(existing: existing, desired: want, bundleID: bundle)
        let ns = store[QuickKeySync.namespace] as? [String: String]
        XCTAssertNil(ns?["\(bundle).SearchGitHubIntent"], "stole an abbreviation another action owns")
        XCTAssertEqual(ns?["com.other.app.SomeIntent"], "code")
        XCTAssertEqual(ns?["\(bundle).SearchGoogleIntent"], "google", "non-colliding entries should still land")
    }

    func testStaleOwnEntriesArePruned() {
        let want = QuickKeySync.desired(bundleID: bundle, sites: SiteStore.defaults)
        let existing: [String: Any] = [QuickKeySync.namespace: [
            "\(bundle).SearchYouTubeIntent": "yt",
            "com.other.app.SomeIntent": "zz",
        ]]
        let (store, changed) = QuickKeySync.merged(existing: existing, desired: want, bundleID: bundle)
        let ns = store[QuickKeySync.namespace] as? [String: String]
        XCTAssertTrue(changed)
        XCTAssertNil(ns?["\(bundle).SearchYouTubeIntent"], "stale entry for removed intent kept")
        XCTAssertEqual(ns?["com.other.app.SomeIntent"], "zz", "other app's entry touched")
    }

    func testMergeIsIdempotent() {
        let want = QuickKeySync.desired(bundleID: bundle, sites: SiteStore.defaults)
        let (once, changedOnce) = QuickKeySync.merged(existing: nil, desired: want, bundleID: bundle)
        let (twice, changedTwice) = QuickKeySync.merged(existing: once, desired: want, bundleID: bundle)
        XCTAssertTrue(changedOnce)
        XCTAssertFalse(changedTwice)
        XCTAssertEqual(once[QuickKeySync.namespace] as? [String: String],
                       twice[QuickKeySync.namespace] as? [String: String])
    }

    func testSlotIntentsExistForTheWholeRange() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/SlotIntents.swift"), encoding: .utf8)
        for i in 1...SiteStore.slotCount {
            XCTAssertTrue(source.contains("struct CustomSearch\(i)Intent"), "missing slot intent \(i)")
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
