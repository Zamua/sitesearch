import Foundation

// MCP stdio transport: newline-delimited JSON-RPC 2.0 on stdin/stdout.
// Lines that are not JSON objects are skipped rather than fatal - a client
// that sends garbage should not take the server down. Notifications produce
// no output. The loop ends when stdin closes.
let handler = MCPHandler()

while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let data = trimmed.data(using: .utf8),
          let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let response = handler.handle(request),
          let out = try? JSONSerialization.data(withJSONObject: response)
    else { continue }

    FileHandle.standardOutput.write(out)
    FileHandle.standardOutput.write(Data("\n".utf8))
}
