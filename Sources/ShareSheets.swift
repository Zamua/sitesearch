import SwiftUI
import AppKit

/// Export: pick which sites to share, then hand a .sitesearch file to the
/// system share sheet or save it directly.
struct ExportSheet: View {
    let sites: [Site]
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Site.ID>
    @State private var shareURL: URL?

    init(sites: [Site]) {
        self.sites = sites
        _selected = State(initialValue: Set(sites.map(\.id)))
    }

    private var selectedSites: [Site] { sites.filter { selected.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share Sites").font(.headline)
            Text("Pick the search patterns to include. The file carries only name, keyword, and URL template.")
                .font(.callout).foregroundStyle(.secondary)

            List(sites) { site in
                Toggle(isOn: Binding(
                    get: { selected.contains(site.id) },
                    set: { on in if on { selected.insert(site.id) } else { selected.remove(site.id) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(site.name)
                        Text(site.template).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .frame(minHeight: 220)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text("\(selected.count) selected").font(.callout).foregroundStyle(.secondary)
                if let shareURL {
                    ShareLink(item: shareURL) { Label("Share", systemImage: "square.and.arrow.up") }
                        .disabled(selected.isEmpty)
                }
                Button("Save…") { save() }.disabled(selected.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 480)
        .onAppear { regenerate() }
        .onChange(of: selected) { regenerate() }
    }

    /// ShareLink needs its item up front, so the temp file is regenerated on
    /// every selection change (it is a few hundred bytes).
    private func regenerate() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SiteSearchExport", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("My Sites.\(SiteExchange.fileExtension)")
        if let data = try? SiteExchange.export(selectedSites) {
            try? data.write(to: url, options: .atomic)
            shareURL = url
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [SiteExchange.contentType]
        panel.nameFieldStringValue = "My Sites.\(SiteExchange.fileExtension)"
        if panel.runModal() == .OK, let dest = panel.url,
           let data = try? SiteExchange.export(selectedSites) {
            try? data.write(to: dest, options: .atomic)
            dismiss()
        }
    }
}

/// Import: preview what a received .sitesearch file would add, with per-site
/// toggles so the recipient can take only what they want.
struct ImportSheet: View {
    let entries: [SiteExchange.Entry]
    /// Entries the file carried that cannot be imported, each with why.
    let skipped: [String]
    let onImport: ([SiteExchange.Entry]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>

    init(entries: [SiteExchange.Entry], skipped: [String], onImport: @escaping ([SiteExchange.Entry]) -> Void) {
        self.entries = entries
        self.skipped = skipped
        self.onImport = onImport
        _selected = State(initialValue: Set(entries.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Shared Sites").font(.headline)
            Text("Turn off anything you don't want. Duplicates of sites you already have are skipped automatically.")
                .font(.callout).foregroundStyle(.secondary)

            List(entries) { entry in
                Toggle(isOn: Binding(
                    get: { selected.contains(entry.id) },
                    set: { on in if on { selected.insert(entry.id) } else { selected.remove(entry.id) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.name)
                            if !entry.keyword.isEmpty {
                                Text(entry.keyword)
                                    .font(.caption).padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        Text(entry.template).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .frame(minHeight: 220)

            if !skipped.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Skipped \(skipped.count) that cannot be imported:", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    ForEach(skipped, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
                .font(.callout)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add \(selected.count) Site\(selected.count == 1 ? "" : "s")") {
                    onImport(entries.filter { selected.contains($0.id) })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 480)
    }
}
