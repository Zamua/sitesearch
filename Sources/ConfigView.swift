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
    @State private var showingExport = false
    @State private var importEntries: [SiteExchange.Entry]?
    /// Modification stamp of the last write we know about, so our own saves
    /// are not mistaken for someone else's edit.
    @State private var seenStamp: Date?

    private let pollTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private static func stamp(of url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Table(sites, selection: $selection) {
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
                    let new = Site(keyword: "", name: "New Site", template: "https://example.com/search?q={query}")
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

                Text(syncMessage ?? "In Spotlight (Cmd-Space): ss, then a keyword, Tab, your query")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .onAppear {
            baseline = sites
            seenStamp = Self.stamp(of: SiteStore.fileURL)
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

    private struct ImportPayload: Identifiable {
        var entries: [SiteExchange.Entry]
        var id: String { entries.map(\.id).joined(separator: ",") }
    }

    /// Reconciles this window's edits against fresh disk state under the
    /// store's lock, so a site added by an agent is never overwritten.
    private func save() {
        let edited = sites
        let base = baseline
        let written = (try? SiteStore.mutate { disk in
            let result = SiteReconcile.apply(edited: edited, baseline: base, disk: disk)
            return (result, result)
        }) ?? edited
        sites = written
        baseline = written
        seenStamp = Self.stamp(of: SiteStore.fileURL)
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
