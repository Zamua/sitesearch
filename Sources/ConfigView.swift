import SwiftUI

/// The config window: edit the list of sites Spotlight can search. Changes
/// save to disk on their own; the intent reads the file fresh on every
/// invocation, so there is no sync step. `ConfigSync` owns the save, poll and
/// import state; this view forwards events to it and performs its effects.
struct ConfigView: View {
    @State private var sync = ConfigSync(sites: SiteStore.load())
    @State private var saveTimer: Task<Void, Never>?
    @State private var selection: Site.ID?
    @State private var showingExport = false
    @State private var importing: SiteExchange.Parsed?
    /// Bumped when background icon fetches finish, to redraw the rows.
    @State private var iconGeneration = 0

    private let pollTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private static func stamp(of url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    private var sites: [Site] { sync.sites }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Table(sites, selection: $selection) {
                TableColumn("") { site in
                    if let problem = SiteOps.problem(with: site, among: sites) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help(problem.localizedDescription)
                    } else {
                        SiteIcon(site: site, generation: iconGeneration)
                    }
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
                    send(.edited(sites + [new]))
                    selection = new.id
                } label: {
                    Label("Add Site", systemImage: "plus")
                }
                Button {
                    if let selection {
                        send(.edited(sites.filter { $0.id != selection }))
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

                if let saveError = sync.saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                } else if sites.contains(where: { SiteOps.problem(with: $0, among: sites) != nil }) {
                    Label("Rows marked with a warning are not saved until fixed.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else {
                    Text(sync.message ?? "In Spotlight (Cmd-Space): ss, then a keyword, Tab, your query")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .onAppear { send(.appeared(stamp: Self.stamp(of: SiteStore.fileURL))) }
        // Someone else (the MCP server) may write while the window sits open.
        .onReceive(pollTimer) { _ in send(.polled(stamp: Self.stamp(of: SiteStore.fileURL))) }
        .sheet(isPresented: $showingExport) {
            ExportSheet(sites: sites)
        }
        .sheet(item: Binding(
            get: { importing.map(ImportPayload.init) },
            set: { importing = $0?.parsed }
        )) { payload in
            ImportSheet(
                entries: payload.parsed.entries,
                skipped: payload.parsed.rejected.map { "\($0.entry.name): \($0.reason)" }
            ) { chosen in
                send(.imported(chosen))
            }
        }
        .onOpenURL { url in
            guard url.pathExtension.lowercased() == SiteExchange.fileExtension else { return }
            do {
                let parsed = try SiteExchange.parse(try Data(contentsOf: url))
                guard !parsed.entries.isEmpty || !parsed.rejected.isEmpty else { return }
                importing = parsed
            } catch {
                send(.importFailed(file: url.lastPathComponent, reason: error.localizedDescription))
            }
        }
    }

    /// A site's cached favicon, or a neutral glyph. `generation` exists purely
    /// to force a redraw when a background fetch lands, since the bytes live on
    /// disk rather than in view state.
    private struct SiteIcon: View {
        let site: Site
        let generation: Int

        var body: some View {
            if let data = Favicon.cachedData(for: site), let image = NSImage(data: data) {
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
        var parsed: SiteExchange.Parsed
        var id: String { (parsed.entries + parsed.rejected.map(\.entry)).map(\.id).joined(separator: ",") }
    }

    private func send(_ event: ConfigSync.Event) {
        for effect in sync.handle(event) { perform(effect) }
    }

    private func perform(_ effect: ConfigSync.Effect) {
        switch effect {
        case .scheduleSave(let delay):
            saveTimer?.cancel()
            saveTimer = Task {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                send(.saveDue)
            }
        case .save(let edited, let baseline):
            // Under the store's lock against fresh disk, so a site an agent
            // added meanwhile is never overwritten.
            do {
                let written = try SiteStore.mutate { disk in
                    let result = SiteReconcile.persistable(edited: edited, baseline: baseline, disk: disk)
                    return (result, result)
                }
                send(.saved(written: written, stamp: Self.stamp(of: SiteStore.fileURL)))
            } catch {
                send(.saveFailed(error.localizedDescription))
            }
        case .reload(let stamp):
            send(.reloaded(stamp: stamp, disk: SiteStore.load()))
        case .refreshIcons(let previous, let current):
            // Off the main thread: icon fetches hit the network, and Spotlight
            // only ever reads what is already cached.
            Task.detached(priority: .utility) {
                if Favicon.refresh(from: previous, to: current, fetch: Favicon.download) {
                    await MainActor.run { iconGeneration += 1 }
                }
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
                var edited = sites
                edited[idx][keyPath: keyPath] = newValue
                send(.edited(edited))
            }
        )
    }
}
