import SwiftUI

@main
struct SiteSearchApp: App {
    var body: some Scene {
        WindowGroup {
            ConfigView()
                .frame(minWidth: 560, minHeight: 360)
        }
        .windowResizability(.contentMinSize)
    }
}
