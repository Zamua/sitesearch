import SwiftUI

/// The config window: edit the list of sites Spotlight can search.
/// Changes save to disk immediately; the intent reads the file fresh on
/// every invocation, so there is no sync step.
struct ConfigView: View {
    @State private var sites: [Site] = SiteStore.load()
    @State private var selection: Site.ID?
    @State private var saveTask: Task<Void, Never>?
    @State private var syncMessage: String?
    @State private var showingExport = false
    @State private var importEntries: [SiteExchange.Entry]?

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
                    let added = QuickKeySync.sync()
                    syncMessage = added > 0
                        ? "Added \(added) Spotlight quick keys"
                        : "All quick keys already assigned"
                } label: {
                    Label("Set Up Quick Keys", systemImage: "command.square")
                }
                .help("Assigns each site's keyword as its Spotlight quick key, skipping any you've customized")

                Button {
                    showingExport = true
                } label: {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                .help("Export selected sites as a .sitesearch file others can double-click to import")

                Spacer()

                Text(syncMessage ?? "Type a quick key in Spotlight (Cmd-Space), e.g. repo query")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .onChange(of: sites) {
            // Debounced: a save per keystroke is needless disk churn and
            // widens the window where Spotlight reads a half-typed template.
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                SiteStore.save(sites)
            }
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
                SiteStore.save(sites)
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
