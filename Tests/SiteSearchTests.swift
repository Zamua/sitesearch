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
        SiteStore.save(SiteStore.defaults, to: file)
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
        SiteStore.save(SiteStore.defaults, to: file)
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
        SiteStore.save(SiteStore.defaults, to: file)
        XCTAssertThrowsError(try SiteStore.mutate(at: file) {
            try SiteOps.add(to: $0, name: "Bad", keyword: "bad", template: "not a url")
        })
        XCTAssertEqual(SiteStore.load(from: file).count, SiteStore.defaults.count)
    }

    func testLockIsReentrantEnoughForNestedReads() throws {
        SiteStore.save(SiteStore.defaults, to: file)
        let count = SiteStore.withLock(at: file) { SiteStore.load(from: file).count }
        XCTAssertEqual(count, SiteStore.defaults.count)
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
final class ReleaseConfigTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The bundle reported 1.0 for every release from 0.7.0 on, because the
    /// custom Info.plist hardcoded it. Homebrew and bug reports both read this.
    func testInfoPlistTracksTheBuildSettingVersions() throws {
        let plist = try read("Sources/Info.plist")
        XCTAssertTrue(plist.contains("$(MARKETING_VERSION)"),
                      "CFBundleShortVersionString must follow MARKETING_VERSION, not a literal")
        XCTAssertTrue(plist.contains("$(CURRENT_PROJECT_VERSION)"),
                      "CFBundleVersion must follow CURRENT_PROJECT_VERSION, not a literal")
    }

    /// Homebrew's `depends_on macos:` and the installer both read this, and the
    /// app genuinely cannot run below 26.
    func testInfoPlistDeclaresTheMinimumSystemVersion() throws {
        let plist = try read("Sources/Info.plist")
        XCTAssertTrue(plist.contains("LSMinimumSystemVersion"), "missing LSMinimumSystemVersion")
        XCTAssertTrue(plist.contains("26.0"), "minimum system version should be macOS 26")
    }

    /// Notarization rejects anything without the hardened runtime.
    func testHardenedRuntimeIsEnabled() throws {
        let project = try read("project.yml")
        XCTAssertFalse(project.contains("ENABLE_HARDENED_RUNTIME: NO"),
                       "notarization requires the hardened runtime")
        XCTAssertTrue(project.contains("ENABLE_HARDENED_RUNTIME: YES"))
    }

    /// The embedded MCP binary is a second executable inside the bundle; if it
    /// is not signed on copy, notarization fails on the nested code.
    func testEmbeddedToolIsCodeSignedOnCopy() throws {
        let project = try read("project.yml")
        XCTAssertTrue(project.contains("codeSign: true"),
                      "the copied sitesearch-mcp must be signed, or notarization rejects the bundle")
    }

    /// Signing the nested binary is not enough - it needs the hardened runtime
    /// in its own right. The app target having it does not cover the tool.
    func testEmbeddedToolAlsoEnablesTheHardenedRuntime() throws {
        let project = try read("project.yml")
        let enabled = project.components(separatedBy: "ENABLE_HARDENED_RUNTIME: YES").count - 1
        XCTAssertGreaterThanOrEqual(enabled, 2,
                                    "both the app and the sitesearch-mcp target need the hardened runtime")
    }

    /// Xcode injects com.apple.security.get-task-allow unless told not to, and
    /// the notary service rejects every binary carrying it ("The executable
    /// requests the com.apple.security.get-task-allow entitlement"). Both
    /// executables in the bundle are checked, so both targets must opt out for
    /// Release. Debug keeps it - that is what lets a debugger attach.
    func testReleaseDoesNotInjectTheDebuggerEntitlement() throws {
        let project = try read("project.yml")
        let optedOut = project.components(separatedBy: "CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO").count - 1
        XCTAssertGreaterThanOrEqual(optedOut, 2,
                                    "the app and sitesearch-mcp targets must both opt out of the injected debugger entitlement for Release")
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

    func testCachedDataIsNilUntilSomethingIsWritten() throws {
        let id = UUID()
        XCTAssertNil(Favicon.cachedData(for: id, in: tmp))
        try Data("png".utf8).write(to: Favicon.cacheURL(for: id, in: tmp))
        XCTAssertEqual(Favicon.cachedData(for: id, in: tmp), Data("png".utf8))
    }

    func testCacheURLIsPerSite() {
        let a = UUID(), b = UUID()
        XCTAssertNotEqual(Favicon.cacheURL(for: a, in: tmp), Favicon.cacheURL(for: b, in: tmp))
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
        XCTAssertEqual(Favicon.cachedData(for: site.id, in: tmp), png)
    }

    func testEnsureCachedSkipsTheNetworkWhenAlreadyCached() throws {
        let site = site("https://example.com/search?q={query}")
        try Data("existing".utf8).write(to: Favicon.cacheURL(for: site.id, in: tmp))
        var fetched: [URL] = []
        let ok = Favicon.ensureCached(for: site, in: tmp) { url in
            fetched.append(url)
            return Data("new".utf8)
        }
        XCTAssertTrue(ok)
        XCTAssertTrue(fetched.isEmpty, "re-fetched an icon it already had")
        XCTAssertEqual(Favicon.cachedData(for: site.id, in: tmp), Data("existing".utf8))
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
        XCTAssertEqual(Favicon.cachedData(for: site.id, in: tmp), png)
    }

    func testEnsureCachedWritesNothingWhenEverythingFails() {
        let site = site("https://example.com/search?q={query}")
        let ok = Favicon.ensureCached(for: site, in: tmp) { _ in nil }
        XCTAssertFalse(ok)
        XCTAssertNil(Favicon.cachedData(for: site.id, in: tmp))
    }

    func testEnsureCachedIgnoresEmptyResponses() {
        let site = site("https://example.com/search?q={query}")
        let ok = Favicon.ensureCached(for: site, in: tmp) { _ in Data() }
        XCTAssertFalse(ok, "an empty body is not an icon")
        XCTAssertNil(Favicon.cachedData(for: site.id, in: tmp))
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
        SiteStore.save(SiteStore.defaults, to: file)
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
        XCTAssertEqual(Favicon.cachedData(for: id, in: iconDir), Data("PNGBYTES".utf8))
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
        XCTAssertNil(Favicon.cachedData(for: try addedSiteID(text), in: iconDir))
    }

    func testChangingATemplateRefetchesTheIcon() throws {
        network.response = Data("OLD".utf8)
        let (addText, _) = try callTool("add_site", [
            "name": "Site", "keyword": "s1", "template": "https://one.example/?q={query}",
        ])
        let id = try addedSiteID(addText)
        XCTAssertEqual(Favicon.cachedData(for: id, in: iconDir), Data("OLD".utf8))

        network.response = Data("NEW".utf8)
        let (text, isError) = try callTool("update_site", [
            "site": "s1", "template": "https://two.example/?q={query}",
        ])
        XCTAssertFalse(isError, text)
        XCTAssertEqual(Favicon.cachedData(for: id, in: iconDir), Data("NEW".utf8),
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
