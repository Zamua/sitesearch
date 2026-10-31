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
    /// Every editable field of `Site`. A test checks this covers all stored
    /// properties but `id`, so a new field cannot be silently dropped on merge.
    static var fields: [WritableKeyPath<Site, String>] { [\.name, \.keyword, \.template] }

    /// What a save may write: the window's changes on top of disk, where a row
    /// the window changed or added is written only once it is valid
    /// (`SiteOps.problem`); until then disk's version stays. Rows the window
    /// did not touch are disk's own state and are kept as they are, valid or
    /// not, so a hand-edited row is never erased.
    static func persistable(edited: [Site], baseline: [Site], disk: [Site]) -> [Site] {
        let merged = apply(edited: edited, baseline: baseline, disk: disk)
        let diskByID = Dictionary(disk.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return merged.compactMap { site in
            if diskByID[site.id] == site { return site }
            return SiteOps.problem(with: site, among: merged) == nil ? site : diskByID[site.id]
        }
    }

    /// The window after reading `disk`: its unsaved edits shown on top of it,
    /// and `disk` as the new baseline, so those edits stay pending and the
    /// next save writes them. (Baselining the merged view instead would mark
    /// an unsaved edit as already saved.)
    static func absorb(disk: [Site], edited: [Site], baseline: [Site]) -> (shown: [Site], baseline: [Site]) {
        (apply(edited: edited, baseline: baseline, disk: disk), disk)
    }

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
                for field in fields where edit[keyPath: field] != base[keyPath: field] {
                    site[keyPath: field] = edit[keyPath: field]
                }
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
