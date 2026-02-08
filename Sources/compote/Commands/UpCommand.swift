import ArgumentParser
import CompoteCore
import Foundation
import Logging

struct UpCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "up",
        abstract: "Create and start containers"
    )

    @Option(name: .shortAndLong, help: "Path to compose file")
    var file: String?

    @Option(name: .shortAndLong, help: "Project name")
    var projectName: String?

    @Flag(name: .shortAndLong, help: "Detached mode: Run containers in the background")
    var detach = false

    @Flag(help: "Recreate containers even if their configuration hasn't changed")
    var forceRecreate = false

    @Flag(help: "Pull image before running")
    var pull = false

    @Argument(help: "Service names to start (all if not specified)")
    var services: [String] = []

    mutating func run() throws {
        // Capture values before async context
        let fileArg = file
        let projectNameArg = projectName
        let detachFlag = detach
        let pullFlag = pull
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

            logger.info("Using compose file", metadata: ["path": "\(composePath)"])

            // Parse compose file
            let composeFile = try parser.parse(from: composePath)

            // Determine project name
            let project = projectNameArg ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .lastPathComponent

            logger.info("Starting project", metadata: ["project": "\(project)"])

            // Create orchestrator
            let orchestrator = try Orchestrator(
                composeFile: composeFile,
                projectName: project,
                logger: logger
            )

            // Start services
            let servicesToStart = servicesArg.isEmpty ? nil : servicesArg
            if pullFlag {
                try await orchestrator.pull(services: servicesToStart)
            }
            try await orchestrator.up(
                services: servicesToStart,
                detach: detachFlag
            )

            if detachFlag {
                logger.info("Services started in detached mode")
            }
        }
    }
}

enum CompoteError: Error, CustomStringConvertible {
    case noComposeFile
    case noRunningContainers
    case noCommand
    case commandFailed(Int32)

    var description: String {
        switch self {
        case .noComposeFile:
            return "No compose file found. Please specify with --file or create compote.yml/docker-compose.yml"
        case .noRunningContainers:
            return "No running containers found"
        case .noCommand:
            return "No command specified"
        case .commandFailed(let code):
            return "Command exited with code \(code)"
        }
    }
}
