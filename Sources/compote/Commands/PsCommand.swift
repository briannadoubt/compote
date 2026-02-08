import ArgumentParser
import CompoteCore
import Foundation
import Logging

struct PsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ps",
        abstract: "List containers"
    )

    @Option(name: .shortAndLong, help: "Path to compose file")
    var file: String?

    @Option(name: .shortAndLong, help: "Project name")
    var projectName: String?

    mutating func run() throws {
        // Capture values before async context
        let fileArg = file
        let projectNameArg = projectName

        try runAsyncTask {
            // Setup logger
            var logger = Logger(label: "compote")
            logger.logLevel = .warning

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

            // List services
            let services = await orchestrator.listServiceStatuses()

            // Print table
            print("NAME                    STATUS")
            print("─────────────────────────────────────────")

            for service in services.sorted(by: { $0.name < $1.name }) {
                let status: String
                if service.isRunning {
                    status = "Up (\(service.runningReplicas))"
                } else if service.isKnown {
                    status = "Exited (\(service.knownReplicas))"
                } else {
                    status = "Not Created"
                }
                let paddedName = service.name.padding(toLength: 24, withPad: " ", startingAt: 0)
                print("\(paddedName)\(status)")
            }
        }
    }
}
