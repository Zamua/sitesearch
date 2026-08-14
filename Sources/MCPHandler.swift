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
    static let serverVersion = "0.9.0"
    static let defaultProtocolVersion = "2025-06-18"

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
            return result(id, ["tools": Self.toolSchemas])
        case "tools/call":
            return callTool(request["params"] as? [String: Any] ?? [:], id: id)
        default:
            return error(id, -32601, "Unknown method: \(method)")
        }
    }

    private func callTool(_ params: [String: Any], id: Any?) -> [String: Any] {
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        guard Self.toolNames.contains(name) else {
            return error(id, -32602, "Unknown tool: \(name)")
        }
        do {
            return toolResult(id, text: try run(tool: name, args: args))
        } catch {
            // Tool failures are results with isError, not protocol errors: the
            // call succeeded, the operation did not, and the agent needs to
            // read why and retry.
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return toolResult(id, text: message, isError: true)
        }
    }

    // MARK: - Tools

    private func run(tool: String, args: [String: Any]) throws -> String {
        switch tool {
        case "list_sites":
            return try encode(SiteStore.load(from: storeURL).map(Self.describe))

        case "add_site", "add_bookmark":
            // Storage accepts either kind; the two tools exist so an agent
            // states which it means and gets told when it mixes them up.
            let template = try string(args, "template")
            let wantsSearch = tool == "add_site"
            if wantsSearch, !SiteURL.requiresQuery(template) {
                throw SiteOpError.missingPlaceholder(template)
            }
            if !wantsSearch, SiteURL.requiresQuery(template) {
                throw MCPArgumentError.unexpectedPlaceholder(template)
            }
            let added = try SiteStore.mutate(at: storeURL) {
                try SiteOps.add(
                    to: $0,
                    name: try string(args, "name"),
                    keyword: try string(args, "keyword"),
                    template: template
                )
            }
            // Best-effort: a site whose icon will not load is still a good site.
            Favicon.ensureCached(for: added, in: iconDirectory, fetch: iconFetch)
            return try encode(Self.describe(added))

        case "update_site":
            let selector = try string(args, "site")
            let newTemplate = args["template"] as? String
            let previousOrigin = newTemplate.flatMap { _ in
                SiteOps.find(SiteStore.load(from: storeURL), selector)
                    .flatMap { Favicon.origin(forTemplate: $0.template) }
            }
            let updated = try SiteStore.mutate(at: storeURL) {
                try SiteOps.update(
                    in: $0,
                    selector: selector,
                    name: args["name"] as? String,
                    keyword: args["keyword"] as? String,
                    template: newTemplate
                )
            }
            // Only re-fetch when the icon could actually have changed - a
            // rename should not hit the network.
            if let newTemplate, Favicon.origin(forTemplate: newTemplate) != previousOrigin {
                Favicon.invalidate(updated.id, in: iconDirectory)
                Favicon.ensureCached(for: updated, in: iconDirectory, fetch: iconFetch)
            }
            return try encode(Self.describe(updated))

        case "remove_site":
            let removed = try SiteStore.mutate(at: storeURL) {
                try SiteOps.remove(from: $0, selector: try string(args, "site"))
            }
            Favicon.invalidate(removed.id, in: iconDirectory)
            return try encode(Self.describe(removed))

        case "search_site":
            let selector = try string(args, "site")
            let query = try string(args, "query")
            let sites = SiteStore.load(from: storeURL)
            guard let site = SiteOps.find(sites, selector) else {
                throw SiteOpError.notFound(selector)
            }
            // A bookmark has nothing to substitute, so the query is ignored.
            let url = try SiteURL.resolve(template: site.template, query: query)
            guard opener(url) else {
                throw SearchSiteError.openFailed(url.absoluteString)
            }
            return "Opened \(url.absoluteString)"

        default:
            throw SiteOpError.notFound(tool)
        }
    }

    private func string(_ args: [String: Any], _ key: String) throws -> String {
        guard let value = args[key] as? String else {
            throw MCPArgumentError.missing(key)
        }
        return value
    }

    private static func describe(_ site: Site) -> [String: String] {
        ["id": site.id.uuidString, "name": site.name, "keyword": site.keyword, "template": site.template]
    }

    private func encode(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Schemas

    static let toolNames: Set<String> = ["list_sites", "add_site", "add_bookmark", "update_site", "remove_site", "search_site"]

    private static func schema(_ properties: [String: Any], required: [String]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required]
    }

    // Computed, not stored: a stored [String: Any] is not Sendable and Swift 6
    // rejects it as shared mutable state.
    private static var siteSelector: [String: Any] {
        ["type": "string", "description": "The site's keyword (e.g. 'hn') or its id."]
    }

    static var toolSchemas: [[String: Any]] { [
        [
            "name": "list_sites",
            "description": "List every configured site search, with its keyword and URL template.",
            "inputSchema": schema([:], required: []),
        ],
        [
            "name": "add_site",
            "description": "Add a site search. It becomes usable in Spotlight immediately: Cmd-Space, 'ss', the keyword, Tab, the query.",
            "inputSchema": schema([
                "name": ["type": "string", "description": "Display name shown in Spotlight, e.g. 'Hacker News'."],
                "keyword": ["type": "string", "description": "Short alias typed to pick the site, e.g. 'hn'. Must be unique."],
                "template": ["type": "string", "description": "Search URL with the literal placeholder {query}, e.g. https://hn.algolia.com/?q={query}"],
            ], required: ["name", "keyword", "template"]),
        ],
        [
            "name": "add_bookmark",
            "description": "Save a URL to open directly - no query. Usable in Spotlight immediately: Cmd-Space, 'ss', the keyword, Return.",
            "inputSchema": schema([
                "name": ["type": "string", "description": "Display name shown in Spotlight, e.g. 'SiteSearch Repo'."],
                "keyword": ["type": "string", "description": "Short alias typed to open it, e.g. 'repo1'. Must be unique across sites and bookmarks."],
                "template": ["type": "string", "description": "The URL to open, with NO {query} placeholder, e.g. https://github.com/zamua/sitesearch"],
            ], required: ["name", "keyword", "template"]),
        ],
        [
            "name": "update_site",
            "description": "Change a site's name, keyword, or template. Omitted fields are left alone.",
            "inputSchema": schema([
                "site": siteSelector,
                "name": ["type": "string"],
                "keyword": ["type": "string"],
                "template": ["type": "string", "description": "Must contain {query}."],
            ], required: ["site"]),
        ],
        [
            "name": "remove_site",
            "description": "Delete a configured site search.",
            "inputSchema": schema(["site": siteSelector], required: ["site"]),
        ],
        [
            "name": "search_site",
            "description": "Run a search now: builds the URL from the site's template and opens it in the default browser.",
            "inputSchema": schema([
                "site": siteSelector,
                "query": ["type": "string", "description": "What to search for."],
            ], required: ["site", "query"]),
        ],
    ] }

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

enum MCPArgumentError: Error, LocalizedError {
    case missing(String)
    case unexpectedPlaceholder(String)

    var errorDescription: String? {
        switch self {
        case .missing(let key):
            return "Missing required argument '\(key)'."
        case .unexpectedPlaceholder(let template):
            return "A bookmark opens a fixed URL, so its template must not contain {query}: \(template). Use add_site for a search."
        }
    }
}
