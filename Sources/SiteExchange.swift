import Foundation
import UniformTypeIdentifiers

/// The .sitesearch share format: plain JSON, no ids (the receiver mints its
/// own so imported sites never collide with the sender's entity identifiers).
///
///   { "version": 1, "sites": [ { "name", "keyword", "template" }, ... ] }
enum SiteExchange {
    static let fileExtension = "sitesearch"
    static let contentType = UTType(exportedAs: "com.zamua.sitesearch.sites")

    struct Document: Codable {
        var version: Int
        var sites: [Entry]
    }

    struct Entry: Codable, Identifiable, Hashable {
        var name: String
        var keyword: String
        var template: String
        // Local identity for selection UI only; not serialized.
        var id: String { "\(name)|\(keyword)|\(template)" }

        private enum CodingKeys: String, CodingKey { case name, keyword, template }
    }

    static func export(_ sites: [Site]) throws -> Data {
        let doc = Document(version: 1, sites: sites.map {
            Entry(name: $0.name, keyword: $0.keyword, template: $0.template)
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(doc)
    }

    /// A shared file's entries, split into what can be imported and what
    /// cannot (with why), so the import sheet can say what it skipped.
    struct Parsed {
        var entries: [Entry]
        var rejected: [(entry: Entry, reason: String)]
    }

    /// The file is untrusted input: each entry must pass the same rules as a
    /// site added any other way. Keyword collisions are not a rejection; the
    /// merge suffixes them.
    static func parse(_ data: Data) throws -> Parsed {
        let doc = try JSONDecoder().decode(Document.self, from: data)
        guard doc.version == 1 else { throw ExchangeError.unsupportedVersion(doc.version) }
        var parsed = Parsed(entries: [], rejected: [])
        for entry in doc.sites {
            do {
                try SiteOps.validate(name: entry.name, keyword: entry.keyword, template: entry.template)
                parsed.entries.append(entry)
            } catch {
                parsed.rejected.append((entry, error.localizedDescription))
            }
        }
        return parsed
    }

    /// Merge semantics for import: entries whose (name, template) already
    /// exist are skipped; keyword collisions get a numeric suffix so the
    /// recipient's aliases stay unique. New UUIDs are always minted.
    static func merge(_ entries: [Entry], into sites: [Site]) -> (result: [Site], addedCount: Int) {
        var result = sites
        var existingPairs = Set(sites.map { "\($0.name)|\($0.template)" })
        var added = 0
        for entry in entries {
            guard !existingPairs.contains("\(entry.name)|\(entry.template)") else { continue }
            let keyword = SiteOps.uniqueKeyword(entry.keyword, among: result)
            result.append(Site(keyword: keyword, name: entry.name, template: entry.template))
            existingPairs.insert("\(entry.name)|\(entry.template)")
            added += 1
        }
        return (result, added)
    }
}

enum ExchangeError: Error, LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            return "This file uses format version \(v); this app understands version 1. Update SiteSearch and try again."
        }
    }
}
