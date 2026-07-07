import SwiftUI

@main
struct SiteSearchApp: App {
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
