import ArgumentParser
import CompoteCore
import Foundation
import Logging

struct DownCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "down",
        abstract: "Stop and remove containers, networks"
    )

    @Option(name: .shortAndLong, help: "Path to compose file")
    var file: String?

    @Option(name: .shortAndLong, help: "Project name")
    var projectName: String?

    @Flag(name: .shortAndLong, help: "Remove named volumes")
    var volumes = false

    @Flag(help: "Remove images used by services")
    var rmi = false

    mutating func run() throws {
        // Capture values before async context
        let fileArg = file
        let projectNameArg = projectName
        let volumesFlag = volumes

        try runAsyncTask {
            // Setup logger
            var logger = Logger(label: "compote")
            logger.logLevel = .info

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

            logger.info("Stopping project", metadata: ["project": "\(project)"])

            // Create orchestrator
            let orchestrator = try Orchestrator(
                composeFile: composeFile,
                projectName: project,
                logger: logger
            )

            // Stop services
            try await orchestrator.down(removeVolumes: volumesFlag)

            logger.info("Project stopped")
        }
    }
}
