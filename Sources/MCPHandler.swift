import Foundation

/// The MCP server's request handling, as a pure function of (request, config
/// file) so it is testable without spawning a process or a browser. The stdio
/// loop in MCPMain/main.swift is a thin wrapper around this.
///
/// Transport is newline-delimited JSON-RPC 2.0 on stdin/stdout.
///
/// Every mutation goes through SiteStore.mutate, so an agent and the config
/// window can write concurrently without either clobbering the other, and a
/// site added here is searchable in Spotlight immediately - no slot, no
/// quick-key write, no relaunch.
struct MCPHandler {
    static let serverName = "sitesearch"
    static let defaultProtocolVersion = "2025-06-18"

    /// The app's marketing version. Inside the app bundle `Bundle.main` is the
    /// app; built standalone, the tool carries the same value in its embedded
    /// Info.plist.
    static var serverVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    let storeURL: URL
    let opener: @Sendable (URL) -> Bool
    /// Injected so tests never touch the network.
    let iconFetch: @Sendable (URL) -> Data?

    /// Icons live beside whichever config this handler is pointed at.
    var iconDirectory: URL {
        storeURL.deletingLastPathComponent().appendingPathComponent("icons")
    }

    init(
        storeURL: URL = SiteStore.fileURL,
        opener: @escaping @Sendable (URL) -> Bool = MCPHandler.openInBrowser,
        iconFetch: @escaping @Sendable (URL) -> Data? = Favicon.download
    ) {
        self.storeURL = storeURL
        self.opener = opener
        self.iconFetch = iconFetch
    }

    /// Opens a URL in the default browser. A CLI has no NSWorkspace worth
    /// linking AppKit for, so shell out to /usr/bin/open.
    static let openInBrowser: @Sendable (URL) -> Bool = { url in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Dispatch

    /// Returns the response to send, or nil for notifications (which get none).
    func handle(_ request: [String: Any]) -> [String: Any]? {
        let method = request["method"] as? String ?? ""
        let id = request["id"]
        // A request without an id is a notification: act, never answer.
        guard id != nil else { return nil }

        switch method {
        case "initialize":
            let params = request["params"] as? [String: Any]
            let version = params?["protocolVersion"] as? String ?? Self.defaultProtocolVersion
            return result(id, [
                "protocolVersion": version,
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": Self.serverName, "version": Self.serverVersion],
            ])
        case "ping":
            return result(id, [:])
        case "tools/list":
            return result(id, ["tools": Tool.allCases.map(\.schema)])
        case "tools/call":
            return callTool(request["params"] as? [String: Any] ?? [:], id: id)
        default:
            return error(id, -32601, "Unknown method: \(method)")
        }
    }

    private func callTool(_ params: [String: Any], id: Any?) -> [String: Any] {
        let name = params["name"] as? String ?? ""
        guard let tool = Tool(rawValue: name) else {
            return error(id, -32602, "Unknown tool: \(name)")
        }
        do {
            let call = try ToolCall(tool, arguments: params["arguments"])
            return toolResult(id, text: try run(call))
        } catch {
            // Tool failures are results with isError, not protocol errors: the
            // call succeeded, the operation did not, and the agent needs to
            // read why and retry.
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return toolResult(id, text: message, isError: true)
        }
    }

    // MARK: - Tools

    private func run(_ call: ToolCall) throws -> String {
        switch call {
        case .listSites:
            return try encode(SiteStore.load(from: storeURL).map(Self.describe))

        case .add(let name, let keyword, let template):
            let added = try SiteStore.mutate(at: storeURL) {
                try SiteOps.add(to: $0, name: name, keyword: keyword, template: template)
            }
            // Best-effort: a site whose icon will not load is still a good site.
            Favicon.ensureCached(for: added, in: iconDirectory, fetch: iconFetch)
            return try encode(Self.describe(added))

        case .update(let selector, let name, let keyword, let template):
            let previousOrigin = template.flatMap { _ in
                SiteOps.find(SiteStore.load(from: storeURL), selector)
                    .flatMap { Favicon.origin(forTemplate: $0.template) }
            }
            let updated = try SiteStore.mutate(at: storeURL) {
                try SiteOps.update(in: $0, selector: selector, name: name, keyword: keyword, template: template)
            }
            // Only re-fetch when the icon could actually have changed - a
            // rename should not hit the network.
            if let template, Favicon.origin(forTemplate: template) != previousOrigin {
                Favicon.invalidate(updated.id, in: iconDirectory)
                Favicon.ensureCached(for: updated, in: iconDirectory, fetch: iconFetch)
            }
            return try encode(Self.describe(updated))

        case .remove(let selector):
            let removed = try SiteStore.mutate(at: storeURL) {
                try SiteOps.remove(from: $0, selector: selector)
            }
            Favicon.invalidate(removed.id, in: iconDirectory)
            return try encode(Self.describe(removed))

        case .search(let selector, let query):
            guard let site = SiteOps.find(SiteStore.load(from: storeURL), selector) else {
                throw SiteOpError.notFound(selector)
            }
            // A bookmark has nothing to substitute, so the query is ignored.
            let url = try SiteURL.resolve(template: site.template, query: query)
            guard opener(url) else {
                throw SearchSiteError.openFailed(url.absoluteString)
            }
            return "Opened \(url.absoluteString)"
        }
    }

    private static func describe(_ site: Site) -> [String: String] {
        ["id": site.id.uuidString, "name": site.name, "keyword": site.keyword, "template": site.template]
    }

    private func encode(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - JSON-RPC envelopes

    private func result(_ id: Any?, _ value: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": value]
    }

    private func error(_ id: Any?, _ code: Int, _ message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func toolResult(_ id: Any?, text: String, isError: Bool = false) -> [String: Any] {
        result(id, [
            "content": [["type": "text", "text": text]],
            "isError": isError,
        ])
    }
}

/// The tool table. Every switch over it is exhaustive, so a new tool cannot be
/// advertised without a schema, argument parsing and an implementation.
enum Tool: String, CaseIterable {
    case listSites = "list_sites"
    case addSite = "add_site"
    case addBookmark = "add_bookmark"
    case updateSite = "update_site"
    case removeSite = "remove_site"
    case searchSite = "search_site"

    var schema: [String: Any] {
        ["name": rawValue, "description": description, "inputSchema": inputSchema]
    }

    private var description: String {
        switch self {
        case .listSites:
            return "List every configured site search and bookmark, with its keyword and URL template."
        case .addSite:
            return "Add a site search. It becomes usable in Spotlight immediately: Cmd-Space, 'ss', the keyword, Tab, the query."
        case .addBookmark:
            return "Save a URL to open directly - no query. Usable in Spotlight immediately: Cmd-Space, 'sb', the keyword, Return."
        case .updateSite:
            return "Change a site's name, keyword, or template. Omitted fields are left alone."
        case .removeSite:
            return "Delete a configured site search or bookmark."
        case .searchSite:
            return "Run a search now: builds the URL from the site's template and opens it in the default browser."
        }
    }

    private var inputSchema: [String: Any] {
        let site: [String: Any] = ["type": "string", "description": "The site's keyword (e.g. 'hn') or its id."]
        switch self {
        case .listSites:
            return Self.object([:], required: [])
        case .addSite:
            return Self.object([
                "name": ["type": "string", "description": "Display name shown in Spotlight, e.g. 'Hacker News'."],
                "keyword": ["type": "string", "description": "Short alias typed to pick the site, e.g. 'hn'. Must be unique."],
                "template": ["type": "string", "description": "Search URL with the literal placeholder {query}, e.g. https://hn.algolia.com/?q={query}"],
            ], required: ["name", "keyword", "template"])
        case .addBookmark:
            return Self.object([
                "name": ["type": "string", "description": "Display name shown in Spotlight, e.g. 'SiteSearch Repo'."],
                "keyword": ["type": "string", "description": "Short alias typed to open it, e.g. 'repo1'. Must be unique across sites and bookmarks."],
                "template": ["type": "string", "description": "The URL to open, with NO {query} placeholder, e.g. https://github.com/zamua/sitesearch"],
            ], required: ["name", "keyword", "template"])
        case .updateSite:
            return Self.object([
                "site": site,
                "name": ["type": "string"],
                "keyword": ["type": "string"],
                "template": ["type": "string", "description": "A search URL with {query}, or a plain URL to make it a bookmark."],
            ], required: ["site"])
        case .removeSite:
            return Self.object(["site": site], required: ["site"])
        case .searchSite:
            return Self.object([
                "site": site,
                "query": ["type": "string", "description": "What to search for."],
            ], required: ["site", "query"])
        }
    }

    private static func object(_ properties: [String: Any], required: [String]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required]
    }
}

/// A tool call's arguments, parsed once at the edge into exactly what each
/// tool needs. A present argument of the wrong type is an error, never a
/// silently-omitted field.
enum ToolCall {
    case listSites
    case add(name: String, keyword: String, template: String)
    case update(selector: String, name: String?, keyword: String?, template: String?)
    case remove(selector: String)
    case search(selector: String, query: String)

    init(_ tool: Tool, arguments: Any?) throws {
        let args: [String: Any]
        switch arguments {
        case nil, is NSNull: args = [:]
        case let object as [String: Any]: args = object
        default: throw MCPArgumentError.notAnObject
        }
        switch tool {
        case .listSites:
            self = .listSites
        case .addSite, .addBookmark:
            // Storage accepts either kind; the two tools exist so an agent
            // states which it means and is told when it mixes them up.
            let template = try Self.required(args, "template")
            switch (tool, SiteURL.requiresQuery(template)) {
            case (.addSite, false): throw SiteOpError.missingPlaceholder(template)
            case (.addBookmark, true): throw MCPArgumentError.unexpectedPlaceholder(template)
            default: break
            }
            self = .add(name: try Self.required(args, "name"), keyword: try Self.required(args, "keyword"), template: template)
        case .updateSite:
            self = .update(
                selector: try Self.required(args, "site"),
                name: try Self.optional(args, "name"),
                keyword: try Self.optional(args, "keyword"),
                template: try Self.optional(args, "template")
            )
        case .removeSite:
            self = .remove(selector: try Self.required(args, "site"))
        case .searchSite:
            self = .search(selector: try Self.required(args, "site"), query: try Self.required(args, "query"))
        }
    }

    private static func required(_ args: [String: Any], _ key: String) throws -> String {
        guard let value = try optional(args, key) else { throw MCPArgumentError.missing(key) }
        return value
    }

    private static func optional(_ args: [String: Any], _ key: String) throws -> String? {
        guard let value = args[key], !(value is NSNull) else { return nil }
        guard let string = value as? String else { throw MCPArgumentError.notAString(key) }
        return string
    }
}

enum MCPArgumentError: Error, LocalizedError {
    case missing(String)
    case notAString(String)
    case notAnObject
    case unexpectedPlaceholder(String)

    var errorDescription: String? {
        switch self {
        case .missing(let key):
            return "Missing required argument '\(key)'."
        case .notAString(let key):
            return "Argument '\(key)' must be a string."
        case .notAnObject:
            return "Tool arguments must be a JSON object."
        case .unexpectedPlaceholder(let template):
            return "A bookmark opens a fixed URL, so its template must not contain {query}: \(template). Use add_site for a search."
        }
    }
}
