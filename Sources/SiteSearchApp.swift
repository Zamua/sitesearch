import SwiftUI

@main
struct SiteSearchApp: App {
    init() {
        // Idempotent, merge-only: registers the `ss` and `sb` quick keys on
        // every launch without touching other apps' assignments. Independent
        // of the site list, so adding a site needs no sync.
        QuickKeySync.sync()
        // Backfill missing favicons at the app level, not just when the config
        // window appears: a fresh install seeds its defaults without icons,
        // and a launch that quits quickly can kill the window's fetch task
        // mid-flight. Every launch retries whatever is still missing.
        let sites = SiteStore.load()
        Task.detached(priority: .utility) {
            Favicon.refresh(from: [], to: sites, fetch: Favicon.download)
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
