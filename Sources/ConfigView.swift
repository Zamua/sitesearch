import SwiftUI

/// The config window: edit the list of sites Spotlight can search.
/// Changes save to disk immediately; the intent reads the file fresh on
/// every invocation, so there is no sync step.
///
/// The window is not the only writer - the MCP server edits the same file - so
/// it never writes its `@State` list back wholesale. `baseline` records what it
/// last saw, saves reconcile against fresh disk state under the store's lock,
/// and a poll picks up external changes while the window is open.
struct ConfigView: View {
    @State private var sites: [Site] = SiteStore.load()
    @State private var baseline: [Site] = []
    @State private var selection: Site.ID?
    @State private var saveTask: Task<Void, Never>?
    @State private var syncMessage: String?
    @State private var saveError: String?
    @State private var showingExport = false
    @State private var importEntries: [SiteExchange.Entry]?
    /// Modification stamp of the last write we know about, so our own saves
    /// are not mistaken for someone else's edit.
    @State private var seenStamp: Date?
    /// Bumped when background icon fetches finish, to redraw the rows.
    @State private var iconGeneration = 0

    private let pollTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private static func stamp(of url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Table(sites, selection: $selection) {
                TableColumn("") { site in
                    SiteIcon(site: site, generation: iconGeneration)
                }
                .width(20)
                TableColumn("Name") { site in
                    TextField("Name", text: binding(for: site.id, \.name))
                }
                .width(min: 100, ideal: 130)
                TableColumn("Keyword") { site in
                    TextField("Keyword", text: binding(for: site.id, \.keyword))
                }
                .width(min: 60, ideal: 80)
                TableColumn("URL template ({query} = your search)") { site in
                    TextField("https://example.com/search?q={query}", text: binding(for: site.id, \.template))
                        .font(.system(.body, design: .monospaced))
                }
            }

            HStack(spacing: 12) {
                Button {
                    let new = LinkInference.draftSite(
                        pasted: NSPasteboard.general.string(forType: .string),
                        among: sites
                    )
                    sites.append(new)
                    selection = new.id
                } label: {
                    Label("Add Site", systemImage: "plus")
                }
                Button {
                    if let selection {
                        sites.removeAll { $0.id == selection }
                    }
                    selection = nil
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(selection == nil)

                Button {
                    showingExport = true
                } label: {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                .help("Export selected sites as a .sitesearch file others can double-click to import")

                Spacer()

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                } else {
                    Text(syncMessage ?? "In Spotlight (Cmd-Space): ss, then a keyword, Tab, your query")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .onAppear {
            baseline = sites
            seenStamp = Self.stamp(of: SiteStore.fileURL)
            refreshIcons(previous: [], current: sites)
        }
        .onChange(of: sites) {
            // Debounced: a save per keystroke is needless disk churn and
            // widens the window where Spotlight reads a half-typed template.
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                save()
            }
        }
        .onReceive(pollTimer) { _ in
            // Someone else (the MCP server) may have written while the window
            // sat open. Merge their changes in rather than overwriting them on
            // the next keystroke.
            let current = Self.stamp(of: SiteStore.fileURL)
            guard current != seenStamp else { return }
            seenStamp = current
            let merged = SiteReconcile.apply(edited: sites, baseline: baseline, disk: SiteStore.load())
            guard merged != sites else { return }
            saveTask?.cancel()
            sites = merged
            baseline = merged
        }
        .sheet(isPresented: $showingExport) {
            ExportSheet(sites: sites)
        }
        .sheet(item: Binding(
            get: { importEntries.map(ImportPayload.init) },
            set: { importEntries = $0?.entries }
        )) { payload in
            ImportSheet(entries: payload.entries) { chosen in
                let (merged, added) = SiteExchange.merge(chosen, into: sites)
                sites = merged
                save()
                syncMessage = "Imported \(added) site\(added == 1 ? "" : "s")"
            }
        }
        .onOpenURL { url in
            guard url.pathExtension.lowercased() == SiteExchange.fileExtension,
                  let data = try? Data(contentsOf: url),
                  let entries = try? SiteExchange.parse(data), !entries.isEmpty else { return }
            importEntries = entries
        }
    }

    /// A site's cached favicon, or a neutral glyph. `generation` exists purely
    /// to force a redraw when a background fetch lands, since the bytes live on
    /// disk rather than in view state.
    private struct SiteIcon: View {
        let site: Site
        let generation: Int

        var body: some View {
            if let data = Favicon.cachedData(for: site.id), let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct ImportPayload: Identifiable {
        var entries: [SiteExchange.Entry]
        var id: String { entries.map(\.id).joined(separator: ",") }
    }

    /// Reconciles this window's edits against fresh disk state under the
    /// store's lock, so a site added by an agent is never overwritten.
    private func save() {
        let edited = sites
        let base = baseline
        do {
            let written = try SiteStore.mutate { disk in
                let result = SiteReconcile.apply(edited: edited, baseline: base, disk: disk)
                return (result, result)
            }
            sites = written
            baseline = written
            saveError = nil
            seenStamp = Self.stamp(of: SiteStore.fileURL)
            refreshIcons(previous: base, current: written)
        } catch {
            // The baseline stays put, so the edit is still pending and the
            // next save retries it.
            saveError = error.localizedDescription
        }
    }

    /// Fetches any missing favicons off the main thread. Never blocks the UI,
    /// and never runs while Spotlight is drawing - the entity reads whatever
    /// is already cached.
    private func refreshIcons(previous: [Site], current: [Site]) {
        let previousByID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var wanted: [Site] = []
        for site in current {
            if let old = previousByID[site.id],
               Favicon.origin(forTemplate: old.template) != Favicon.origin(forTemplate: site.template) {
                Favicon.invalidate(site.id)
            }
            if Favicon.cachedData(for: site.id) == nil { wanted.append(site) }
        }
        guard !wanted.isEmpty else { return }
        let targets = wanted
        Task.detached(priority: .utility) {
            var fetched = false
            for site in targets where Favicon.ensureCached(for: site, fetch: Favicon.download) {
                fetched = true
            }
            if fetched {
                await MainActor.run { iconGeneration += 1 }
            }
        }
    }

    private func binding(for id: Site.ID, _ keyPath: WritableKeyPath<Site, String>) -> Binding<String> {
        Binding(
            get: {
                guard let site = sites.first(where: { $0.id == id }) else { return "" }
                return site[keyPath: keyPath]
            },
            set: { newValue in
                guard let idx = sites.firstIndex(where: { $0.id == id }) else { return }
                sites[idx][keyPath: keyPath] = newValue
            }
        )
    }
}
