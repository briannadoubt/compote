import ArgumentParser
import CompoteCore
import Foundation
import Logging

struct ExecCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "exec",
        abstract: "Execute a command in a running container"
    )

    @Option(name: .shortAndLong, help: "Path to compose file")
    var file: String?

    @Option(name: .shortAndLong, help: "Project name")
    var projectName: String?

    @Argument(help: "Service name")
    var service: String

    @Argument(parsing: .remaining, help: "Command to execute")
    var command: [String] = []

    mutating func run() throws {
        // Capture values before async context
        let fileArg = file
        let projectNameArg = projectName
        let serviceArg = service
        let commandArg = command

        guard !commandArg.isEmpty else {
            throw CompoteError.noCommand
        }

        try runAsyncTask {
            // Setup logger
            var logger = Logger(label: "compote")
            logger.logLevel = .warning  // Quiet logger for exec command

            // Find compose file
            let parser = ComposeFileParser()
            let composePath: String
            if let file = fileArg {
                composePath = file
            } else if let found = parser.findComposeFile() {
                composePath = found
            } else {
                throw CompoteError.noComposeFile
            }

            // Parse compose file
            let composeFile = try parser.parse(from: composePath)

            // Determine project name
            let project = projectNameArg ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .lastPathComponent

            // Create orchestrator
            let orchestrator = try Orchestrator(
                composeFile: composeFile,
                projectName: project,
                logger: logger
            )

            // Execute command in container
            let exitCode = try await orchestrator.exec(
                serviceName: serviceArg,
                command: commandArg,
                environment: [:]
            )

            // Exit with the same code as the executed command
            if exitCode != 0 {
                throw CompoteError.commandFailed(exitCode)
            }
        }
    }
}
