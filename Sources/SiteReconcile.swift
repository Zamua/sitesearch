import Foundation

/// Three-way merge for the config window.
///
/// The window necessarily holds the whole list in `@State`, so writing that
/// list back wholesale would erase anything an agent added underneath it. This
/// reconciles instead: `baseline` is what the window last saw, `edited` is what
/// the user has now, `disk` is current truth. Only the window's actual changes
/// are applied on top of disk.
///
/// STUB (red): returns the window's list verbatim - the clobbering behaviour.
enum SiteReconcile {
    static func apply(edited: [Site], baseline: [Site], disk: [Site]) -> [Site] {
        _ = (baseline, disk)
        return edited
    }
}
