import ArgumentParser
import CompoteCore
import Foundation
import Logging

struct StopCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop running containers without removing them"
    )

    @Option(name: .shortAndLong, help: "Path to compose file")
    var file: String?

    @Option(name: .shortAndLong, help: "Project name")
    var projectName: String?

    @Option(name: .shortAndLong, help: "Timeout in seconds to wait for stop")
    var timeout: Int = 10

    @Argument(help: "Service selectors (service or service#replica)")
    var services: [String] = []

    mutating func run() throws {
        // Capture values before async context
        let fileArg = file
        let projectNameArg = projectName
        let timeoutArg = timeout
        let servicesArg = services

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

            // Create orchestrator
            let orchestrator = try Orchestrator(
                composeFile: composeFile,
                projectName: project,
                logger: logger
            )

            // Stop services
            let servicesToStop = servicesArg.isEmpty ? nil : servicesArg
            try await orchestrator.stop(
                services: servicesToStop,
                timeout: .seconds(Int64(timeoutArg))
            )

            logger.info("Services stopped successfully")
        }
    }
}
