import AppIntents
import Cocoa

// MARK: AppEntity

@available(macOS 14.0, *)
struct CommandEntity: AppEntity {
    let id: ID

    @Property(title: "Title")
    var title: String

    @Property(title: "Description")
    var description: String

    @Property(title: "Action")
    var action: String

    let command: Ghostty.Command

    struct ID: Hashable {
        let terminalId: TerminalEntity.ID
        let actionKey: String
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Command Palette Command")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: command.title),
            subtitle: LocalizedStringResource(stringLiteral: command.description),
        )
    }

    static var defaultQuery = CommandQuery()

    init(_ command: Ghostty.Command, for terminal: TerminalEntity) {
        self.id = .init(terminalId: terminal.id, actionKey: command.actionKey)
        self.command = command
        self.title = command.title
        self.description = command.description
        self.action = command.action
    }
}

@available(macOS 14.0, *)
extension CommandEntity.ID: RawRepresentable {
    var rawValue: String {
        "\(terminalId):\(actionKey)"
    }

    init?(rawValue: String) {
        let components = rawValue.split(separator: ":", maxSplits: 1)
        guard components.count == 2 else { return nil }
        guard let terminalId = TerminalEntity.ID(uuidString: String(components[0])) else {
            return nil
        }

        self.terminalId = terminalId
        self.actionKey = String(components[1])
    }
}

@available(macOS 14.0, *)
extension CommandEntity.ID: EntityIdentifierConvertible {
    static func entityIdentifier(for entityIdentifierString: String) -> CommandEntity.ID? {
        .init(rawValue: entityIdentifierString)
    }

    var entityIdentifierString: String {
        rawValue
    }
}

@available(macOS 14.0, *)
struct CommandQuery: EntityQuery {
    @IntentParameterDependency<CommandPaletteIntent>(\.$terminal)
    var commandPaletteIntent

    @MainActor
    func entities(for identifiers: [CommandEntity.ID]) async throws -> [CommandEntity] {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return [] }
        let commands = appDelegate.ghostty.config.commandPaletteEntries

        let terminalIds = Set(identifiers.map(\.terminalId))
        let terminals = try await TerminalEntity.defaultQuery.entities(for: Array(terminalIds))

        let terminalMap: [TerminalEntity.ID: TerminalEntity] =
            terminals.reduce(into: [:]) { result, terminal in
                result[terminal.id] = terminal
            }

        return identifiers.compactMap { id in
            guard let terminal = terminalMap[id.terminalId],
                  let command = commands.first(where: { $0.actionKey == id.actionKey }) else {
                return nil
            }

            return CommandEntity(command, for: terminal)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [CommandEntity] {
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let terminal = commandPaletteIntent?.terminal else { return [] }
        return appDelegate.ghostty.config.commandPaletteEntries.map { CommandEntity($0, for: terminal) }
    }
}
