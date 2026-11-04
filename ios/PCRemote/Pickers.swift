import SwiftUI

struct AppPickerView: View {
    enum Mode { case installed, running }

    let mode: Mode
    let onPick: (InstalledApp) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [InstalledApp] = []
    @State private var query = ""
    @State private var error = ""
    @State private var loading = true

    private var filtered: [InstalledApp] {
        query.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if loading { ProgressView() }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            ForEach(filtered) { app in
                Button {
                    onPick(app)
                    dismiss()
                } label: {
                    Text(app.name).foregroundStyle(.primary)
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search apps")
        .navigationTitle(mode == .installed ? "Installed apps" : "Running apps")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            items = mode == .installed ? try await API.installedApps() : try await API.runningApps()
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct PresetsView: View {
    @Environment(\.dismiss) private var dismiss
    let existing: Set<String>
    let onChanged: () async -> Void

    @State private var added: Set<String> = []
    @State private var error = ""

    var body: some View {
        NavigationStack {
            List {
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
                ForEach(Presets.all) { c in
                    let have = existing.contains(c.name) || added.contains(c.name)
                    Button {
                        Task { await add([c]) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).foregroundStyle(.primary)
                                Text(c.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: have ? "checkmark.circle.fill" : "plus.circle")
                                .foregroundStyle(have ? .green : .accentColor)
                        }
                    }
                    .disabled(have)
                }
            }
            .navigationTitle("Presets")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Add all") {
                        Task { await add(Presets.all.filter { !existing.contains($0.name) && !added.contains($0.name) }) }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func add(_ cmds: [Command]) async {
        for c in cmds {
            do {
                try await API.save(c)
                added.insert(c.name)
            } catch {
                self.error = error.localizedDescription
                break
            }
        }
        await onChanged()
    }
}
