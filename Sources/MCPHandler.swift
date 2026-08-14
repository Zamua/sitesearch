import Foundation

/// The MCP server's request handling, as a pure function of (request, config
/// file) so it is testable without spawning a process or a browser. The stdio
/// loop in MCPMain/main.swift is a thin wrapper around this.
///
/// Transport is newline-delimited JSON-RPC 2.0 on stdin/stdout.
///
/// STUB (red): answers nothing.
struct MCPHandler {
    static let serverName = "sitesearch"
    static let serverVersion = "0.9.0"
    static let defaultProtocolVersion = "2025-06-18"

    let storeURL: URL
    let opener: @Sendable (URL) -> Bool

    init(storeURL: URL = SiteStore.fileURL, opener: @escaping @Sendable (URL) -> Bool = MCPHandler.openInBrowser) {
        self.storeURL = storeURL
        self.opener = opener
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

    /// Returns the response to send, or nil for notifications (which get none).
    func handle(_ request: [String: Any]) -> [String: Any]? {
        _ = request
        return nil
    }
}
