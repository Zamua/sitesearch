import SwiftUI

@main
struct SiteSearchApp: App {
    init() {
        // Idempotent, merge-only: assigns default Spotlight quick keys on
        // every launch without touching user customizations.
        QuickKeySync.sync()
        // Expand parameterized App Shortcut phrases from the current config.
        SiteSearchShortcuts.updateAppShortcutParameters()
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
