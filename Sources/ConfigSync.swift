import Foundation

/// The config window's sync loop: what it shows, what it last read from disk,
/// and whether a save is due. `handle` is the only place this state changes;
/// the window forwards events to it and performs the effects it returns.
///
/// The window is not the only writer (the MCP server edits the same file), so
/// it never writes its list back wholesale: a save reconciles the edits
/// (`sites` against `baseline`) with fresh disk state under the store's lock,
/// and a poll absorbs external changes while the window is open.
struct ConfigSync {
    /// What the window shows, unsaved edits included.
    private(set) var sites: [Site]
    /// Disk as the window last read it; the edits are the difference.
    private(set) var baseline: [Site] = []
    /// Modification stamp of the last write we know about, so our own saves
    /// are not mistaken for someone else's edit.
    private(set) var seenStamp: Date?
    /// Why the last save failed, until one succeeds.
    private(set) var saveError: String?
    /// A status line for an import's outcome, until the user's next edit.
    private(set) var message: String?
    private(set) var phase: Phase = .idle

    enum Phase: Equatable {
        case idle
        /// A save runs when the scheduled delay passes.
        case saveScheduled
    }

    enum Event {
        /// The window opened; `stamp` is the file's at that moment.
        case appeared(stamp: Date?)
        /// The user changed the table.
        case edited([Site])
        /// A scheduled delay passed.
        case saveDue
        case saved(written: [Site], stamp: Date?)
        case saveFailed(String)
        /// The poll read the file's stamp.
        case polled(stamp: Date?)
        case reloaded(stamp: Date?, disk: [Site])
        case imported([SiteExchange.Entry])
        case importFailed(file: String, reason: String)
    }

    enum Effect: Equatable {
        /// Replaces any save already scheduled.
        case scheduleSave(after: Duration)
        /// Performed synchronously: its outcome is the next event, so the state
        /// it answers is the one that asked for it.
        case save(edited: [Site], baseline: [Site])
        case reload(stamp: Date?)
        case refreshIcons(previous: [Site], current: [Site])
    }

    /// A save per keystroke is needless disk churn and widens the window where
    /// Spotlight reads a half-typed template.
    static let debounce: Duration = .milliseconds(400)
    /// A failed save keeps retrying while the window is open, so an edit made
    /// during a transient failure still lands without another keystroke.
    static let retry: Duration = .seconds(3)

    init(sites: [Site]) {
        self.sites = sites
    }

    mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .appeared(let stamp):
            baseline = sites
            seenStamp = stamp
            return [.refreshIcons(previous: [], current: sites)]

        case .edited(let edited):
            guard edited != sites else { return [] }
            sites = edited
            message = nil
            phase = .saveScheduled
            return [.scheduleSave(after: Self.debounce)]

        case .saveDue:
            // A timer can outlive the save it was for: an import saves at once.
            guard phase == .saveScheduled else { return [] }
            phase = .idle
            return [.save(edited: sites, baseline: baseline)]

        case .saved(let written, let stamp):
            let previous = baseline
            // A row held back as invalid stays on screen and pending, so the
            // user keeps typing into it instead of watching it revert.
            (sites, baseline) = SiteReconcile.absorb(disk: written, edited: sites, baseline: baseline)
            saveError = nil
            seenStamp = stamp
            return [.refreshIcons(previous: previous, current: written)]

        case .saveFailed(let reason):
            // The baseline stays put, so the edit is still pending.
            saveError = reason
            phase = .saveScheduled
            return [.scheduleSave(after: Self.retry)]

        case .polled(let stamp):
            return stamp == seenStamp ? [] : [.reload(stamp: stamp)]

        case .reloaded(let stamp, let disk):
            seenStamp = stamp
            (sites, baseline) = SiteReconcile.absorb(disk: disk, edited: sites, baseline: baseline)
            return []

        case .imported(let entries):
            let (merged, added) = SiteExchange.merge(entries, into: sites)
            sites = merged
            message = "Imported \(added) site\(added == 1 ? "" : "s")"
            phase = .idle
            return [.save(edited: sites, baseline: baseline)]

        case .importFailed(let file, let reason):
            message = "Could not import \(file): \(reason)"
            return []
        }
    }
}
