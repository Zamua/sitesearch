import SwiftUI

@main
struct SiteSearchApp: App {
    init() {
        // Idempotent, merge-only: registers the single `ss` quick key on every
        // launch without touching other apps' assignments. Independent of the
        // site list, so adding a site needs no sync.
        QuickKeySync.sync()
        // Backfill missing favicons at the app level, not just when the config
        // window appears: a fresh install seeds its defaults without icons,
        // and a launch that quits quickly can kill the window's fetch task
        // mid-flight. Every launch retries whatever is still missing.
        let missing = SiteStore.load().filter { Favicon.cachedData(for: $0.id) == nil }
        if !missing.isEmpty {
            Task.detached(priority: .utility) {
                for site in missing {
                    _ = Favicon.ensureCached(for: site, fetch: Favicon.download)
                }
            }
        }
    }

    var body: some Scene {
        // Single window: multiple config windows would each hold their own
        // @State copy of the site list and clobber each other's saves.
        Window("SiteSearch", id: "config") {
            ConfigView()
                .frame(minWidth: 560, minHeight: 360)
        }
        .windowResizability(.contentMinSize)
    }
}
