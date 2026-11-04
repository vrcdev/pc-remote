import AppIntents

struct CommandEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "PC Command")
    static let defaultQuery = CommandQuery()

    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct CommandQuery: EntityStringQuery {
    private func names() async -> [String] {
        if let live = try? await API.list() { return live.map(\.name) }
        return API.cachedNames()
    }

    func entities(for identifiers: [String]) async throws -> [CommandEntity] {
        identifiers.map { CommandEntity(id: $0) }
    }

    func entities(matching string: String) async throws -> [CommandEntity] {
        await names().filter { $0.localizedCaseInsensitiveContains(string) }.map { CommandEntity(id: $0) }
    }

    func suggestedEntities() async throws -> [CommandEntity] {
        await names().map { CommandEntity(id: $0) }
    }
}

struct RunCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Run PC Command"
    static let description = IntentDescription("Runs one of your saved commands on your PC.")

    @Parameter(title: "Command")
    var command: CommandEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$command) on PC")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await API.run(command.id)
        return .result(dialog: "Done, nya~")
    }
}

struct PCShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunCommandIntent(),
            phrases: [
                "Run \(\.$command) with \(.applicationName)",
                "\(.applicationName) \(\.$command)",
                "Tell \(.applicationName) to \(\.$command)"
            ],
            shortTitle: "Run PC command",
            systemImageName: "desktopcomputer"
        )
    }
}
