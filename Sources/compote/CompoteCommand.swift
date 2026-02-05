import ArgumentParser

struct CompoteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compote",
        abstract: "A docker-compose like tool using Apple's containerization framework",
        version: "0.2.0",
        subcommands: [
            SetupCommand.self,
            UpCommand.self,
            DownCommand.self,
            PsCommand.self,
            LogsCommand.self,
            StartCommand.self,
            StopCommand.self,
            RestartCommand.self,
            ExecCommand.self,
            ConfigCommand.self
        ],
        defaultSubcommand: UpCommand.self
    )
}
