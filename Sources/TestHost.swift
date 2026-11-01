import Foundation

/// The unit tests run inside the app itself (it is their test host), so when
/// XCTest is driving, the app's launch work stands down and its storage moves
/// to a directory private to the run: a test can never read or write the real
/// config, icons or Spotlight quick keys.
enum TestHost {
    static let isActive = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SiteSearchTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
}
