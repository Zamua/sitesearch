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
