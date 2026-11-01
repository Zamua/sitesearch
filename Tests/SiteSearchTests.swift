import XCTest
@testable import SiteSearch

final class BuildURLTests: XCTestCase {
    func testSpacesArePercentEncoded() throws {
        let url = try SiteURL.build(template: "https://example.com/s?q={query}", query: "hello world")
        XCTAssertEqual(url.absoluteString, "https://example.com/s?q=hello%20world")
    }

    func testReservedCharactersAreEncoded() throws {
        let url = try SiteURL.build(template: "https://example.com/s?q={query}", query: "c++ & a=b?")
        XCTAssertEqual(url.absoluteString, "https://example.com/s?q=c%2B%2B%20%26%20a%3Db%3F")
    }

    func testNonASCIIIsEncoded() throws {
        let url = try SiteURL.build(template: "https://example.com/s?q={query}", query: "café")
        XCTAssertEqual(url.absoluteString, "https://example.com/s?q=caf%C3%A9")
    }

    func testUnreservedCharactersPassThrough() throws {
        let url = try SiteURL.build(template: "https://example.com/s?q={query}", query: "a-b_c.d~e")
        XCTAssertEqual(url.absoluteString, "https://example.com/s?q=a-b_c.d~e")
    }

    func testMissingPlaceholderThrows() {
        XCTAssertThrowsError(try SiteURL.build(template: "https://example.com/s?q=", query: "x")) { error in
            guard case SearchSiteError.missingPlaceholder = error else {
                return XCTFail("expected missingPlaceholder, got \(error)")
            }
        }
    }

    func testNonHTTPSchemeThrows() {
        XCTAssertThrowsError(try SiteURL.build(template: "file:///tmp/{query}", query: "x")) { error in
            guard case SearchSiteError.invalidURL = error else {
                return XCTFail("expected invalidURL, got \(error)")
            }
        }
    }

    func testUppercaseSchemeAccepted() throws {
        let url = try SiteURL.build(template: "HTTPS://example.com/s?q={query}", query: "x")
        XCTAssertEqual(url.scheme?.lowercased(), "https")
    }
}

/// The app registers exactly ONE Spotlight quick key - `ss` for the single
/// Search Site action. Site keywords are filter text inside that action's
/// entity dropdown, not registered abbreviations, so the quick-key store no
/// longer varies with the config.
final class QuickKeySyncTests: XCTestCase {
    let bundle = "com.zamua.SiteSearch"

    /// Two actions, two keys: searches need a query, bookmarks must not be
    /// asked for one. Spotlight cannot vary a summary per entity, so the split
    /// has to happen at the action level.
    func testDesiredRegistersBothActions() {
        XCTAssertEqual(QuickKeySync.desired(bundleID: bundle), [
            "\(bundle).SearchSiteIntent": "ss",
            "\(bundle).OpenBookmarkIntent": "sb",
        ])
    }

    func testMergeInstallsBothEntries() {
        let want = QuickKeySync.desired(bundleID: bundle)
        let (store, changed) = QuickKeySync.merged(existing: nil, desired: want, bundleID: bundle)
        XCTAssertTrue(changed)
        XCTAssertEqual(store[QuickKeySync.namespace] as? [String: String], [
            "\(bundle).SearchSiteIntent": "ss",
            "\(bundle).OpenBookmarkIntent": "sb",
        ])
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
    private var tmp: URL!
    private var file: URL { tmp.appendingPathComponent("sites.json") }
    private let legacyJSON = """
    [{"id":"9D2C63A0-5B21-4A2E-9C5A-000000000099","keyword":"hn","name":"Hacker News","template":"https://hn.algolia.com/?q={query}","slot":3}]
    """

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sitesearch-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try Data(legacyJSON.utf8).write(to: file)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testLegacyConfigWithSlotFieldStillLoads() {
        let sites = SiteStore.load(from: file)
        XCTAssertEqual(sites.map(\.keyword), ["hn"])
        XCTAssertEqual(sites.first?.template, "https://hn.algolia.com/?q={query}")
    }

    func testResavingLegacyConfigDropsTheSlotField() throws {
        _ = try SiteStore.mutate(at: file) { ($0, ()) }
        let raw = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(raw.contains("hn.algolia.com"))
        XCTAssertFalse(raw.contains("slot"), "slot should no longer be persisted")
    }
}

final class SiteExchangeTests: XCTestCase {
    func testExportParseRoundtrip() throws {
        let data = try SiteExchange.export(SiteStore.defaults)
        let entries = try SiteExchange.parse(data).entries
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

    func testInvalidEntriesAreRejectedWithAReason() throws {
        let data = Data(#"""
        {"version": 1, "sites": [
          {"name": "Good", "keyword": "good", "template": "https://good.example/?q={query}"},
          {"name": "No URL", "keyword": "bad", "template": "javascript:alert(1)"},
          {"name": "No keyword", "keyword": "", "template": "https://k.example/?q={query}"}
        ]}
        """#.utf8)
        let parsed = try SiteExchange.parse(data)
        XCTAssertEqual(parsed.entries.map(\.name), ["Good"])
        XCTAssertEqual(parsed.rejected.map(\.entry.name), ["No URL", "No keyword"])
        XCTAssertFalse(parsed.rejected.contains { $0.reason.isEmpty })
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
            let url = try SiteURL.build(template: site.template, query: "hello world")
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

final class SiteOpsTests: XCTestCase {
    private var base: [Site] { SiteStore.defaults }

    private func assertThrows(_ expected: SiteOpError, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) {
        do {
            try body()
            XCTFail("expected \(expected), no error thrown", file: file, line: line)
        } catch let error as SiteOpError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected \(expected), got \(error)", file: file, line: line)
        }
    }

    func testFindMatchesByKeywordOrID() {
        XCTAssertEqual(SiteOps.find(base, "code")?.name, "GitHub")
        XCTAssertEqual(SiteOps.find(base, "CODE")?.name, "GitHub", "keyword lookup should be case-insensitive")
        XCTAssertEqual(SiteOps.find(base, base[0].id.uuidString)?.name, "Google")
        XCTAssertNil(SiteOps.find(base, "nope"))
    }

    func testAddAppendsAndMintsAFreshID() throws {
        let (sites, added) = try SiteOps.add(to: base, name: "Hacker News", keyword: "hn", template: "https://hn.algolia.com/?q={query}")
        XCTAssertEqual(sites.count, base.count + 1)
        XCTAssertEqual(added.name, "Hacker News")
        XCTAssertEqual(added.keyword, "hn")
        XCTAssertEqual(sites.last?.id, added.id)
        XCTAssertFalse(base.map(\.id).contains(added.id), "reused an existing id")
    }

    /// A template without {query} is a bookmark now, not an error - so the
    /// storage layer only rejects things that are not URLs at all.
    func testAddRejectsATemplateThatIsNotAURL() {
        assertThrows(.invalidTemplate("not a url")) {
            _ = try SiteOps.add(to: base, name: "X", keyword: "x", template: "not a url")
        }
    }

    func testAddRejectsNonHTTPScheme() {
        assertThrows(.invalidTemplate("file:///tmp/{query}")) {
            _ = try SiteOps.add(to: base, name: "X", keyword: "x", template: "file:///tmp/{query}")
        }
    }

    func testAddRejectsEmptyNameAndKeyword() {
        assertThrows(.emptyName) {
            _ = try SiteOps.add(to: base, name: "  ", keyword: "x", template: "https://x.example/?q={query}")
        }
        assertThrows(.emptyKeyword) {
            _ = try SiteOps.add(to: base, name: "X", keyword: " ", template: "https://x.example/?q={query}")
        }
    }

    /// An agent that asked for `hn` should be told the keyword is taken, not
    /// silently handed `hn2` (which import-merge does, on purpose).
    func testAddRejectsDuplicateKeywordCaseInsensitively() {
        assertThrows(.keywordTaken("GOOGLE")) {
            _ = try SiteOps.add(to: base, name: "My Google", keyword: "GOOGLE", template: "https://g.example/?q={query}")
        }
    }

    func testUpdateChangesOnlyTheGivenFields() throws {
        let before = try XCTUnwrap(SiteOps.find(base, "code"))
        let (sites, updated) = try SiteOps.update(in: base, selector: "code", name: nil, keyword: "gh", template: nil)
        XCTAssertEqual(updated.keyword, "gh")
        XCTAssertEqual(updated.name, before.name, "name should be untouched")
        XCTAssertEqual(updated.template, before.template, "template should be untouched")
        XCTAssertEqual(updated.id, before.id, "id must be stable across edits")
        XCTAssertEqual(sites.count, base.count)
    }

    func testUpdateAllowsKeepingItsOwnKeyword() throws {
        let (_, updated) = try SiteOps.update(in: base, selector: "code", name: "GitHub Code", keyword: "code", template: nil)
        XCTAssertEqual(updated.name, "GitHub Code")
        XCTAssertEqual(updated.keyword, "code")
    }

    func testUpdateRejectsAKeywordAnotherSiteHolds() {
        assertThrows(.keywordTaken("google")) {
            _ = try SiteOps.update(in: base, selector: "code", name: nil, keyword: "google", template: nil)
        }
    }

    func testUpdateValidatesANewTemplate() {
        assertThrows(.invalidTemplate("not a url")) {
            _ = try SiteOps.update(in: base, selector: "code", name: nil, keyword: nil, template: "not a url")
        }
    }

    /// Turning a search into a bookmark by dropping the placeholder is a legal
    /// edit, not a validation failure.
    func testUpdateCanConvertASearchIntoABookmark() throws {
        let (_, updated) = try SiteOps.update(in: base, selector: "code", name: nil, keyword: nil,
                                              template: "https://github.com/zamua")
        XCTAssertEqual(updated.template, "https://github.com/zamua")
    }

    func testUpdateUnknownSelectorThrows() {
        assertThrows(.notFound("nope")) {
            _ = try SiteOps.update(in: base, selector: "nope", name: "X", keyword: nil, template: nil)
        }
    }

    func testRemoveByKeyword() throws {
        let (sites, removed) = try SiteOps.remove(from: base, selector: "code")
        XCTAssertEqual(removed.name, "GitHub")
        XCTAssertEqual(sites.count, base.count - 1)
        XCTAssertNil(SiteOps.find(sites, "code"))
    }

    func testRemoveUnknownSelectorThrows() {
        assertThrows(.notFound("nope")) {
            _ = try SiteOps.remove(from: base, selector: "nope")
        }
    }

    func testUniqueKeywordIsCaseInsensitive() {
        let sites = [Site(keyword: "repo", name: "r", template: "https://r.example/?q={query}")]
        XCTAssertEqual(SiteOps.uniqueKeyword("Repo", among: sites), "Repo2")
        XCTAssertEqual(SiteOps.uniqueKeyword("free", among: sites), "free")
        XCTAssertEqual(SiteOps.uniqueKeyword("", among: sites), "")
    }

    func testASearchTemplateNeedsAHost() {
        XCTAssertThrowsError(try SiteOps.validate(template: "https:///search?q={query}"))
    }
}

/// Disk-level behaviour, against a temp file - never the real config.
final class SiteStoreMutationTests: XCTestCase {
    private var tmp: URL!
    private var file: URL { tmp.appendingPathComponent("sites.json") }

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sitesearch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testMutateAppliesAndPersists() throws {
        try SiteStore.save(SiteStore.defaults, to: file)
        let added = try SiteStore.mutate(at: file) {
            try SiteOps.add(to: $0, name: "Hacker News", keyword: "hn", template: "https://hn.algolia.com/?q={query}")
        }
        XCTAssertEqual(added.keyword, "hn")
        let reloaded = SiteStore.load(from: file)
        XCTAssertEqual(reloaded.count, SiteStore.defaults.count + 1)
        XCTAssertNotNil(SiteOps.find(reloaded, "hn"))
    }

    /// The lost-update case that made agent-added sites vanish: a caller
    /// holding a stale snapshot must not be able to erase a concurrent write,
    /// because mutate re-reads under the lock rather than trusting the caller.
    func testMutateRereadsSoAConcurrentAdditionSurvives() throws {
        try SiteStore.save(SiteStore.defaults, to: file)
        let stale = SiteStore.load(from: file)

        _ = try SiteStore.mutate(at: file) {
            try SiteOps.add(to: $0, name: "Hacker News", keyword: "hn", template: "https://hn.algolia.com/?q={query}")
        }
        _ = try SiteStore.mutate(at: file) {
            try SiteOps.update(in: $0, selector: "code", name: "GH", keyword: nil, template: nil)
        }

        let final = SiteStore.load(from: file)
        XCTAssertEqual(stale.count, SiteStore.defaults.count, "sanity: the snapshot predates the addition")
        XCTAssertNotNil(SiteOps.find(final, "hn"), "concurrently added site was clobbered")
        XCTAssertEqual(SiteOps.find(final, "code")?.name, "GH")
    }

    func testFailedMutationLeavesTheFileUntouched() throws {
        try SiteStore.save(SiteStore.defaults, to: file)
        XCTAssertThrowsError(try SiteStore.mutate(at: file) {
            try SiteOps.add(to: $0, name: "Bad", keyword: "bad", template: "not a url")
        })
        XCTAssertEqual(SiteStore.load(from: file).count, SiteStore.defaults.count)
    }

    func testLockIsReentrantEnoughForNestedReads() throws {
        try SiteStore.save(SiteStore.defaults, to: file)
        let count = SiteStore.withLock(at: file) { SiteStore.load(from: file).count }
        XCTAssertEqual(count, SiteStore.defaults.count)
    }
}

/// sites.json is hand-editable, so `id` is optional on disk. An entry written
/// without one must load, not reset the whole config to defaults.
final class StoredSiteTests: XCTestCase {
    private var tmp: URL!
    private var file: URL { tmp.appendingPathComponent("sites.json") }

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sitesearch-stored-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        try? FileManager.default.removeItem(at: tmp)
    }

    private func write(_ json: String) throws {
        try Data(json.utf8).write(to: file)
    }

    func testEntryWithoutAnIDLoadsInsteadOfResettingTheConfig() throws {
        try write(#"[{"name": "Hacker News", "keyword": "hn", "template": "https://hn.algolia.com/?q={query}"}]"#)
        let sites = SiteStore.load(from: file)
        XCTAssertEqual(sites.map(\.keyword), ["hn"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.appendingPathExtension("corrupt").path))
    }

    /// Spotlight caches entity ids, so a missing id must resolve the same way
    /// in every process, not mint a fresh one per load.
    func testMissingIDIsStableAcrossLoads() throws {
        try write(#"[{"name": "Hacker News", "keyword": "hn", "template": "https://hn.algolia.com/?q={query}"}]"#)
        XCTAssertEqual(SiteStore.load(from: file).first?.id, SiteStore.load(from: file).first?.id)
    }

    func testIdenticalEntriesWithoutIDsGetDistinctIDs() throws {
        let entry = #"{"name": "Docs", "keyword": "d", "template": "https://example.com/?q={query}"}"#
        try write("[\(entry), \(entry)]")
        XCTAssertEqual(Set(SiteStore.load(from: file).map(\.id)).count, 2)
    }

    func testExplicitIDIsKept() throws {
        let id = UUID()
        try write(#"[{"id": "\#(id.uuidString)", "name": "N", "keyword": "k", "template": "https://example.com/?q={query}"}]"#)
        XCTAssertEqual(SiteStore.load(from: file).first?.id, id)
    }

    /// The next write persists the id, so a later hand edit cannot move it.
    func testAMutationPersistsTheResolvedID() throws {
        try write(#"[{"name": "Hacker News", "keyword": "hn", "template": "https://hn.algolia.com/?q={query}"}]"#)
        let before = try XCTUnwrap(SiteStore.load(from: file).first?.id)
        _ = try SiteStore.mutate(at: file) { ($0, ()) }
        let raw = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(raw.contains(before.uuidString))
    }

    func testAFailedWriteIsReportedAndLeavesTheFileUntouched() throws {
        try SiteStore.save(SiteStore.defaults, to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tmp.path)
        XCTAssertThrowsError(try SiteStore.mutate(at: file) {
            try SiteOps.add(to: $0, name: "Hacker News", keyword: "hn", template: "https://hn.algolia.com/?q={query}")
        })
        XCTAssertNil(SiteOps.find(SiteStore.load(from: file), "hn"))
    }
}

/// A bookmark is a site whose template has no {query}: `ss repo1` opens it
/// directly instead of asking what to search for.
final class BookmarkTests: XCTestCase {
    private let bookmark = "https://github.com/zamua/sitesearch"
    private let search = "https://github.com/search?q={query}"

    func testTemplateKindIsInferredFromThePlaceholder() {
        XCTAssertTrue(SiteURL.requiresQuery(search))
        XCTAssertFalse(SiteURL.requiresQuery(bookmark))
    }

    func testResolvingABookmarkOpensItUntouched() throws {
        let url = try SiteURL.resolve(template: bookmark, query: nil)
        XCTAssertEqual(url.absoluteString, bookmark)
    }

    /// Whatever the user typed after the keyword is irrelevant to a bookmark;
    /// it must not be appended or silently turn the URL into nonsense.
    func testABookmarkIgnoresAnyQuery() throws {
        let url = try SiteURL.resolve(template: bookmark, query: "ignored text")
        XCTAssertEqual(url.absoluteString, bookmark)
    }

    func testResolvingASearchSubstitutesTheQuery() throws {
        let url = try SiteURL.resolve(template: search, query: "hello world")
        XCTAssertEqual(url.absoluteString, "https://github.com/search?q=hello%20world")
    }

    /// Return pressed with no query: open the search page empty rather than
    /// failing, which is what a browser does anyway.
    func testASearchWithNoQueryResolvesToTheBareSearchPage() throws {
        let url = try SiteURL.resolve(template: search, query: nil)
        XCTAssertEqual(url.absoluteString, "https://github.com/search?q=")
    }

    func testBookmarksMustStillBeHTTPURLs() {
        XCTAssertThrowsError(try SiteURL.resolve(template: "file:///etc/passwd", query: nil))
        XCTAssertThrowsError(try SiteURL.resolve(template: "not a url", query: nil))
    }

    func testSiteOpsAcceptsABookmarkTemplate() throws {
        let (sites, added) = try SiteOps.add(to: SiteStore.defaults, name: "SiteSearch Repo", keyword: "repo1", template: bookmark)
        XCTAssertEqual(added.template, bookmark)
        XCTAssertEqual(sites.count, SiteStore.defaults.count + 1)
    }

    /// Text filtering is kind-blind; separating searches from bookmarks is the
    /// job of each action's own dropdown.
    func testFilteringIsPurelyTextual() {
        let sites = [
            Site(keyword: "repo", name: "GitHub Repos", template: search),
            Site(keyword: "repo1", name: "SiteSearch", template: bookmark),
            Site(keyword: "repo2", name: "Other", template: "https://github.com/zamua/other"),
        ]
        XCTAssertEqual(SiteEntityQuery.filter(sites, matching: "repo").count, 3)
        XCTAssertEqual(SiteEntityQuery.filter(sites, matching: "repo1").count, 1)
    }

    func testKindIsExposedOnTheModel() {
        XCTAssertTrue(Site(keyword: "b", name: "B", template: bookmark).isBookmark)
        XCTAssertFalse(Site(keyword: "s", name: "S", template: search).isBookmark)
    }

    /// Each Spotlight action lists only its own kind: picking a bookmark from
    /// the search action would demand a query it has no use for, which is the
    /// whole reason the actions are separate.
    func testEachActionSeesOnlyItsOwnKind() {
        let sites = [
            Site(keyword: "repo", name: "GitHub Repos", template: search),
            Site(keyword: "repo1", name: "SiteSearch", template: bookmark),
            Site(keyword: "repo2", name: "Other", template: "https://github.com/zamua/other"),
        ]
        XCTAssertEqual(Site.searches(sites).map(\.keyword), ["repo"])
        XCTAssertEqual(Site.bookmarks(sites).map(\.keyword), ["repo1", "repo2"])
    }
}

/// Guards the settings a public release depends on. These drift silently and
/// only bite at notarization or install time, which is far too late.
/// What notarization and Homebrew depend on, checked where it takes effect:
/// the built bundle, and the generated Xcode project that xcodebuild reads
/// (parsed, so a setting on the wrong target or config fails, while moving a
/// setting between project and target level does not).
final class ReleaseConfigTests: XCTestCase {
    /// The generated project.pbxproj, an OpenStep plist.
    private struct Project {
        let objects: [String: [String: Any]]

        init() throws {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("SiteSearch.xcodeproj/project.pbxproj")
            let root = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
            objects = try XCTUnwrap((root as? [String: Any])?["objects"] as? [String: [String: Any]])
        }

        private func release(_ owner: [String: Any]) -> [String: Any] {
            let list = objects[owner["buildConfigurationList"] as? String ?? ""]
            let ids = list?["buildConfigurations"] as? [String] ?? []
            let config = ids.compactMap { objects[$0] }.first { $0["name"] as? String == "Release" }
            return config?["buildSettings"] as? [String: Any] ?? [:]
        }

        func target(_ name: String) -> [String: Any]? {
            objects.values.first { $0["isa"] as? String == "PBXNativeTarget" && $0["name"] as? String == name }
        }

        /// A Release build setting for `target`, falling back to the project level.
        func releaseSetting(_ key: String, target name: String) -> String? {
            let project = objects.values.first { $0["isa"] as? String == "PBXProject" } ?? [:]
            let own = target(name).map(release) ?? [:]
            return (own[key] ?? release(project)[key]) as? String
        }

        /// Paths `target` copies into Contents/MacOS (copy-phase subfolder 6).
        func executablesCopied(by name: String) -> [String] {
            let phases = target(name)?["buildPhases"] as? [String] ?? []
            return phases.compactMap { objects[$0] }
                .filter { $0["isa"] as? String == "PBXCopyFilesBuildPhase" && "\($0["dstSubfolderSpec"] ?? "")" == "6" }
                .flatMap { ($0["files"] as? [String] ?? []) }
                .compactMap { objects[$0]?["fileRef"] as? String }
                .compactMap { objects[$0]?["path"] as? String }
        }
    }

    private let executables = ["SiteSearch", "sitesearch-mcp"]

    /// The bundle once reported 1.0 for every release because a plist
    /// hardcoded it; Homebrew and bug reports both read this.
    func testTheBuiltBundleReportsTheProjectVersions() throws {
        let project = try Project()
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(info["CFBundleShortVersionString"] as? String,
                       project.releaseSetting("MARKETING_VERSION", target: "SiteSearch"))
        XCTAssertEqual(info["CFBundleVersion"] as? String,
                       project.releaseSetting("CURRENT_PROJECT_VERSION", target: "SiteSearch"))
    }

    /// Homebrew's `depends_on macos:` and the installer read this, and the app
    /// cannot run below 26.
    func testTheBuiltBundleRequiresTahoe() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String, "26.0")
    }

    /// Notarization checks every executable in the bundle for the hardened runtime.
    func testReleaseHardensEveryExecutable() throws {
        let project = try Project()
        for name in executables {
            XCTAssertEqual(project.releaseSetting("ENABLE_HARDENED_RUNTIME", target: name), "YES", name)
        }
    }

    /// Xcode injects com.apple.security.get-task-allow unless told not to, and
    /// the notary rejects any executable carrying it. Debug keeps it so a
    /// debugger can attach.
    func testReleaseOmitsTheDebuggerEntitlementEverywhere() throws {
        let project = try Project()
        for name in executables {
            XCTAssertEqual(project.releaseSetting("CODE_SIGN_INJECT_BASE_ENTITLEMENTS", target: name), "NO", name)
        }
    }

    /// The MCP server ships inside the app, signed: the path the README and
    /// `claude mcp add` point at.
    func testTheAppShipsTheSignedMCPToolInContentsMacOS() throws {
        XCTAssertEqual(try Project().executablesCopied(by: "SiteSearch"), ["sitesearch-mcp"])
        let tool = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/sitesearch-mcp")
        var code: SecStaticCode?
        XCTAssertEqual(SecStaticCodeCreateWithPath(tool as CFURL, [], &code), errSecSuccess)
        XCTAssertEqual(SecStaticCodeCheckValidity(try XCTUnwrap(code), [], nil), errSecSuccess, "embedded tool is not validly signed")
    }
}

final class FaviconTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sitesearch-icons-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func site(_ template: String) -> Site {
        Site(keyword: "k", name: "N", template: template)
    }

    // MARK: refresh

    private func icon(_ site: Site) -> Data? { Favicon.cachedData(for: site, in: tmp) }

    func testRefreshFetchesNewSitesAndDropsRemovedOnes() {
        let kept = site("https://a.example/?q={query}")
        let gone = site("https://b.example/?q={query}")
        let net = FakeNetwork()
        net.response = Data("icon".utf8)
        Favicon.refresh(from: [], to: [kept, gone], in: tmp, fetch: net.fetch)
        XCTAssertNotNil(icon(kept))
        XCTAssertNotNil(icon(gone))

        Favicon.refresh(from: [kept, gone], to: [kept], in: tmp, fetch: net.fetch)
        XCTAssertNotNil(icon(kept))
        XCTAssertNil(icon(gone), "a removed site's icon should be dropped")
    }

    func testRefreshRefetchesOnlyWhenTheOriginMoved() {
        var s = site("https://a.example/?q={query}")
        let net = FakeNetwork()
        net.response = Data("old".utf8)
        Favicon.refresh(from: [], to: [s], in: tmp, fetch: net.fetch)

        var renamed = s
        renamed.name = "Renamed"
        net.response = Data("new".utf8)
        Favicon.refresh(from: [s], to: [renamed], in: tmp, fetch: net.fetch)
        XCTAssertEqual(icon(s), Data("old".utf8), "a rename must not refetch")

        let before = s
        s.template = "https://elsewhere.example/?q={query}"
        Favicon.refresh(from: [before], to: [s], in: tmp, fetch: net.fetch)
        XCTAssertEqual(icon(s), Data("new".utf8), "a new origin must refetch")
    }

    func testALateFetchForAnOldOriginCannotReplaceTheNewOnesIcon() {
        let id = UUID()
        let atA = Site(id: id, keyword: "k", name: "N", template: "https://a.example/?q={query}")
        let atB = Site(id: id, keyword: "k", name: "N", template: "https://b.example/?q={query}")
        // A's fetch stalls; while it waits the site moves to B and B's icon lands.
        Favicon.refresh(from: [], to: [atA], in: tmp) { url in
            guard url.host == "a.example" else { return nil }
            Favicon.refresh(from: [atA], to: [atB], in: tmp) { _ in Data("B".utf8) }
            return Data("A".utf8)
        }
        XCTAssertEqual(icon(atB), Data("B".utf8))
    }

    // MARK: origin

    func testOriginStripsPathAndQuery() {
        XCTAssertEqual(Favicon.origin(forTemplate: "https://hn.algolia.com/?q={query}")?.absoluteString,
                       "https://hn.algolia.com")
        XCTAssertEqual(Favicon.origin(forTemplate: "https://github.com/search?q={query}&type=repositories")?.absoluteString,
                       "https://github.com")
    }

    func testOriginRejectsNonHTTPTemplates() {
        XCTAssertNil(Favicon.origin(forTemplate: "file:///tmp/{query}"))
        XCTAssertNil(Favicon.origin(forTemplate: "not a url"))
    }

    // MARK: cache

    func testTheCacheIsKeptPerSiteAndOrigin() {
        let a = site("https://a.example/?q={query}")
        var moved = a
        moved.template = "https://b.example/path?q={query}"
        let sameOrigin = site("https://a.example/other?q={query}")
        let urls = [a, moved, sameOrigin].compactMap { Favicon.cacheURL(for: $0, in: tmp) }
        XCTAssertEqual(Set(urls).count, 3)
        XCTAssertNil(Favicon.cacheURL(for: site("file:///tmp/{query}"), in: tmp))
    }

    func testAPlainFileFromThePerSiteLayoutGivesWay() throws {
        let s = site("https://a.example/?q={query}")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: tmp.appendingPathComponent(s.id.uuidString))
        XCTAssertNil(icon(s))
        XCTAssertTrue(Favicon.ensureCached(for: s, in: tmp) { _ in Data("new".utf8) })
        XCTAssertEqual(icon(s), Data("new".utf8))
    }

    // MARK: HTML parsing

    func testIconHrefsResolveRelativeAndAbsoluteLinks() throws {
        let origin = try XCTUnwrap(URL(string: "https://example.com"))
        let html = """
        <html><head>
        <link rel="stylesheet" href="/style.css">
        <link rel="icon" href="/fav.png">
        <link rel="apple-touch-icon" href="https://cdn.example.com/touch.png">
        </head></html>
        """
        let hrefs = Favicon.iconHrefs(inHTML: html, origin: origin).map(\.absoluteString)
        XCTAssertTrue(hrefs.contains("https://example.com/fav.png"), "got \(hrefs)")
        XCTAssertTrue(hrefs.contains("https://cdn.example.com/touch.png"), "got \(hrefs)")
        XCTAssertFalse(hrefs.contains { $0.hasSuffix("style.css") }, "picked up a non-icon link")
    }

    func testIconHrefsHandleShortcutIconAndSingleQuotes() throws {
        let origin = try XCTUnwrap(URL(string: "https://example.com"))
        let html = "<link rel='shortcut icon' href='/legacy.ico'>"
        let hrefs = Favicon.iconHrefs(inHTML: html, origin: origin).map(\.absoluteString)
        XCTAssertEqual(hrefs, ["https://example.com/legacy.ico"])
    }

    func testIconHrefsAreEmptyWhenThePageDeclaresNone() throws {
        let origin = try XCTUnwrap(URL(string: "https://example.com"))
        XCTAssertTrue(Favicon.iconHrefs(inHTML: "<html><body>hi</body></html>", origin: origin).isEmpty)
    }

    // MARK: fetching

    func testEnsureCachedWritesTheFetchedIcon() {
        let site = site("https://example.com/search?q={query}")
        let png = Data("PNGDATA".utf8)
        let ok = Favicon.ensureCached(for: site, in: tmp) { url in
            url.absoluteString == "https://example.com/favicon.ico" ? png : nil
        }
        XCTAssertTrue(ok)
        XCTAssertEqual(icon(site), png)
    }

    func testEnsureCachedSkipsTheNetworkWhenAlreadyCached() throws {
        let site = site("https://example.com/search?q={query}")
        XCTAssertTrue(Favicon.ensureCached(for: site, in: tmp) { _ in Data("existing".utf8) })
        var fetched: [URL] = []
        let ok = Favicon.ensureCached(for: site, in: tmp) { url in
            fetched.append(url)
            return Data("new".utf8)
        }
        XCTAssertTrue(ok)
        XCTAssertTrue(fetched.isEmpty, "re-fetched an icon it already had")
        XCTAssertEqual(icon(site), Data("existing".utf8))
    }

    /// Most sites do not serve /favicon.ico any more; fall back to what the
    /// page declares.
    func testEnsureCachedFallsBackToTheDeclaredIcon() {
        let site = site("https://example.com/search?q={query}")
        let png = Data("REALICON".utf8)
        let ok = Favicon.ensureCached(for: site, in: tmp) { url in
            switch url.absoluteString {
            case "https://example.com/favicon.ico": return nil
            case "https://example.com": return Data(#"<link rel="icon" href="/i.png">"#.utf8)
            case "https://example.com/i.png": return png
            default: return nil
            }
        }
        XCTAssertTrue(ok)
        XCTAssertEqual(icon(site), png)
    }

    func testEnsureCachedFetchesEachURLOnceEvenWhenThePageDeclaresTheConventionalOne() {
        let site = site("https://example.com/search?q={query}")
        var fetched: [String] = []
        let ok = Favicon.ensureCached(for: site, in: tmp) { url in
            fetched.append(url.absoluteString)
            return url.absoluteString == "https://example.com"
                ? Data(#"<link rel="icon" href="/favicon.ico"><link rel="icon" href="/i.png"><link rel="icon" href="/i.png">"#.utf8)
                : nil
        }
        XCTAssertFalse(ok)
        XCTAssertEqual(fetched, ["https://example.com/favicon.ico", "https://example.com", "https://example.com/i.png"])
    }

    func testEnsureCachedWritesNothingWhenEverythingFails() {
        let site = site("https://example.com/search?q={query}")
        let ok = Favicon.ensureCached(for: site, in: tmp) { _ in nil }
        XCTAssertFalse(ok)
        XCTAssertNil(icon(site))
    }

    func testEnsureCachedIgnoresEmptyResponses() {
        let site = site("https://example.com/search?q={query}")
        let ok = Favicon.ensureCached(for: site, in: tmp) { _ in Data() }
        XCTAssertFalse(ok, "an empty body is not an icon")
        XCTAssertNil(icon(site))
    }

    func testEnsureCachedIsANoOpForAnUnusableTemplate() {
        let site = site("file:///tmp/{query}")
        XCTAssertFalse(Favicon.ensureCached(for: site, in: tmp) { _ in Data("x".utf8) })
    }
}

/// The config window holds the whole list in @State, so it is the one writer
/// that could still erase an agent's concurrent addition. These pin the
/// three-way merge that stops it.
final class SiteReconcileTests: XCTestCase {
    private func site(_ name: String, _ keyword: String) -> Site {
        Site(keyword: keyword, name: name, template: "https://\(keyword).example/?q={query}")
    }

    func testExternalAdditionSurvivesAWindowEdit() {
        let a = site("Alpha", "a"), b = site("Beta", "b"), c = site("Gamma", "c")
        var renamed = b
        renamed.name = "Beta Renamed"

        let result = SiteReconcile.apply(edited: [a, renamed], baseline: [a, b], disk: [a, b, c])

        XCTAssertEqual(result.count, 3, "the externally added site was dropped")
        XCTAssertNotNil(result.first { $0.id == c.id }, "agent's site was clobbered")
        XCTAssertEqual(result.first { $0.id == b.id }?.name, "Beta Renamed", "window's rename was lost")
    }

    func testWindowDeletionIsApplied() {
        let a = site("Alpha", "a"), b = site("Beta", "b"), c = site("Gamma", "c")
        let result = SiteReconcile.apply(edited: [a], baseline: [a, b], disk: [a, b, c])
        XCTAssertNil(result.first { $0.id == b.id }, "window's deletion was ignored")
        XCTAssertNotNil(result.first { $0.id == c.id }, "unrelated site was deleted")
    }

    func testWindowAdditionIsAppended() {
        let a = site("Alpha", "a"), c = site("Gamma", "c"), new = site("New", "n")
        let result = SiteReconcile.apply(edited: [a, new], baseline: [a], disk: [a, c])
        XCTAssertEqual(result.count, 3)
        XCTAssertNotNil(result.first { $0.id == new.id })
        XCTAssertNotNil(result.first { $0.id == c.id })
    }

    func testFieldTheWindowDidNotTouchKeepsTheExternalValue() {
        let a = site("Alpha", "a")
        var external = a
        external.template = "https://changed.example/?q={query}"
        let result = SiteReconcile.apply(edited: [a], baseline: [a], disk: [external])
        XCTAssertEqual(result.first?.template, "https://changed.example/?q={query}",
                       "an untouched field should not be reverted to the window's stale copy")
    }

    func testFieldTheWindowChangedWins() {
        let a = site("Alpha", "a")
        var windowEdit = a
        windowEdit.name = "Window Wins"
        var external = a
        external.name = "Agent Wrote"
        let result = SiteReconcile.apply(edited: [windowEdit], baseline: [a], disk: [external])
        XCTAssertEqual(result.first?.name, "Window Wins")
    }

    func testExternallyDeletedSiteIsNotResurrected() {
        let a = site("Alpha", "a"), b = site("Beta", "b")
        let result = SiteReconcile.apply(edited: [a, b], baseline: [a, b], disk: [a])
        XCTAssertEqual(result.count, 1, "a site deleted by an agent came back")
        XCTAssertNil(result.first { $0.id == b.id })
    }

    func testTheFieldTableCoversEveryEditableSiteField() {
        let stored = Mirror(reflecting: SiteStore.defaults[0]).children.compactMap(\.label).filter { $0 != "id" }
        XCTAssertEqual(stored.count, SiteReconcile.fields.count, "a Site field is missing from SiteReconcile.fields")
        let base = Site(keyword: "k", name: "n", template: "https://t.example/?q={query}")
        for field in SiteReconcile.fields {
            var edited = base
            edited[keyPath: field] += "-changed"
            let merged = SiteReconcile.apply(edited: [edited], baseline: [base], disk: [base])
            XCTAssertEqual(merged.first?[keyPath: field], edited[keyPath: field])
        }
    }

    // MARK: what a save persists, and what the window shows after reading disk

    private let g = Site(id: UUID(), keyword: "g", name: "Google", template: "https://www.google.com/search?q={query}")
    private let h = Site(id: UUID(), keyword: "h", name: "HN", template: "https://hn.algolia.com/?q={query}")

    func testAValidEditPersists() {
        var edited = g
        edited.name = "Search"
        XCTAssertEqual(SiteReconcile.persistable(edited: [edited, h], baseline: [g, h], disk: [g, h]).first?.name, "Search")
    }

    func testAnEditThatBreaksARowIsHeldBack() {
        var emptied = g
        emptied.keyword = ""
        XCTAssertEqual(SiteReconcile.persistable(edited: [emptied, h], baseline: [g, h], disk: [g, h]).first?.keyword, "g")

        var taken = g
        taken.keyword = "H"
        XCTAssertEqual(SiteReconcile.persistable(edited: [taken, h], baseline: [g, h], disk: [g, h]).first?.keyword, "g")

        var broken = g
        broken.template = "not a url"
        XCTAssertEqual(SiteReconcile.persistable(edited: [broken, h], baseline: [g, h], disk: [g, h]).first?.template, g.template)
    }

    func testANewRowPersistsOnlyOnceValid() {
        let draft = Site(keyword: "", name: "New Site", template: "https://example.com/search?q={query}")
        XCTAssertEqual(SiteReconcile.persistable(edited: [g, draft], baseline: [g], disk: [g]).count, 1)
        var ready = draft
        ready.keyword = "ex"
        XCTAssertEqual(SiteReconcile.persistable(edited: [g, ready], baseline: [g], disk: [g]).count, 2)
    }

    /// Validation guards the window's edits, never erases what is on disk.
    func testAnUntouchedInvalidRowOnDiskIsKept() {
        let handEdited = Site(keyword: "", name: "Hand", template: "nope")
        let result = SiteReconcile.persistable(edited: [g, handEdited], baseline: [g, handEdited], disk: [g, handEdited])
        XCTAssertEqual(result.count, 2)
    }

    /// An external change read during the save debounce must not swallow the
    /// edit still waiting to be saved.
    func testAnExternalChangeDoesNotSwallowAPendingEdit() {
        var edited = g
        edited.name = "Search"
        let external = [g, h]  // someone else added h
        let (shown, baseline) = SiteReconcile.absorb(disk: external, edited: [edited], baseline: [g])
        XCTAssertEqual(shown.map(\.name), ["Search", "HN"])
        let saved = SiteReconcile.persistable(edited: shown, baseline: baseline, disk: external)
        XCTAssertEqual(saved.first?.name, "Search", "the pending edit was lost")
        XCTAssertEqual(saved.count, 2)
    }

    /// A held-back edit stays on screen, so the user keeps typing into it.
    func testAHeldBackEditStaysShownAndPending() {
        var typing = g
        typing.template = "https://"
        let written = SiteReconcile.persistable(edited: [typing], baseline: [g], disk: [g])
        let (shown, baseline) = SiteReconcile.absorb(disk: written, edited: [typing], baseline: [g])
        XCTAssertEqual(shown.first?.template, "https://")
        XCTAssertEqual(baseline.first?.template, g.template, "still pending, so the next save retries it")
    }
}

/// Records browser opens so search_site can be tested without launching one.
final class OpenRecorder: @unchecked Sendable {
    private(set) var urls: [URL] = []
    func record(_ url: URL) -> Bool {
        urls.append(url)
        return true
    }
}

/// Stands in for the network so icon fetching is testable offline.
final class FakeNetwork: @unchecked Sendable {
    var response: Data?
    private(set) var requested: [URL] = []
    func fetch(_ url: URL) -> Data? {
        requested.append(url)
        return response
    }
}

final class MCPHandlerTests: XCTestCase {
    private var tmp: URL!
    private var recorder: OpenRecorder!
    private var network: FakeNetwork!
    private var handler: MCPHandler!
    private var file: URL { tmp.appendingPathComponent("sites.json") }
    private var iconDir: URL { tmp.appendingPathComponent("icons") }

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sitesearch-mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try SiteStore.save(SiteStore.defaults, to: file)
        let recorder = OpenRecorder()
        let network = FakeNetwork()
        self.recorder = recorder
        self.network = network
        handler = MCPHandler(
            storeURL: file,
            opener: { recorder.record($0) },
            iconFetch: { network.fetch($0) }
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: helpers

    private func request(_ method: String, _ params: [String: Any]? = nil, id: Int? = 1) -> [String: Any] {
        var req: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let id { req["id"] = id }
        if let params { req["params"] = params }
        return req
    }

    private func callTool(_ name: String, _ arguments: [String: Any]) throws -> (text: String, isError: Bool) {
        let response = try XCTUnwrap(handler.handle(request("tools/call", ["name": name, "arguments": arguments])))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        return (text, result["isError"] as? Bool ?? false)
    }

    // MARK: protocol

    func testInitializeAdvertisesToolsCapability() throws {
        let response = try XCTUnwrap(handler.handle(request("initialize", ["protocolVersion": "2025-06-18"])))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(response["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-06-18")
        let capabilities = try XCTUnwrap(result["capabilities"] as? [String: Any])
        XCTAssertNotNil(capabilities["tools"])
        let info = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(info["name"] as? String, MCPHandler.serverName)
    }

    func testNotificationGetsNoResponse() {
        XCTAssertNil(handler.handle(request("notifications/initialized", nil, id: nil)))
    }

    func testUnknownMethodIsMethodNotFound() throws {
        let response = try XCTUnwrap(handler.handle(request("does/notExist")))
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32601)
    }

    func testToolsListAdvertisesEveryTool() throws {
        let response = try XCTUnwrap(handler.handle(request("tools/list")))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        let names = Set(tools.compactMap { $0["name"] as? String })
        XCTAssertEqual(names, ["list_sites", "add_site", "add_bookmark", "update_site", "remove_site", "search_site"])
        for tool in tools {
            XCTAssertNotNil(tool["description"] as? String, "\(tool["name"] ?? "?") needs a description")
            XCTAssertNotNil(tool["inputSchema"] as? [String: Any], "\(tool["name"] ?? "?") needs an inputSchema")
        }
    }

    func testCallingAnUnknownToolIsAnError() throws {
        let response = try XCTUnwrap(handler.handle(request("tools/call", ["name": "nope", "arguments": [:]])))
        XCTAssertNotNil(response["error"], "unknown tool should be a protocol error")
    }

    // MARK: tools

    func testListSitesReturnsTheConfiguredSites() throws {
        let (text, isError) = try callTool("list_sites", [:])
        XCTAssertFalse(isError)
        XCTAssertTrue(text.contains("google"), "expected default keywords in: \(text)")
        XCTAssertTrue(text.contains("GitHub"))
    }

    func testAddSitePersistsAndIsImmediatelySearchable() throws {
        let (text, isError) = try callTool("add_site", [
            "name": "Hacker News", "keyword": "hn", "template": "https://hn.algolia.com/?q={query}",
        ])
        XCTAssertFalse(isError, "add failed: \(text)")
        let stored = SiteStore.load(from: file)
        XCTAssertNotNil(SiteOps.find(stored, "hn"), "site was not persisted")
        XCTAssertEqual(stored.count, SiteStore.defaults.count + 1)
    }

    func testAddSiteWithABadTemplateIsAToolErrorNotACrash() throws {
        let (text, isError) = try callTool("add_site", [
            "name": "Bad", "keyword": "bad", "template": "https://x.example/search",
        ])
        XCTAssertTrue(isError)
        XCTAssertTrue(text.contains("{query}"), "error should name the missing placeholder: \(text)")
        XCTAssertEqual(SiteStore.load(from: file).count, SiteStore.defaults.count, "failed add wrote anyway")
    }

    // MARK: bookmarks

    func testAddBookmarkStoresAURLWithNoPlaceholder() throws {
        let (text, isError) = try callTool("add_bookmark", [
            "name": "SiteSearch Repo", "keyword": "repo1", "template": "https://github.com/zamua/sitesearch",
        ])
        XCTAssertFalse(isError, text)
        let stored = try XCTUnwrap(SiteOps.find(SiteStore.load(from: file), "repo1"))
        XCTAssertEqual(stored.template, "https://github.com/zamua/sitesearch")
    }

    /// The two tools exist so an agent states which kind it means; mixing them
    /// up should say so rather than quietly storing the wrong thing.
    func testAddBookmarkRejectsASearchTemplate() throws {
        let (text, isError) = try callTool("add_bookmark", [
            "name": "Nope", "keyword": "nope", "template": "https://github.com/search?q={query}",
        ])
        XCTAssertTrue(isError)
        XCTAssertTrue(text.contains("{query}"), "error should explain the mix-up: \(text)")
        XCTAssertNil(SiteOps.find(SiteStore.load(from: file), "nope"))
    }

    func testOpeningABookmarkIgnoresAnyQuery() throws {
        _ = try callTool("add_bookmark", [
            "name": "SiteSearch Repo", "keyword": "repo1", "template": "https://github.com/zamua/sitesearch",
        ])
        let (_, isError) = try callTool("search_site", ["site": "repo1", "query": "ignored"])
        XCTAssertFalse(isError)
        XCTAssertEqual(recorder.urls.map(\.absoluteString), ["https://github.com/zamua/sitesearch"])
    }

    func testAddSiteRejectsADuplicateKeyword() throws {
        let (text, isError) = try callTool("add_site", [
            "name": "Another Google", "keyword": "google", "template": "https://g.example/?q={query}",
        ])
        XCTAssertTrue(isError)
        XCTAssertTrue(text.lowercased().contains("google"), "error should name the clash: \(text)")
    }

    func testUpdateSiteChangesOnlyWhatWasPassed() throws {
        let (text, isError) = try callTool("update_site", ["site": "code", "keyword": "gh"])
        XCTAssertFalse(isError, "update failed: \(text)")
        let stored = SiteStore.load(from: file)
        let site = try XCTUnwrap(SiteOps.find(stored, "gh"))
        XCTAssertEqual(site.name, "GitHub", "name should be untouched")
    }

    func testRemoveSiteByKeyword() throws {
        let (_, isError) = try callTool("remove_site", ["site": "code"])
        XCTAssertFalse(isError)
        XCTAssertNil(SiteOps.find(SiteStore.load(from: file), "code"))
    }

    func testSearchSiteOpensTheBuiltURL() throws {
        let (text, isError) = try callTool("search_site", ["site": "google", "query": "hello world"])
        XCTAssertFalse(isError, "search failed: \(text)")
        XCTAssertEqual(recorder.urls.map(\.absoluteString),
                       ["https://www.google.com/search?q=hello%20world"])
    }

    func testSearchingAnUnknownSiteIsAToolError() throws {
        let (_, isError) = try callTool("search_site", ["site": "nope", "query": "x"])
        XCTAssertTrue(isError)
        XCTAssertTrue(recorder.urls.isEmpty, "should not have opened anything")
    }

    func testMissingRequiredArgumentIsAToolError() throws {
        let (_, isError) = try callTool("add_site", ["name": "No Keyword"])
        XCTAssertTrue(isError)
    }

    // MARK: favicons

    private func icon(_ id: UUID) -> Data? {
        SiteStore.load(from: file).first { $0.id == id }.flatMap { Favicon.cachedData(for: $0, in: iconDir) }
    }

    private func addedSiteID(_ text: String) throws -> UUID {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        return try XCTUnwrap(UUID(uuidString: try XCTUnwrap(json["id"] as? String)))
    }

    func testAddSiteCachesTheSitesIcon() throws {
        network.response = Data("PNGBYTES".utf8)
        let (text, isError) = try callTool("add_site", [
            "name": "Hacker News", "keyword": "hn", "template": "https://hn.algolia.com/?q={query}",
        ])
        XCTAssertFalse(isError, text)
        let id = try addedSiteID(text)
        XCTAssertEqual(icon(id), Data("PNGBYTES".utf8))
        XCTAssertEqual(network.requested.first?.absoluteString, "https://hn.algolia.com/favicon.ico")
    }

    /// A site whose icon cannot be fetched is still a perfectly good site.
    func testAddSiteSucceedsWhenTheIconCannotBeFetched() throws {
        network.response = nil
        let (text, isError) = try callTool("add_site", [
            "name": "Hacker News", "keyword": "hn", "template": "https://hn.algolia.com/?q={query}",
        ])
        XCTAssertFalse(isError, text)
        XCTAssertNotNil(SiteOps.find(SiteStore.load(from: file), "hn"))
        XCTAssertNil(icon(try addedSiteID(text)))
    }

    func testChangingATemplateRefetchesTheIcon() throws {
        network.response = Data("OLD".utf8)
        let (addText, _) = try callTool("add_site", [
            "name": "Site", "keyword": "s1", "template": "https://one.example/?q={query}",
        ])
        let id = try addedSiteID(addText)
        XCTAssertEqual(icon(id), Data("OLD".utf8))

        network.response = Data("NEW".utf8)
        let (text, isError) = try callTool("update_site", [
            "site": "s1", "template": "https://two.example/?q={query}",
        ])
        XCTAssertFalse(isError, text)
        XCTAssertEqual(icon(id), Data("NEW".utf8),
                       "icon should be refetched when the origin changes")
        XCTAssertEqual(network.requested.last?.absoluteString, "https://two.example/favicon.ico")
    }

    func testRenamingASiteDoesNotRefetchTheIcon() throws {
        network.response = Data("ICON".utf8)
        let (addText, _) = try callTool("add_site", [
            "name": "Site", "keyword": "s1", "template": "https://one.example/?q={query}",
        ])
        _ = try addedSiteID(addText)
        let before = network.requested.count

        let (_, isError) = try callTool("update_site", ["site": "s1", "name": "Renamed"])
        XCTAssertFalse(isError)
        XCTAssertEqual(network.requested.count, before, "a rename should not hit the network")
    }

    func testAWriteFailureIsAnErrorNotASuccess() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tmp.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path) }
        let result = try callTool("add_site", ["name": "Hacker News", "keyword": "hn", "template": "https://hn.algolia.com/?q={query}"])
        XCTAssertTrue(result.isError, "reported success for a write that never landed: \(result.text)")
    }

    func testInitializeReportsTheShippedVersion() throws {
        let response = try XCTUnwrap(handler.handle(request("initialize", ["protocolVersion": "2025-06-18"])))
        let info = try XCTUnwrap((response["result"] as? [String: Any])?["serverInfo"] as? [String: Any])
        let shipped = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertEqual(info["version"] as? String, shipped)
    }

    func testAFailedOpenReadsAsASentence() throws {
        let failing = MCPHandler(storeURL: file, opener: { _ in false }, iconFetch: { _ in nil })
        let response = try XCTUnwrap(failing.handle(request("tools/call", ["name": "search_site", "arguments": ["site": "google", "query": "x"]])))
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let text = try XCTUnwrap((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertTrue(text.contains("could not open"), text)
        XCTAssertFalse(text.contains("openFailed("), text)
    }

    func testAWrongTypedArgumentIsRejectedNotIgnored() throws {
        let result = try callTool("update_site", ["site": "google", "name": 42])
        XCTAssertTrue(result.isError, result.text)
        XCTAssertEqual(SiteOps.find(SiteStore.load(from: file), "google")?.name, "Google")
    }

    func testUpdateSiteCanTurnASearchIntoABookmark() throws {
        let result = try callTool("update_site", ["site": "google", "template": "https://www.google.com/"])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(SiteOps.find(SiteStore.load(from: file), "google")?.isBookmark, true)
    }

    func testEveryListedToolIsDispatched() throws {
        let response = try XCTUnwrap(handler.handle(request("tools/list")))
        let tools = try XCTUnwrap((response["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        for name in tools.compactMap({ $0["name"] as? String }) {
            let reply = try XCTUnwrap(handler.handle(request("tools/call", ["name": name, "arguments": [:] as [String: Any]])))
            XCTAssertNil(reply["error"], "\(name) is listed but not dispatched")
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
        XCTAssertEqual(SiteEntityQuery.filter(sites, matching: "hn").count, 1, "keyword prefix should match")
        XCTAssertEqual(SiteEntityQuery.filter(sites, matching: "hacker").count, 1, "name substring should match")
        XCTAssertTrue(SiteEntityQuery.filter(sites, matching: "zzz").isEmpty)
    }
}

final class LinkInferenceTests: XCTestCase {
    func testGitHubRepoLinkBecomesABookmarkOfTheRepo() throws {
        let hit = try XCTUnwrap(LinkInference.infer(from: "https://github.com/Zamua/sitesearch"))
        XCTAssertEqual(hit.name, "sitesearch")
        XCTAssertEqual(hit.keyword, "sitesearch")
        // No {query}: the inferred entry is a bookmark, so it lands in the
        // sb action and opens the repo page directly.
        XCTAssertEqual(hit.template, "https://github.com/Zamua/sitesearch")
    }

    func testDeepRepoPathsAndGitSuffixStillResolveTheRepo() throws {
        let deep = try XCTUnwrap(LinkInference.infer(from: "https://github.com/apple/swift/tree/main/stdlib"))
        XCTAssertEqual(deep.name, "swift")
        let cloneURL = try XCTUnwrap(LinkInference.infer(from: "https://github.com/apple/swift.git"))
        XCTAssertEqual(cloneURL.name, "swift")
    }

    func testKeywordIsLowercasedEvenWhenRepoIsNot() throws {
        let hit = try XCTUnwrap(LinkInference.infer(from: "https://github.com/torvalds/Linux"))
        XCTAssertEqual(hit.name, "Linux")
        XCTAssertEqual(hit.keyword, "linux")
    }

    func testNonRepoGitHubPathsAreDeclined() {
        XCTAssertNil(LinkInference.infer(from: "https://github.com/topics/swift"))
        XCTAssertNil(LinkInference.infer(from: "https://github.com/orgs/apple/repositories"))
        XCTAssertNil(LinkInference.infer(from: "https://github.com/torvalds"))
        XCTAssertNil(LinkInference.infer(from: "https://github.com/search?q=x"))
    }

    func testUnknownHostsAndNonURLsAreDeclined() {
        XCTAssertNil(LinkInference.infer(from: "https://gitlab.com/group/project"))
        XCTAssertNil(LinkInference.infer(from: "not a url at all"))
        XCTAssertNil(LinkInference.infer(from: "file:///etc/hosts"))
    }

    func testInferredEntryIsABookmarkAndResolvesDirectly() throws {
        let hit = try XCTUnwrap(LinkInference.infer(from: "https://github.com/Zamua/sitesearch"))
        let site = Site(keyword: hit.keyword, name: hit.name, template: hit.template)
        XCTAssertTrue(site.isBookmark)
        let url = try SiteURL.resolve(template: hit.template, query: nil)
        XCTAssertEqual(url.absoluteString, "https://github.com/Zamua/sitesearch")
    }

    func testDraftFromARepoLinkIsABookmarkWithAFreeKeyword() {
        let existing = [Site(keyword: "SiteSearch", name: "x", template: "https://x.example/?q={query}")]
        let draft = LinkInference.draftSite(pasted: "https://github.com/Zamua/sitesearch", among: existing)
        XCTAssertTrue(draft.isBookmark)
        XCTAssertEqual(draft.name, "sitesearch")
        XCTAssertEqual(draft.keyword, "sitesearch2", "keyword collides case-insensitively with an existing one")
    }

    func testDraftWithNothingRecognizedIsABlankSearchRow() {
        let draft = LinkInference.draftSite(pasted: "not a link", among: [])
        XCTAssertEqual(draft.keyword, "")
        XCTAssertFalse(draft.isBookmark)
        XCTAssertEqual(LinkInference.draftSite(pasted: nil, among: []).keyword, "")
    }
}

/// The config window's sync loop, driven by event sequences.
final class ConfigSyncTests: XCTestCase {
    private let a = Site(keyword: "a", name: "A", template: "https://a.example/?q={query}")
    private let b = Site(keyword: "b", name: "B", template: "https://b.example/?q={query}")
    private let t0 = Date(timeIntervalSince1970: 0)
    private let t1 = Date(timeIntervalSince1970: 1)

    private func opened(_ sites: [Site]) -> ConfigSync {
        var sync = ConfigSync(sites: sites)
        _ = sync.handle(.appeared(stamp: t0))
        return sync
    }

    private func renamed(_ site: Site, _ name: String) -> Site {
        var s = site
        s.name = name
        return s
    }

    func testOpeningBaselinesTheListAndBackfillsIcons() {
        var sync = ConfigSync(sites: [a])
        XCTAssertEqual(sync.handle(.appeared(stamp: t0)), [.refreshIcons(previous: [], current: [a])])
        XCTAssertEqual(sync.baseline, [a])
        XCTAssertEqual(sync.seenStamp, t0)
    }

    func testAnEditIsSavedOnceTheDebounceElapses() {
        var sync = opened([a])
        let edit = [renamed(a, "A2")]
        XCTAssertEqual(sync.handle(.edited(edit)), [.scheduleSave(after: ConfigSync.debounce)])
        XCTAssertEqual(sync.phase, .saveScheduled)
        XCTAssertEqual(sync.handle(.saveDue), [.save(edited: edit, baseline: [a])])
        XCTAssertEqual(sync.phase, .idle)
        XCTAssertEqual(sync.handle(.saved(written: edit, stamp: t1)), [.refreshIcons(previous: [a], current: edit)])
        XCTAssertEqual(sync.baseline, edit)
        XCTAssertEqual(sync.seenStamp, t1)
    }

    func testAnUnchangedListIsNotAnEdit() {
        var sync = opened([a])
        XCTAssertEqual(sync.handle(.edited([a])), [])
        XCTAssertEqual(sync.phase, .idle)
    }

    func testATimerWithNoSaveScheduledDoesNothing() {
        var sync = opened([a])
        XCTAssertEqual(sync.handle(.saveDue), [])
    }

    func testAFailedSaveKeepsTheEditPendingAndRetries() {
        var sync = opened([a])
        let edit = [renamed(a, "A2")]
        _ = sync.handle(.edited(edit))
        _ = sync.handle(.saveDue)
        XCTAssertEqual(sync.handle(.saveFailed("disk full")), [.scheduleSave(after: ConfigSync.retry)])
        XCTAssertEqual(sync.saveError, "disk full")
        XCTAssertEqual(sync.baseline, [a], "the edit must stay pending")
        XCTAssertEqual(sync.handle(.saveDue), [.save(edited: edit, baseline: [a])])
        _ = sync.handle(.saved(written: edit, stamp: t1))
        XCTAssertNil(sync.saveError)
    }

    func testThePollReloadsOnlyWhenTheStampMoved() {
        var sync = opened([a])
        XCTAssertEqual(sync.handle(.polled(stamp: t0)), [])
        XCTAssertEqual(sync.handle(.polled(stamp: t1)), [.reload(stamp: t1)])
    }

    func testAReloadShowsExternalChangesAndKeepsPendingEdits() {
        var sync = opened([a])
        let edit = [renamed(a, "A2")]
        _ = sync.handle(.edited(edit))
        XCTAssertEqual(sync.handle(.reloaded(stamp: t1, disk: [a, b])), [])
        XCTAssertEqual(sync.sites, [renamed(a, "A2"), b])
        XCTAssertEqual(sync.baseline, [a, b])
        XCTAssertEqual(sync.phase, .saveScheduled, "the pending edit still saves")
        XCTAssertEqual(sync.handle(.polled(stamp: t1)), [])
    }

    func testAnImportSavesAtOnceAndAPendingDebounceIsDropped() {
        var sync = opened([a])
        _ = sync.handle(.edited([renamed(a, "A2")]))
        let entry = SiteExchange.Entry(name: b.name, keyword: b.keyword, template: b.template)
        let effects = sync.handle(.imported([entry]))
        guard case .save(let edited, let baseline)? = effects.first, effects.count == 1 else {
            return XCTFail("expected one immediate save, got \(effects)")
        }
        XCTAssertEqual(edited.map(\.name), ["A2", "B"])
        XCTAssertEqual(baseline, [a])
        XCTAssertEqual(sync.message, "Imported 1 site")
        XCTAssertEqual(sync.handle(.saveDue), [])
    }

    func testAStatusMessageLastsUntilTheNextEdit() {
        var sync = opened([a])
        let entry = SiteExchange.Entry(name: b.name, keyword: b.keyword, template: b.template)
        _ = sync.handle(.imported([entry]))
        XCTAssertEqual(sync.message, "Imported 1 site")
        _ = sync.handle(.edited([renamed(a, "A2")] + sync.sites.dropFirst()))
        XCTAssertNil(sync.message)

        _ = sync.handle(.importFailed(file: "x.sitesearch", reason: "bad"))
        XCTAssertEqual(sync.message, "Could not import x.sitesearch: bad")
        _ = sync.handle(.edited([renamed(a, "A3")]))
        XCTAssertNil(sync.message)
    }
}
