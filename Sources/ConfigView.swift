import SwiftUI

/// The config window: edit the list of sites Spotlight can search.
/// Changes save to disk immediately; the intent reads the file fresh on
/// every invocation, so there is no sync step.
struct ConfigView: View {
    @State private var sites: [Site] = SiteStore.load()
    @State private var selection: Site.ID?

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

                Spacer()

                Text("Run \"Search Site\" from Spotlight (Cmd-Space), then assign it a quick key.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .onChange(of: sites) {
            SiteStore.save(sites)
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
