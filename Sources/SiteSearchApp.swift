import SwiftUI

@main
struct SiteSearchApp: App {
    init() {
        // Idempotent, merge-only: registers the single `ss` quick key on every
        // launch without touching other apps' assignments. Independent of the
        // site list, so adding a site needs no sync.
        QuickKeySync.sync()
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
