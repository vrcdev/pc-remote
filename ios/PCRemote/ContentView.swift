import SwiftUI
import AppIntents

struct ContentView: View {
    @State private var commands: [Command] = []
    @State private var status = ""
    @State private var editing: EditTarget?
    @State private var showSettings = false

    struct EditTarget: Identifiable {
        let id = UUID()
        let command: Command
        let original: String?
    }

    var body: some View {
        NavigationStack {
            List {
                if !status.isEmpty {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(commands) { c in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.headline)
                            Text(c.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Button { Task { await run(c) } } label: { Image(systemName: "play.fill") }
                            .buttonStyle(.borderedProminent)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = EditTarget(command: c, original: c.name) }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("PC Remote")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = EditTarget(command: Command(name: "", steps: [Step(type: .url, value: "")]), original: nil)
                    } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await reload() }
            .task { await reload() }
            .sheet(item: $editing) { t in
                EditorView(command: t.command, original: t.original) { await reload() }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    func reload() async {
        do {
            commands = try await API.list()
            status = ""
            PCShortcuts.updateAppShortcutParameters()
        } catch {
            status = error.localizedDescription
        }
    }

    func run(_ c: Command) async {
        do {
            try await API.run(c.name)
            status = "Ran \(c.name) ✓"
        } catch {
            status = error.localizedDescription
        }
    }

    func delete(at offsets: IndexSet) {
        let names = offsets.map { commands[$0].name }
        commands.remove(atOffsets: offsets)
        Task {
            for n in names { try? await API.delete(n) }
            await reload()
        }
    }
}

struct EditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var command: Command
    let original: String?
    let onSaved: () async -> Void
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Name (what you say to Siri)") {
                    TextField("e.g. open overwatch", text: $command.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Steps (run in order)") {
                    ForEach($command.steps) { $s in
                        VStack(alignment: .leading) {
                            Picker("Type", selection: $s.type) {
                                ForEach(StepType.allCases) { Text($0.label).tag($0) }
                            }
                            TextField(s.type.hint, text: $s.value)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    .onDelete { command.steps.remove(atOffsets: $0) }
                    .onMove { command.steps.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add step") { command.steps.append(Step(type: .url, value: "")) }
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(original == nil ? "New command" : "Edit command")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(command.name.trimmingCharacters(in: .whitespaces).isEmpty || command.steps.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
    }

    func save() async {
        command.name = command.name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: " ")
        do {
            try await API.save(command)
            if let o = original, o != command.name { try await API.delete(o) }
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("host") private var host = ""
    @AppStorage("port") private var port = "8765"
    @AppStorage("token") private var token = ""
    @State private var result = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("PC (Tailscale IP)") {
                    TextField("100.x.y.z", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $port).keyboardType(.numberPad)
                    SecureField("Token", text: $token)
                }
                Section {
                    Button("Test connection") {
                        Task {
                            do { try await API.ping(); result = "Connected ✓" }
                            catch { result = error.localizedDescription }
                        }
                    }
                    if !result.isEmpty { Text(result) }
                }
                Section("Siri") {
                    Text("Say “Hey Siri, PC Remote <command>” or “Run <command> with PC Remote”. For a phrase without the app name, make a Shortcut named e.g. “open overwatch” containing the “Run PC Command” action.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
