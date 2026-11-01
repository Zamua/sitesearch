import XCTest
@testable import SiteSearch

/// The test bundle's principal class: loaded before any test runs, it fails
/// every test after which the user's real data changed. "Changed" means a file
/// in the real data directory modified since this process started (so a write
/// by the app's own launch work counts too), or a different quick-key store.
/// A real SiteSearch or MCP server writing during a local run trips it as well.
final class TestIsolation: NSObject, XCTestObservation {
    private let quickKeys = TestIsolation.quickKeyStore()

    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        testCase.addTeardownBlock { [quickKeys] in
            let touched = TestIsolation.touchedSinceLaunch(in: SiteStore.userDirectory)
            XCTAssertEqual(touched, [], "a test wrote the real data directory")
            XCTAssertEqual(TestIsolation.quickKeyStore(), quickKeys, "a test changed the real Spotlight quick keys")
        }
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        try? FileManager.default.removeItem(at: TestHost.directory)
    }

    /// The store in a canonical form, so two reads compare equal exactly when
    /// the store is unchanged.
    static func quickKeyStore() -> Data? {
        let store = CFPreferencesCopyAppValue(QuickKeySync.storeKey as CFString, QuickKeySync.suite as CFString)
        return store.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
    }

    /// Paths under `directory` modified at or after this process started.
    static func touchedSinceLaunch(in directory: URL) -> [String] {
        let started = processStart()
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return [] }
        return walker.compactMap { item in
            guard let url = item as? URL,
                  let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified >= started
            else { return nil }
            return url.path
        }
    }

    static func processStart() -> Date {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return .distantPast }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}

final class TestIsolationTests: XCTestCase {
    func testStorageUnderTheTestHostIsPrivateToTheRun() {
        XCTAssertTrue(TestHost.isActive)
        let temp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        XCTAssertTrue(TestHost.directory.standardizedFileURL.path.hasPrefix(temp))
        XCTAssertTrue(SiteStore.fileURL.path.hasPrefix(TestHost.directory.path))
        XCTAssertTrue(Favicon.directoryURL.path.hasPrefix(TestHost.directory.path))
        XCTAssertNotEqual(SiteStore.fileURL.deletingLastPathComponent(), SiteStore.userDirectory)
    }

    func testTheGuardSeesAWriteMadeDuringTheRun() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(TestIsolation.touchedSinceLaunch(in: dir), [])
        let file = dir.appendingPathComponent("sites.json")
        try Data("[]".utf8).write(to: file)
        let touched = TestIsolation.touchedSinceLaunch(in: dir)
        XCTAssertEqual(touched.count, 1)
        XCTAssertEqual(touched.first.map { URL(fileURLWithPath: $0).lastPathComponent }, file.lastPathComponent)
    }
}
