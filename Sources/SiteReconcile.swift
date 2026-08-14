import Foundation

/// Three-way merge for the config window.
///
/// The window necessarily holds the whole list in `@State`, so writing that
/// list back wholesale would erase anything an agent added underneath it. This
/// reconciles instead: `baseline` is what the window last saw, `edited` is what
/// the user has now, `disk` is current truth. Only the window's actual changes
/// are applied on top of disk.
///
/// Membership in `baseline` is what separates "the window added this" from
/// "someone else deleted this", and per-field comparison against baseline is
/// what separates "the window changed this" from "leave the external value".
enum SiteReconcile {
    static func apply(edited: [Site], baseline: [Site], disk: [Site]) -> [Site] {
        let baselineByID = Dictionary(baseline.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let editedByID = Dictionary(edited.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let diskIDs = Set(disk.map(\.id))

        // Rows the window removed: present in baseline, gone from edited.
        let removedByWindow = Set(baseline.map(\.id)).subtracting(editedByID.keys)

        var result: [Site] = []
        for var site in disk {
            guard !removedByWindow.contains(site.id) else { continue }
            // Untouched by the window (or unknown to it) - keep disk's version.
            guard let edit = editedByID[site.id] else {
                result.append(site)
                continue
            }
            // Known to the window: take only the fields it actually changed,
            // leaving everything else at the external value.
            if let base = baselineByID[site.id] {
                if edit.name != base.name { site.name = edit.name }
                if edit.keyword != base.keyword { site.keyword = edit.keyword }
                if edit.template != base.template { site.template = edit.template }
            } else {
                site = edit
            }
            result.append(site)
        }

        // Rows the window added: unknown to baseline AND absent from disk. A
        // row the window knows from baseline but disk no longer has was
        // deleted externally, and must not be resurrected.
        for site in edited where !baselineByID.keys.contains(site.id) && !diskIDs.contains(site.id) {
            result.append(site)
        }

        return result
    }
}
