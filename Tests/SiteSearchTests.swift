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

    func testAddRejectsTemplateWithoutPlaceholder() {
        assertThrows(.missingPlaceholder("https://x.example/?q=")) {
            _ = try SiteOps.add(to: base, name: "X", keyword: "x", template: "https://x.example/?q=")
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
        assertThrows(.missingPlaceholder("https://x.example/")) {
            _ = try SiteOps.update(in: base, selector: "code", name: nil, keyword: nil, template: "https://x.example/")
        }
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
            try SiteOps.add(to: $0, name: "Bad", keyword: "bad", template: "https://x.example/")
        })
        XCTAssertEqual(SiteStore.load(from: file).count, SiteStore.defaults.count)
    }

    func testLockIsReentrantEnoughForNestedReads() throws {
        SiteStore.save(SiteStore.defaults, to: file)
        let count = SiteStore.withLock(at: file) { SiteStore.load(from: file).count }
        XCTAssertEqual(count, SiteStore.defaults.count)
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

final class MCPHandlerTests: XCTestCase {
    private var tmp: URL!
    private var recorder: OpenRecorder!
    private var handler: MCPHandler!
    private var file: URL { tmp.appendingPathComponent("sites.json") }

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sitesearch-mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        SiteStore.save(SiteStore.defaults, to: file)
        let recorder = OpenRecorder()
        self.recorder = recorder
        handler = MCPHandler(storeURL: file, opener: { recorder.record($0) })
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
        XCTAssertEqual(names, ["list_sites", "add_site", "update_site", "remove_site", "search_site"])
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
