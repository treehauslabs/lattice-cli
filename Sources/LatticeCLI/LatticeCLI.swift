import ArgumentParser

@main
struct LatticeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lattice",
        abstract: "The Lattice blockchain command-line interface",
        version: "0.1.0",
        subcommands: [
            InitCommand.self,
            DevnetCommand.self,
            KeysCommand.self,
            StatusCommand.self,
            QueryCommand.self,
        ]
    )
}
